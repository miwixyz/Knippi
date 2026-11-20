import AppKit
import SwiftUI
import XCTest
@testable import Knippi

/// Die Hilfe liest drei Dateien aus dem App-Bundle. Fehlt eine, zeigt das
/// Fenster „Dokument fehlt“. Das soll ein roter Test sein, kein Fund beim Nutzer.
@MainActor
final class HelpViewTests: XCTestCase {
    func testAllHelpDocumentsShipInTheBundle() {
        for doc in HelpView.Doc.allCases {
            let text = HelpView.text(for: doc)
            XCTAssertFalse(text.contains("Dokument fehlt"), "\(doc.resource).md fehlt im App-Bundle")
            XCTAssertGreaterThan(text.count, 200, "\(doc.resource).md ist verdächtig kurz")
        }
    }

    func testChangelogInBundleNamesTheAppVersion() throws {
        let version = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        XCTAssertTrue(HelpView.text(for: .changes).contains("## [\(version)]"),
                      "CHANGELOG im Bundle hat keinen Abschnitt für \(version)")
    }

    /// Nur zur Sichtprüfung: rendert jede Seite als PNG, wenn
    /// TEST_RUNNER_KNIPPI_HELP_SNAPSHOT=<Ordner> gesetzt ist. Sonst ein No-op.
    func testRenderSnapshotsWhenRequested() throws {
        guard let dir = ProcessInfo.processInfo.environment["KNIPPI_HELP_SNAPSHOT"] else { return }
        for doc in HelpView.Doc.allCases {
            let view = MarkdownView(source: HelpView.text(for: doc))
                .padding(16)
                .frame(width: 560)
                .background(Color(nsColor: .windowBackgroundColor))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.nsImage)
            let rep = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("hilfe-\(doc.rawValue).png"))
        }
    }
}
