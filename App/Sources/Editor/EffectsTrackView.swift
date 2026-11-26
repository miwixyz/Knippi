import SwiftUI
import EditorKit

struct EffectsTrackView: View {
    @Bindable var coordinator: EditorCoordinator
    @State private var activeDrag: TimelineDragState?

    private let laneHeight: Double = 30
    private let laneGap: Double = 6
    private let handleWidth: Double = 10

    private enum TimelineDragAction: Equatable {
        case move
        case resizeLeading
        case resizeTrailing
    }

    private struct TimelineDragState {
        let id: UUID
        let action: TimelineDragAction
        let startTime: TimeInterval
        let endTime: TimeInterval
    }

    var body: some View {
        GeometryReader { geo in
            let trackWidth = geo.size.width

            VStack(spacing: laneGap) {
                cutLane(trackWidth: trackWidth)
                effectLane(.zoom, title: String(localized: "Zoom"), trackWidth: trackWidth)
                effectLane(.blur, title: String(localized: "Blur"), trackWidth: trackWidth)
            }
            .padding(6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(FamilyTheme.card)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(FamilyTheme.cardStroke, lineWidth: 0.8))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                coordinator.selectedEffectSegmentID = nil
                coordinator.selectedCutRegionID = nil
            }
        }
        .frame(height: laneHeight * 3 + laneGap * 2 + 12)
        .animation(.default, value: coordinator.project.effectSegments.map(\.id))
        .animation(.default, value: coordinator.timelineCuts.map(\.id))
    }

    private func cutLane(trackWidth: Double) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(FamilyTheme.backgroundTop)

            Text("Cut")
                .font(FamilyTheme.font(9, weight: .medium))
                .foregroundStyle(FamilyTheme.textSecondary)
                .padding(.leading, 6)
                .allowsHitTesting(false)

            ForEach(coordinator.timelineCuts) { cut in
                cutSegmentView(cut, trackWidth: trackWidth)
            }
        }
        .frame(height: laneHeight)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { location in
            coordinator.addCut(at: xToTime(location.x, in: trackWidth))
        }
    }

    private func effectLane(_ kind: RecordingEffectKind, title: String, trackWidth: Double) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(FamilyTheme.backgroundTop)

            Text(title)
                .font(FamilyTheme.font(9, weight: .medium))
                .foregroundStyle(FamilyTheme.textSecondary)
                .padding(.leading, 6)
                .allowsHitTesting(false)

            ForEach(Array(effects(of: kind).enumerated()), id: \.element.id) { index, segment in
                effectSegmentView(segment, trackWidth: trackWidth)
                    .transition(
                        .opacity.animation(
                            .easeOut(duration: 0.2).delay(Double(index) * 0.03)
                        )
                    )
            }
        }
        .frame(height: laneHeight)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { location in
            let time = xToTime(location.x, in: trackWidth)
            switch kind {
            case .zoom:
                coordinator.addZoomSegment(at: time)
            case .blur:
                coordinator.addBlurEffect(at: time)
            }
        }
    }

    private func effectSegmentView(_ segment: RecordingEffectSegment, trackWidth: Double) -> some View {
        let startX = timeToX(segment.startTime, in: trackWidth)
        let endX = timeToX(segment.endTime, in: trackWidth)
        let width = max(28, endX - startX)
        let isSelected = coordinator.selectedEffectSegmentID == segment.id
        let color = color(for: segment.kind)

        return ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(color.opacity(isSelected ? 1 : 0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            isSelected ? FamilyTheme.textPrimary : Color.clear,
                            lineWidth: 1.5
                        )
                )

            HStack(spacing: FamilyTheme.Space.xs) {
                Image(systemName: icon(for: segment))
                    .font(.system(size: 9, weight: .semibold))
                Text(label(for: segment))
                    .font(FamilyTheme.font(10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(FamilyTheme.onAccent)
            .allowsHitTesting(false)

            HStack {
                resizeHandle(segment: segment, edge: .leading, trackWidth: trackWidth)
                Spacer()
                resizeHandle(segment: segment, edge: .trailing, trackWidth: trackWidth)
            }
        }
        .frame(width: width, height: laneHeight - 4)
        .offset(x: startX)
        .gesture(dragToMoveGesture(segment: segment, trackWidth: trackWidth))
        .onTapGesture {
            coordinator.selectedEffectSegmentID = segment.id
            coordinator.selectedCutRegionID = nil
        }
        .contextMenu {
            Button("Delete") { coordinator.removeEffectSegment(id: segment.id) }
            if case .zoom = segment.payload {
                Divider()
                Menu("Zoom Level") {
                    ForEach([1.25, 1.5, 1.8, 2.0, 2.5, 3.0], id: \.self) { level in
                        Button(String(format: "%.1fx", level)) {
                            coordinator.setZoomLevel(id: segment.id, level: level)
                        }
                    }
                }
            }
        }
    }

    private func cutSegmentView(_ cut: TrimRegion, trackWidth: Double) -> some View {
        let startX = timeToX(cut.startTime, in: trackWidth)
        let endX = timeToX(cut.endTime, in: trackWidth)
        let width = max(28, endX - startX)
        let isSelected = coordinator.selectedCutRegionID == cut.id

        return ZStack {
            // Schnitt = entfernter Teil → `danger` (statt festem Orange), mit Scheren-Symbol.
            RoundedRectangle(cornerRadius: 5)
                .fill(FamilyTheme.danger.opacity(isSelected ? 1 : 0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            isSelected ? FamilyTheme.textPrimary : Color.clear,
                            lineWidth: 1.5
                        )
                )

            HStack(spacing: FamilyTheme.Space.xs) {
                Image(systemName: "scissors")
                    .font(.system(size: 9, weight: .semibold))
                Text(String(format: "%.1fs", cut.duration))
                    .font(FamilyTheme.font(10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(FamilyTheme.onAccent)
            .allowsHitTesting(false)

            HStack {
                cutResizeHandle(cut: cut, edge: .leading, trackWidth: trackWidth)
                Spacer()
                cutResizeHandle(cut: cut, edge: .trailing, trackWidth: trackWidth)
            }
        }
        .frame(width: width, height: laneHeight - 4)
        .offset(x: startX)
        .gesture(cutDragGesture(cut: cut, trackWidth: trackWidth))
        .onTapGesture {
            coordinator.selectedCutRegionID = cut.id
            coordinator.selectedEffectSegmentID = nil
        }
        .contextMenu {
            Button("Delete") { coordinator.removeTrimRegion(id: cut.id) }
        }
    }

    private func cutResizeHandle(cut: TrimRegion, edge: HorizontalEdge, trackWidth: Double) -> some View {
        resizeHandleChrome(isSelected: coordinator.selectedCutRegionID == cut.id)
            .frame(width: handleWidth, height: laneHeight - 4)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let action: TimelineDragAction = edge == .leading ? .resizeLeading : .resizeTrailing
                        let state = dragState(id: cut.id, action: action, startTime: cut.startTime, endTime: cut.endTime)
                        let delta = timeDelta(for: value.translation.width, in: trackWidth)
                        if edge == .leading {
                            coordinator.resizeCutRegion(id: cut.id, newStart: state.startTime + delta)
                        } else {
                            coordinator.resizeCutRegion(id: cut.id, newEnd: state.endTime + delta)
                        }
                    }
                    .onEnded { _ in activeDrag = nil }
            )
            // pointerStyle instead of NSCursor push/pop: a pop missed when the
            // view goes away mid-hover left the resize cursor stuck.
            .pointerStyle(.columnResize)
    }

    private func cutDragGesture(cut: TrimRegion, trackWidth: Double) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                coordinator.selectedCutRegionID = cut.id
                coordinator.selectedEffectSegmentID = nil
                let state = dragState(id: cut.id, action: .move, startTime: cut.startTime, endTime: cut.endTime)
                coordinator.moveCutRegion(id: cut.id, to: state.startTime + timeDelta(for: value.translation.width, in: trackWidth))
            }
            .onEnded { _ in activeDrag = nil }
    }

    private func resizeHandle(
        segment: RecordingEffectSegment,
        edge: HorizontalEdge,
        trackWidth: Double
    ) -> some View {
        resizeHandleChrome(isSelected: coordinator.selectedEffectSegmentID == segment.id)
            .frame(width: handleWidth, height: laneHeight - 4)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let action: TimelineDragAction = edge == .leading ? .resizeLeading : .resizeTrailing
                        let state = dragState(id: segment.id, action: action, startTime: segment.startTime, endTime: segment.endTime)
                        let delta = timeDelta(for: value.translation.width, in: trackWidth)
                        if edge == .leading {
                            coordinator.resizeEffectSegment(id: segment.id, newStart: state.startTime + delta)
                        } else {
                            coordinator.resizeEffectSegment(id: segment.id, newEnd: state.endTime + delta)
                        }
                    }
                    .onEnded { _ in activeDrag = nil }
            )
            // pointerStyle instead of NSCursor push/pop: a pop missed when the
            // view goes away mid-hover left the resize cursor stuck.
            .pointerStyle(.columnResize)
    }

    private func dragToMoveGesture(segment: RecordingEffectSegment, trackWidth: Double) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                coordinator.selectedEffectSegmentID = segment.id
                coordinator.selectedCutRegionID = nil
                let state = dragState(id: segment.id, action: .move, startTime: segment.startTime, endTime: segment.endTime)
                coordinator.moveEffectSegment(id: segment.id, to: state.startTime + timeDelta(for: value.translation.width, in: trackWidth))
            }
            .onEnded { _ in activeDrag = nil }
    }

    private func resizeHandleChrome(isSelected: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(FamilyTheme.card.opacity(isSelected ? 1 : 0.8))
            .overlay {
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 0.5)
                            .fill(FamilyTheme.accent)
                            .frame(width: 3.5, height: 1)
                    }
                }
            }
            .padding(.vertical, -2)
    }

    private func dragState(
        id: UUID,
        action: TimelineDragAction,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) -> TimelineDragState {
        if let activeDrag, activeDrag.id == id, activeDrag.action == action {
            return activeDrag
        }

        let state = TimelineDragState(id: id, action: action, startTime: startTime, endTime: endTime)
        activeDrag = state
        return state
    }

    private func timeDelta(for xDelta: Double, in width: Double) -> TimeInterval {
        guard width > 0, coordinator.duration > 0 else { return 0 }
        return (xDelta / width) * coordinator.duration
    }

    private func effects(of kind: RecordingEffectKind) -> [RecordingEffectSegment] {
        coordinator.project.effectSegments
            .filter { $0.kind == kind }
            .sorted { $0.startTime < $1.startTime }
    }

    private func color(for kind: RecordingEffectKind) -> Color {
        switch kind {
        // Ein Akzent (Design-System): Zoom und Unschärfe unterscheiden Spur, Symbol und Text.
        // Unschärfe im Schiefer-Grau, damit sie nicht mit Schnitten (`danger`) verwechselt wird.
        case .zoom: FamilyTheme.accentFill
        case .blur: FamilyTheme.textSecondary
        }
    }

    private func icon(for segment: RecordingEffectSegment) -> String {
        switch segment.payload {
        case .zoom(let payload):
            payload.zoomLevel > 1.6 ? "wand.and.stars" : "magnifyingglass"
        case .blur:
            "drop.fill"
        }
    }

    private func label(for segment: RecordingEffectSegment) -> String {
        switch segment.payload {
        case .zoom(let payload):
            String(format: "%.1fx", payload.zoomLevel)
        case .blur:
            String(localized: "Blur")
        }
    }

    private func timeToX(_ time: TimeInterval, in width: Double) -> Double {
        guard coordinator.duration > 0 else { return 0 }
        return (time / coordinator.duration) * width
    }

    private func xToTime(_ x: Double, in width: Double) -> TimeInterval {
        guard width > 0 else { return 0 }
        return (x / width) * coordinator.duration
    }
}
