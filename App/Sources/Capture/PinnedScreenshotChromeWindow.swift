// App/Sources/Capture/PinnedScreenshotChromeWindow.swift
import AppKit

@MainActor
final class PinnedScreenshotChromeWindow: NSPanel {
    let chromeView: PinnedScreenshotChromeView

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(frame: CGRect, activatesApp: Bool = true) {
        chromeView = PinnedScreenshotChromeView(frame: NSRect(origin: .zero, size: frame.size))

        super.init(
            contentRect: frame,
            styleMask: activatesApp ? [.borderless] : [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces]

        chromeView.autoresizingMask = [.width, .height]
        contentView = chromeView
    }

    func sync(to frame: CGRect) {
        setFrame(frame, display: true)
    }
}

/// Weicher Schatten eines angehefteten Bildes nach Familien-Regel: eigenes, um
/// `Floating.edge` größeres Fenster UNTER dem Bild, das keine Klicks annimmt. So wird der
/// Schatten nie an einer Fenstergrenze abgeschnitten, und ein halb durchsichtiges Bild
/// zeigt keinen dunklen Schatten durch sich hindurch (gezeichnet wird nur außerhalb).
@MainActor
final class PinnedScreenshotShadowWindow: NSPanel {
    /// Rand größer als Schattenradius + Versatz (18 + 8), sonst schnitte das Fenster ihn ab.
    static let edge: CGFloat = 36
    static let cornerRadius: CGFloat = PinnedScreenshotContentView.cornerRadius

    private let shadowLayer = CAShapeLayer()
    private let maskLayer = CAShapeLayer()

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(imageFrame: CGRect, activatesApp: Bool = true) {
        super.init(
            contentRect: imageFrame.insetBy(dx: -Self.edge, dy: -Self.edge),
            styleMask: activatesApp ? [.borderless] : [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces]

        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.addSublayer(shadowLayer)
        shadowLayer.fillColor = NSColor.black.cgColor
        // Weich wie die Familien-Schwebeflächen, für ein großes Bild kräftiger (0,22 war auf
        // hellem Grund kaum zu sehen, gemessen 26.11.).
        shadowLayer.shadowColor = NSColor(srgbRed: 0.08, green: 0.10, blue: 0.16, alpha: 1).cgColor
        shadowLayer.shadowOpacity = 0.34
        shadowLayer.shadowRadius = 18
        shadowLayer.shadowOffset = CGSize(width: 0, height: -8)
        shadowLayer.mask = maskLayer
        maskLayer.fillRule = .evenOdd
        contentView = view
        layoutShadow()
    }

    func sync(to imageFrame: CGRect) {
        setFrame(imageFrame.insetBy(dx: -Self.edge, dy: -Self.edge), display: false)
        layoutShadow()
    }

    private func layoutShadow() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bounds = CGRect(origin: .zero, size: frame.size)
        let imageRect = bounds.insetBy(dx: Self.edge, dy: Self.edge)
        let imagePath = CGPath(roundedRect: imageRect, cornerWidth: Self.cornerRadius,
                               cornerHeight: Self.cornerRadius, transform: nil)
        shadowLayer.frame = bounds
        shadowLayer.path = imagePath
        shadowLayer.shadowPath = imagePath
        // Nur außerhalb des Bildes zeichnen: Rahmen minus Bildfläche (gerade-ungerade).
        let mask = CGMutablePath()
        mask.addRect(bounds)
        mask.addPath(imagePath)
        maskLayer.frame = bounds
        maskLayer.path = mask
        CATransaction.commit()
    }
}
