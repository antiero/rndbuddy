import SwiftUI

struct MixerView: View {
    @Bindable var session: DeviceSession
    @Environment(\.dismiss) private var dismiss
    @State private var seedInput = ""
    @State private var previousDecay = 83
    var body: some View {
        NavigationStack {
            Form {
                Section("Master") {
                    control("Volume", cc: 7, value: session.snapshot.masterVolume)
                    control("Reverb", cc: 91, value: session.snapshot.masterReverb)
                    Stepper("Tempo · \(session.snapshot.tempo ?? 120) BPM", value: Binding(get: { session.snapshot.tempo ?? 120 }, set: { session.setTempo($0) }), in: session.snapshot.firmware == .jg023 ? 50...200 : 20...400)
                    Toggle("Send MIDI clock", isOn: Binding(get: { session.clockSource == "App" }, set: { $0 ? session.startClock() : session.stopClock() }))
                }
                Section("Patch") {
                    HStack {
                        TextField("Seed (hex)",text:$seedInput).monospaced()
                        Button("Load Seed") {
                            if let seed = UInt32(seedInput,radix:16) { session.recall(PatchSnapshot(seed:seed,firmware:session.snapshot.firmware)) }
                        }.disabled(seedInput.isEmpty || seedInput.count > 8 || UInt32(seedInput,radix:16) == nil)
                    }
                    if session.snapshot.firmware == .jg023 {
                        ForEach(0..<3) { type in
                            Toggle(["Generate loops","Generate drones","Generate jingles"][type],isOn:Binding(get:{ (session.snapshot.generationMask ?? 7) & (1 << type) != 0 },set:{ enabled in
                                let current = session.snapshot.generationMask ?? 7
                                let next = enabled ? current | (1 << type) : current & ~(1 << type)
                                session.setGenerationMask(next)
                            }))
                        }
                    } else if session.snapshot.firmware == .official14 {
                        Picker("Active tracks",selection:Binding(get:{session.snapshot.locks?.tracks ?? 0},set:{ session.setTrackCount($0 == 0 ? nil : $0) })) {
                            Text("Random").tag(0)
                            ForEach(1...4,id:\.self) { count in Text(String(count)).tag(count) }
                        }
                    }
                }
                ForEach(0..<4) { track in
                    Section("Track \(track + 1)") {
                        Picker("Engine", selection: Binding(get: { session.snapshot.tracks[track].engineOverride ?? -1 }, set: { if $0 >= 0 { session.setEngine($0, track: track) } })) {
                            Text(session.snapshot.tracks[track].engine ?? "Reported engine unknown").tag(-1)
                            ForEach(0..<8) { index in Text(RNDProtocolCodec.engines[index]).tag(index) }
                        }
                        control("Volume", cc: 7, value: session.snapshot.tracks[track].volume, channel: track+2)
                        control("Reverb", cc: 91, value: session.snapshot.tracks[track].reverb, channel: track+2)
                        HStack {
                            Toggle("Mute", isOn: Binding(get: { session.snapshot.tracks[track].muted }, set: { _ in session.toggleMute(track) }))
                            Toggle("Solo", isOn: Binding(get: { session.snapshot.tracks[track].soloed }, set: { _ in session.toggleSolo(track) }))
                            if session.snapshot.firmware == .jg023 { Button("Reroll", systemImage: "dice") { session.reroll(track) } }
                        }
                    }
                }
                if session.snapshot.firmware.supportsDeepReverb {
                    Section("Reverb") {
                        ForEach(85...90, id: \.self) { cc in
                            control(["Pre-delay", "Tone", "Diffusion 1", "Diffusion 2", "Room size", "Decay"][cc-85], cc: cc, value: session.snapshot.reverbParameters[cc])
                        }
                        Toggle("Freeze",isOn:Binding(get:{session.snapshot.reverbParameters[90] == 127},set:{ freeze in
                            if freeze { previousDecay = min(126,session.snapshot.reverbParameters[90] ?? 83) }
                            session.setControl(90,value:freeze ? 127 : previousDecay)
                        }))
                    }
                }
            }.formStyle(.grouped).disabled(!session.canEdit || session.recalling)
            .navigationTitle("Mixer").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.frame(minWidth: 320, idealWidth: 520, minHeight: 450)
        .onAppear { seedInput = session.snapshot.seed.map { String($0,radix:16,uppercase:true).leftPadded(to:8) } ?? "" }
    }
    private func control(_ name: String, cc: Int, value: Int?, channel: Int = 1) -> some View {
        HStack {
            Text(name).frame(minWidth: 65,alignment:.leading)
            Slider(value: Binding(get: { Double(value ?? 64) }, set: { session.setControl(cc,value:Int($0),channel:channel) }), in: 0...127) { Text(name) }
            Text(value.map(String.init) ?? "—").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width:30)
        }
    }
}
