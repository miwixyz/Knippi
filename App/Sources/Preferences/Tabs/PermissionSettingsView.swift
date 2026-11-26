import AppKit
import SwiftUI
import SharedKit

struct PermissionSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Permissions")
                    .font(FamilyTheme.font(20, weight: .semibold))
                Spacer()
                Button(action: refresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }

            SettingGroup(title: "Privacy & Security") {
                SettingCard {
                    permissionRow(
                        kind: .screenRecording,
                        title: "Screen Recording",
                        subtitle: "Required for screenshots and recording",
                        isGranted: viewModel.screenRecordingGranted
                    )
                    if FeatureFlags.screenRecording || FeatureFlags.scrollingCapture {
                        permissionRow(
                            kind: .accessibility,
                            title: "Accessibility",
                            subtitle: "Required for auto scroll and to cancel recording with Esc",
                            isGranted: viewModel.accessibilityGranted,
                            showDivider: true
                        )
                    }
                    if FeatureFlags.screenRecording {
                        permissionRow(
                            kind: .inputMonitoring,
                            title: "Input Monitoring",
                            subtitle: "Required to show key presses while recording",
                            isGranted: viewModel.inputMonitoringGranted,
                            showDivider: true
                        )
                        permissionRow(
                            kind: .camera,
                            title: "Camera",
                            subtitle: "Required to show your camera picture while recording",
                            isGranted: viewModel.cameraGranted,
                            showDivider: true
                        )
                        permissionRow(
                            kind: .microphone,
                            title: "Microphone",
                            subtitle: "Required for microphone recording",
                            isGranted: viewModel.microphoneGranted,
                            showDivider: true
                        )
                    }
                }
            }
        }
        .task {
            await viewModel.refreshPermissions()
        }
        // Back from System Settings: show the new state without pressing Refresh.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func permissionRow(
        kind: PermissionKind,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        isGranted: Bool,
        showDivider: Bool = false
    ) -> some View {
        SettingRow(label: title, sublabel: subtitle, showDivider: showDivider) {
            HStack(spacing: 10) {
                statusBadge(isGranted)
                // Granted: the badge says it all, no buttons. Missing: ask or open settings.
                if !isGranted {
                    Button(action: { request(kind) }) {
                        Label(actionTitle(for: kind), systemImage: actionIcon(for: kind))
                    }
                    .controlSize(.small)
                    Button(action: { viewModel.openPermissionSettings(kind) }) {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderless)
                    .help("Open System Settings")
                    .accessibilityLabel(Text("Open System Settings"))
                }
            }
        }
    }

    private func statusBadge(_ isGranted: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isGranted ? FamilyTheme.success : FamilyTheme.warning)
                .frame(width: 7, height: 7)
            Text(isGranted ? "Allowed" : "Needs Access")
                .font(FamilyTheme.font(11, weight: .medium))
                .foregroundStyle(isGranted ? .secondary : .primary)
        }
        .frame(width: 96, alignment: .leading)
    }

    private func actionTitle(for kind: PermissionKind) -> LocalizedStringKey {
        switch kind {
        case .camera, .microphone:
            return "Request"
        case .screenRecording, .accessibility, .inputMonitoring:
            return "Open"
        }
    }

    private func actionIcon(for kind: PermissionKind) -> String {
        switch kind {
        case .camera, .microphone:
            return "hand.tap"
        case .screenRecording, .accessibility, .inputMonitoring:
            return "gearshape"
        }
    }

    private func request(_ kind: PermissionKind) {
        Task { await viewModel.requestPermission(kind) }
    }

    private func refresh() {
        Task { await viewModel.refreshPermissions() }
    }
}
