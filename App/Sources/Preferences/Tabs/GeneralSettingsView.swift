// App/Sources/Preferences/Tabs/GeneralSettingsView.swift
import SwiftUI
import LaunchAtLogin
import AppKit
import KeyboardShortcuts
import SharedKit

struct GeneralSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel
    let updateManager: UpdateManager?
    @State private var showHideMenuBarConfirmation = false
    @State private var showingAutomationURLs = false

    private var menuBarToggleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showMenuBarIcon },
            set: { newValue in
                if newValue {
                    viewModel.showMenuBarIcon = true
                } else {
                    showHideMenuBarConfirmation = true
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PreferencesTabHeader(tab: .general)

            SettingGroup(title: "Startup") {
                SettingCard {
                    SettingRow(label: "Launch at Login", sublabel: "Start Knippi when you log in") {
                        LaunchAtLogin.Toggle { Text("") }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(label: "Show Menu Bar Icon", sublabel: "Hide for a minimalist menu bar — shortcuts still work", showDivider: true) {
                        Toggle("", isOn: menuBarToggleBinding)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }

            SettingGroup(title: "Automation") {
                SettingCard {
                    SettingRow(
                        label: "Automation URLs",
                        sublabel: "Allow Alfred, Raycast, Shortcuts, and other apps to trigger captures"
                    ) {
                        Toggle("", isOn: $viewModel.automationURLsEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(
                        label: "Supported URLs",
                        sublabel: "View all commands for Raycast, Alfred, and Shortcuts",
                        showDivider: true
                    ) {
                        Button("View Commands…") {
                            showingAutomationURLs = true
                        }
                        .controlSize(.small)
                    }
                }
            }

            SettingGroup(title: "Sound") {
                SettingCard {
                    SettingRow(label: "Shutter Sound", sublabel: "Play sound after capture") {
                        Toggle("", isOn: $viewModel.playShutterSound)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }

            if let updateManager {
                UpdatesSettingsSection(updateManager: updateManager)
            }

            SettingGroup(title: "Diagnostics") {
                SettingCard {
                    SettingRow(label: "Diagnostic Logging", sublabel: "Write local troubleshooting logs when enabled") {
                        Toggle("", isOn: $viewModel.diagnosticLoggingEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(label: "Diagnostic Logs", sublabel: "Open Knippi's local log folder", showDivider: true) {
                        ExternalLinkButton(title: "Open", icon: "folder") {
                            openDiagnosticLogs()
                        }
                    }
                    SettingRow(label: "Crash Reports", sublabel: "Open macOS DiagnosticReports", showDivider: true) {
                        ExternalLinkButton(title: "Open", icon: "doc.text.magnifyingglass") {
                            openCrashReports()
                        }
                    }
                }
            }

            SettingGroup(title: "About") {
                SettingCard {
                    SettingRow(label: "Version") {
                        Text(viewModel.appVersion)
                            .font(FamilyTheme.font(12))
                            .foregroundStyle(.tertiary)
                            .fontDesign(.monospaced)
                    }
                    SettingRow(label: "Report a Bug", sublabel: "Found something broken?", showDivider: true) {
                        ExternalLinkButton(title: "Report", icon: "ladybug") {
                            openURL("https://github.com/miwixyz/Knippi/issues/new?template=bug_report.yml&labels=bug")
                        }
                    }
                    SettingRow(label: "Request a Feature", sublabel: "Have an idea?", showDivider: true) {
                        ExternalLinkButton(title: "Request", icon: "lightbulb") {
                            openURL("https://github.com/miwixyz/Knippi/issues/new?template=feature_request.yml&labels=enhancement")
                        }
                    }
                    SettingRow(label: "Source Code", sublabel: "View on GitHub", showDivider: true) {
                        ExternalLinkButton(title: "Open", icon: "chevron.left.forwardslash.chevron.right") {
                            openURL("https://github.com/miwixyz/Knippi")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAutomationURLs) {
            AutomationURLsSheetView(isPresented: $showingAutomationURLs)
        }
        .alert("Hide menu bar icon?", isPresented: $showHideMenuBarConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Hide Icon", role: .destructive) {
                viewModel.showMenuBarIcon = false
            }
        } message: {
            Text(hideMenuBarMessage)
        }
    }

    private var hideMenuBarMessage: String {
        let captureArea = shortcutDescription(for: .captureArea) ?? String(localized: "not set")
        return String(
            format: String(localized: "Knippi will keep running, and your global shortcuts still work:\n\n• Capture Area: %@\n\nTo open Preferences again, launch Knippi from Spotlight, Launchpad, or Finder — even while it's still running."),
            captureArea
        )
    }

    private func shortcutDescription(for name: KeyboardShortcuts.Name) -> String? {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return nil }
        return shortcut.description
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openDiagnosticLogs() {
        let logFileURL = DiagnosticLogger.prepareLogFile()
        NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
    }

    private func openCrashReports() {
        let directory = DiagnosticLogger.diagnosticReportDirectories.first!
        NSWorkspace.shared.open(directory)
    }
}

private struct ExternalLinkButton: View {
    let title: LocalizedStringKey
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(FamilyTheme.font(12))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .preferencesGlassActionBackground(isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { isHovered = $0 }
    }
}
