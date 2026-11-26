import AppKit
import XCTest
import OCRKit
@testable import Knippi

/// Logic of the menu bar popover and the history grouping (glass redesign, phase 2).
@MainActor
final class MenuBarPopoverTests: XCTestCase {

    // MARK: Which click opens what

    func testPlainLeftClickOpensThePopover() {
        XCTAssertEqual(MenuBarController.clickTarget(isRightClick: false, modifiers: []), .popover)
        // Shift or Command alone do not change it.
        XCTAssertEqual(MenuBarController.clickTarget(isRightClick: false, modifiers: [.shift, .command]), .popover)
    }

    func testRightOptionAndControlClickOpenTheClassicMenu() {
        XCTAssertEqual(MenuBarController.clickTarget(isRightClick: true, modifiers: []), .classicMenu)
        XCTAssertEqual(MenuBarController.clickTarget(isRightClick: false, modifiers: [.option]), .classicMenu)
        XCTAssertEqual(MenuBarController.clickTarget(isRightClick: false, modifiers: [.control]), .classicMenu)
    }

    // MARK: Keyboard focus

    private let grid = PopoverFocusGrid(rows: [
        [.action(0), .action(1), .action(2), .action(3), .action(4), .action(5)],
        [.recent(0), .recent(1), .recent(2)],
        [.recent(3)],
        [.footer(0), .footer(1), .footer(2), .footer(3), .footer(4)],
    ])

    func testFirstKeyFocusesFirstOrLastItem() {
        XCTAssertEqual(grid.move(from: nil, .next), .action(0))
        XCTAssertEqual(grid.move(from: nil, .down), .action(0))
        XCTAssertEqual(grid.move(from: nil, .previous), .footer(4))
    }

    func testTabAndArrowsWalkInReadingOrderAndWrap() {
        XCTAssertEqual(grid.move(from: .action(5), .next), .recent(0))
        XCTAssertEqual(grid.move(from: .action(5), .right), .recent(0))
        XCTAssertEqual(grid.move(from: .recent(0), .previous), .action(5))
        XCTAssertEqual(grid.move(from: .footer(4), .next), .action(0))
        XCTAssertEqual(grid.move(from: .action(0), .left), .footer(4))
    }

    func testUpAndDownKeepTheHorizontalPlace() {
        XCTAssertEqual(grid.move(from: .action(0), .down), .recent(0))
        XCTAssertEqual(grid.move(from: .action(5), .down), .recent(2))
        XCTAssertEqual(grid.move(from: .recent(2), .up), .action(5))
        XCTAssertEqual(grid.move(from: .recent(1), .down), .recent(3))
        XCTAssertEqual(grid.move(from: .recent(3), .down), .footer(0))
        // At the edges up/down stay put.
        XCTAssertEqual(grid.move(from: .action(2), .up), .action(2))
        XCTAssertEqual(grid.move(from: .footer(1), .down), .footer(1))
    }

    func testEmptyRowsAreDropped() {
        let sparse = PopoverFocusGrid(rows: [[], [.action(0)], []])
        XCTAssertEqual(sparse.rows, [[.action(0)]])
        XCTAssertEqual(sparse.move(from: .action(0), .down), .action(0))
        XCTAssertNil(PopoverFocusGrid(rows: []).move(from: nil, .next))
    }

    func testModelKeysMoveFocusAndActivate() {
        let model = MenuBarPopoverModel()
        var ran: [Int] = []
        model.actions = (0..<3).map { i in .init(id: i, title: "\(i)", detail: "\(i)", symbol: "circle", run: { ran.append(i) }) }
        model.actions[1].isEnabled = false
        XCTAssertFalse(model.handleKey(keyCode: 36, shift: false), "Return without focus does nothing")
        XCTAssertTrue(model.handleKey(keyCode: 48, shift: false))          // Tab
        XCTAssertEqual(model.focus, .action(0))
        XCTAssertTrue(model.handleKey(keyCode: 124, shift: false))         // → skips the disabled one
        XCTAssertEqual(model.focus, .action(2))
        XCTAssertTrue(model.handleKey(keyCode: 36, shift: false))          // Return
        XCTAssertEqual(ran, [2])
        XCTAssertFalse(model.handleKey(keyCode: 0, shift: false), "Other keys are not taken")
    }

    func testRecordingClock() {
        XCTAssertEqual(MenuBarPopoverView.clock(0), "00:00")
        XCTAssertEqual(MenuBarPopoverView.clock(83.7), "01:23")
        XCTAssertEqual(MenuBarPopoverView.clock(3_725), "1:02:05")
    }

    // MARK: History grouped by day

    func testHistorySectionsGroupByDayInOrder() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 15)))
        func item(_ name: String, hoursAgo: Double) -> HistoryScanner.Item {
            .init(url: URL(fileURLWithPath: "/tmp/\(name).png"), modified: now.addingTimeInterval(-hoursAgo * 3600))
        }
        let items = [item("a", hoursAgo: 1), item("b", hoursAgo: 10), item("c", hoursAgo: 20),
                     item("d", hoursAgo: 30), item("e", hoursAgo: 24 * 400)]
        let sections = HistoryView.sections(for: items, now: now, calendar: calendar)
        XCTAssertEqual(sections.map { $0.items.map(\.url.lastPathComponent) },
                       [["a.png", "b.png"], ["c.png", "d.png"], ["e.png"]])
        XCTAssertEqual(sections[0].title, String(localized: "Today"))
        XCTAssertEqual(sections[1].title, String(localized: "Yesterday"))
        XCTAssertTrue(sections[2].title.contains("2025"), "Older years show the year: \(sections[2].title)")
    }
}
