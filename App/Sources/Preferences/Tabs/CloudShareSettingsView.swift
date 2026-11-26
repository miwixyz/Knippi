// App/Sources/Preferences/Tabs/CloudShareSettingsView.swift
import SwiftUI
import SharedKit
import ShareKit

struct CloudShareSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel
    @State private var showWizard = false
    @State private var testing = false
    @State private var testResult: TestResultAlert?
    @State private var showingAutoUploadConfirmation = false
    @State private var showingResetConfirmation = false
    @State private var deletingRecordIDs: Set<UUID> = []
    @State private var deletingAll = false
    @State private var showingDeleteAllConfirmation = false

    private var uploadStore: UploadRecordStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Cloud Share")
                .font(FamilyTheme.font(20, weight: .semibold))

            if viewModel.isCloudShareConfigured {
                configuredView
            } else {
                notConfiguredView
                // Entries stay visible after a reset: those files are still online.
                if !uploadStore.records.isEmpty {
                    uploadedGroup
                }
            }
        }
        .alert(
            String(localized: "Delete All Uploaded Screenshots?"),
            isPresented: $showingDeleteAllConfirmation
        ) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Delete All"), role: .destructive) {
                Task { await deleteAllUploads() }
            }
        } message: {
            Text(String(format: String(localized: "This deletes %lld uploaded screenshots from your storage. Their links stop working. This cannot be undone."), deletableRecordCount))
        }
        .sheet(isPresented: $showWizard) {
            CloudShareWizardView(viewModel: viewModel, onComplete: {
                showWizard = false
            })
        }
        .alert(item: $testResult) { result in
            Alert(
                title: Text(result.title),
                message: Text(result.message),
                dismissButton: .default(Text(String(localized: "OK")))
            )
        }
        .alert(
            String(localized: "Enable Automatic Uploads?"),
            isPresented: $showingAutoUploadConfirmation
        ) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Enable")) {
                viewModel.cloudShareAutoUploadEnabled = true
            }
        } message: {
            Text(String(localized: "Every new screenshot and recording will be uploaded to your configured storage. Each successful share link will replace the current clipboard contents."))
        }
        .alert(
            String(localized: "Reset Cloud Share?"),
            isPresented: $showingResetConfirmation
        ) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Reset"), role: .destructive) {
                resetConfig()
            }
        } message: {
            Text(String(localized: "This removes the provider settings and deletes the access keys from Keychain. Files already uploaded stay in your storage."))
        }
    }

    private var notConfiguredView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "icloud")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(String(localized: "Cloud Share is not set up yet"))
                .font(FamilyTheme.font(.headline))
            Text(String(localized: "Connect your own cloud storage bucket to share captures with one click."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "Set up Cloud Share")) {
                showWizard = true
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(FamilyTheme.accentFill)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var configuredView: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingGroup(title: "Status") {
                SettingCard {
                    SettingRow(label: "Provider") {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(FamilyTheme.success)
                                .font(.system(size: 12))
                            Text(currentProvider?.displayName ?? viewModel.cloudShareProvider ?? "—")
                                .font(FamilyTheme.font(12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    SettingRow(label: "Public URL Prefix", showDivider: true) {
                        Text(viewModel.cloudShareURLPrefix ?? "—")
                            .font(FamilyTheme.font(12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    SettingRow(label: "Bucket", showDivider: true) {
                        Text(viewModel.cloudShareBucket ?? "—")
                            .font(FamilyTheme.font(12))
                            .foregroundStyle(.secondary)
                    }
                    if let region = viewModel.cloudShareRegion, !region.isEmpty {
                        SettingRow(label: "Region / Endpoint", showDivider: true) {
                            Text(region)
                                .font(FamilyTheme.font(12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if let pathPrefix = viewModel.cloudSharePathPrefix, !pathPrefix.isEmpty {
                        SettingRow(label: "Path Prefix", showDivider: true) {
                            Text(pathPrefix)
                                .font(FamilyTheme.font(12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            SettingGroup(title: "Behavior") {
                SettingCard {
                    SettingRow(
                        label: "Automatically Upload New Captures",
                        sublabel: "Upload new screenshots and recordings, then copy the share link"
                    ) {
                        Toggle("", isOn: automaticUploadBinding)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingRow(
                        label: "Copy Link When Upload Starts",
                        sublabel: "Paste the link right away; it works once the upload finishes",
                        showDivider: true
                    ) {
                        Toggle("", isOn: $viewModel.cloudShareCopyLinkWhenUploadStarts)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }

            SettingGroup(title: "Actions") {
                SettingCard {
                    SettingRow(label: "Change Provider", sublabel: "Update storage provider or credentials") {
                        Button(String(localized: "Configure")) {
                            showWizard = true
                        }
                        .controlSize(.small)
                    }
                    SettingRow(label: "Test Connection", sublabel: "Verify the bucket is reachable", showDivider: true) {
                        Button {
                            Task { await testConnection() }
                        } label: {
                            HStack(spacing: 4) {
                                if testing {
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.7)
                                }
                                Text(testing ? String(localized: "Testing…") : String(localized: "Test"))
                            }
                        }
                        .controlSize(.small)
                        .disabled(testing)
                    }
                    SettingRow(label: "Reset Configuration", sublabel: "Remove all Cloud Share credentials", showDivider: true) {
                        Button(String(localized: "Reset"), role: .destructive) {
                            showingResetConfirmation = true
                        }
                        .controlSize(.small)
                    }
                }
            }

            uploadedGroup
        }
    }

    // MARK: - Uploaded

    /// The destination deletes go to: only the one configured right now.
    private var currentDestination: (any ShareDestination)? {
        AppDelegate.shared?.shareCoordinator?.destination
    }

    private func belongsToCurrentDestination(_ record: UploadRecord) -> Bool {
        guard let currentDestination else { return false }
        return record.destinationID == currentDestination.destinationID
    }

    private var deletableRecordCount: Int {
        uploadStore.records.filter(belongsToCurrentDestination).count
    }

    private var uploadedGroup: some View {
        SettingGroup(title: "Uploaded") {
            SettingCard {
                HStack(alignment: .center) {
                    Text(String(localized: "Screenshots uploaded with Cloud Share stay public until you delete them here."))
                        .font(FamilyTheme.font(11))
                        .foregroundStyle(FamilyTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(String(localized: "Delete All…"), role: .destructive) {
                        showingDeleteAllConfirmation = true
                    }
                    .controlSize(.small)
                    .disabled(deletingAll || deletableRecordCount == 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                if let error = uploadStore.lastPersistenceError {
                    Divider()
                    Label(
                        String(format: String(localized: "The upload list could not be read or saved: %@"), error),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(FamilyTheme.font(11))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }

                if uploadStore.records.isEmpty {
                    Divider()
                    Text(String(localized: "No uploaded screenshots."))
                        .font(FamilyTheme.font(12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                } else {
                    ForEach(uploadStore.records) { record in
                        Divider()
                        uploadRecordRow(record)
                    }
                }
            }
        }
    }

    private func uploadRecordRow(_ record: UploadRecord) -> some View {
        let matches = belongsToCurrentDestination(record)
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: record.displayName)
                    .font(FamilyTheme.font(13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(record.uploadedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(FamilyTheme.font(11))
                    .foregroundStyle(FamilyTheme.textSecondary)
                if !matches {
                    Text(String(localized: "Uploaded to a different destination than the one set up now. It can't be deleted from here."))
                        .font(FamilyTheme.font(11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if deletingRecordIDs.contains(record.id) {
                ProgressView()
                    .controlSize(.small)
            } else if matches {
                Button(String(localized: "Delete"), role: .destructive) {
                    Task { await deleteUpload(record) }
                }
                .controlSize(.small)
                .disabled(deletingAll)
            } else {
                Button(String(localized: "Remove from List")) {
                    uploadStore.remove(id: record.id)
                }
                .controlSize(.small)
                .help(String(localized: "Removes only the entry. The file stays online."))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func deleteUpload(_ record: UploadRecord) async {
        guard let destination = currentDestination else {
            testResult = TestResultAlert(
                title: String(localized: "Link not deleted"),
                message: humanize(.notConfigured)
            )
            return
        }
        deletingRecordIDs.insert(record.id)
        defer { deletingRecordIDs.remove(record.id) }
        do {
            try await uploadStore.deleteUpload(record, using: destination)
        } catch UploadDeletionError.destinationMismatch {
            testResult = TestResultAlert(
                title: String(localized: "Link not deleted"),
                message: String(localized: "It was uploaded to a different Cloud Share destination than the one set up now.")
            )
        } catch UploadDeletionError.failed(let error) {
            testResult = TestResultAlert(title: String(localized: "Link not deleted"), message: humanize(error))
        } catch {
            testResult = TestResultAlert(title: String(localized: "Link not deleted"), message: error.localizedDescription)
        }
    }

    private func deleteAllUploads() async {
        guard let destination = currentDestination else {
            testResult = TestResultAlert(
                title: String(localized: "Links not deleted"),
                message: humanize(.notConfigured)
            )
            return
        }
        deletingAll = true
        let summary = await uploadStore.deleteAllUploads(using: destination)
        deletingAll = false

        var lines: [String] = [
            String(format: String(localized: "%lld deleted."), summary.deleted)
        ]
        if !summary.failed.isEmpty {
            lines.append(String(format: String(localized: "%lld not deleted; they stay in the list."), summary.failed.count))
            if let first = summary.failed.values.first {
                lines.append(humanize(first))
            }
        }
        if summary.skippedOtherDestination > 0 {
            lines.append(String(format: String(localized: "%lld belong to a different destination and were kept."), summary.skippedOtherDestination))
        }
        testResult = TestResultAlert(
            title: summary.failed.isEmpty
                ? String(localized: "Links deleted")
                : String(localized: "Some links were not deleted"),
            message: lines.joined(separator: "\n")
        )
    }

    private var currentProvider: ShareProvider? {
        guard let raw = viewModel.cloudShareProvider else { return nil }
        return ShareProvider(rawValue: raw)
    }

    private var automaticUploadBinding: Binding<Bool> {
        Binding(
            get: { viewModel.cloudShareAutoUploadEnabled },
            set: { enabled in
                if enabled {
                    showingAutoUploadConfirmation = true
                } else {
                    viewModel.cloudShareAutoUploadEnabled = false
                }
            }
        )
    }

    private func testConnection() async {
        guard
            let providerRaw = viewModel.cloudShareProvider,
            let provider = ShareProvider(rawValue: providerRaw),
            let urlPrefix = viewModel.cloudShareURLPrefix,
            let bucket = viewModel.cloudShareBucket
        else {
            testResult = TestResultAlert(
                title: String(localized: "Not configured"),
                message: String(localized: "Cloud Share isn't fully set up yet — re-run the wizard.")
            )
            return
        }

        let keychain = KeychainHelper(service: "dev.mwlr.knippi.share.\(provider.rawValue)")
        let accessKey = (try? keychain.get(account: "accessKey")) ?? ""
        let secretKey = (try? keychain.get(account: "secretKey")) ?? ""

        guard !accessKey.isEmpty, !secretKey.isEmpty else {
            testResult = TestResultAlert(
                title: String(localized: "Credentials missing"),
                message: String(localized: "Couldn't read the Access Key or Secret Access Key from Keychain. Re-run the wizard to re-enter them.")
            )
            return
        }

        testing = true
        var fields: [String: String] = [:]
        if let accountID = viewModel.cloudShareAccountID {
            fields["accountID"] = accountID
        }
        if let region = viewModel.cloudShareRegion {
            fields["region"] = region
        }
        if let endpoint = viewModel.cloudShareEndpoint {
            fields["endpoint"] = endpoint
        }
        if let pathPrefix = viewModel.cloudSharePathPrefix {
            fields["pathPrefix"] = pathPrefix
        }
        let result = await CloudShareTester.runTest(
            provider: provider,
            urlPrefix: urlPrefix,
            bucket: bucket,
            fields: fields,
            accessKey: accessKey,
            secretKey: secretKey
        )
        testing = false

        switch result {
        case .success(let dt):
            testResult = TestResultAlert(
                title: String(localized: "Connection works"),
                message: String(format: String(localized: "Round-trip in %.1fs · Test file uploaded and removed cleanly."), dt)
            )
        case .failure(let err):
            testResult = TestResultAlert(
                title: String(localized: "Test failed"),
                message: humanize(err)
            )
        }
    }

    private func humanize(_ err: ShareError) -> String {
        switch err {
        case .notConfigured:
            return String(localized: "Configuration is incomplete. Re-run the wizard.")
        case .invalidCredentials:
            return String(localized: "The storage provider rejected the credentials. Verify the access key, secret, and bucket permissions.")
        case .invalidURLPrefix(let reason):
            return String(format: String(localized: "Invalid public URL prefix: %@"), reason)
        case .network(let underlying):
            return String(format: String(localized: "Network error: %@"), underlying)
        case .quotaExceeded:
            return String(localized: "Storage quota exceeded — free up space in your provider dashboard.")
        case .publicAccessUnreachable:
            return String(localized: "Upload worked, but the file isn't publicly reachable. Enable public access or use a public custom domain.")
        case .unknown(let s):
            return s
        }
    }

    private func resetConfig() {
        // 1. Clear AppSettings via viewModel for proper @Observable mutations.
        viewModel.cloudShareAutoUploadEnabled = false
        viewModel.cloudShareProvider = nil
        viewModel.cloudShareURLPrefix = nil
        viewModel.cloudShareAccountID = nil
        viewModel.cloudShareRegion = nil
        viewModel.cloudShareEndpoint = nil
        viewModel.cloudSharePathPrefix = nil
        viewModel.cloudShareBucket = nil

        // 2. Delete Keychain entries — surface failures instead of silently swallowing.
        var keychainErrors: [String] = []
        for provider in ShareProvider.allCases {
            let keychain = KeychainHelper(service: "dev.mwlr.knippi.share.\(provider.rawValue)")
            do {
                try keychain.delete(account: "accessKey")
            } catch {
                keychainErrors.append("\(provider.displayName) \(String(localized: "Access Key")) (\(error.localizedDescription))")
            }
            do {
                try keychain.delete(account: "secretKey")
            } catch {
                keychainErrors.append("\(provider.displayName) \(String(localized: "Secret Access Key")) (\(error.localizedDescription))")
            }
        }

        // 3. Tear down the live coordinator so subsequent shares fail closed.
        // Use AppDelegate.shared (NSApp.delegate cast fails under SwiftUI adaptor).
        let appDelegate = AppDelegate.shared
        appDelegate?.refreshShareCoordinator()

        // 4. Sanity check (debug builds only). After all the above, the live
        //    ShareCoordinator MUST be nil; if not, refresh didn't propagate.
        #if DEBUG
        assert(appDelegate?.shareCoordinator == nil,
               "ShareCoordinator should be nil after reset")
        #endif

        // 5. If Keychain delete failed for either entry, alert the user.
        if !keychainErrors.isEmpty {
            let list = keychainErrors.joined(separator: ", ")
            testResult = TestResultAlert(
                title: String(localized: "Couldn't fully clear Keychain"),
                message: String(format: String(localized: "Some credentials may still be in Keychain: %@.\n\nOpen 'Keychain Access.app' and search for 'dev.mwlr.knippi.share' to remove them manually."), list)
            )
        }
    }
}

// Alert wrapper — `Identifiable` lets `.alert(item:)` re-trigger when a new
// result lands (binding-by-Bool would skip the second presentation if the
// user cancels then re-tests too quickly).
struct TestResultAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
