// App/Sources/Preferences/Components/AutomationURLsSheetView.swift
import SwiftUI
import AppKit
import SharedKit

struct AutomationCommandItem: Identifiable {
    let id: String
    let name: LocalizedStringKey
    let urlString: String
}

struct AutomationCommandSection: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let items: [AutomationCommandItem]

    /// Drops commands for features hidden in phase 1, then empty sections.
    static func visible(_ sections: [AutomationCommandSection]) -> [AutomationCommandSection] {
        var hidden: Set<String> = []
        if !FeatureFlags.scrollingCapture { hidden.insert("scrolling") }
        if !FeatureFlags.screenRecording { hidden.formUnion(["record", "record-fullscreen"]) }
        return sections.compactMap { section in
            let items = section.items.filter { !hidden.contains($0.id) }
            return items.isEmpty ? nil : AutomationCommandSection(id: section.id, title: section.title, items: items)
        }
    }
}

struct AutomationURLsSheetView: View {
    @Binding var isPresented: Bool
    @State private var copiedURL: String? = nil
    @State private var copiedAll = false

    private let sections: [AutomationCommandSection] = AutomationCommandSection.visible([
        AutomationCommandSection(
            id: "screenshots",
            title: "Screenshots",
            items: [
                AutomationCommandItem(id: "all-in-one", name: "All-in-One", urlString: "knippi://grab/all-in-one"),
                AutomationCommandItem(id: "area", name: "Capture Area", urlString: "knippi://grab/area"),
                AutomationCommandItem(id: "fullscreen", name: "Capture Fullscreen", urlString: "knippi://grab/fullscreen"),
                AutomationCommandItem(id: "window", name: "Capture Window", urlString: "knippi://grab/window"),
                AutomationCommandItem(id: "scrolling", name: "Scrolling Capture", urlString: "knippi://grab/scrolling"),
                AutomationCommandItem(id: "self-timer", name: "Self-Timer", urlString: "knippi://grab/self-timer"),
                AutomationCommandItem(id: "last-area", name: "Capture Previous Area", urlString: "knippi://grab/last-area"),
                AutomationCommandItem(id: "clipboard", name: "Capture Area to Clipboard", urlString: "knippi://grab/clipboard"),
                AutomationCommandItem(id: "share", name: "Capture and Share to Cloud", urlString: "knippi://grab/share"),
                AutomationCommandItem(id: "annotate", name: "Capture Area & Annotate", urlString: "knippi://grab/annotate"),
                AutomationCommandItem(id: "area-and-pin", name: "Capture Area & Pin", urlString: "knippi://grab/area-and-pin"),
                AutomationCommandItem(id: "color", name: "Pick Color", urlString: "knippi://grab/color")
            ]
        ),
        AutomationCommandSection(
            id: "clipboard",
            title: "Clipboard",
            items: [
                AutomationCommandItem(id: "pin", name: "Pin from Clipboard", urlString: "knippi://grab/pin"),
                AutomationCommandItem(id: "edit-clipboard", name: "Edit Clipboard Image", urlString: "knippi://grab/edit-clipboard"),
                AutomationCommandItem(id: "open-image", name: "Open Image File", urlString: "knippi://grab/open-image")
            ]
        ),
        AutomationCommandSection(
            id: "ocr",
            title: "Text Recognition",
            items: [
                AutomationCommandItem(id: "ocr", name: "Capture Text (OCR)", urlString: "knippi://grab/ocr")
            ]
        ),
        AutomationCommandSection(
            id: "recording",
            title: "Recording",
            items: [
                AutomationCommandItem(id: "record", name: "Record Area", urlString: "knippi://grab/record"),
                AutomationCommandItem(id: "record-fullscreen", name: "Record Full Screen", urlString: "knippi://grab/record-fullscreen")
            ]
        ),
        AutomationCommandSection(
            id: "desktop",
            title: "Desktop",
            items: [
                AutomationCommandItem(id: "hide-desktop-icons", name: "Hide Desktop Icons", urlString: "knippi://grab/hide-desktop-icons"),
                AutomationCommandItem(id: "show-desktop-icons", name: "Show Desktop Icons", urlString: "knippi://grab/show-desktop-icons"),
                AutomationCommandItem(id: "toggle-desktop-icons", name: "Toggle Desktop Icons", urlString: "knippi://grab/toggle-desktop-icons")
            ]
        ),
        AutomationCommandSection(
            id: "settings",
            title: "Settings",
            items: [
                AutomationCommandItem(id: "history", name: "Screenshot History", urlString: "knippi://grab/history"),
                AutomationCommandItem(id: "preferences", name: "Preferences", urlString: "knippi://grab/preferences")
            ]
        )
    ])

    /// Glas-Umbau Phase 3: lebender Hintergrund, Befehle auf festen Karten (G1), „Alle kopieren“
    /// als Glas-Kapsel, „Fertig“ als leuchtende Akzent-Kapsel.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Automation URLs")
                        .font(FamilyTheme.font(20, weight: .semibold, relativeTo: .title2))
                        .foregroundStyle(FamilyTheme.textPrimary)
                    Text("Trigger Knippi actions from Raycast, Alfred, Shortcuts, or shell scripts.")
                        .font(FamilyTheme.font(12))
                        .foregroundStyle(FamilyTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    copyAllURLs()
                } label: {
                    Label(copiedAll ? "Copied All" : "Copy All",
                          systemImage: copiedAll ? "checkmark" : "doc.on.doc")
                        .font(FamilyTheme.font(12, weight: .medium))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.familyGlass(.capsule, size: 28))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sections) { section in
                        SettingGroup(title: section.title) {
                            SettingCard {
                                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                                    commandRow(item: item, showDivider: index > 0)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            // Feste Höhe: ohne sie fiel die Liste in einem Blatt am Messfoto auf 0 pt zusammen
            // (ScrollView hat keine Wunschhöhe); die Befehle füllen 360 pt immer.
            .frame(height: 360)

            HStack {
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Text("Done")
                        .font(FamilyTheme.font(13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 18)
                        .frame(height: 30)
                        .background(FamilyTheme.accentFill.gradient, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.6))
                        .shadow(color: FamilyTheme.accentFill.opacity(0.45), radius: 8, y: 2)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .background { HelpBackdrop() }
    }

    private func commandRow(item: AutomationCommandItem, showDivider: Bool) -> some View {
        SettingRow(label: item.name, showDivider: showDivider) {
            Button {
                copyURL(item.urlString)
            } label: {
                HStack(spacing: 6) {
                    Text(item.urlString)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(copiedURL == item.urlString ? FamilyTheme.success : FamilyTheme.textSecondary)

                    Image(systemName: copiedURL == item.urlString ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(copiedURL == item.urlString ? FamilyTheme.success : FamilyTheme.textSecondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    copiedURL == item.urlString ? FamilyTheme.success.opacity(0.14) : FamilyTheme.textPrimary.opacity(0.05),
                    in: Capsule(style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .help("Click to copy URL")
        }
    }

    private func copyURL(_ urlString: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urlString, forType: .string)
        copiedURL = urlString
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedURL == urlString {
                copiedURL = nil
            }
        }
    }

    private func copyAllURLs() {
        var lines: [String] = []
        for section in sections {
            for item in section.items {
                lines.append(item.urlString)
            }
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
        copiedAll = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedAll = false
        }
    }
}
