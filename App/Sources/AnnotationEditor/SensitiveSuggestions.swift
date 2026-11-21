// App/Sources/AnnotationEditor/SensitiveSuggestions.swift
import AppKit
import SwiftUI
import AnnotationKit
import OCRKit

/// "Find Sensitive Data": OCR finds email addresses, phone numbers, IBANs, card
/// numbers and secrets; the editor suggests a black bar for each. Suggestions
/// are overlay UI only — they never enter `AnnotationDocument.objects`, so
/// save, copy, pin and drag (all rendered from `objects`) cannot include them.
@MainActor
@Observable
final class SensitiveSuggestionsModel {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        let rect: CGRect
        let isVerified: Bool
        var isSelected = true
    }

    enum Phase: Equatable {
        case idle
        case scanning
        case showing
    }

    private(set) var phase: Phase = .idle
    private(set) var items: [Item] = []
    private var scanTask: Task<Void, Never>?
    private var generation = 0

    var isScanning: Bool { phase == .scanning }
    var isShowing: Bool { phase == .showing }
    var selectedRects: [CGRect] { items.filter(\.isSelected).map(\.rect) }

    /// Runs OCR on `image` and shows the merged suggestions. Every outcome is
    /// visible: suggestions, a "nothing found" toast, or the error text.
    /// `findRegions` is the OCR step; tests pass a stand-in to hold the scan open.
    func scan(
        image: CGImage,
        screen: NSScreen?,
        findRegions: @escaping @Sendable (CGImage) async throws -> [SensitiveRegion] = {
            try await OCRProcessFallback.sensitiveRegions(image: $0)
        }
    ) {
        guard phase != .scanning else { return }
        cancel()
        generation += 1
        let token = generation
        phase = .scanning
        let imageSize = CGSize(width: image.width, height: image.height)
        scanTask = Task { [weak self] in
            do {
                let regions = try await findRegions(image)
                guard let self, self.generation == token else { return }
                let suggestions = redactionSuggestions(from: regions, imageSize: imageSize)
                if suggestions.isEmpty {
                    self.phase = .idle
                    SensitiveSuggestionsToast.show(
                        String(localized: "No sensitive data found"),
                        icon: "checkmark.circle.fill",
                        color: .systemGreen,
                        screen: screen
                    )
                } else {
                    self.items = suggestions.map { Item(rect: $0.rect, isVerified: $0.isVerified) }
                    self.phase = .showing
                }
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.phase = .idle
                SensitiveSuggestionsToast.show(
                    String(localized: "Finding sensitive data failed: \(error.localizedDescription)"),
                    icon: "exclamationmark.triangle.fill",
                    color: .systemOrange,
                    screen: screen,
                    duration: 4
                )
            }
        }
    }

    func toggle(_ id: Item.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isSelected.toggle()
    }

    /// Removes all suggestions (and drops a scan still in flight).
    func cancel() {
        generation += 1
        scanTask?.cancel()
        scanTask = nil
        items = []
        phase = .idle
    }

    /// Shows suggestions directly (tests; no OCR).
    func show(_ suggestions: [RedactionSuggestion]) {
        cancel()
        items = suggestions.map { Item(rect: $0.rect, isVerified: $0.isVerified) }
        phase = items.isEmpty ? .idle : .showing
    }

    enum ExportReadiness: Equatable {
        /// A scan is still running: nothing may leave the editor (or be cropped)
        /// until its suggestions are known.
        case blockedWhileScanning
        case ready(appliedSuggestions: Bool)
    }

    /// The one gate in front of every export and crop: blocks while scanning,
    /// otherwise blacks out pending suggestions ("over-redact, never leak").
    func prepareForExport(_ document: AnnotationDocument) -> ExportReadiness {
        if isScanning { return .blockedWhileScanning }
        return .ready(appliedSuggestions: applyPendingRedactions(to: document))
    }

    /// Pixelates the selected suggestions in one undo step and clears all
    /// suggestions. Returns true when areas were added.
    @discardableResult
    func applyPendingRedactions(to document: AnnotationDocument) -> Bool {
        guard isShowing else { return false }
        let bars: [any AnnotationObject] = selectedRects.map {
            PixelateObject(
                rect: $0, blockSize: Self.secureBlockSize(for: $0), mode: .pixelate,
                noiseSeed: UInt64.random(in: .min ... .max)
            )
        }
        cancel()
        guard !bars.isEmpty else { return false }
        document.addObjects(bars)
        return true
    }

    /// Block size for pixelating a found text line so it can't be read back.
    ///
    /// Ordinary pixelation (small blocks) can be reversed for text in a known font.
    /// `PixelateObject` renders blocks of twice `blockSize`, so half the line height
    /// leaves a single row of blocks, each about as wide as the line is high (1–2
    /// characters): no glyph shape survives, only the rough length of the text.
    /// Never below the editor's default, so tiny rects don't get finer pixels.
    static func secureBlockSize(for rect: CGRect) -> CGFloat {
        max(12, (rect.height / 2).rounded(.up))
    }
}

/// Outlines over the canvas, in the canvas view's coordinate space
/// (`(imagePoint - canvasOrigin) × zoom`, top-left origin). Clicking one toggles it.
struct SensitiveSuggestionsOverlay: View {
    let model: SensitiveSuggestionsModel
    let zoomScale: CGFloat
    let canvasOrigin: CGPoint

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.allowsHitTesting(false)
            ForEach(model.items) { item in
                suggestion(item)
            }
        }
    }

    private func suggestion(_ item: SensitiveSuggestionsModel.Item) -> some View {
        let frame = CGRect(
            x: (item.rect.minX - canvasOrigin.x) * zoomScale,
            y: (item.rect.minY - canvasOrigin.y) * zoomScale,
            width: item.rect.width * zoomScale,
            height: item.rect.height * zoomScale
        )
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        return Button { model.toggle(item.id) } label: {
            shape
                .fill(FamilyTheme.warning.opacity(item.isSelected ? 0.18 : 0.04))
                .overlay {
                    shape.stroke(
                        FamilyTheme.warning.opacity(item.isSelected ? 1 : 0.55),
                        style: SwiftUI.StrokeStyle(lineWidth: 2, dash: item.isVerified ? [] : [5, 3])
                    )
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, FamilyTheme.warning)
                        .background(Circle().fill(item.isSelected ? Color.clear : Color.black.opacity(0.35)))
                        .offset(x: 7, y: -7)
                }
                .frame(width: max(frame.width, 6), height: max(frame.height, 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: frame.minX, y: frame.minY)
        .help(item.isVerified
              ? String(localized: "Click to keep or skip this area")
              : String(localized: "Possibly sensitive (checksum not confirmed). Click to keep or skip this area"))
        .accessibilityLabel(Text("Sensitive data suggestion"))
        .accessibilityValue(Text(item.isSelected ? String(localized: "Selected") : String(localized: "Not selected")))
        .accessibilityAddTraits(item.isSelected ? .isSelected : [])
    }
}

/// Floating glass bar above the canvas: "N found – Black Out All · Cancel".
struct SensitiveSuggestionsBar: View {
    let model: SensitiveSuggestionsModel
    let onBlackOut: () -> Void

    var body: some View {
        let count = model.selectedRects.count
        HStack(spacing: FamilyTheme.Space.s) {
            Image(systemName: "eye.slash")
                .foregroundStyle(FamilyTheme.warning)
                .accessibilityHidden(true)
            Text("\(count) found")
                .font(FamilyTheme.font(13, weight: .semibold))
                .foregroundStyle(FamilyTheme.textPrimary)
                .monospacedDigit()
            Button(action: onBlackOut) {
                Text("Pixelate All")
                    .font(FamilyTheme.font(13, weight: .semibold))
                    .foregroundStyle(FamilyTheme.onAccent)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 26)
                    .background(Capsule().fill(FamilyTheme.accentFill))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(count == 0)
            .opacity(count == 0 ? 0.45 : 1)
            .keyboardShortcut(.return, modifiers: [.command])
            Button(action: model.cancel) {
                Text("Cancel")
                    .font(FamilyTheme.font(13))
            }
            .buttonStyle(.familyGlass(.capsule))
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .familyTintedGlass(in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Sensitive data suggestions"))
    }
}

@MainActor
enum SensitiveSuggestionsToast {
    private static var current: ToastWindow?

    static func show(_ message: String, icon: String, color: NSColor, screen: NSScreen?, duration: TimeInterval = 2) {
        current?.orderOut(nil)
        let toast = ToastWindow(message: message, icon: icon, iconColor: color, screen: screen)
        current = toast
        toast.show(autoDismissAfter: duration)
    }

    static func showStillScanning(screen: NSScreen?) {
        show(
            String(localized: "Still looking for sensitive data …"),
            icon: "hourglass",
            color: .systemOrange,
            screen: screen
        )
    }

    static func showSuggestionsApplied(screen: NSScreen?) {
        show(
            String(localized: "Selected suggestions were pixelated"),
            icon: "eye.slash.fill",
            color: .systemGreen,
            screen: screen
        )
    }
}
