import SwiftUI

/// Perform screen: Pixels fills the stage and the performance layer sits on top
/// (Mac, iPad and phone landscape) or beside it (portrait and unfolded layouts).
struct StageView: View {
    @Bindable var model: AppModel
    enum Arrangement { case overlay, stacked, sideBySide }

    static func arrangement(for size: CGSize) -> (LayoutClass, Arrangement) {
        #if os(macOS)
        return (.mac, .overlay)
        #else
        if size.width > size.height {
            if size.height < 500 { return (.phoneLandscape, .overlay) }
            if size.width / max(1, size.height) < 1.2 { return (.foldOpen, .sideBySide) }
            return (.padLandscape, .overlay)
        }
        return size.width < 500 ? (.phonePortrait, .stacked) : (.padPortrait, .stacked)
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            let (layout, arrangement) = Self.arrangement(for: geometry.size)
            Group {
                switch arrangement {
                case .overlay: overlay(layout)
                case .stacked:
                    VStack(spacing: 0) {
                        visuals.frame(height: geometry.size.height * (layout == .phonePortrait ? 0.34 : 0.42))
                        controls(layout, header: layout == .phonePortrait)
                    }
                case .sideBySide:
                    HStack(spacing: 0) {
                        visuals.frame(width: geometry.size.width / 2)
                        Divider()
                        controls(layout, header: true)
                    }
                }
            }
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
            Button("Take over track \(model.session.selectedTrack + 1)") { model.performance.mode = .play }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Playing notes stops this track’s generated sequence. The other tracks keep running. Generate or recall a patch to restore it.") }
        .disabled(model.session.recalling)
    }

    private func overlay(_ layout: LayoutClass) -> some View {
        ZStack {
            visuals
            if model.overlay != .off {
                VStack(spacing: 10) {
                    if model.performance.mode == .play { TakeoverBanner(model: model).frame(maxWidth: 640) }
                    PerformanceLayer(model: model, layout: layout)
                }
                .padding(16)
                .environment(\.stageGhost, model.overlay == .ghost)
            } else {
                Button("Show Controls", systemImage: "square.3.layers.3d") { model.overlay = .show }
                    .labelStyle(.iconOnly).font(.title3).frame(width: 44, height: 44)
                    .background(.regularMaterial, in: .circle)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(20)
            }
        }
    }
    private func controls(_ layout: LayoutClass, header: Bool) -> some View {
        VStack(spacing: 10) {
            if header { StagePageHeader(performance: model.performance) }
            if model.performance.mode == .play { TakeoverBanner(model: model) }
            PerformanceLayer(model: model, layout: layout)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
    private var visuals: some View {
        PixelsStage(model: model, fullBleed: true)
            .overlay(alignment: .topLeading) {
                if model.performance.method == .hands && model.hands.running && model.showCameraPreview && !model.showHandsPanel {
                    HandsTile(model: model).frame(width: 220, height: 150).padding(16)
                }
            }
            .clipped()
    }

    /// Mac keyboard: 1–4 select tracks; a w s e d f t g y h u j k play the scale in Play mode.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard let character = press.characters.first else { return .ignored }
        if press.phase == .down, let track = Int(String(character)), (1...4).contains(track) {
            model.session.selectedTrack = track - 1; return .handled
        }
        guard model.performance.mode == .play, let step = Array("awsedftgyhujk").firstIndex(of: character) else { return .ignored }
        let snapshot = model.session.snapshot
        let note = RNDProtocolCodec.degreeNote(step, root: snapshot.root ?? 0, scale: snapshot.scale ?? 0, octave: snapshot.octave)
        model.session.note(source: "key-\(character)", note: press.phase == .up ? nil : note, track: model.session.selectedTrack)
        return .handled
    }
}
