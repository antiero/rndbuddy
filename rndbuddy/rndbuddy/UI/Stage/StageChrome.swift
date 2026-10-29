import SwiftUI

struct StageChrome: View {
    @Bindable var model: AppModel
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Button("Previous Page", systemImage: "chevron.left") { model.performance.pageIndex = max(0, model.performance.pageIndex - 1) }.disabled(model.performance.pageIndex == 0)
                Menu(model.performance.page.name) {
                    ForEach(model.performance.pages.indices, id: \.self) { index in Button(model.performance.pages[index].name) { model.performance.pageIndex = index } }
                }
                Button("Next Page", systemImage: "chevron.right") { model.performance.pageIndex = min(model.performance.pages.count - 1, model.performance.pageIndex + 1) }.disabled(model.performance.pageIndex == model.performance.pages.count - 1)
            }.padding(.horizontal, 8).background(.regularMaterial, in: .capsule)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Menu("Overlay", systemImage: "square.3.layers.3d") {
                    Picker("Overlay", selection: $model.overlay) { ForEach(OverlayVisibility.allCases) { Text($0.rawValue).tag($0) } }
                }
                if model.stagePresentation == .hands {
                    Button(model.performance.armed ? "Disarm" : "Arm", systemImage: model.performance.armed ? "stop.circle" : "hand.raised") {
                        if model.performance.method != .hands { model.performance.method = .hands }
                        model.arm(!model.performance.armed)
                    }
                }
                Menu("Stage Options", systemImage: "ellipsis") {
                    Button("Edit Layout", systemImage: "pencil") { model.editingStage = true }
                    Button("Mixer", systemImage: "slider.vertical.3") { model.showMixer = true }
                    Button("Capture", systemImage: "waveform") { model.showCapture = true }
                    Button("Save Patch", systemImage: "bookmark") { model.showSave = true }.disabled(model.session.snapshot.seed == nil || model.library == nil)
                    PerformanceMenu(model: model)
                    Button("Fullscreen Hands", systemImage: "video") { model.presentStage(.hands) }
                    if model.pixels.permission { PixelsMenuItems(model: model) }
                    else { Button("Enable Pixels", systemImage: "sparkles") { model.pixels.allow() } }
                    Button(model.session.connected ? "RND Connected" : "Connection Settings") { model.destination = .settings; model.presentStage(.normal) }
                }
                Button(model.stagePresentation == .normal ? "Fullscreen Stage" : "Exit Fullscreen", systemImage: model.stagePresentation == .normal ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left") {
                    model.presentStage(model.stagePresentation == .normal ? .stage : .normal)
                }
            }.background(.regularMaterial, in: .capsule)
        }
        .buttonStyle(.plain).labelStyle(.iconOnly)
        .controlSize(.large)
        .padding(.horizontal, 16).padding(.top, 12)
        .foregroundStyle(.white)
    }
}
