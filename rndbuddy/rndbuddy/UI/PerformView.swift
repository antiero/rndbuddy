import SwiftUI

struct PerformView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    PixelsStage(model: model)
                        .frame(height: geometry.size.width > 740 ? min(420, max(220, geometry.size.height * 0.42)) : min(200, max(140, geometry.size.height * 0.25)))
                    if geometry.size.width > 740 {
                        HStack(alignment: .top, spacing: 16) {
                            TrackSelector(session: model.session, vertical: true).frame(width: 160)
                            PerformancePad(model: model)
                        }
                    } else {
                        TrackSelector(session: model.session)
                        PerformancePad(model: model)
                    }
                }.padding(geometry.size.width > 740 ? 24 : 16)
            }
            .background(Design.background(scheme))
            .onChange(of: geometry.size, initial: true) { _, size in model.hands.setPortrait(size.height > size.width) }
            .safeAreaInset(edge: .bottom) {
                PatchBar(model: model).padding(.horizontal, 20).padding(.vertical, 8)
                    .frame(maxWidth:.infinity)
                    .background(Design.background(scheme).opacity(0.97))
            }
        }
        .confirmationDialog("Play this track?", isPresented: $model.showTakeover, titleVisibility: .visible) {
            Button("Take over track \(model.session.selectedTrack + 1)") { model.performance.mode = .play }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Playing notes stops this track’s generated sequence. The other tracks keep running. Generate or recall a patch to restore it.") }
    }
}

struct TrackSelector: View {
    @Bindable var session: DeviceSession
    var vertical = false
    var body: some View {
        Group {
            if vertical { VStack(spacing: 8) { ForEach(0..<4) { track in trackButton(track) } } }
            else { HStack(spacing: 8) { ForEach(0..<4) { track in trackButton(track) } } }
        }
    }
    private func trackButton(_ track: Int) -> some View {
        Button { session.selectedTrack = track } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(String(track + 1)).font(.title3.monospacedDigit())
                    Spacer(minLength: 8)
                    Circle().fill(Design.tracks[track].opacity(0.25 + session.activity[track] * 0.75)).frame(width: 6,height: 6)
                }
                Text(session.snapshot.tracks[track].engine ?? "Track \(track + 1)").font(.caption).lineLimit(1)
                Capsule().fill(session.selectedTrack == track ? Design.tracks[track] : Color.primary.opacity(0.12)).frame(height: 2)
            }.padding(12).frame(minWidth: 52, maxWidth: .infinity).background(.primary.opacity(session.selectedTrack == track ? 0.055 : 0.015), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Track \(track + 1), \(session.snapshot.tracks[track].engine ?? "unknown instrument")")
        .accessibilityAddTraits(session.selectedTrack == track ? .isSelected : [])
    }
}

struct PatchBar: View {
    @Bindable var model: AppModel
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { musicalSettings; Spacer(); generate(showInfo:true) }
            HStack(spacing: 12) { musicalSettings; Spacer(minLength:0); generate(showInfo:false) }
            VStack(spacing: 12) { musicalSettings; generate(showInfo:false) }
        }.padding(.vertical, 4)
    }
    private var musicalSettings: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(0..<12) { index in Button(RNDProtocolCodec.roots[index]) { model.session.setRoot(index) } }
            } label: { Text(model.session.snapshot.root.map { RNDProtocolCodec.roots[$0] } ?? "Tonic").monospaced() }
            Menu {
                ForEach(0..<20) { index in Button(RNDProtocolCodec.scales[index]) { model.session.setScale(index) } }
            } label: { Text(model.session.snapshot.scale.map { RNDProtocolCodec.scales[$0] } ?? "Scale") }
            Menu {
                ForEach(0..<3) { index in Button(["Loop", "Drone", "Jingle"][index]) { model.session.setType(index) } }
            } label: { Label(model.session.snapshot.type.map { ["Loop", "Drone", "Jingle"][$0] } ?? "Type", systemImage: "repeat") }
        }.buttonStyle(.bordered).disabled(!model.session.canEdit || model.session.recalling)
    }
    private func generate(showInfo:Bool) -> some View {
        HStack(spacing: 14) {
            if showInfo { VStack(alignment: .trailing, spacing: 3) {
                Text(model.session.snapshot.seedHex).font(.caption.monospaced()).foregroundStyle(.secondary)
                Text(model.session.snapshot.tempo.map { "\($0) BPM" } ?? "Ready when you are").font(.caption).foregroundStyle(.secondary)
            } }
            Button { model.performance.cancel(); model.session.generate() } label: {
                Image(systemName: "shuffle").font(.title2).frame(width: 64,height: 64).foregroundStyle(.white).background(Design.accent, in: .circle)
            }.buttonStyle(.plain).accessibilityLabel("Generate new patch").help("Generate a new RND patch")
                .disabled(!model.session.canEdit || model.session.recalling)
        }
    }
}
