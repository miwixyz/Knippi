import AppKit
import XCTest
@testable import Knippi

/// Misst, dass Plus Jakarta Sans im App-Bundle liegt und registriert werden kann –
/// ohne Registrierung fiele SwiftUI still auf die Systemschrift zurück.
final class FamilyThemeFontTests: XCTestCase {
    func testFontShipsInAppBundleAndRegisters() {
        XCTAssertNotNil(Bundle.main.url(forResource: "PlusJakartaSans-Variable", withExtension: "ttf"),
                        "TTF fehlt im App-Bundle")
        XCTAssertNotNil(Bundle.main.url(forResource: "OFL", withExtension: "txt"), "Lizenz fehlt im App-Bundle")
        XCTAssertTrue(FamilyTheme.registerFonts(bundle: .main))
        let font = NSFontManager.shared.font(withFamily: FamilyTheme.fontFamily, traits: [], weight: 5, size: 13)
        XCTAssertNotNil(font, "Familie \(FamilyTheme.fontFamily) nach Registrierung nicht auffindbar")
        XCTAssertEqual(font?.familyName, FamilyTheme.fontFamily)
    }
}
