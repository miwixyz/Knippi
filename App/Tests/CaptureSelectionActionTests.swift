import SharedKit
import ShareKit
import XCTest
@testable import Knippi

@MainActor
final class CaptureSelectionActionTests: XCTestCase {
    func testRejectedAreaShortcutsPreserveTheActiveCaptureAction() throws {
        let actions: [CaptureCoordinator.PostCaptureAction] = [.default, .clipboard, .annotate, .pin, .share]

        for activeAction in actions {
            for rejectedAction in actions {
                let suiteName = "CaptureSelectionActionTests.\(UUID().uuidString)"
                let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
                defer { defaults.removePersistentDomain(forName: suiteName) }
                let coordinator = CaptureCoordinator(settings: AppSettings(defaults: defaults))
                coordinator.shareCoordinator = ShareCoordinator(destination: UnusedShareDestination())

                // Stay on the main actor without yielding: the selection start is
                // pending, and no real screen capture or selection UI is needed.
                start(activeAction, on: coordinator)
                XCTAssertTrue(coordinator.isCaptureSelectionActive)
                XCTAssertEqual(coordinator.pendingAction, activeAction)

                start(rejectedAction, on: coordinator)
                XCTAssertTrue(coordinator.isCaptureSelectionActive)
                XCTAssertEqual(
                    coordinator.pendingAction,
                    activeAction,
                    "Rejected \(rejectedAction) must preserve active \(activeAction)"
                )
            }
        }
    }

    /// Audit C1 (21.11.): Esc in an area selection kept the chosen action, so the next
    /// full-screen, window or scrolling capture was shared/pinned/copied by surprise.
    func testCancelledSelectionDropsThePendingAction() throws {
        let actions: [CaptureCoordinator.PostCaptureAction] = [.clipboard, .annotate, .pin, .share]

        for action in actions {
            let suiteName = "CaptureSelectionActionTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let coordinator = CaptureCoordinator(settings: AppSettings(defaults: defaults))
            coordinator.shareCoordinator = ShareCoordinator(destination: UnusedShareDestination())

            start(action, on: coordinator)
            XCTAssertEqual(coordinator.pendingAction, action)

            coordinator.handleSelectionCancelled()
            XCTAssertEqual(coordinator.pendingAction, .default, "Esc must drop \(action)")
        }
    }

    private func start(_ action: CaptureCoordinator.PostCaptureAction, on coordinator: CaptureCoordinator) {
        switch action {
        case .default: coordinator.captureArea()
        case .clipboard: coordinator.captureAreaToClipboard()
        case .annotate: coordinator.captureAreaAndAnnotate()
        case .pin: coordinator.captureAreaAndPin()
        case .share: coordinator.captureAreaAndShare()
        default: XCTFail("Unsupported area shortcut: \(action)")
        }
    }
}

private struct UnusedShareDestination: ShareDestination {
    func publicURL(for key: String) -> URL {
        URL(string: "https://example.invalid")!.appendingPathComponent(key)
    }

    func upload(file: URL, key: String, contentType: String) async throws -> URL {
        throw URLError(.unsupportedURL)
    }

    func delete(key: String) async throws {}
    func validateConfig() async throws {}
}
