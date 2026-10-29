import SwiftUI
import MIDIVisionHandTrackingCore

struct HandsBackdrop: View {
    @Bindable var model: AppModel
    var body: some View {
        ZStack {
            Color.black
            if model.hands.running {
                CameraPreview(session: model.hands.captureSession, portrait: model.hands.portrait)
                Canvas { context, size in
                    let mapper = AspectFillPointMapper(frameSize: model.hands.frameSize, viewSize: size, normalizePoint: { CGPoint(x: 1 - $0.x, y: $0.y) })
                    for hand in model.hands.skeletons {
                        for chain in HandSkeletonLayout.boneChains {
                            var path = Path()
                            var started = false
                            for joint in chain {
                                guard let point = hand.joints[joint] else { started = false; continue }
                                let mapped = mapper.map(point)
                                if started { path.addLine(to: mapped) } else { path.move(to: mapped); started = true }
                                context.fill(Path(ellipseIn: CGRect(x: mapped.x - 3, y: mapped.y - 3, width: 6, height: 6)), with: .color(.white))
                            }
                            context.stroke(path, with: .color(Design.stageTracks[1]), lineWidth: 2)
                        }
                    }
                }.allowsHitTesting(false).accessibilityHidden(true)
            } else {
                VStack(spacing: 12) {
                    Label(model.hands.error ?? "Camera preview", systemImage: "video.slash")
                    Button("Start Camera") { Task { await model.hands.start() } }
                    if model.hands.error != nil { CameraSettingsButton() }
                }.font(.callout).frame(maxWidth: 300).padding().background(.regularMaterial, in: .rect(cornerRadius: 16))
            }
        }.clipped()
    }
}
