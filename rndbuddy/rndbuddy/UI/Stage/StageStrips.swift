import SwiftUI

struct StageTrackStrip: View {
    @Bindable var session: DeviceSession
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 52
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { track in chip(track, compact: compact, veryCompact: geometry.size.width < 400) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tracks")
    }
    private func chip(_ track: Int, compact: Bool, veryCompact: Bool = false) -> some View {
        let state = session.snapshot.tracks[track]
        let selected = session.selectedTrack == track
        let colour = Design.stageTracks[track]
        let engine = state.engine ?? "Track \(track + 1)"
        let flags = state.muted ? " · M" : state.soloed ? " · S" : ""
        return Button { session.selectedTrack = track } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(track + 1)\(flags)").font(.callout.monospaced())
                    if compact && !veryCompact { Text(engine).font(.caption).lineLimit(1).foregroundStyle(Design.stageInk.opacity(selected ? 1 : 0.7)) }
                    Spacer(minLength: 0)
                    Circle().fill(colour.opacity(0.3 + session.activity[track] * 0.7)).frame(width: 7, height: 7)
                }
                if !compact {
                    Text(engine).font(.caption).lineLimit(1).foregroundStyle(Design.stageInk.opacity(selected ? 1 : 0.7))
                    Spacer(minLength: 0)
                    Capsule().fill(selected ? colour : .white.opacity(0.14)).frame(height: 2)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, compact ? 4 : 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(selected ? Color.white.opacity(0.1) : .clear, in: .rect(cornerRadius: 14))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .stageSurface(active: selected && compact, tint: colour, radius: 14)
        .opacity(state.muted ? 0.6 : 1)
        .contextMenu {
            Button(state.muted ? "Unmute" : "Mute", systemImage: "speaker.slash") { session.toggleMute(track) }
            Button(state.soloed ? "Unsolo" : "Solo", systemImage: "headphones") { session.toggleSolo(track) }
            if FirmwareCapabilities.supports(.reroll, firmware: session.snapshot.firmware) { Button("Reroll", systemImage: "dice") { session.reroll(track) } }
        }
        .accessibilityLabel("Track \(track + 1), \(state.engine ?? "unknown instrument")\(state.muted ? ", muted" : "")\(state.soloed ? ", solo" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct StagePatchBar: View {
    @Bindable var model: AppModel
    var body: some View {
        let session = model.session
        GeometryReader { geometry in
            HStack(spacing: 8) {
                if geometry.size.width >= 330 { musical }
                else {
                    Menu {
                        Section("Key") { ForEach(0..<12, id: \.self) { index in Button(RNDProtocolCodec.roots[index]) { session.setRoot(index) } } }
                        Section("Scale") { ForEach(0..<20, id: \.self) { index in Button(RNDProtocolCodec.scales[index]) { session.setScale(index) } } }
                        Section("Type") { ForEach(0..<3, id: \.self) { index in Button(["Loop", "Drone", "Jingle"][index]) { session.setType(index) } } }
                    } label: { Label("Patch", systemImage: "music.note") }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                if geometry.size.width > 440 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(session.snapshot.seedHex).foregroundStyle(Design.stageInk.opacity(0.7))
                        Text(session.snapshot.tempo.map { "\($0) BPM" } ?? "—")
                    }.font(.caption.monospaced())
                }
                Button { model.performance.cancel(); session.generate() } label: {
                    Image(systemName: "shuffle").font(.title3.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: max(44, min(64, geometry.size.height - 12)), height: max(44, min(64, geometry.size.height - 12)))
                        .background(Design.accent, in: .circle)
                        .shadow(color: Design.accent.opacity(0.35), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Generate new patch").help("Generate a new RND patch")
                .disabled(!session.canEdit || session.recalling || model.editingStage)
            }
            .padding(.leading, 10).padding(.trailing, 6).padding(.vertical, 6)
            .frame(height: min(80, geometry.size.height))
            .stageSurface(radius: 22)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
    private var musical: some View {
        let session = model.session
        let snapshot = session.snapshot
        return HStack(spacing: 6) {
            Menu {
                ForEach(0..<12, id: \.self) { index in Button(RNDProtocolCodec.roots[index]) { session.setRoot(index) } }
            } label: { pill(snapshot.root.map { RNDProtocolCodec.roots[$0] } ?? "Key", mono: true) }
            Menu {
                ForEach(0..<20, id: \.self) { index in Button(RNDProtocolCodec.scales[index]) { session.setScale(index) } }
            } label: { pill(snapshot.scale.map { RNDProtocolCodec.scales[$0] } ?? "Scale") }
            Menu {
                ForEach(0..<3, id: \.self) { index in Button(["Loop", "Drone", "Jingle"][index]) { session.setType(index) } }
            } label: { pill(snapshot.type.map { ["Loop", "Drone", "Jingle"][$0] } ?? "Type") }
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .disabled(!session.canEdit || session.recalling || model.editingStage)
    }
    private func pill(_ text: String, mono: Bool = false) -> some View {
        Text(text).font(mono ? .callout.monospaced() : .callout).lineLimit(1)
            .padding(.horizontal, 12).frame(minHeight: 36)
            .background(.white.opacity(0.09), in: .rect(cornerRadius: 10))
    }
}

/// Camera control on a page, and the floating tile shown while Hands is armed.
struct HandsTile: View {
    @Bindable var model: AppModel
    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.hands.running {
                HandsBackdrop(model: model).accessibilityHidden(true)
            } else {
                Color.black.opacity(0.4)
            }
            HStack(spacing: 6) {
                Circle().fill(model.performance.armed ? Design.accent : .secondary).frame(width: 7, height: 7)
                Text(model.performance.armed ? "Hands armed" : "Hands").font(.caption.weight(.semibold))
                Spacer()
                Button("Expand Camera", systemImage: "arrow.up.left.and.arrow.down.right") { model.presentStage(.hands) }
                    .labelStyle(.iconOnly).buttonStyle(.plain).frame(width: 44, height: 44)
                Button(model.performance.armed ? "Disarm" : "Arm", systemImage: model.performance.armed ? "stop.circle" : "hand.raised") {
                    if model.performance.method != .hands { model.performance.method = .hands }
                    model.arm(!model.performance.armed)
                }
                .labelStyle(.iconOnly).buttonStyle(.plain).frame(width: 44, height: 44)
            }
            .padding(.leading, 10).padding(.trailing, 4).padding(.top, 4)
            if let error = model.hands.error {
                Text(error).font(.caption2).padding(10).frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .clipShape(.rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.18)))
    }
}
