import SwiftUI

private struct StageGhostKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// Ghost overlay: outlines only until a control is touched.
    var stageGhost: Bool {
        get { self[StageGhostKey.self] }
        set { self[StageGhostKey.self] = newValue }
    }
}

enum StageText {
    static func label(_ binding: ControlBinding, selected: Int) -> String {
        let name: String
        switch binding.target {
        case .volume: name = "Volume"
        case .reverb: name = "Reverb"
        case .masterVolume: return "Master vol"
        case .masterReverb: return "Master verb"
        case .tone: return "Reverb tone"
        case .decay: return "Reverb decay"
        }
        return "\(name) · T\(binding.track(selected: selected) + 1)"
    }
    static func colour(_ binding: ControlBinding?, selected: Int) -> Color {
        guard let binding, binding.target == .volume || binding.target == .reverb else { return Design.stageInk }
        return Design.stageTracks[binding.track(selected: selected)]
    }
}

/// Shared surface for stage controls: scrim in Show, dashed outline in Ghost, track-coloured edge while active.
struct StageSurface: ViewModifier {
    @Environment(\.stageGhost) private var ghost
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    var active = false
    var tint = Design.stageInk
    var radius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .background(ghost && !active ? Color.clear : Design.scrim, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(active ? tint : (contrast == .increased ? Color.white.opacity(0.65) : Design.stageLine), style: StrokeStyle(lineWidth: active ? 1.5 : 1, dash: ghost && !active ? [5, 4] : []))
            }
            .shadow(color: active ? tint.opacity(0.35) : .clear, radius: 14)
            .opacity(ghost && !active ? 0.5 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: active)
    }
}
extension View {
    func stageSurface(active: Bool = false, tint: Color = Design.stageInk, radius: CGFloat = 16) -> some View {
        modifier(StageSurface(active: active, tint: tint, radius: radius))
    }
}

struct FaderControl: View {
    @Bindable var model: AppModel
    let control: ControlSpec
    var body: some View {
        let performance = model.performance
        let binding = control.bindings[0]
        let live = performance.faderValues[control.id]
        let value = live.map { Int((binding.mapped($0) * 127).rounded()) } ?? performance.reported(binding)
        let fraction = value.map { Double($0) / 127 }
        let tint = StageText.colour(binding, selected: model.session.selectedTrack)
        GeometryReader { geometry in
            let vertical = geometry.size.height >= geometry.size.width
            ZStack(alignment: vertical ? .bottom : .leading) {
                if let fraction {
                    let length = (vertical ? geometry.size.height : geometry.size.width) * fraction
                    ZStack(alignment: vertical ? .top : .trailing) {
                        tint.opacity(0.28)
                        Rectangle().fill(tint).frame(width: vertical ? nil : 2, height: vertical ? 2 : nil)
                    }.frame(width: vertical ? nil : length, height: vertical ? length : nil)
                }
                labels(vertical: vertical, value: value)
            }
            .clipShape(.rect(cornerRadius: 16))
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let input = vertical ? 1 - drag.location.y / max(1, geometry.size.height) : drag.location.x / max(1, geometry.size.width)
                    performance.setFader(control.id, value: Double(input).clamped(0...1))
                }
                .onEnded { _ in performance.setFader(control.id, value: nil) })
        }
        .stageSurface(active: live != nil, tint: tint)
        .accessibilityElement()
        .accessibilityLabel("\(control.title), \(StageText.label(binding, selected: model.session.selectedTrack))")
        .accessibilityValue(value.map(String.init) ?? "Unknown")
        .accessibilityAdjustableAction { direction in
            let step = (direction == .increment ? 8.0 : -8.0) / 127
            performance.setFader(control.id, value: ((fraction ?? 0.5) + step).clamped(0...1))
            performance.setFader(control.id, value: nil)
        }
        .help(StageText.label(binding, selected: model.session.selectedTrack))
        .opacity(performance.isOverridden(control) ? 0.55 : 1)
        .accessibilityHint(performance.isOverridden(control) ? "Overridden by another control" : "")
    }
    @ViewBuilder private func labels(vertical: Bool, value: Int?) -> some View {
        let text = Text(value.map(String.init) ?? "—").font(.caption.monospacedDigit())
        let title = Text(control.title).font(.caption.weight(.medium))
        if vertical {
            VStack { text; Spacer(); title }.padding(.vertical, 10).frame(maxWidth: .infinity)
        } else {
            HStack { title; Spacer(); text }.padding(.horizontal, 14)
        }
    }
}

struct TriggerControl: View {
    @Bindable var model: AppModel
    let control: ControlSpec
    var body: some View {
        let performance = model.performance
        let on = performance.isOn(control)
        let reason = FirmwareCapabilities.reason(control, firmware: model.session.snapshot.firmware)
        Button {
            if control.kind == .toggle { performance.toggle(control.id) } else { performance.trigger(control) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title3).foregroundStyle(on ? Design.accent : Design.stageInk)
                Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .stageSurface(active: on, tint: Design.accent)
        .opacity(reason == nil ? 1 : 0.45)
        .disabled(reason != nil)
        .help(reason ?? title)
        .accessibilityHint(reason ?? "")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
    private var title: String {
        let track = " T\(model.session.selectedTrack + 1)"
        switch control.action { case .mute, .solo, .reroll: return control.title + track; default: return control.title }
    }
    private var symbol: String {
        switch control.action {
        case .hold: "pause"
        case .generate: "shuffle"
        case .freeze: "snowflake"
        case .reroll: "dice"
        case .mute: "speaker.slash"
        case .solo: "headphones"
        case nil: "switch.2"
        }
    }
}

struct KeysControl: View {
    @Bindable var model: AppModel
    let control: ControlSpec
    var body: some View {
        let snapshot = model.session.snapshot
        let intervals = RNDProtocolCodec.intervals[(snapshot.scale ?? 0).clamped(0...19)]
        let root = snapshot.root ?? 0
        GeometryReader { geometry in
            let rows = geometry.size.height >= 150 ? 2 : 1
            ScrollView(.horizontal) {
            VStack(spacing: 6) {
                ForEach((0..<rows).reversed(), id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(intervals.indices, id: \.self) { index in
                            key(degree: row * intervals.count + index, name: RNDProtocolCodec.roots[(root + intervals[index]) % 12], isRoot: index == 0 && row == 0)
                        }
                    }
                }
            }
            .frame(width: max(geometry.size.width, CGFloat(intervals.count) * 50), height: geometry.size.height)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scale keys")
    }
    private func key(degree: Int, name: String, isRoot: Bool) -> some View {
        let performance = model.performance
        let down = performance.pressedKeys[control.id]?.contains(degree) ?? false
        return Text(name).font(.callout)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 10)
            .foregroundStyle(down ? .white : Design.stageInk)
            .background(down ? Design.accent : isRoot ? Color.white.opacity(0.1) : .clear, in: .rect(cornerRadius: 12))
            .stageSurface(radius: 12)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !down else { return }
                    if performance.mode == .play || model.requestPlay() { performance.key(control.id, degree: degree, down: true) }
                }
                .onEnded { _ in performance.key(control.id, degree: degree, down: false) })
            .accessibilityElement()
            .accessibilityLabel(degree >= RNDProtocolCodec.intervals[(model.session.snapshot.scale ?? 0).clamped(0...19)].count ? "\(name), upper octave" : name)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                guard performance.mode == .play || model.requestPlay() else { return }
                performance.key(control.id, degree: degree, down: true)
                Task { @MainActor in try? await Task.sleep(for: .milliseconds(250)); performance.key(control.id, degree: degree, down: false) }
            }
    }
}
