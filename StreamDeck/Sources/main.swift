import AppKit
import Foundation
import OSLog

// KnippiDeck – Stream Deck plugin for Knippi. Every key and dial only opens one of Knippi's fixed automation URLs
// (`knippi://grab/…`, the same list as Settings → General → Automation URLs). No socket, no permissions, no own logic.
// Knippi's own gate stays in charge: Automation URLs off → Knippi asks once or ignores the request.
// Never writes to stdout/stderr (Stream Deck keeps a log file of that per plugin) – only os_log with fixed texts.

let log = Logger(subsystem: "dev.mwlr.knippi.deck", category: "plugin")
let knippiID = "dev.mwlr.knippi" as CFString

/// One Knippi command. `path` is the fixed automation URL path, never built from input.
struct Command {
    let id: String
    let path: String
    let de: String
    let en: String
}

let commands: [Command] = [
    Command(id: "area", path: "/area", de: "Bereich", en: "Area"),
    Command(id: "window", path: "/window", de: "Fenster", en: "Window"),
    Command(id: "fullscreen", path: "/fullscreen", de: "Vollbild", en: "Full Screen"),
    Command(id: "scrolling", path: "/scrolling", de: "Scrollen", en: "Scrolling"),
    Command(id: "last-area", path: "/last-area", de: "Wiederholen", en: "Last Area"),
    Command(id: "ocr", path: "/ocr", de: "Text", en: "Text"),
    Command(id: "color", path: "/color", de: "Farbe", en: "Color"),
    Command(id: "self-timer", path: "/self-timer", de: "Timer", en: "Self-Timer"),
    Command(id: "record-area", path: "/record", de: "Video", en: "Video"),
    Command(id: "record-fullscreen", path: "/record-fullscreen", de: "Video voll", en: "Video Full"),
]

/// Dial lists: rotate picks, push or tap runs.
let dialLists: [String: [String]] = [
    "shot": ["area", "window", "fullscreen", "scrolling", "last-area", "ocr", "color", "self-timer"],
    "video": ["record-area", "record-fullscreen"],
]

let keyPrefix = "dev.mwlr.knippi.deck."
let dialAction = "dev.mwlr.knippi.deck.dial"

func command(_ id: String) -> Command? { commands.first { $0.id == id } }

/// Arguments from Stream Deck: `-port N -pluginUUID … -registerEvent … -info …`.
struct DeckArgs {
    let port: Int
    let uuid: String
    let register: String
    let german: Bool
}

func streamDeckArguments(_ argv: [String]) -> DeckArgs? {
    var a: [String: String] = [:]
    var i = 1
    while i + 1 < argv.count { a[argv[i]] = argv[i + 1]; i += 2 }
    guard let p = a["-port"].flatMap(Int.init), (1...65_535).contains(p), let u = a["-pluginUUID"], let r = a["-registerEvent"] else {
        return nil
    }
    var german = true
    if let info = a["-info"]?.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: info) as? [String: Any],
       let lang = (obj["application"] as? [String: Any])?["language"] as? String {
        german = lang.hasPrefix("de")
    }
    return DeckArgs(port: p, uuid: u, register: r, german: german)
}

/// Why a press cannot reach Knippi – shown as Stream Deck's warning triangle instead of failing silently.
func blockedReason() -> String? {
    guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: knippiID as String) != nil else {
        return "Knippi not installed"
    }
    CFPreferencesAppSynchronize(knippiID)
    let enabled = CFPreferencesCopyAppValue("automationURLsEnabled" as CFString, knippiID) as? Bool ?? false
    let asked = CFPreferencesCopyAppValue("automationURLsAsked" as CFString, knippiID) as? Bool ?? false
    // Off and already answered "Don't Allow": Knippi would ignore the request without a word.
    if !enabled && asked { return "Automation URLs off" }
    return nil
}

struct Dial {
    var list: String
    var index: Int
}

final class Plugin {
    private let task: URLSessionWebSocketTask
    private let german: Bool
    private var dials: [String: Dial] = [:]
    private var dialIcons: [String: String] = [:]

    init(_ args: DeckArgs) {
        german = args.german
        task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(args.port)")!)
        task.resume()
        send(["event": args.register, "uuid": args.uuid])
        receiveLoop()
    }

    private func title(_ c: Command) -> String { german ? c.de : c.en }

    private func send(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: data, encoding: .utf8) else { return }
        task.send(.string(s)) { error in if error != nil { log.error("sending to Stream Deck failed") } }
    }

    private func receiveLoop() {
        task.receive { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .failure:
                    log.notice("Stream Deck gone – exit")
                    exit(0)
                case .success(let msg):
                    if case .string(let s) = msg, let d = s.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                        self?.handle(obj)
                    }
                    self?.receiveLoop()
                }
            }
        }
    }

    private func handle(_ obj: [String: Any]) {
        guard let event = obj["event"] as? String, let ctx = obj["context"] as? String else { return }
        let action = obj["action"] as? String ?? ""
        let payload = obj["payload"] as? [String: Any] ?? [:]
        switch event {
        case "willAppear", "didReceiveSettings":
            guard action == dialAction else { return }
            let settings = payload["settings"] as? [String: Any] ?? [:]
            let list = (settings["list"] as? String).flatMap { dialLists[$0] != nil ? $0 : nil } ?? "shot"
            let count = dialLists[list]!.count
            let index = min(max(settings["index"] as? Int ?? 0, 0), count - 1)
            dials[ctx] = Dial(list: list, index: index)
            showDial(ctx)
        case "willDisappear":
            dials[ctx] = nil
        case "keyUp":
            guard action.hasPrefix(keyPrefix), let c = command(String(action.dropFirst(keyPrefix.count))) else { return }
            run(c, ctx)
        case "dialRotate":
            guard var d = dials[ctx], let raw = payload["ticks"] as? Int, raw != 0 else { return }
            let ticks = max(-100, min(100, raw))   // no overflow on absurd values
            let count = dialLists[d.list]!.count
            d.index = ((d.index + ticks) % count + count) % count
            dials[ctx] = d
            send(["event": "setSettings", "context": ctx, "payload": ["list": d.list, "index": d.index]])
            showDial(ctx)
        case "dialUp", "touchTap":
            guard let d = dials[ctx], let c = command(dialLists[d.list]![d.index]) else { return }
            run(c, ctx)
        default:
            break
        }
    }

    private func run(_ c: Command, _ ctx: String) {
        if let reason = blockedReason() {
            log.notice("press blocked: \(reason, privacy: .public)")
            send(["event": "showAlert", "context": ctx])
            return
        }
        guard let url = URL(string: "knippi://grab\(c.path)") else { return }
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error == nil {
                log.notice("sent \(c.path, privacy: .public)")
            } else {
                log.error("opening Knippi failed")
                DispatchQueue.main.async { self.send(["event": "showAlert", "context": ctx]) }
            }
        }
    }

    private func showDial(_ ctx: String) {
        guard let d = dials[ctx], let c = command(dialLists[d.list]![d.index]) else { return }
        var feedback: [String: Any] = ["title": "Knippi", "value": title(c)]
        if let icon = dialIcon(c.id) { feedback["icon"] = icon }
        send(["event": "setFeedback", "context": ctx, "payload": feedback])
    }

    /// The dial picture of a command as data URL (read once from the plugin folder).
    private func dialIcon(_ id: String) -> String? {
        if let cached = dialIcons[id] { return cached }
        guard let dir = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("imgs/dial-\(id)@2x.png")) else { return nil }
        let url = "data:image/png;base64," + data.base64EncodedString()
        dialIcons[id] = url
        return url
    }
}

guard let args = streamDeckArguments(CommandLine.arguments) else {
    log.error("started without Stream Deck arguments")
    exit(1)
}
let plugin = Plugin(args)
RunLoop.main.run()
