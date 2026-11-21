// Packages/AnnotationKit/Sources/AnnotationKit/AnnotationDocument.swift
import Foundation
import CoreGraphics
import Observation

@MainActor
@Observable
public final class AnnotationDocument {
    public private(set) var imageSize: CGSize
    public private(set) var objects: [any AnnotationObject] = []
    public private(set) var selectedObjectID: ObjectID?
    public private(set) var cropRect: CGRect?

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    /// Object + property of the style change that pushed the newest undo step; further
    /// changes of the same pair (slider drag) join that step (audit A9, 21.11.).
    private var openStyleChange: (id: ObjectID, property: String)?
    /// Set once the working image was rotated/flipped. That step is not undoable, so it
    /// must count as unsaved work on its own (audit A8, 21.11.).
    private var hasReplacedImage = false

    private struct Snapshot {
        let objects: [any AnnotationObject]
        let cropRect: CGRect?
        let imageSize: CGSize

        /// The same snapshot on a grown/shifted canvas (snapshot objects are private copies).
        func resized(to size: CGSize, offset: CGSize) -> Snapshot {
            if offset != .zero { objects.forEach { $0.move(by: offset) } }
            return Snapshot(objects: objects, cropRect: nil, imageSize: size)
        }
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Whether the document has anything a user would be upset to lose.
    /// `canUndo` is included (not just `objects`/`cropRect`) so that
    /// destructive edits which don't leave visible objects behind — e.g. a
    /// rotate/flip via `replaceImage` — still count as unsaved work.
    public var hasUnsavedChanges: Bool {
        !objects.isEmpty || cropRect != nil || canUndo || hasReplacedImage
    }

    public init(imageSize: CGSize) {
        self.imageSize = imageSize
    }

    public func addObject(_ object: any AnnotationObject) {
        pushUndo()
        objects.append(object)
        selectedObjectID = object.id
    }

    /// Inserts several objects as one undo step without changing the selection
    /// (e.g. blacking out all suggested sensitive regions at once).
    public func addObjects(_ newObjects: [any AnnotationObject]) {
        guard !newObjects.isEmpty else { return }
        pushUndo()
        objects.append(contentsOf: newObjects)
    }

    public func removeObject(id: ObjectID) {
        pushUndo()
        objects.removeAll { $0.id == id }
        if selectedObjectID == id { selectedObjectID = nil }
    }

    public func removeSelected() {
        guard let id = selectedObjectID else { return }
        removeObject(id: id)
    }

    @discardableResult
    public func duplicateSelected(by offset: CGSize) -> Bool {
        guard let selectedObject else { return false }
        let duplicate = selectedObject.copy()
        duplicate.move(by: offset)
        addObject(duplicate)
        return true
    }

    public func selectObject(id: ObjectID?) {
        selectedObjectID = id
        openStyleChange = nil
    }

    public func clearSelection() {
        selectedObjectID = nil
        openStyleChange = nil
    }

    /// Call before restyling an object (colour, width, pattern ...). Books one undo step
    /// per gesture: repeated calls for the same object and property without any other
    /// edit in between (a slider drag) share the first step (audit A9, 21.11.).
    public func beginStyleChange(for id: ObjectID, property: String) {
        if let open = openStyleChange, open.id == id, open.property == property { return }
        pushUndo()
        openStyleChange = (id, property)
    }

    public var selectedObject: (any AnnotationObject)? {
        guard let id = selectedObjectID else { return nil }
        return objects.first { $0.id == id }
    }

    public func objectAt(point: CGPoint, threshold: CGFloat = 8) -> (any AnnotationObject)? {
        for object in objects.reversed() {
            if object.hitTest(point: point, threshold: threshold) {
                return object
            }
        }
        return nil
    }

    public func moveObject(id: ObjectID, by delta: CGSize) {
        guard let obj = objects.first(where: { $0.id == id }) else { return }
        obj.move(by: delta)
    }

    public func beginDrag() {
        pushUndo()
    }

    public func setCropRect(_ rect: CGRect?) {
        pushUndo()
        cropRect = rect
    }

    /// Called after the crop editor replaces the working image (e.g. after
    /// rotate + commit). Updates `imageSize` and sets `cropRect` (in the new
    /// image's coordinates) in one go. Callers are expected to avoid calling
    /// this when `objects` is non-empty — the annotations' coordinates would
    /// be invalidated.
    ///
    /// The undo/redo history is dropped on purpose: the image itself lives in
    /// the view, not in the snapshots, so undoing would restore the old size
    /// and crop on the rotated image and cut out the wrong region. Rotate/flip
    /// is therefore not undoable, but never yields a wrong crop (audit A8, 21.11.).
    public func replaceImage(size: CGSize, cropRect newCropRect: CGRect? = nil) {
        undoStack.removeAll()
        redoStack.removeAll()
        openStyleChange = nil
        imageSize = size
        cropRect = newCropRect
        hasReplacedImage = true
    }

    /// Updates the backing image size while keeping annotation coordinates meaningful.
    /// Used when the visible canvas grows or shifts around already-created objects.
    public func updateImageSizePreservingObjects(size: CGSize, objectOffset: CGSize = .zero) {
        imageSize = size
        cropRect = nil
        // Undo/redo snapshots live in the same canvas: move them along, or Undo would put
        // objects (e.g. a redaction) back at stale coordinates next to what they covered
        // (audit A3, 21.11.).
        undoStack = undoStack.map { $0.resized(to: size, offset: objectOffset) }
        redoStack = redoStack.map { $0.resized(to: size, offset: objectOffset) }
        if objectOffset != .zero {
            for object in objects {
                object.move(by: objectOffset)
            }
        }
    }

    private func currentSnapshot() -> Snapshot {
        Snapshot(objects: objects.map { $0.copy() }, cropRect: cropRect, imageSize: imageSize)
    }

    private func apply(_ snapshot: Snapshot) {
        objects = snapshot.objects
        cropRect = snapshot.cropRect
        imageSize = snapshot.imageSize
        selectedObjectID = nil
    }

    private func pushUndo() {
        undoStack.append(currentSnapshot())
        redoStack.removeAll()
        openStyleChange = nil
    }

    public func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot())
        apply(snapshot)
        openStyleChange = nil
    }

    public func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot())
        apply(snapshot)
        openStyleChange = nil
    }
}
