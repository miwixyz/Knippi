import Foundation
import Testing
@testable import SharedKit

@Suite("Color format")
struct ColorFormatTests {
    let c = RGBColor(r: 46, g: 111, b: 128)
    @Test func hex() { #expect(ColorFormat.hex.string(for: c) == "#2E6F80") }
    @Test func rgb() { #expect(ColorFormat.rgb.string(for: c) == "rgb(46, 111, 128)") }
    @Test func hsl() { #expect(ColorFormat.hsl.string(for: c) == "hsl(192, 47%, 34%)") }
    @Test func swiftUI() { #expect(ColorFormat.swiftUI.string(for: c) == "Color(red: 0.180, green: 0.435, blue: 0.502)") }
    @Test func recentKeepsTenNewestFirstNoDuplicates() {
        var list = RecentColors(limit: 10)
        for i in 0..<12 { list.add(RGBColor(r: i, g: 0, b: 0)) }
        list.add(RGBColor(r: 5, g: 0, b: 0))
        #expect(list.items.count == 10)
        #expect(list.items.first == RGBColor(r: 5, g: 0, b: 0))
        #expect(list.items.filter { $0 == RGBColor(r: 5, g: 0, b: 0) }.count == 1)
    }

    @Test("Color format defaults to HEX and persists")
    func colorFormatSettingPersists() {
        let suite = "test.colorFormat"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let first = AppSettings(defaults: defaults)
        #expect(first.colorFormat == .hex)
        first.colorFormat = .hsl
        #expect(AppSettings(defaults: defaults).colorFormat == .hsl)
        #expect(defaults.string(forKey: "colorFormat") == "hsl")
    }

    @Test("Recent colors persist and corrupt data yields an empty list")
    func recentColorsSettingPersists() {
        let suite = "test.recentColors"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let first = AppSettings(defaults: defaults)
        #expect(first.recentColors.items.isEmpty)
        var list = first.recentColors
        list.add(RGBColor(r: 1, g: 2, b: 3))
        first.recentColors = list
        #expect(AppSettings(defaults: defaults).recentColors.items == [RGBColor(r: 1, g: 2, b: 3)])

        defaults.set(Data("not json".utf8), forKey: "recentColors")
        #expect(AppSettings(defaults: defaults).recentColors.items.isEmpty)
    }
}
