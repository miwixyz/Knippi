// Packages/EditorKit/Tests/EditorKitTests/FrameCompositorTests.swift

import Testing
import Foundation
import CoreImage
import CoreGraphics
@testable import EditorKit

@Suite("FrameCompositor")
struct FrameCompositorTests {

    private func makeTestImage(width: Int = 1920, height: Int = 1080, color: CIColor = .red) -> CIImage {
        CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    private func renderedBytes(_ image: CIImage, width: Int, height: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        CIContext().render(
            image,
            toBitmap: &bytes,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return bytes
    }

    @Test("Identity transform returns image with same dimensions")
    func identityTransform() {
        let source = makeTestImage()
        let compositor = FrameCompositor(
            sourceSize: CGSize(width: 1920, height: 1080),
            backgroundStyle: BackgroundStyle(enabled: false),
            outputScale: 1.0
        )
        let result = compositor.compose(frame: source, zoomTransform: .identity, cursorPosition: nil, cursorImage: nil)
        #expect(result.extent.width == 1920)
        #expect(result.extent.height == 1080)
    }

    @Test("Zoom transform produces same-size output")
    func zoomTransform() {
        let source = makeTestImage()
        let compositor = FrameCompositor(
            sourceSize: CGSize(width: 1920, height: 1080),
            backgroundStyle: BackgroundStyle(enabled: false),
            outputScale: 1.0
        )
        // translateX/Y = focus point in normalized 0-1 coords; 0.5 = center
        let zoom = FrameTransform(scale: 2.0, translateX: 0.5, translateY: 0.5)
        let result = compositor.compose(frame: source, zoomTransform: zoom, cursorPosition: nil, cursorImage: nil)
        #expect(result.extent.width == 1920)
        #expect(result.extent.height == 1080)
    }

    @Test("Background enabled produces larger output with padding")
    func backgroundWithPadding() {
        let source = makeTestImage(width: 1920, height: 1080)
        let style = BackgroundStyle(enabled: true, padding: 40, cornerRadius: 12, shadowEnabled: false, shadowRadius: 0, shadowOpacity: 0)
        let compositor = FrameCompositor(sourceSize: CGSize(width: 1920, height: 1080), backgroundStyle: style, outputScale: 1.0)
        let result = compositor.compose(frame: source, zoomTransform: .identity, cursorPosition: nil, cursorImage: nil)
        #expect(result.extent.width == 2000)
        #expect(result.extent.height == 1160)
    }

    @Test("Background disabled returns source dimensions")
    func backgroundDisabled() {
        let source = makeTestImage(width: 800, height: 600)
        let style = BackgroundStyle(enabled: false, padding: 40)
        let compositor = FrameCompositor(sourceSize: CGSize(width: 800, height: 600), backgroundStyle: style, outputScale: 1.0)
        let result = compositor.compose(frame: source, zoomTransform: .identity, cursorPosition: nil, cursorImage: nil)
        #expect(result.extent.width == 800)
        #expect(result.extent.height == 600)
    }

    @Test("Output dimensions are even numbers for video encoding")
    func evenDimensions() {
        let source = makeTestImage(width: 801, height: 601)
        let style = BackgroundStyle(enabled: true, padding: 15)
        let compositor = FrameCompositor(sourceSize: CGSize(width: 801, height: 601), backgroundStyle: style, outputScale: 1.0)
        let result = compositor.compose(frame: source, zoomTransform: .identity, cursorPosition: nil, cursorImage: nil)
        #expect(Int(result.extent.width) % 2 == 0)
        #expect(Int(result.extent.height) % 2 == 0)
    }

    @Test("Output size is computed correctly")
    func outputSizeComputation() {
        let style = BackgroundStyle(enabled: true, padding: 20)
        let compositor = FrameCompositor(sourceSize: CGSize(width: 1920, height: 1080), backgroundStyle: style, outputScale: 1.0)
        let size = compositor.outputSize
        #expect(size.width == 1960)
        #expect(size.height == 1120)
    }

    @Test("Output size without background equals source size")
    func outputSizeNoBackground() {
        let style = BackgroundStyle(enabled: false)
        let compositor = FrameCompositor(sourceSize: CGSize(width: 1920, height: 1080), backgroundStyle: style, outputScale: 1.0)
        let size = compositor.outputSize
        #expect(size.width == 1920)
        #expect(size.height == 1080)
    }

    @Test("Blur effect changes only while active")
    func blurEffectChangesOnlyWhileActive() {
        let base = CIImage(color: .white)
            .cropped(to: CGRect(x: 0, y: 0, width: 120, height: 80))
        let centerBlock = CIImage(color: .black)
            .cropped(to: CGRect(x: 46, y: 26, width: 28, height: 28))
        let source = centerBlock.composited(over: base)
        let effect = RecordingEffectSegment(
            startTime: 1,
            endTime: 3,
            payload: .blur(
                BlurEffectPayload(
                    rect: NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                    radius: 12
                )
            )
        )
        let compositor = FrameCompositor(
            sourceSize: CGSize(width: 120, height: 80),
            backgroundStyle: BackgroundStyle(enabled: false),
            outputScale: 1.0
        )

        let inactive = compositor.compose(
            frame: source,
            zoomTransform: .identity,
            cursorPosition: nil,
            cursorImage: nil,
            blurEffects: [effect],
            time: 0.5
        )
        let active = compositor.compose(
            frame: source,
            zoomTransform: .identity,
            cursorPosition: nil,
            cursorImage: nil,
            blurEffects: [effect],
            time: 2
        )

        #expect(inactive.extent == source.extent)
        #expect(active.extent == source.extent)
        #expect(
            renderedBytes(active, width: 120, height: 80) !=
                renderedBytes(inactive, width: 120, height: 80)
        )
    }

    // The blur rect lives in source coordinates, so it must be applied before
    // the zoom; otherwise zooming moves the hidden content out from under it
    // (audit E2, 21.11.).
    @Test("Blur stays on the hidden content while zoomed")
    func blurFollowsContentUnderZoom() {
        let width = 200, height = 100
        let base = CIImage(color: .white)
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        // Secret: 2 px black/white stripes at x 20..60, CI y 50..90
        // (screen-normalized x 0.1..0.3, y 0.1..0.5).
        var secret = CIImage.empty()
        for x in stride(from: 20, to: 60, by: 4) {
            secret = CIImage(color: .black)
                .cropped(to: CGRect(x: x, y: 50, width: 2, height: 40))
                .composited(over: secret)
        }
        let source = secret.composited(over: base)
        let effect = RecordingEffectSegment(
            startTime: 0,
            endTime: 10,
            payload: .blur(BlurEffectPayload(
                rect: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.4),
                radius: 10
            ))
        )
        let compositor = FrameCompositor(
            sourceSize: CGSize(width: width, height: height),
            backgroundStyle: BackgroundStyle(enabled: false),
            outputScale: 1.0
        )
        // 2x zoom centred on the secret: it now fills output x 60..140, y 10..90.
        let result = compositor.compose(
            frame: source,
            zoomTransform: FrameTransform(scale: 2, translateX: 0.2, translateY: 0.3),
            cursorPosition: nil,
            cursorImage: nil,
            blurEffects: [effect],
            time: 1
        )
        let bytes = renderedBytes(result, width: width, height: height)
        // Row 50 in bitmap rows (top-down) is the vertical middle of the secret.
        let row = 50
        let lumas = (80..<120).map { bytes[(row * width + $0) * 4 + 1] }
        let spread = Int(lumas.max()!) - Int(lumas.min()!)
        #expect(spread < 80, "Stripes under the blur must not be readable, spread \(spread)")
    }

    @Test("Rounded corners still mask the frame")
    func roundedCornersMaskFrame() {
        var style = BackgroundStyle(enabled: true)
        style.padding = 10
        style.cornerRadius = 20
        style.shadowEnabled = false
        style.colorType = .solid
        style.solidColor = .init(red: 0, green: 0, blue: 1, alpha: 1)
        let compositor = FrameCompositor(
            sourceSize: CGSize(width: 100, height: 80),
            backgroundStyle: style,
            outputScale: 1.0
        )
        let out = compositor.outputSize
        let w = Int(out.width), h = Int(out.height)
        for _ in 0..<2 {
            let result = compositor.compose(
                frame: makeTestImage(width: 100, height: 80, color: .red),
                zoomTransform: .identity,
                cursorPosition: nil,
                cursorImage: nil
            )
            let bytes = renderedBytes(result, width: w, height: h)
            func px(_ x: Int, _ y: Int) -> (UInt8, UInt8) {
                let i = (y * w + x) * 4
                return (bytes[i], bytes[i + 2])
            }
            // Frame corner pixel is masked away (background blue shows) …
            #expect(px(11, 11).0 < 50 && px(11, 11).1 > 200)
            // … while the frame centre is red.
            #expect(px(w / 2, h / 2).0 > 200 && px(w / 2, h / 2).1 < 50)
        }
    }

    @Test("Without zoom the cursor is drawn where it was", arguments: [
        CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.8, y: 0.75),
    ])
    func cursorPlacedWithoutZoom(position: CGPoint) {
        let (width, height) = (400, 200)
        let compositor = FrameCompositor(sourceSize: CGSize(width: width, height: height), backgroundStyle: BackgroundStyle(enabled: false), outputScale: 1)
        let cursor = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        let result = compositor.compose(frame: makeTestImage(width: width, height: height, color: .black),
                                        zoomTransform: .identity, cursorPosition: position, cursorImage: cursor)
        let bytes = renderedBytes(result, width: width, height: height)
        var xs: [Int] = [], ys: [Int] = []
        for row in 0..<height { for x in 0..<width where bytes[(row * width + x) * 4] > 200 {
            xs.append(x); ys.append(row)  // bitmap rows run top to bottom, like the normalized position
        } }
        #expect(!xs.isEmpty, "cursor not drawn inside the frame")
        guard !xs.isEmpty else { return }
        let centre = (x: Double(xs.min()! + xs.max()!) / 2, y: Double(ys.min()! + ys.max()!) / 2)
        #expect(abs(centre.x - position.x * Double(width)) < 10, "x \(centre.x)")
        #expect(abs(centre.y - position.y * Double(height)) < 10, "y \(centre.y)")
    }

    @Test("The click ripple is drawn centred where the cursor is")
    func rippleUnderCursor() {
        let (width, height) = (400, 200)
        let compositor = FrameCompositor(sourceSize: CGSize(width: width, height: height), backgroundStyle: BackgroundStyle(enabled: false), outputScale: 1)
        let ripple = CIImage(color: .green).cropped(to: CGRect(x: -10, y: -10, width: 20, height: 20))
        let result = compositor.compose(frame: makeTestImage(width: width, height: height, color: .black),
                                        zoomTransform: .identity, cursorPosition: CGPoint(x: 0.25, y: 0.5),
                                        cursorImage: nil, clickRipple: ripple)
        let bytes = renderedBytes(result, width: width, height: height)
        var xs: [Int] = [], ys: [Int] = []
        for row in 0..<height { for x in 0..<width where bytes[(row * width + x) * 4 + 1] > 200 { xs.append(x); ys.append(row) } }
        #expect(!xs.isEmpty)
        guard !xs.isEmpty else { return }
        #expect(abs(Double(xs.min()! + xs.max()!) / 2 - 100) < 2)
        #expect(abs(Double(ys.min()! + ys.max()!) / 2 - 100) < 2)
    }

    @Test("Gradient angle maps to the same unit points the preview draws", arguments: [
        (0.0, CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5)),
        (90.0, CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1)),
        (135.0, CGPoint(x: 0.854, y: 0.146), CGPoint(x: 0.146, y: 0.854)),
    ])
    func gradientUnitPoints(angle: Double, start: CGPoint, end: CGPoint) {
        let points = BackgroundStyle(gradientAngle: angle).gradientUnitPoints
        #expect(abs(points.start.x - start.x) < 0.001 && abs(points.start.y - start.y) < 0.001, "start \(points.start)")
        #expect(abs(points.end.x - end.x) < 0.001 && abs(points.end.y - end.y) < 0.001, "end \(points.end)")
    }

    @Test("Exported 135° gradient runs from the top-right corner to the bottom-left")
    func exportedGradientDirection() {
        let style = BackgroundStyle(
            enabled: true, colorType: .gradient,
            gradientFrom: CodableColor(red: 0, green: 0, blue: 0), gradientTo: CodableColor(red: 1, green: 1, blue: 1),
            gradientAngle: 135, padding: 40, cornerRadius: 0, shadowEnabled: false
        )
        let compositor = FrameCompositor(sourceSize: CGSize(width: 200, height: 100), backgroundStyle: style, outputScale: 1)
        let result = compositor.compose(frame: makeTestImage(width: 200, height: 100),
                                        zoomTransform: .identity, cursorPosition: nil, cursorImage: nil)
        let (width, height) = (Int(result.extent.width), Int(result.extent.height))
        let bytes = renderedBytes(result, width: width, height: height)
        func luma(_ x: Int, _ row: Int) -> UInt8 { bytes[(row * width + x) * 4 + 1] }
        let topRight = luma(width - 2, 1), bottomLeft = luma(1, height - 2)
        #expect(topRight < 40, "top-right should hold the start colour, got \(topRight)")
        #expect(bottomLeft > 215, "bottom-left should hold the end colour, got \(bottomLeft)")
    }
}
