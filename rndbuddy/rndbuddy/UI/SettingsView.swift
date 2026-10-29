import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var profile = FirmwareProfile.unknown
    var body: some View {
        Form {
            Section("RND") {
                Picker("MIDI device",selection:Binding(get:{model.session.connectedID ?? 0},set:{ model.session.connect($0 == 0 ? nil : $0) })) {
                    Text("Not connected").tag(Int32(0))
                    ForEach(model.session.transport.endpoints) { endpoint in Text(endpoint.name).tag(endpoint.id) }
                }
                if model.session.connected {
                    Picker("Firmware profile",selection:Binding(get:{model.session.snapshot.firmware},set:{model.session.selectFirmware($0)})) {
                        ForEach(FirmwareProfile.allCases) { Text($0.title).tag($0) }
                    }
                    Button("Read Current Patch",systemImage:"arrow.down.circle") { model.session.requestSnapshot() }
                }
                Button("Refresh Devices",systemImage:"arrow.clockwise") { model.session.transport.refresh() }
                Toggle("Demo",isOn:Binding(get:{model.session.demo},set:{ $0 ? model.session.startDemo() : model.session.connect(nil) }))
            }
            Section("Listening") {
                #if os(macOS)
                Picker("Output",selection:Binding(get: { model.audio.outputID }, set: { model.audio.outputID = $0 })) {
                    Text("System output").tag(UInt32(0))
                    ForEach(model.audio.outputs) { output in Text(output.name).tag(output.id) }
                }.disabled(model.audio.running)
                #endif
                Toggle("Monitor RND audio",isOn:Binding(get:{model.audio.running},set:{ value in
                    if value { Task { await model.audio.start(profile:model.session.snapshot.firmware) } } else { model.audio.stop() }
                })).disabled(!model.session.connected)
                if model.audio.running { Slider(value:Binding(get:{Double(model.audio.gain)},set:{model.audio.gain=Float($0)}),in:0...1) { Text("Monitor volume") } }
                Text(model.audio.error ?? model.audio.status).font(.caption).foregroundStyle(.secondary)
            }
            Section("Visuals") {
                Toggle("Allow Pixels MIDI and SysEx",isOn:Binding(get:{model.pixels.permission},set:{ $0 ? model.pixels.allow() : model.pixels.revoke() }))
                Button(model.pixels.external ? "Return Pixels to App" : "Send Pixels to External Display",systemImage:"display") { model.pixels.toggleExternal() }.disabled(!model.pixels.permission)
                Link("RND pixels · cyma forma",destination:URL(string:"https://pixels.cymaforma.com")!)
            }
            Section("Library") {
                Text(model.library?.syncStatus ?? model.startupError ?? "Library unavailable").font(.callout)
                Text("Patches and saved mappings use your private iCloud library when available. Device selection and calibration stay on this device.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Performance") {
                Button("Release All Notes",systemImage:"hand.raised") { model.performance.cancel(); model.session.releaseAll() }
                Text("Camera processing stays on this device. Motion and hands stop when the app leaves the foreground. Started audio monitoring can continue.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Link("RND manual",destination:URL(string:"https://www.cymaforma.com/pages/rnd-synth-manual")!)
                Link("JG-RND",destination:URL(string:"https://github.com/jgharding/JG-RND")!)
                Text("rndbuddy · independent companion").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).navigationTitle("Settings")
    }
}
