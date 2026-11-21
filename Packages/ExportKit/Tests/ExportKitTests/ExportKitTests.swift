import Foundation
import CoreGraphics
import Testing
import XCTest
@testable import ExportKit

final class ExportKitTests: XCTestCase {
    func testPlaceholder() {
        // Placeholder — add real tests here
        XCTAssertTrue(true)
    }
}

@Suite("GIF size plan")
struct GIFPlanTests {
    private func pixels(_ plan: (fps: Double, maxWidth: CGFloat), seconds: Double, source: CGSize) -> Double {
        let h = source.height * plan.maxWidth / source.width
        return ceil(seconds * plan.fps) * Double(plan.maxWidth) * Double(h)
    }

    @Test("A short GIF keeps full rate and width")
    func shortKeepsQuality() {
        let plan = GIFExporter.plan(seconds: 2, sourceSize: CGSize(width: 1920, height: 1200), baseFps: 25, maxWidth: 1920)
        #expect(plan.fps == 25)
        #expect(plan.maxWidth == 1920)
    }

    @Test("A long GIF stays within the memory budget")
    func longStaysInBudget() {
        let source = CGSize(width: 2880, height: 1800)
        for seconds in [10.0, 30, 120, 600] {
            let plan = GIFExporter.plan(seconds: seconds, sourceSize: source, baseFps: 25, maxWidth: 1920)
            #expect(pixels(plan, seconds: seconds, source: CGSize(width: 1920, height: 1200)) <= GIFExporter.pixelBudget * 1.01)
            #expect(ceil(seconds * plan.fps) <= Double(GIFExporter.maxTotalFrames))
        }
    }

    @Test("Frame rate drops to 10 before the picture gets smaller")
    func rateBeforeSize() {
        let plan = GIFExporter.plan(seconds: 5, sourceSize: CGSize(width: 1920, height: 1200), baseFps: 25, maxWidth: 1920)
        #expect(plan.maxWidth == 1920)
        #expect(plan.fps >= 10)
    }
}
