// Packages/CameraKit/Tests/CameraKitTests/CameraManagerTests.swift
import Testing
@testable import CameraKit

@Suite("CameraManager")
struct CameraManagerTests {
    @Test("CameraClipShape has expected cases")
    func shapes() {
        let shapes: [CameraClipShape] = [.circle, .roundedRect]
        #expect(shapes.count == 2)
    }

    /// Audit R8 (21.11.): a missing camera made start() return silently, so the recording
    /// showed an empty camera bubble without any hint.
    @Test("Starting an unavailable camera throws instead of failing silently")
    @MainActor
    func unavailableCameraThrows() {
        let manager = CameraManager()
        manager.selectedDeviceID = "no-such-camera"
        #expect(throws: CameraError.deviceUnavailable) { try manager.start() }
        #expect(!manager.isRunning)
    }

    @Test("CameraPosition has expected cases")
    func positions() {
        let positions: [CameraPosition] = [.bottomLeft, .bottomRight, .topLeft, .topRight]
        #expect(positions.count == 4)
    }
}
