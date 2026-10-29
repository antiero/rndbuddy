import SwiftUI

/// Perform screen: Pixels fills the stage and the performance layer sits on top
/// (Mac, iPad and phone landscape) or beside it (portrait and unfolded layouts).
struct StageView: View {
    @Bindable var model: AppModel
    var isPresentation = false
    enum Arrangement { case overlay, stacked, sideBySide }

    static func arrangement(for size: CGSize) -> (LayoutClass, Arrangement) {
        #if os(macOS)
        return (.mac, .overlay)
        #else
        if size.width > size.height {
            if size.height < 500 { return (.phoneLandscape, .overlay) }
            return (.padLandscape, .overlay)
        }
        return size.width < 500 ? (.phonePortrait, .stacked) : (.padPortrait, .stacked)
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            let (layout, proposed) = Self.arrangement(for: geometry.size)
            let arrangement: Arrangement = model.stagePresentation == .hands || isPresentation ? .overlay : proposed
            Group {
                switch arrangement {
                case .overlay: overlay(layout)
                case .stacked:
                    VStack(spacing: 0) {
                        if model.pixelsVisible {
                            visuals
                                .frame(height: geometry.size.height * (layout == .phonePortrait ? 0.34 : (model.portraitFraction > 0 ? model.portraitFraction : 0.42)))
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if layout == .padPortrait && model.pixelsVisible {
                            Capsule().fill(.secondary).frame(width: 44, height: 4).frame(maxWidth: .infinity).frame(height: 44)
                                .contentShape(.rect)
                                .gesture(DragGesture().onChanged { value in
                                    let base = model.portraitFraction > 0 ? model.portraitFraction : 0.42
                                    model.portraitFraction = (base + value.translation.height / geometry.size.height * 0.05).clamped(0.2...0.65)
                                }).accessibilityLabel("Visuals height")
                                .accessibilityAdjustableAction { direction in model.portraitFraction = ((model.portraitFraction > 0 ? model.portraitFraction : 0.42) + (direction == .increment ? 0.05 : -0.05)).clamped(0.2...0.65) }
                        }
                        controls(layout, header: true)
                    }
                case .sideBySide:
                    HStack(spacing: 0) {
                        visuals.frame(width: geometry.size.width / 2)
                        Divider()
                        controls(layout, header: true)
                    }
                }
            }
            .inspector(isPresented: Binding(get: { model.editingStage && geometry.size.width >= 700 }, set: { if !$0 { model.editingStage = false } })) {
                if model.editingStage { StageEditorInspector(model: model, editor: model.stageEditor).inspectorColumnWidth(min: 280, ideal: 320, max: 380) }
            }
            .sheet(isPresented: Binding(get: { model.editingStage && geometry.size.width < 700 }, set: { if !$0 { model.editingStage = false } })) {
                StageEditorInspector(model: model, editor: model.stageEditor)
                    .presentationDetents([.medium, .large]).presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
            .onChange(of: layout, initial: true) { _, layout in model.stageLayout = layout }
            .onChange(of: arrangement == .overlay, initial: true) { _, overlay in model.stageSplit = !overlay }
            .onChange(of: geometry.size, initial: true) { _, size in model.hands.setPortrait(size.height > size.width) }
        }
        .background(Design.stageBackground)
        .foregroundStyle(Design.stageInk)
        .environment(\.colorScheme, .dark)
        #if os(iOS)
        .overlay(alignment: .topLeading) { if model.showHandsPanel { FloatingHandsPanel(model: model) } }
        #endif
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .up], action: handleKey)
        .confirmationDialog("Play this track?", isPresented: $model.showTakeover, titleVisibility: .visible) {
            Button("Take over track \(model.session.selectedTrack + 1)") { model.confirmPlay() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Playing notes stops this track’s generated sequence. The other tracks keep running. Generate or recall a patch to restore it.") }
        .onDisappear { model.performance.cancelTouches() }
        .onKeyPress(.escape) {
            if model.editingStage { model.editingStage = false; return .handled }
            if model.stagePresentation != .normal { model.presentStage(.normal); return .handled }
            return .ignored
        }
        .disabled(model.session.recalling)
    }

    private func overlay(_ layout: LayoutClass) -> some View {
        ZStack {
            visuals
            if model.overlay != .off || model.editingStage {
                VStack(spacing: 10) {
                    if model.performance.mode == .play { TakeoverBanner(model: model).frame(maxWidth: 640) }
                    // There is nothing to shield before Pixels has been enabled.
                    // Leaving the native setup card reachable lets its Enable and
                    // Explore Demo actions work even while the Stage controls are shown.
                    PerformanceLayer(
                        model: model,
                        layout: layout,
                        editor: model.stageEditor,
                        blocksBackground: model.pixels.permission && !model.pixels.external
                    )
                }
                .padding(.horizontal, 16).padding(.top, floatingChrome ? 60 : 16).padding(.bottom, 6)
                .environment(\.stageGhost, model.overlay == .ghost)
            } else {
                Button("Show Controls", systemImage: "square.3.layers.3d") { model.overlay = .show }
                    .labelStyle(.iconOnly).font(.title3).frame(width: 44, height: 44)
                    .background(.regularMaterial, in: .circle)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(20)
            }
        }
        .overlay(alignment: .top) { if floatingChrome { StageChrome(model: model) } }
    }
    private var floatingChrome: Bool {
        #if os(macOS)
        isPresentation
        #else
        !model.stageSplit || isPresentation
        #endif
    }
    private func controls(_ layout: LayoutClass, header: Bool) -> some View {
        VStack(spacing: 10) {
            if header { StagePageHeader(performance: model.performance) }
            if model.performance.mode == .play { TakeoverBanner(model: model) }
            GeometryReader { geometry in
                ScrollView(.vertical) {
                    PerformanceLayer(model: model, layout: layout, editor: model.stageEditor)
                        .frame(height: max(geometry.size.height, CGFloat(layout.grid.rows) * 50))
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if layout == .phonePortrait {
                HStack(spacing: 12) {
                    StageTrackStrip(session: model.session)
                    Button { model.performance.cancel(); model.session.generate() } label: {
                        Image(systemName: "shuffle").font(.title3).frame(width: 52, height: 52)
                            .background(Design.accent, in: .circle).foregroundStyle(.white)
                    }.buttonStyle(.plain).accessibilityLabel("Generate new patch").disabled(!model.session.canEdit || model.editingStage)
                }
                .frame(height: 56)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 18)
                .background(Design.stageBackground)
            }
        }
    }
    private var visuals: some View {
        ZStack {
            if model.stagePresentation == .hands && isPresentation { HandsBackdrop(model: model) }
            else if !isPresentation && model.stagePresentation != .normal { Color.black }
            else { PixelsStage(model: model, fullBleed: true) }
        }
            .overlay(alignment: .topLeading) {
                if model.stagePresentation != .hands && model.hands.running && model.showCameraPreview && !model.showHandsPanel {
                    HandsTile(model: model).frame(width: 220, height: 150).padding(16)
                }
            }
            .clipped()
    }

    /// Mac keyboard: 1–4 select tracks; a w s e d f t g y h u j k play the scale in Play mode.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isEmpty else { return .ignored }
        let character = press.characters.first ?? "\0"
        if model.editingStage {
            guard let id = model.stageEditor.selection,
                  var placement = PerformanceLayout.flow(model.performance.page, in: model.stageLayout).placements.first(where: { $0.controlID == id }) else { return .ignored }
            switch press.key {
            case .leftArrow: placement.column -= 1
            case .rightArrow: placement.column += 1
            case .upArrow: placement.row -= 1
            case .downArrow: placement.row += 1
            default: return .ignored
            }
            if press.phase == .down { model.stageEditor.place(model, placement) }; return .handled
        }
        if press.phase == .down && model.performance.mode != .play && character == "g" { model.performance.cancel(); model.session.generate(); return .handled }
        if press.phase == .down && character == " " { model.performance.held.toggle(); return .handled }
        if press.phase == .down, let track = Int(String(character)), (1...4).contains(track) {
            model.session.selectedTrack = track - 1; return .handled
        }
        guard model.performance.mode == .play, let step = Array("awsedftgyhujk").firstIndex(of: character) else { return .ignored }
        guard let control = model.performance.page.controls.first(where: { $0.kind == .keys || $0.kind == .xy }) else { return .ignored }
        model.performance.key(control.id, degree: step, down: press.phase != .up)
        return .handled
    }
}
