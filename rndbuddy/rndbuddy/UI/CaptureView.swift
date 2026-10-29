import SwiftUI

struct CaptureView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        @Bindable var audio = model.audio
        NavigationStack {
            Form {
                Section("USB Audio") {
                    #if os(macOS)
                    Picker("Output", selection: $audio.outputID) {
                        Text("System output").tag(UInt32(0))
                        ForEach(model.audio.outputs) { Text($0.name).tag($0.id) }
                    }.disabled(model.audio.running || model.audio.preparing)
                    #endif
                    Toggle("Monitor", isOn: Binding(get: { model.audio.running && model.audio.monitoring }, set: { enabled in
                        model.audio.setMonitoring(enabled)
                        if enabled && !model.audio.running {
                            Task { await model.audio.start(profile: model.session.snapshot.firmware) }
                        } else if !enabled && !model.audio.recording { model.audio.stop() }
                    })).disabled(!model.session.connected || model.audio.preparing)
                    if model.audio.running {
                        ProgressView(value: Double(min(1, model.audio.level)))
                            .tint(model.audio.level >= 0.99 ? .red : Design.accent)
                            .accessibilityLabel("Input level")
                        if model.audio.monitoring {
                            Slider(value: $audio.gain, in: 0...1) { Text("Monitor volume") }
                        }
                    }
                    HStack {
                        Button(model.audio.recording ? "Stop Recording" : "Record", systemImage: model.audio.recording ? "stop.fill" : "record.circle") {
                            if model.audio.recording { model.audio.stopRecording() }
                            else { Task { await model.audio.startRecording(profile: model.session.snapshot.firmware) } }
                        }.buttonStyle(.borderedProminent)
                            .tint(model.audio.recording ? .red : Design.accent)
                            .disabled(!model.session.connected || model.audio.preparing)
                        Spacer()
                        if model.audio.recording {
                            Text(Duration.seconds(model.audio.elapsed), format: .time(pattern: .minuteSecond))
                                .monospacedDigit().accessibilityLabel("Recording duration")
                        }
                    }
                    if model.audio.running { Text(model.audio.status).font(.caption).foregroundStyle(.secondary) }
                    if let error = model.audio.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                }
                if !model.audio.takes.isEmpty {
                    Section("Recordings") {
                        ForEach(model.audio.takes, id: \.self) { url in
                            HStack {
                                Text(url.deletingPathExtension().lastPathComponent).lineLimit(1)
                                Spacer()
                                ShareLink(item: url) { Label("Export Recording", systemImage: "square.and.arrow.up") }
                                    .labelStyle(.iconOnly)
                                    .help("Export this WAV recording")
                                #if os(macOS)
                                Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                    .labelStyle(.iconOnly)
                                #endif
                            }
                        }
                    }
                }
            }.formStyle(.grouped).navigationTitle("Capture")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .frame(minWidth: 320, idealWidth: 480, minHeight: 360, idealHeight: 520)
    }
}
