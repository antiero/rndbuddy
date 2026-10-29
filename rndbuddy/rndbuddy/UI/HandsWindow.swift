import SwiftUI

struct HandsControls: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(spacing: 12) {
            if model.showCameraPreview && model.hands.running {
                CameraPreview(session: model.hands.captureSession, portrait: model.hands.portrait)
                    .frame(minHeight: 160, idealHeight: 220)
                    .clipShape(.rect(cornerRadius: 12))
                    .accessibilityLabel("Live camera preview")
            }
            HStack {
                Toggle("Preview", isOn: $model.showCameraPreview).toggleStyle(.button)
                    .help("Hide the preview while keeping hand tracking active")
                Button("Expand Camera", systemImage: "arrow.up.left.and.arrow.down.right") { model.presentStage(.hands) }
                Spacer()
                Button(model.performance.armed && model.performance.method == .hands ? "Disarm Hands" : "Arm Hands") {
                    if model.performance.method != .hands { model.performance.method = .hands }
                    model.arm(!model.performance.armed)
                }.buttonStyle(.borderedProminent)
            }
            if let error = model.hands.error { Text(error).font(.caption).foregroundStyle(.secondary) }
        }.padding(16)
    }
}

#if os(iOS)
struct FloatingHandsPanel: View {
    @Bindable var model: AppModel
    @State private var position = CGSize.zero
    @GestureState private var translation = CGSize.zero
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Label("Hands", systemImage: "hand.raised")
                    Spacer()
                    Button("Hide Camera Controls", systemImage: "xmark") { model.showHandsPanel = false }
                        .labelStyle(.iconOnly).frame(width: 44, height: 44)
                }
                .padding(.leading, 16)
                .contentShape(.rect)
                .gesture(DragGesture().updating($translation) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        position.width = (position.width + value.translation.width).clamped(0...max(0, geometry.size.width - 300))
                        position.height = (position.height + value.translation.height).clamped(0...max(0, geometry.size.height - 320))
                    })
                HandsControls(model: model)
            }
            .frame(width: min(300, geometry.size.width))
            .background(.regularMaterial, in: .rect(cornerRadius: 18))
            .shadow(radius: 12)
            .offset(x: (position.width + translation.width).clamped(0...max(0, geometry.size.width - 300)),
                    y: (position.height + translation.height).clamped(0...max(0, geometry.size.height - 320)))
        }
    }
}
#endif
