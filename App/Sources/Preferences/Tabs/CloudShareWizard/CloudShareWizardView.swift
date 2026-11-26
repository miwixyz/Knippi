// App/Sources/Preferences/Tabs/CloudShareWizard/CloudShareWizardView.swift
import AppKit
import Observation
import SwiftUI
import SharedKit
import ShareKit

// MARK: - Wizard root

struct CloudShareWizardView: View {
    @Bindable var viewModel: PreferencesViewModel
    let onComplete: () -> Void

    @State private var model: CloudShareWizardModel
    @Environment(\.dismiss) private var dismiss

    /// `model` nur für Render-Tests vorgeben (Schritt direkt zeigen); die App nutzt den Standard.
    init(viewModel: PreferencesViewModel, onComplete: @escaping () -> Void,
         model: CloudShareWizardModel = CloudShareWizardModel()) {
        self.viewModel = viewModel
        self.onComplete = onComplete
        _model = State(initialValue: model)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                // Schritte gleiten weich herein (Bewegung reduzieren: nur Überblendung).
                stepContent
                    .id(model.step)
                    .transition(reduceMotion
                                ? .opacity
                                : .asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .frame(width: 640, height: 560)
        // Glas-Umbau Phase 3: lebender Hintergrund wie Einstellungen; Inhalte bleiben feste Karten (G1).
        .background { WizardBackdrop() }
        .foregroundStyle(FamilyTheme.textPrimary)
        .familyAnimation(FamilyTheme.Motion.appear, value: model.step)
    }

    // MARK: Header (title bar surrogate)

    private var header: some View {
        ZStack {
            HStack(spacing: FamilyTheme.Space.s) {
                Text(String(localized: "Cloud Share Setup"))
                    .font(FamilyTheme.font(13, weight: .semibold))
                    .foregroundStyle(FamilyTheme.textPrimary)
                Spacer()
                Button {
                    onComplete()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(FamilyTheme.textPrimary)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .floatingGlassIsland(in: Circle())
                .help(String(localized: "Close"))
                .keyboardShortcut(.cancelAction)
            }
            // Schritt-Leiste: schwebende Glas-Kapsel, die Akzent-Pille gleitet zum aktuellen Schritt.
            WizardStepCapsule(current: model.step.rawValue,
                              total: CloudShareWizardModel.WizardStep.allCases.count)
        }
        .padding(.horizontal, FamilyTheme.Space.l)
        .padding(.top, FamilyTheme.Space.m)
        .padding(.bottom, FamilyTheme.Space.xs)
    }

    // MARK: Body content

    @ViewBuilder
    private var stepContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                switch model.step {
                case .welcome:    WelcomeStep(model: model)
                case .provider:   ProviderStep(model: model)
                case .getKeys:    GetKeysStep(model: model)
                case .credentials: CredentialsStep(model: model)
                case .urlPrefix:  URLPrefixStep(model: model)
                case .done:       DoneStep(model: model, onComplete: onComplete)
                }
            }
            .padding(FamilyTheme.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Footer (progress + actions)

    private var footer: some View {
        HStack(spacing: FamilyTheme.Space.m) {
            Text("\(model.step.rawValue + 1) of \(CloudShareWizardModel.WizardStep.allCases.count)")
                .font(FamilyTheme.font(11, weight: .medium))
                .foregroundStyle(FamilyTheme.textSecondary)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(model.step.rawValue)))
            Spacer()

            if model.step != .welcome && model.step != .done {
                Button {
                    model.goBack()
                } label: {
                    Text(String(localized: "Back"))
                        .font(FamilyTheme.font(13, weight: .medium))
                        .frame(minWidth: 64)
                }
                .buttonStyle(.familyGlass(.capsule, size: 32))
                // No .cancelAction here — the close (X) button owns Escape.
                // Two cancelAction shortcuts in the same scene have undefined behavior.
            }

            primaryActionButton
        }
        .padding(.horizontal, FamilyTheme.Space.xl)
        .padding(.vertical, FamilyTheme.Space.m)
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        switch model.step {
        case .welcome, .provider, .getKeys, .credentials:
            WizardPrimaryButton(
                title: String(localized: "Next"),
                isEnabled: model.canAdvance
            ) {
                model.goNext()
            }
        case .urlPrefix:
            if case .success = model.testState {
                WizardPrimaryButton(
                    title: String(localized: "Save"),
                    isEnabled: true
                ) {
                    Task { await save() }
                }
            } else {
                WizardPrimaryButton(
                    title: String(localized: "Next"),
                    isEnabled: false  // disabled until test succeeds
                ) {}
            }
        case .done:
            WizardPrimaryButton(
                title: String(localized: "Done"),
                isEnabled: true
            ) {
                onComplete()
            }
        }
    }

    private func save() async {
        // Step 1: Keychain first — if this fails, abort (no AppSettings writes,
        // so the UI never shows a half-saved "configured" state).
        let keychain = KeychainHelper(service: "dev.mwlr.knippi.share.\(model.provider.rawValue)")
        do {
            try keychain.set(model.accessKey, account: "accessKey")
            try keychain.set(model.secretKey, account: "secretKey")
        } catch {
            // Surface the failure on the URL-prefix step's test panel — the user
            // sees the error and stays on screen 5 with their data intact.
            model.testState = .failure(.unknown(String(format: String(localized: "Could not save credentials to Keychain: %@"), error.localizedDescription)))
            return
        }

        // Step 2: Persist non-secret values via the viewModel so its
        // @Observable mutations fire (this is what drives the
        // notConfiguredView → configuredView transition in CloudShareSettingsView).
        viewModel.cloudShareProvider = model.provider.rawValue
        viewModel.cloudShareURLPrefix = ShareConfig.normalizePrefix(model.urlPrefix)
        viewModel.cloudShareAccountID = model.provider == .r2 ? model.accountID : nil
        viewModel.cloudShareRegion = model.provider == .r2 ? nil : model.region
        viewModel.cloudShareEndpoint = model.endpoint.isEmpty ? nil : model.endpoint
        viewModel.cloudSharePathPrefix = model.pathPrefix.isEmpty ? nil : model.pathPrefix
        viewModel.cloudShareBucket = model.bucket

        // Step 3: Rebuild the live ShareCoordinator with the new credentials.
        // Use AppDelegate.shared (NSApp.delegate cast fails under SwiftUI adaptor).
        AppDelegate.shared?.refreshShareCoordinator()

        // Step 4: Advance to the success screen.
        model.advanceTo(.done)
    }
}

// MARK: - View model

@MainActor
@Observable
final class CloudShareWizardModel {
    var step: WizardStep = .welcome

    // Form state
    var provider: ShareProvider = .r2
    var accountID: String = ""
    var region: String = ""
    var endpoint: String = ""
    var pathPrefix: String = ""
    var bucket: String = ""
    var accessKey: String = ""
    var secretKey: String = ""
    var urlPrefix: String = ""

    // Field-blur tracking for inline validation (only show errors after the user
    // has interacted with — and left — a field).
    var blurredAccountID: Bool = false
    var blurredBucket: Bool = false
    var blurredAccessKey: Bool = false

    // Reveal toggle for the secret-access-key field
    var showSecret: Bool = false

    // Test-connection state machine
    var testState: TestState = .idle

    enum WizardStep: Int, CaseIterable {
        case welcome = 0
        case provider
        case getKeys
        case credentials
        case urlPrefix
        case done
    }

    enum TestState: Equatable {
        case idle
        case validating(phase: String)
        case success(roundTripSeconds: TimeInterval)
        case failure(ShareError)
    }

    // MARK: Navigation

    var canAdvance: Bool {
        switch step {
        case .welcome:     return true
        case .provider:    return true
        case .getKeys:     return true
        case .credentials: return credentialsValid
        case .urlPrefix:
            if case .success = testState { return true }
            return false
        case .done:        return true
        }
    }

    var credentialsValid: Bool {
        providerSpecificFieldsValid
            && accountIDError == nil
            && bucketError == nil
            && accessKeyError == nil
            && !bucket.isEmpty
            && !accessKey.isEmpty
            && !secretKey.isEmpty
    }

    var providerSpecificFieldsValid: Bool {
        switch provider {
        case .r2:
            return !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .s3, .tencentCOS, .aliyunOSS:
            return !region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var providerDisplayName: String {
        provider.displayName
    }

    var regionLabel: String {
        switch provider {
        case .r2:
            return String(localized: "Account ID")
        case .s3:
            return String(localized: "Region")
        case .tencentCOS:
            return String(localized: "Region")
        case .aliyunOSS:
            return String(localized: "Endpoint / Region")
        }
    }

    var regionPlaceholder: String {
        switch provider {
        case .r2:
            return String(localized: "32-character hex")
        case .s3:
            return "us-east-1"
        case .tencentCOS:
            return "ap-guangzhou"
        case .aliyunOSS:
            return "oss-cn-hangzhou"
        }
    }

    var accessKeyLabel: String {
        switch provider {
        case .tencentCOS:
            return "SecretId"
        case .aliyunOSS:
            return String(localized: "AccessKey ID")
        case .r2, .s3:
            return String(localized: "Access Key ID")
        }
    }

    var secretKeyLabel: String {
        switch provider {
        case .aliyunOSS:
            return String(localized: "AccessKey Secret")
        case .r2, .s3, .tencentCOS:
            return String(localized: "Secret Access Key")
        }
    }

    var endpointPlaceholder: String {
        switch provider {
        case .s3:
            return String(localized: "Optional for S3-compatible services")
        case .r2, .tencentCOS, .aliyunOSS:
            return ""
        }
    }

    var shouldShowEndpoint: Bool {
        provider == .s3
    }

    var configFields: [String: String] {
        var fields: [String: String] = [:]
        if !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields["accountID"] = accountID
        }
        if !region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields["region"] = region
        }
        if !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields["endpoint"] = endpoint
        }
        if !pathPrefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields["pathPrefix"] = pathPrefix
        }
        return fields
    }

    func goNext() {
        guard let next = WizardStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func goBack() {
        guard let prev = WizardStep(rawValue: step.rawValue - 1) else { return }
        // Clear test state when leaving the URL-prefix step backwards
        if step == .urlPrefix { testState = .idle }
        step = prev
    }

    func advanceTo(_ s: WizardStep) {
        step = s
    }

    // MARK: Inline validation

    /// Returns nil if the value passes the heuristic, or a localized error message.
    var accountIDError: String? {
        // Account IDs exist only for R2; a value left over from R2 must not block other providers.
        guard provider == .r2, blurredAccountID, !accountID.isEmpty else { return nil }
        let trimmed = accountID.trimmingCharacters(in: .whitespaces)
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        let isAllHex = trimmed.unicodeScalars.allSatisfy { hex.contains($0) }
        if trimmed.count != 32 || !isAllHex {
            return String(localized: "Looks short — Cloudflare Account IDs are 32 hex characters")
        }
        return nil
    }

    /// http:// sends screenshots and signed requests unencrypted, and macOS
    /// only allows it for local-network hosts (audit Q6, 21.11.).
    var endpointWarning: String? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.hasPrefix("http://") else { return nil }
        return String(localized: "Unencrypted connection. Use http:// only for a server in your local network.")
    }

    var bucketError: String? {
        guard blurredBucket, !bucket.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        let trimmed = bucket.trimmingCharacters(in: .whitespaces)
        if trimmed.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return String(localized: "Bucket names must be lowercase, no spaces")
        }
        return nil
    }

    var accessKeyError: String? {
        guard blurredAccessKey, !accessKey.isEmpty else { return nil }
        let trimmed = accessKey.trimmingCharacters(in: .whitespaces)
        if trimmed.count < 16 {
            guard provider == .r2 else {
                return String(localized: "Access keys are usually at least 16 characters long. Check that you copied the whole key.")
            }
            return String(localized: "Cloudflare R2 Access Key IDs are typically 32+ chars. This looks like an API token instead — verify you created an R2 token, not a regular API token.")
        }
        return nil
    }

    var prefixError: String? {
        guard !urlPrefix.isEmpty else { return nil }
        do {
            try ShareConfig.validatePrefix(urlPrefix)
            return nil
        } catch let err as ShareError {
            if case .invalidURLPrefix(let reason) = err { return reason }
            return String(describing: err)
        } catch {
            return error.localizedDescription
        }
    }

    var canTest: Bool {
        guard !urlPrefix.isEmpty, prefixError == nil else { return false }
        if case .validating = testState { return false }
        return true
    }

    // MARK: Test execution

    func runConnectionTest() async {
        testState = .validating(phase: String(localized: "Uploading test file…"))

        // Phase narrator — runs concurrently to give the user confidence the test
        // isn't stuck. We cancel it explicitly once the real call returns so a
        // fast network round-trip isn't padded out to 1.4s by sleep tasks.
        let narrator = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            if case .validating = self.testState {
                self.testState = .validating(phase: String(localized: "Fetching public URL…"))
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            if case .validating = self.testState {
                self.testState = .validating(phase: String(localized: "Cleaning up…"))
            }
        }

        let result = await CloudShareTester.runTest(
            provider: provider,
            urlPrefix: urlPrefix,
            bucket: bucket,
            fields: configFields,
            accessKey: accessKey,
            secretKey: secretKey
        )

        // Cancel the narrator BEFORE writing the final state. Any in-flight phase
        // update will see the still-`.validating` state when it checks, but its
        // own `Task.isCancelled` guard will keep it from writing.
        narrator.cancel()

        // If the outer test Task was cancelled (e.g. user edited the URL prefix
        // mid-flight), don't write a stale `.success`/`.failure` — `onChange`
        // already reset `testState` to `.idle`.
        guard !Task.isCancelled else { return }

        switch result {
        case .success(let dt): testState = .success(roundTripSeconds: dt)
        case .failure(let err): testState = .failure(err)
        }
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    @Bindable var model: CloudShareWizardModel

    var body: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.xl) {
            HStack(alignment: .center, spacing: FamilyTheme.Space.l) {
                IconBadge(systemName: "icloud.and.arrow.up.fill")
                VStack(alignment: .leading, spacing: FamilyTheme.Space.xs) {
                    Text(String(localized: "Set up Cloud Share"))
                        .font(FamilyTheme.font(22, weight: .semibold, relativeTo: .title))
                        .foregroundStyle(FamilyTheme.textPrimary)
                    Text(String(localized: "Step 1 — Introduction"))
                        .font(FamilyTheme.font(11, weight: .semibold))
                        .foregroundStyle(FamilyTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                }
                Spacer()
            }

            Text(.init(String(localized: "Knippi uploads to **your own cloud storage** — never our servers. You bring the bucket, you own the files, you keep the bill. We just hand you the share link.")))
                .font(FamilyTheme.font(13))
                .foregroundStyle(FamilyTheme.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: FamilyTheme.Space.m) {
                CheckBullet(
                    title: String(localized: "Yours forever."),
                    detail: String(localized: "Files live in your account. Cancel Knippi, keep your screenshots.")
                )
                CheckBullet(
                    title: String(localized: "Free tier friendly."),
                    detail: String(localized: "Cloudflare R2 includes 10 GB and zero egress fees.")
                )
                CheckBullet(
                    title: String(localized: "Five minutes to set up."),
                    detail: String(localized: "Paste four keys, test, done.")
                )
            }
            .padding(FamilyTheme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .familyCard(radius: FamilyTheme.Radius.tile)

            Spacer(minLength: 8)

            InfoCard(
                icon: "info.circle.fill",
                text: String(localized: "Already have credentials? You'll be done in under a minute.")
            )
        }
    }
}

// MARK: - Step 2: Provider

private struct ProviderStep: View {
    @Bindable var model: CloudShareWizardModel

    var body: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.xl) {
            StepHeader(
                stepLabel: String(localized: "Step 2 — Provider"),
                title: String(localized: "Choose a storage provider"),
                subtitle: String(localized: "Choose where Knippi uploads screenshots. Files stay in your own storage account and Knippi copies the public share link.")
            )

            VStack(spacing: FamilyTheme.Space.s) {
                ProviderCard(
                    badge: "R2",
                    name: String(localized: "Cloudflare R2"),
                    sub: String(localized: "10 GB free · $0 egress · S3-compatible"),
                    pillText: String(localized: "RECOMMENDED"),
                    selected: model.provider == .r2,
                    enabled: true
                ) {
                    model.provider = .r2
                }
                ProviderCard(
                    badge: "S3",
                    name: String(localized: "Amazon S3"),
                    sub: String(localized: "AWS buckets and S3-compatible endpoints"),
                    pillText: nil,
                    selected: model.provider == .s3,
                    enabled: true
                ) {
                    model.provider = .s3
                }
                ProviderCard(
                    badge: "COS",
                    name: String(localized: "Tencent COS"),
                    sub: String(localized: "Tencent Cloud object storage"),
                    pillText: nil,
                    selected: model.provider == .tencentCOS,
                    enabled: true
                ) {
                    model.provider = .tencentCOS
                }
                ProviderCard(
                    badge: "OSS",
                    name: String(localized: "Aliyun OSS"),
                    sub: String(localized: "Alibaba Cloud object storage"),
                    pillText: nil,
                    selected: model.provider == .aliyunOSS,
                    enabled: true
                ) {
                    model.provider = .aliyunOSS
                }
            }

            Spacer(minLength: 8)
        }
    }
}

// MARK: - Step 3: Get keys

private struct GetKeysStep: View {
    @Bindable var model: CloudShareWizardModel

    private var steps: [(title: String, detail: AttributedString)] {
        [
            (String(localized: "Create or choose a bucket"),
             Self.attributed(String(format: String(localized: "Use a bucket in **%@** that Knippi can write objects into."), model.providerDisplayName))),
            (String(localized: "Make uploaded files publicly readable"),
             Self.attributed(String(localized: "Use a public bucket URL or connect a custom domain/CDN. Knippi needs a public HTTPS prefix so it can copy a share link."))),
            (String(localized: "Create access credentials"),
             Self.attributed(String(localized: "Create a key with object read/write permission scoped to this bucket when your provider supports scoped keys."))),
            (String(localized: "Copy the required values"),
             Self.attributed(String(localized: "Keep the bucket, region/endpoint, access key, and secret ready. The secret will be stored in macOS Keychain.")))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.l) {
            StepHeader(
                stepLabel: String(localized: "Step 3 — Provider"),
                title: String(format: String(localized: "Prepare %@ credentials"), model.providerDisplayName),
                subtitle: String(localized: "Open your provider dashboard and keep this window nearby. You'll paste the values on the next screen.")
            )

            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { idx, item in
                    if idx > 0 {
                        WizardDivider().padding(.leading, 52)
                    }
                    NumberedStepRow(number: idx + 1, title: item.title, detail: item.detail)
                }
            }
            .familyCard(radius: FamilyTheme.Radius.tile)

            HStack {
                Spacer()
                // Zweitaktion: Die Hauptaktion („Weiter“) sitzt in der Fußleiste.
                Button {
                    NSWorkspace.shared.open(providerURL)
                } label: {
                    HStack(spacing: FamilyTheme.Space.s) {
                        Image(systemName: "safari")
                            .font(.system(size: 12, weight: .semibold))
                        Text(String(localized: "Open Provider Dashboard"))
                            .font(FamilyTheme.font(13, weight: .semibold))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(FamilyTheme.accent)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private var providerURL: URL {
        switch model.provider {
        case .r2:
            return URL(string: "https://dash.cloudflare.com/?to=/:account/r2/overview")!
        case .s3:
            return URL(string: "https://s3.console.aws.amazon.com/s3/home")!
        case .tencentCOS:
            return URL(string: "https://console.cloud.tencent.com/cos")!
        case .aliyunOSS:
            return URL(string: "https://oss.console.aliyun.com/")!
        }
    }

    /// Render `text` with backtick-delimited spans as monospace pills.
    /// Markdown-style **bold** is also recognized.
    private static func attributed(_ raw: String) -> AttributedString {
        // Use SwiftUI's Markdown to handle **bold** and `code`.
        if let parsed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            var result = parsed
            // Visually upgrade the inline code spans
            for run in result.runs where run.inlinePresentationIntent?.contains(.code) == true {
                let range = run.range
                // Code/IDs bewusst Monospace (Design-System, Abschnitt Schrift).
                result[range].font = .system(size: 12, weight: .medium, design: .monospaced)
                result[range].foregroundColor = FamilyTheme.accent
                result[range].backgroundColor = FamilyTheme.accent.opacity(0.10)
            }
            return result
        }
        return AttributedString(raw)
    }
}

// MARK: - Step 4: Credentials

private struct CredentialsStep: View {
    @Bindable var model: CloudShareWizardModel

    @FocusState private var focused: Field?

    enum Field: Hashable {
        case accountID, region, endpoint, pathPrefix, bucket, accessKey, secretKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.l) {
            StepHeader(
                stepLabel: String(localized: "Step 4 — Credentials"),
                title: String(localized: "Paste your credentials"),
                subtitle: String(localized: "These are stored in macOS Keychain on this Mac and never sent anywhere except your bucket.")
            )

            VStack(alignment: .leading, spacing: FamilyTheme.Space.m) {
                if model.provider == .r2 {
                    FieldGroup(
                        label: model.regionLabel,
                        icon: nil,
                        error: model.accountIDError
                    ) {
                        MonoTextField(
                            text: $model.accountID,
                            placeholder: model.regionPlaceholder,
                            secure: false
                        )
                        .focused($focused, equals: .accountID)
                        .onChange(of: focused) { _, newValue in
                            if newValue != .accountID && !model.accountID.isEmpty {
                                model.blurredAccountID = true
                            }
                        }
                    }
                } else {
                    FieldGroup(
                        label: model.regionLabel,
                        icon: nil,
                        error: nil
                    ) {
                        MonoTextField(
                            text: $model.region,
                            placeholder: model.regionPlaceholder,
                            secure: false
                        )
                        .focused($focused, equals: .region)
                    }
                }

                if model.shouldShowEndpoint {
                    FieldGroup(
                        label: String(localized: "Endpoint"),
                        icon: nil,
                        error: model.endpointWarning
                    ) {
                        MonoTextField(
                            text: $model.endpoint,
                            placeholder: model.endpointPlaceholder,
                            secure: false
                        )
                        .focused($focused, equals: .endpoint)
                    }
                }

                FieldGroup(
                    label: String(localized: "Bucket name"),
                    icon: nil,
                    error: model.bucketError
                ) {
                    MonoTextField(
                        text: $model.bucket,
                        placeholder: String(localized: "lowercase, hyphens OK"),
                        secure: false
                    )
                    .focused($focused, equals: .bucket)
                    .onChange(of: focused) { _, newValue in
                        if newValue != .bucket && !model.bucket.isEmpty {
                            model.blurredBucket = true
                        }
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    FieldGroup(
                        label: model.accessKeyLabel,
                        icon: nil,
                        error: model.accessKeyError
                    ) {
                        MonoTextField(
                            text: $model.accessKey,
                            placeholder: String(localized: "32+ characters"),
                            secure: false
                        )
                        .focused($focused, equals: .accessKey)
                        .onChange(of: focused) { _, newValue in
                            if newValue != .accessKey && !model.accessKey.isEmpty {
                                model.blurredAccessKey = true
                            }
                        }
                    }
                    FieldGroup(
                        label: model.secretKeyLabel,
                        icon: "lock.fill",
                        error: nil
                    ) {
                        SecretField(
                            text: $model.secretKey,
                            isRevealed: $model.showSecret,
                            placeholder: String(localized: "Won't be shown again")
                        )
                        .focused($focused, equals: .secretKey)
                    }
                }

                FieldGroup(
                    label: String(localized: "Path prefix"),
                    icon: nil,
                    error: nil
                ) {
                    MonoTextField(
                        text: $model.pathPrefix,
                        placeholder: String(localized: "Optional, e.g. screenshots"),
                        secure: false
                    )
                    .focused($focused, equals: .pathPrefix)
                }
            }

            Spacer(minLength: 8)

            // Trust footer
            HStack(spacing: FamilyTheme.Space.s) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(FamilyTheme.success)
                Text(String(localized: "Stored in Keychain · Encrypted at rest · Never leaves this device"))
                    .font(FamilyTheme.font(11, weight: .medium))
                    .foregroundStyle(FamilyTheme.textSecondary)
            }
        }
    }
}

// MARK: - Step 5: URL prefix + test

private struct URLPrefixStep: View {
    @Bindable var model: CloudShareWizardModel

    // Tracks the in-flight test so a prefix edit can cancel it. Without this,
    // a slow test can write a stale `.success(...)` for the previous prefix.
    @State private var currentTestTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.l) {
            StepHeader(
                stepLabel: String(localized: "Step 5 — Public URL"),
                title: String(localized: "Public URL & test"),
                subtitle: String(localized: "Knippi uses this HTTPS prefix to build the share link after upload. Use your public bucket URL, custom domain, or CDN URL.")
            )

            FieldGroup(
                label: String(localized: "Public URL prefix"),
                icon: "link",
                error: model.prefixError
            ) {
                MonoTextField(
                    text: $model.urlPrefix,
                    placeholder: "https://cdn.example.com",
                    secure: false
                )
                .onChange(of: model.urlPrefix) { _, _ in
                    // Any prefix change invalidates the previous test result —
                    // including in-flight ones. Cancel the running task so the
                    // narrator and `runConnectionTest`'s `Task.isCancelled` guard
                    // both bail without writing a stale state.
                    if model.testState != .idle {
                        model.testState = .idle
                    }
                    currentTestTask?.cancel()
                    currentTestTask = nil
                }
            }

            // Live preview
            VStack(alignment: .leading, spacing: FamilyTheme.Space.s) {
                Text(String(localized: "Final share link will look like"))
                    .font(FamilyTheme.font(11, weight: .semibold))
                    .foregroundStyle(FamilyTheme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                // Link bewusst Monospace (Design-System: Code/IDs).
                Text(previewLink)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(model.urlPrefix.isEmpty ? FamilyTheme.textSecondary : FamilyTheme.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(.horizontal, FamilyTheme.Space.m)
                    .padding(.vertical, FamilyTheme.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .wizardField()
            }

            // Test result panel
            testResultPanel
                .frame(maxWidth: .infinity)

            Spacer(minLength: 4)
        }
    }

    private var previewLink: String {
        let prefix = model.urlPrefix.isEmpty ? "https://<your-prefix>" : ShareConfig.normalizePrefix(model.urlPrefix)
        let key = ShareConfig.normalizePathPrefix(model.pathPrefix) + "2026-04-25-screenshot.png"
        return "\(prefix)/\(key)"
    }

    /// Cancel any in-flight test before launching a new one, and store the new
    /// task handle so a subsequent prefix edit can cancel it.
    private func runTest() {
        currentTestTask?.cancel()
        currentTestTask = Task { await model.runConnectionTest() }
    }

    @ViewBuilder
    private var testResultPanel: some View {
        switch model.testState {
        case .idle:
            HStack {
                Spacer()
                TestButton(
                    label: String(localized: "Test Connection"),
                    icon: "bolt.fill",
                    enabled: model.canTest,
                    style: .primary
                ) {
                    runTest()
                }
            }

        case .validating(let phase):
            HStack(spacing: FamilyTheme.Space.m) {
                ProgressView()
                    .controlSize(.small)
                    .tint(FamilyTheme.accent)
                Text(phase)
                    .font(FamilyTheme.font(12, weight: .medium))
                    .foregroundStyle(FamilyTheme.textPrimary)
                    .id(phase)
                    .transition(.opacity)
                Spacer()
            }
            .padding(.horizontal, FamilyTheme.Space.l)
            .padding(.vertical, FamilyTheme.Space.m)
            .wizardField()
            .animation(.easeInOut(duration: 0.2), value: phase)

        case .success(let dt):
            VStack(alignment: .leading, spacing: FamilyTheme.Space.m) {
                HStack(spacing: FamilyTheme.Space.m) {
                    SuccessCheck(systemName: "checkmark.circle.fill", size: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Connection works."))
                            .font(FamilyTheme.font(13, weight: .semibold))
                            .foregroundStyle(FamilyTheme.textPrimary)
                        Text(String(format: String(localized: "Round-trip in %.1fs · Test file written and removed cleanly."), dt))
                            .font(FamilyTheme.font(11))
                            .foregroundStyle(FamilyTheme.textSecondary)
                    }
                    Spacer()
                    TestButton(
                        label: String(localized: "Re-test"),
                        icon: "arrow.clockwise",
                        enabled: true,
                        style: .secondary
                    ) {
                        runTest()
                    }
                }
            }
            .padding(.horizontal, FamilyTheme.Space.l)
            .padding(.vertical, FamilyTheme.Space.m)
            .wizardNotice(tint: FamilyTheme.success)

        case .failure(let err):
            VStack(alignment: .leading, spacing: FamilyTheme.Space.m) {
                HStack(alignment: .top, spacing: FamilyTheme.Space.m) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(FamilyTheme.warning)
                    VStack(alignment: .leading, spacing: FamilyTheme.Space.xs) {
                        Text(humanize(err).headline)
                            .font(FamilyTheme.font(13, weight: .semibold))
                            .foregroundStyle(FamilyTheme.textPrimary)
                        Text(humanize(err).detail)
                            .font(FamilyTheme.font(11))
                            .foregroundStyle(FamilyTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                HStack {
                    Spacer()
                    TestButton(
                        label: String(localized: "Re-test"),
                        icon: "arrow.clockwise",
                        enabled: true,
                        style: .secondary
                    ) {
                        runTest()
                    }
                }
            }
            .padding(.horizontal, FamilyTheme.Space.l)
            .padding(.vertical, FamilyTheme.Space.m)
            .wizardNotice(tint: FamilyTheme.warning)
        }
    }

    private func humanize(_ err: ShareError) -> (headline: String, detail: String) {
        switch err {
        case .notConfigured:
            return (String(localized: "Configuration is incomplete."),
                    String(localized: "One or more required values are missing. Go back and double-check the previous step."))
        case .invalidCredentials:
            return (String(localized: "Those credentials were rejected."),
                    String(localized: "The storage provider returned an authentication error. Verify the access key, secret, and bucket permissions."))
        case .invalidURLPrefix(let reason):
            return (String(localized: "That URL prefix doesn't look right."),
                    reason)
        case .network(let underlying):
            return (String(localized: "Network error reaching storage."),
                    underlying)
        case .quotaExceeded:
            return (String(localized: "Storage quota exceeded."),
                    String(localized: "Your storage account is at its limit. Free up space or upgrade your provider plan."))
        case .publicAccessUnreachable:
            return (String(localized: "The upload worked, but the file isn't publicly reachable."),
                    String(localized: "The bucket URL is not publicly readable. Enable public access or use a public custom domain, then re-test."))
        case .unknown(let s):
            return (String(localized: "Something went wrong."),
                    s)
        }
    }
}

// MARK: - Step 6: Done

private struct DoneStep: View {
    @Bindable var model: CloudShareWizardModel
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: FamilyTheme.Space.xl) {
            Spacer()
            ZStack {
                // Weiches Erfolgs-Leuchten hinter einer Glaslinse, das Siegel hüpft beim Erscheinen.
                Circle()
                    .fill(FamilyTheme.success.opacity(0.34))
                    .frame(width: 150, height: 150)
                    .blur(radius: 36)
                    .accessibilityHidden(true)
                Color.clear
                    .frame(width: 136, height: 136)
                    .floatingGlassIsland(in: Circle(), tint: FamilyTheme.success.opacity(0.10))
                SuccessCheck(systemName: "checkmark.seal.fill", size: 72)
            }

            Text(String(localized: "Cloud Share is ready"))
                .font(FamilyTheme.font(22, weight: .semibold, relativeTo: .title))
                .foregroundStyle(FamilyTheme.textPrimary)

            Text(String(localized: "Next time you capture a screenshot, click the cloud icon in Quick Access — your share link will be on your clipboard, ready to paste in Slack or Discord."))
                .font(FamilyTheme.font(13))
                .foregroundStyle(FamilyTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, FamilyTheme.Space.xl)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onComplete()
                // Slight delay so the sheet closes first, then capture is invoked.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                    AppDelegate.shared?.captureCoordinator?.captureArea()
                }
            } label: {
                HStack(spacing: FamilyTheme.Space.s) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 12, weight: .semibold))
                    Text(String(localized: "Take a test capture"))
                        .font(FamilyTheme.font(12, weight: .medium))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(FamilyTheme.accent)
            }
            .buttonStyle(.familyGlass(.capsule, size: 32))

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Erfolgs-Häkchen mit einmaligem Hüpfer beim Erscheinen (Bewegung reduzieren: still).
private struct SuccessCheck: View {
    let systemName: String
    let size: CGFloat
    @State private var bounce = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(FamilyTheme.success)
            .symbolEffect(.bounce, options: .nonRepeating, value: bounce)
            .onAppear {
                guard !reduceMotion else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { bounce = true }
            }
            .accessibilityHidden(true)
    }
}

/// Lebender Hintergrund des Assistenten: AmbientBackdrop plus Akzent-Licht oben links, damit
/// die Glas-Kapseln etwas zum Brechen haben (wie in den Einstellungen).
private struct WizardBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            AmbientBackdrop(glow: 1.1)
            if !reduceTransparency && contrast != .increased {
                Ellipse()
                    .fill(FamilyTheme.accent.opacity(colorScheme == .light ? 0.40 : 0.34))
                    .frame(width: 420, height: 200)
                    .blur(radius: 70)
                    .offset(x: 90, y: -90)
                Ellipse()
                    .fill(FamilyTheme.iris.opacity(0.22))
                    .frame(width: 360, height: 240)
                    .blur(radius: 90)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: 100, y: 80)
            }
        }
        .accessibilityHidden(true)
        .ignoresSafeArea()
    }
}

/// Schritt-Leiste als schwebende Glas-Kapsel: erledigte Schritte mit Häkchen, der aktuelle als
/// leuchtende Akzent-Pille mit Nummer, die per matchedGeometryEffect weitergleitet.
/// Nur Anzeige (die Logik des Assistenten bleibt bei Weiter/Zurück).
private struct WizardStepCapsule: View {
    let current: Int
    let total: Int
    @Namespace private var space
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<total, id: \.self) { i in
                ZStack {
                    if i == current {
                        Capsule(style: .continuous)
                            .fill(FamilyTheme.accentFill.gradient)
                            .overlay(Capsule().strokeBorder(.white.opacity(contrast == .increased ? 0.6 : 0.22),
                                                            lineWidth: 0.6))
                            .shadow(color: FamilyTheme.accentFill.opacity(0.45), radius: 7, y: 2)
                            .matchedGeometryEffect(id: "step", in: space)
                    }
                    Group {
                        if i < current {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(FamilyTheme.accent)
                        } else {
                            Text(verbatim: "\(i + 1)")
                                .font(FamilyTheme.font(11, weight: i == current ? .bold : .medium))
                                .foregroundStyle(i == current ? Color.white : FamilyTheme.textSecondary)
                                .monospacedDigit()
                        }
                    }
                }
                .frame(width: i == current ? 38 : 24, height: 24)
            }
        }
        .padding(3)
        .floatingGlassIsland(in: Capsule(style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(current + 1) of \(total)"))
    }
}

// MARK: - Shared helpers / components

private struct StepHeader: View {
    let stepLabel: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.s) {
            Text(stepLabel)
                .font(FamilyTheme.font(11, weight: .semibold))
                .foregroundStyle(FamilyTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Text(title)
                .font(FamilyTheme.font(22, weight: .semibold, relativeTo: .title))
                .foregroundStyle(FamilyTheme.textPrimary)
            Text(subtitle)
                .font(FamilyTheme.font(13))
                .foregroundStyle(FamilyTheme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Feine Trennlinie in der Kartenrand-Farbe (statt Weiß-Transparenz, die im Hellen verschwindet).
private struct WizardDivider: View {
    var body: some View {
        Rectangle().fill(FamilyTheme.cardStroke).frame(height: 0.8)
    }
}

private extension View {
    /// Feste Feldfläche: Karte, Rand, Radius „Feld“ (14).
    func wizardField() -> some View {
        let shape = RoundedRectangle(cornerRadius: FamilyTheme.Radius.field, style: .continuous)
        return background(FamilyTheme.card, in: shape)
            .overlay(shape.strokeBorder(FamilyTheme.cardStroke, lineWidth: 0.8))
    }

    /// Hinweisfläche der Familie: Ton 12 % Fläche + 26 % Rand, Radius 14.
    func wizardNotice(tint: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: FamilyTheme.Radius.field, style: .continuous)
        // Feste Karte darunter, damit der Ton nicht vom Verlauf abhängt.
        return background {
            shape.fill(FamilyTheme.card)
                .overlay(shape.fill(tint.opacity(0.12)))
                .overlay(shape.strokeBorder(tint.opacity(0.26), lineWidth: 0.8))
        }
    }
}

/// Symbol-Kachel (Akzent 14 %, Symbol im Akzent) statt eigenem Farbverlauf.
private struct IconBadge: View {
    let systemName: String

    var body: some View {
        RoundedRectangle(cornerRadius: FamilyTheme.Radius.tile, style: .continuous)
            .fill(FamilyTheme.accent.opacity(0.14))
            .frame(width: 64, height: 64)
            .overlay {
                Image(systemName: systemName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(FamilyTheme.accent)
            }
    }
}

private struct CheckBullet: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: FamilyTheme.Space.m) {
            Circle()
                .fill(FamilyTheme.success.opacity(0.14))
                .frame(width: 24, height: 24)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(FamilyTheme.success)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FamilyTheme.font(13, weight: .semibold))
                    .foregroundStyle(FamilyTheme.textPrimary)
                Text(detail)
                    .font(FamilyTheme.font(12))
                    .foregroundStyle(FamilyTheme.textSecondary)
            }
        }
    }
}

/// Hinweisfläche im App-Akzent.
private struct InfoCard: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: FamilyTheme.Space.s) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(FamilyTheme.accent)
            Text(text)
                .font(FamilyTheme.font(12, weight: .medium))
                .foregroundStyle(FamilyTheme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, FamilyTheme.Space.m)
        .padding(.vertical, FamilyTheme.Space.m)
        .wizardNotice(tint: FamilyTheme.accent)
    }
}

private struct ProviderCard: View {
    let badge: String
    let name: String
    let sub: String
    let pillText: String?
    let selected: Bool
    let enabled: Bool
    let onTap: () -> Void

    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FamilyTheme.Radius.tile, style: .continuous)
        let lifted = hovered && enabled && !reduceMotion
        Button(action: onTap) {
            HStack(spacing: FamilyTheme.Space.m) {
                // Kürzel-Kachel: neutral im App-Akzent statt Markenfarben (keine bunten Kacheln).
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(FamilyTheme.accent.opacity(selected ? 0.20 : 0.10))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Text(badge)
                            .font(FamilyTheme.font(13, weight: .bold))
                            .foregroundStyle(FamilyTheme.accent)
                    }

                VStack(alignment: .leading, spacing: FamilyTheme.Space.xs) {
                    HStack(spacing: FamilyTheme.Space.s) {
                        Text(name)
                            .font(FamilyTheme.font(14, weight: .semibold))
                            .foregroundStyle(FamilyTheme.textPrimary)
                        if let pillText {
                            StatusPill(text: pillText)
                        }
                    }
                    Text(sub)
                        .font(FamilyTheme.font(11))
                        .foregroundStyle(FamilyTheme.textSecondary)
                }
                Spacer()

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? FamilyTheme.accent : FamilyTheme.cardStroke)
            }
            .padding(.horizontal, FamilyTheme.Space.l)
            .padding(.vertical, FamilyTheme.Space.m)
            // Feste Karte (G1) mit weicher Tiefe; Hover hebt sie an, Auswahl leuchtet am Rand.
            .background {
                shape.fill(FamilyTheme.card)
                    .shadow(color: Color(light: 0x1E2846, dark: 0x000000).opacity(lifted ? 0.16 : 0.08),
                            radius: lifted ? 16 : 10, y: lifted ? 7 : 4)
                    .shadow(color: FamilyTheme.accent.opacity(selected ? 0.38 : 0), radius: 12)
            }
            .overlay(
                shape.strokeBorder(selected ? FamilyTheme.accent : FamilyTheme.cardStroke,
                                   lineWidth: selected ? 1.5 : 0.8)
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .scaleEffect(lifted ? 1.012 : 1)
        .offset(y: lifted ? -2 : 0)
        .opacity(enabled ? 1.0 : 0.50)
        .disabled(!enabled)
        .onHover { hovered = $0 && enabled }
        .familyAnimation(FamilyTheme.Motion.hover, value: hovered)
        .familyAnimation(FamilyTheme.Motion.select, value: selected)
    }
}

/// Kleines Etikett („Empfohlen“): Akzent-Umriss, kein zweiter Farbton.
private struct StatusPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(FamilyTheme.font(9, weight: .bold))
            .foregroundStyle(FamilyTheme.accent)
            .tracking(0.6)
            .padding(.horizontal, FamilyTheme.Space.s)
            .padding(.vertical, 2)
            .background(Capsule().fill(FamilyTheme.accent.opacity(0.10)))
            .overlay(Capsule().strokeBorder(FamilyTheme.accent.opacity(0.35), lineWidth: 0.8))
    }
}

private struct NumberedStepRow: View {
    let number: Int
    let title: String
    let detail: AttributedString

    var body: some View {
        HStack(alignment: .top, spacing: FamilyTheme.Space.m) {
            // Number badge
            Circle()
                .fill(FamilyTheme.accent.opacity(0.14))
                .frame(width: 24, height: 24)
                .overlay {
                    Text("\(number)")
                        .font(FamilyTheme.font(12, weight: .bold))
                        .foregroundStyle(FamilyTheme.accent)
                }

            VStack(alignment: .leading, spacing: FamilyTheme.Space.xs) {
                Text(title)
                    .font(FamilyTheme.font(13, weight: .semibold))
                    .foregroundStyle(FamilyTheme.textPrimary)
                Text(detail)
                    .font(FamilyTheme.font(12))
                    .foregroundStyle(FamilyTheme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, FamilyTheme.Space.l)
        .padding(.vertical, FamilyTheme.Space.m)
    }
}

private struct FieldGroup<Content: View>: View {
    let label: String
    let icon: String?
    let error: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: FamilyTheme.Space.s) {
            HStack(spacing: FamilyTheme.Space.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundStyle(FamilyTheme.textSecondary)
                }
                Text(label)
                    .font(FamilyTheme.font(11, weight: .semibold))
                    .foregroundStyle(FamilyTheme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            content
            if let error {
                HStack(alignment: .top, spacing: FamilyTheme.Space.xs) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(FamilyTheme.danger)
                        .padding(.top, 1)
                    Text(error)
                        .font(FamilyTheme.font(11))
                        .foregroundStyle(FamilyTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct MonoTextField: View {
    @Binding var text: String
    let placeholder: String
    let secure: Bool

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        // Schlüssel/IDs bewusst Monospace (Design-System: Code und IDs).
        .font(.system(size: 13, weight: .regular, design: .monospaced))
        .foregroundStyle(FamilyTheme.textPrimary)
        .padding(.horizontal, FamilyTheme.Space.m)
        .padding(.vertical, FamilyTheme.Space.s)
        .wizardField()
    }
}

private struct SecretField: View {
    @Binding var text: String
    @Binding var isRevealed: Bool
    let placeholder: String

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            .foregroundStyle(FamilyTheme.textPrimary)
            .padding(.leading, FamilyTheme.Space.m)
            .padding(.vertical, FamilyTheme.Space.s)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(FamilyTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isRevealed ? String(localized: "Hide secret") : String(localized: "Reveal secret"))
        }
        .wizardField()
    }
}

private enum TestButtonStyle { case primary, secondary }

private struct TestButton: View {
    let label: String
    let icon: String
    let enabled: Bool
    let style: TestButtonStyle
    let action: () -> Void

    var body: some View {
        switch style {
        case .primary:
            button.buttonStyle(.borderedProminent).tint(FamilyTheme.accentFill)
        case .secondary:
            button.buttonStyle(.bordered)
        }
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: FamilyTheme.Space.s) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(FamilyTheme.font(13, weight: .semibold))
            }
        }
        .controlSize(.large)
        .disabled(!enabled)
    }
}

private struct WizardPrimaryButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(FamilyTheme.font(13, weight: .semibold))
                .frame(minWidth: 80)
        }
        .buttonStyle(.borderedProminent)
        .tint(FamilyTheme.accentFill)
        .controlSize(.large)
        .disabled(!isEnabled)
        .keyboardShortcut(.defaultAction)
    }
}

// MARK: - Test runner (shared between wizard step 5 and the configured-state Test button)

@MainActor
enum CloudShareTester {
    static func runTest(
        provider: ShareProvider,
        urlPrefix: String,
        bucket: String,
        fields: [String: String],
        accessKey: String,
        secretKey: String
    ) async -> Result<TimeInterval, ShareError> {
        // Validate the prefix on this side first so the user gets a sharper
        // error message instead of an opaque network failure.
        do {
            try ShareConfig.validatePrefix(urlPrefix)
        } catch let err as ShareError {
            return .failure(err)
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }

        let config = ShareConfig(
            provider: provider,
            urlPrefix: urlPrefix,
            bucket: bucket,
            fields: fields
        )
        let dest: any ShareDestination
        do {
            dest = try ShareDestinationFactory.make(config: config, accessKey: accessKey, secretKey: secretKey)
        } catch let err as ShareError {
            return .failure(err)
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }

        let start = Date()
        do {
            try await dest.validateConfig()
            return .success(Date().timeIntervalSince(start))
        } catch let err as ShareError {
            return .failure(err)
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }
    }
}
