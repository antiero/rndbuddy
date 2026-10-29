import SwiftUI

/// Places the current page's controls on the layout class's grid.
struct PerformanceLayer: View {
    @Bindable var model: AppModel
    let layout: LayoutClass
    /// Swallow touches between controls so stray taps don't reach Pixels.
    var blocksBackground = true
    var body: some View {
        let page = model.performance.page
        let flow = PerformanceLayout.flow(page, in: layout)
        let grid = layout.grid
        GeometryReader { geometry in
            let cell = CGSize(width: geometry.size.width / CGFloat(grid.columns), height: geometry.size.height / CGFloat(grid.rows))
            ZStack(alignment: .topLeading) {
                if blocksBackground { Color.clear.contentShape(.rect) }
                ForEach(flow.placements, id: \.controlID) { placement in
                    if let control = page.controls.first(where: { $0.id == placement.controlID }) {
                        let frame = frame(placement, cell: cell, kind: control.kind)
                        StageControlView(model: model, control: control)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                    }
                }
            }
        }
        .id(page.id)
    }
    private func frame(_ placement: Placement, cell: CGSize, kind: ControlKind) -> CGRect {
        let gap: CGFloat = 10
        var rect = CGRect(x: CGFloat(placement.column) * cell.width, y: CGFloat(placement.row) * cell.height,
                          width: CGFloat(placement.width) * cell.width, height: CGFloat(placement.height) * cell.height)
            .insetBy(dx: gap / 2, dy: gap / 2)
        // Vertical faders read as faders, not slabs.
        if kind == .fader, rect.height > rect.width, rect.width > 84 { rect.origin.x += (rect.width - 84) / 2; rect.size.width = 84 }
        return rect
    }
}

struct StageControlView: View {
    @Bindable var model: AppModel
    let control: ControlSpec
    var body: some View {
        switch control.kind {
        case .xy where control.bindings.count == 2: FieldControl(model: model, control: control)
        case .fader where control.bindings.count == 1: FaderControl(model: model, control: control)
        case .trigger, .toggle: TriggerControl(model: model, control: control)
        case .keys: KeysControl(model: model, control: control)
        case .tracks: StageTrackStrip(session: model.session)
        case .patchBar: StagePatchBar(model: model)
        case .camera: HandsTile(model: model)
        default: Color.clear.accessibilityHidden(true)
        }
    }
}

/// Page name, dots and arrows for layouts without a toolbar page picker.
struct StagePageHeader: View {
    @Bindable var performance: PerformanceController
    var body: some View {
        HStack(spacing: 10) {
            Text(performance.page.name).font(.title3.bold())
            HStack(spacing: 6) {
                ForEach(performance.pages.indices, id: \.self) { index in
                    Circle().fill(Design.stageInk.opacity(index == performance.pageIndex ? 1 : 0.3)).frame(width: 6, height: 6)
                }
            }
            .accessibilityElement().accessibilityLabel("Page \(performance.pageIndex + 1) of \(performance.pages.count)")
            Spacer()
            Button("Previous Page", systemImage: "chevron.left") { performance.pageIndex = max(0, performance.pageIndex - 1) }
                .disabled(performance.pageIndex == 0)
            Button("Next Page", systemImage: "chevron.right") { performance.pageIndex = min(performance.pages.count - 1, performance.pageIndex + 1) }
                .disabled(performance.pageIndex >= performance.pages.count - 1)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .frame(minHeight: 44)
    }
}

/// Play mode is visible state, not a one-off dialog.
struct TakeoverBanner: View {
    @Bindable var model: AppModel
    var body: some View {
        let track = model.session.selectedTrack
        HStack(spacing: 12) {
            Circle().fill(Design.stageTracks[track]).frame(width: 8, height: 8)
            (Text("Playing track \(track + 1). ").bold() + Text("Its sequence has stopped; generate or recall a patch to restore it.").foregroundStyle(Design.stageInk.opacity(0.7)))
                .font(.footnote).lineLimit(2)
            Spacer(minLength: 0)
            Button("Stop Playing") { model.performance.mode = .modulate }.buttonStyle(.bordered)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Design.stageTracks[track].opacity(0.16), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Design.stageTracks[track].opacity(0.45)))
    }
}
