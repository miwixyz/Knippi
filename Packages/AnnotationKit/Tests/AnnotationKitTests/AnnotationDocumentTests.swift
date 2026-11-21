// Packages/AnnotationKit/Tests/AnnotationKitTests/AnnotationDocumentTests.swift
import Testing
import Foundation
import CoreGraphics
@testable import AnnotationKit

@Suite("AnnotationDocument")
struct AnnotationDocumentTests {
    @Test("Add and remove objects")
    @MainActor
    func addRemove() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let arrow = ArrowObject(start: .zero, end: CGPoint(x: 100, y: 100))
        doc.addObject(arrow)
        #expect(doc.objects.count == 1)
        doc.removeObject(id: arrow.id)
        #expect(doc.objects.count == 0)
    }

    /// Audit A3 (21.11.): growing the All-in-One selection to the left/top moved the current
    /// objects but not the undo snapshots; Undo put a redaction next to the secret it covered.
    @Test("Undo after growing the canvas keeps objects where the content is")
    @MainActor
    func undoAfterCanvasGrowKeepsPositions() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 200, height: 100))
        let first = RectangleObject(rect: CGRect(x: 10, y: 10, width: 20, height: 20))
        doc.addObject(first)
        doc.addObject(RectangleObject(rect: CGRect(x: 60, y: 10, width: 20, height: 20)))

        doc.updateImageSizePreservingObjects(size: CGSize(width: 250, height: 130), objectOffset: CGSize(width: 50, height: 30))
        doc.undo()

        #expect(doc.objects.count == 1)
        #expect(doc.objects.first?.bounds.origin == CGPoint(x: 60, y: 40))
        #expect(doc.imageSize == CGSize(width: 250, height: 130))
    }

    @Test("A discarded click on a full history keeps all 100 steps")
    @MainActor
    func discardedClickKeepsFullHistory() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        for i in 0..<(AnnotationDocument.maxUndoSteps + 5) {
            doc.addObject(RectangleObject(rect: CGRect(x: i, y: 0, width: 4, height: 4)))
        }
        let selected = doc.objects[0]
        doc.beginDrag()          // tentative step from a plain click …
        doc.discardUnchangedStep() // … that changed nothing
        _ = selected
        var undos = 0
        while doc.canUndo { doc.undo(); undos += 1 }
        #expect(undos == AnnotationDocument.maxUndoSteps)
    }

    @Test("Undo and redo add")
    @MainActor
    func undoRedo() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let arrow = ArrowObject(start: .zero, end: CGPoint(x: 100, y: 100))
        doc.addObject(arrow)
        #expect(doc.objects.count == 1)
        #expect(doc.canUndo)

        doc.undo()
        #expect(doc.objects.count == 0)
        #expect(doc.canRedo)

        doc.redo()
        #expect(doc.objects.count == 1)
    }

    @Test("Selection")
    @MainActor
    func selection() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let arrow = ArrowObject(start: .zero, end: CGPoint(x: 100, y: 100))
        doc.addObject(arrow)
        doc.selectObject(id: arrow.id)
        #expect(doc.selectedObjectID == arrow.id)
        doc.clearSelection()
        #expect(doc.selectedObjectID == nil)
    }

    @Test("cropRect starts nil")
    @MainActor
    func cropRectDefaultNil() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        #expect(doc.cropRect == nil)
    }

    @Test("setCropRect updates value and pushes undo")
    @MainActor
    func setCropRectUndo() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let rect = CGRect(x: 100, y: 50, width: 400, height: 300)
        doc.setCropRect(rect)
        #expect(doc.cropRect == rect)
        #expect(doc.canUndo)

        doc.undo()
        #expect(doc.cropRect == nil)
        #expect(doc.canRedo)

        doc.redo()
        #expect(doc.cropRect == rect)
    }

    @Test("setCropRect with nil clears the crop")
    @MainActor
    func clearCropRect() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        doc.setCropRect(CGRect(x: 0, y: 0, width: 100, height: 100))
        doc.setCropRect(nil)
        #expect(doc.cropRect == nil)
    }

    @Test("undo restores objects AND cropRect together")
    @MainActor
    func undoRestoresBothObjectsAndCrop() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let arrow = ArrowObject(start: .zero, end: CGPoint(x: 50, y: 50))
        doc.addObject(arrow)
        doc.setCropRect(CGRect(x: 10, y: 10, width: 100, height: 100))

        #expect(doc.objects.count == 1)
        #expect(doc.cropRect != nil)

        doc.undo()
        #expect(doc.objects.count == 1)
        #expect(doc.cropRect == nil)

        doc.undo()
        #expect(doc.objects.count == 0)
        #expect(doc.cropRect == nil)
    }

    @Test("Update image size preserves and offsets objects without pushing undo")
    @MainActor
    func updateImageSizePreservesObjects() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 400, height: 300))
        let line = LineObject(start: CGPoint(x: 20, y: 30), end: CGPoint(x: 120, y: 30))
        doc.addObject(line)
        doc.setCropRect(CGRect(x: 5, y: 5, width: 50, height: 50))
        doc.undo()
        #expect(doc.canUndo)

        doc.updateImageSizePreservingObjects(
            size: CGSize(width: 520, height: 380),
            objectOffset: CGSize(width: 15, height: 25)
        )

        #expect(doc.imageSize == CGSize(width: 520, height: 380))
        #expect(doc.cropRect == nil)
        let movedLine = doc.objects[0] as? LineObject
        #expect(movedLine?.start == CGPoint(x: 35, y: 55))
        #expect(movedLine?.end == CGPoint(x: 135, y: 55))

        doc.undo()
        #expect(doc.objects.count == 0)
    }

    @Test("Fresh document has no unsaved changes")
    @MainActor
    func freshDocumentIsClean() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        #expect(doc.hasUnsavedChanges == false)
    }

    @Test("Adding an object marks the document dirty")
    @MainActor
    func addObjectMarksDirty() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        doc.addObject(ArrowObject(start: .zero, end: CGPoint(x: 100, y: 100)))
        #expect(doc.hasUnsavedChanges == true)
    }

    @Test("Undoing back to the start is clean again")
    @MainActor
    func undoBackToCleanIsClean() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        doc.addObject(ArrowObject(start: .zero, end: CGPoint(x: 100, y: 100)))
        doc.undo()
        #expect(doc.hasUnsavedChanges == false)
    }

    @Test("Adding then removing the object stays dirty")
    @MainActor
    func addThenRemoveStaysDirty() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let arrow = ArrowObject(start: .zero, end: CGPoint(x: 100, y: 100))
        doc.addObject(arrow)
        doc.removeObject(id: arrow.id)
        #expect(doc.hasUnsavedChanges == true)
    }

    @Test("Setting a crop rect marks the document dirty")
    @MainActor
    func cropRectMarksDirty() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        doc.setCropRect(CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(doc.hasUnsavedChanges == true)
        doc.undo()
        #expect(doc.hasUnsavedChanges == false)
    }

    @Test("Replacing the image (rotate/flip) marks the document dirty")
    @MainActor
    func replaceImageMarksDirty() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        doc.replaceImage(size: CGSize(width: 600, height: 800))
        #expect(doc.hasUnsavedChanges == true)
    }

    @Test("addObjects inserts all and undoes in one step")
    @MainActor
    func batchInsertSingleUndo() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 100, height: 100))
        let a = PixelateObject(rect: CGRect(x: 0, y: 0, width: 4, height: 4), mode: .solid)
        let b = PixelateObject(rect: CGRect(x: 8, y: 0, width: 4, height: 4), mode: .solid)
        doc.addObjects([a, b])
        #expect(doc.objects.count == 2)
        #expect(doc.selectedObjectID == nil)
        doc.undo()
        #expect(doc.objects.isEmpty)
        #expect(!doc.canUndo)
    }

    @Test("addObjects with an empty array pushes no undo step")
    @MainActor
    func batchInsertEmptyIsNoop() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 100, height: 100))
        doc.addObjects([])
        #expect(!doc.canUndo)
    }

    /// Audit A8 (21.11.): rotate + crop used to book two undo steps; undo restored the
    /// old crop rect/size while the view kept the rotated image -> wrong cut-out.
    /// Replacing the image now drops the history (rotate is not undoable) and sets the
    /// crop in the same call.
    @Test("replaceImage clears undo/redo history and applies the crop in one go")
    @MainActor
    func replaceImageClearsHistory() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        doc.setCropRect(CGRect(x: 10, y: 10, width: 100, height: 50))
        let crop = CGRect(x: 5, y: 5, width: 40, height: 80)
        doc.replaceImage(size: CGSize(width: 600, height: 800), cropRect: crop)
        #expect(doc.imageSize == CGSize(width: 600, height: 800))
        #expect(doc.cropRect == crop)
        #expect(!doc.canUndo)
        #expect(!doc.canRedo)
        doc.undo()
        #expect(doc.imageSize == CGSize(width: 600, height: 800))
        #expect(doc.cropRect == crop)
    }

    @Test("Replaced image stays dirty even with an empty history")
    @MainActor
    func replaceImageWithoutHistoryStaysDirty() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        doc.replaceImage(size: CGSize(width: 600, height: 800), cropRect: nil)
        #expect(!doc.canUndo)
        #expect(doc.hasUnsavedChanges)
    }

    /// Audit A9 (21.11.): restyling the selected object booked no undo step, so Cmd-Z
    /// right after a colour change removed the whole freshly drawn object.
    @Test("Style change books its own undo step")
    @MainActor
    func styleChangeIsUndoable() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let arrow = ArrowObject(start: .zero, end: CGPoint(x: 100, y: 100))
        doc.addObject(arrow)
        doc.beginStyleChange(for: arrow.id, property: "color")
        arrow.style.color = .blue
        doc.undo()
        #expect(doc.objects.count == 1)
        #expect(doc.objects.first?.style.color == .red)
        doc.undo()
        #expect(doc.objects.isEmpty)
    }

    @Test("Repeated changes of one property on one object coalesce (slider drag)")
    @MainActor
    func sliderChangesCoalesce() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let arrow = ArrowObject(start: .zero, end: CGPoint(x: 100, y: 100))
        doc.addObject(arrow)
        for width in stride(from: 4.0, through: 20.0, by: 1.0) {
            doc.beginStyleChange(for: arrow.id, property: "lineWidth")
            arrow.style.lineWidth = width
        }
        doc.undo()
        #expect(doc.objects.count == 1)
        #expect(doc.objects.first?.style.lineWidth == 3)
        doc.undo()
        #expect(doc.objects.isEmpty)
    }

    @Test("A different property or object starts a new style step")
    @MainActor
    func styleStepsSplitOnPropertyOrObject() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let a = ArrowObject(start: .zero, end: CGPoint(x: 100, y: 100))
        let b = ArrowObject(start: .zero, end: CGPoint(x: 50, y: 50))
        doc.addObject(a)
        doc.addObject(b)
        doc.beginStyleChange(for: b.id, property: "color")
        b.style.color = .blue
        doc.beginStyleChange(for: b.id, property: "lineWidth")
        b.style.lineWidth = 9
        doc.beginStyleChange(for: a.id, property: "lineWidth")
        a.style.lineWidth = 9
        doc.undo() // a width
        #expect(doc.objects[0].style.lineWidth == 3)
        #expect(doc.objects[1].style.lineWidth == 9)
        doc.undo() // b width
        #expect(doc.objects[1].style.lineWidth == 3)
        #expect(doc.objects[1].style.color == .blue)
        doc.undo() // b color
        #expect(doc.objects[1].style.color == .red)
        #expect(doc.objects.count == 2)
    }

    @Test("Another edit in between ends the coalescing")
    @MainActor
    func otherEditEndsCoalescing() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let arrow = ArrowObject(start: .zero, end: CGPoint(x: 100, y: 100))
        doc.addObject(arrow)
        doc.beginStyleChange(for: arrow.id, property: "lineWidth")
        arrow.style.lineWidth = 5
        doc.beginDrag()
        arrow.move(by: CGSize(width: 10, height: 0))
        doc.beginStyleChange(for: arrow.id, property: "lineWidth")
        arrow.style.lineWidth = 7
        doc.undo()
        #expect(doc.objects.first?.style.lineWidth == 5)
    }

    @Test("A drag that changed nothing leaves no undo step and keeps redo (audit A10)")
    @MainActor
    func unchangedDragIsDiscarded() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        doc.addObject(RectangleObject(rect: CGRect(x: 0, y: 0, width: 10, height: 10)))
        doc.addObject(RectangleObject(rect: CGRect(x: 20, y: 0, width: 10, height: 10)))
        doc.undo()
        #expect(doc.canRedo)
        doc.beginDrag()          // plain click on the remaining object to select it
        doc.discardUnchangedStep()
        #expect(doc.canRedo)
        doc.redo()
        #expect(doc.objects.count == 2)
        doc.undo()
        doc.undo()
        #expect(doc.objects.isEmpty)
        #expect(!doc.canUndo)
    }

    @Test("Discarding after another edit does nothing")
    @MainActor
    func discardAfterOtherEditIsNoOp() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let a = RectangleObject(rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        doc.beginDrag()
        doc.addObject(a)
        doc.discardUnchangedStep()
        #expect(doc.objects.count == 1)
        doc.undo()
        #expect(doc.objects.isEmpty)
    }

    @Test("A joined style change can't be discarded, a fresh unchanged one can")
    @MainActor
    func styleChangeDiscard() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        let arrow = ArrowObject(start: .zero, end: CGPoint(x: 100, y: 100))
        doc.addObject(arrow)
        #expect(doc.beginStyleChange(for: arrow.id, property: "color"))
        arrow.style.color = .blue
        // Preset: the next control's onChange finds everything already applied.
        let before = AnnotationStyleState(of: arrow)
        #expect(doc.beginStyleChange(for: arrow.id, property: "filled"))
        #expect(AnnotationStyleState(of: arrow) == before)
        doc.discardUnchangedStep()
        // Same property again joins the open colour step.
        #expect(!doc.beginStyleChange(for: arrow.id, property: "color"))
        doc.undo()
        #expect(arrow.style.color == .blue) // undo restores a copy, check the document
        #expect(doc.objects.first?.style.color == .red)
        doc.undo()
        #expect(doc.objects.isEmpty)
    }

    @Test("Undo history is capped (audit A20)")
    @MainActor
    func undoHistoryIsCapped() {
        let doc = AnnotationDocument(imageSize: CGSize(width: 800, height: 600))
        for i in 0..<(AnnotationDocument.maxUndoSteps + 20) {
            doc.addObject(RectangleObject(rect: CGRect(x: CGFloat(i), y: 0, width: 5, height: 5)))
        }
        var steps = 0
        while doc.canUndo { doc.undo(); steps += 1 }
        #expect(steps == AnnotationDocument.maxUndoSteps)
        #expect(doc.objects.count == 20)
    }
}
