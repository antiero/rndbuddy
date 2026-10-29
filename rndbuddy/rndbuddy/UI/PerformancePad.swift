import SwiftUI

struct PerformancePad: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @State private var accessibleX = 0.5
    @State private var accessibleY = 0.5
    @State private var accessibleDegree = 0
    @State private var accessibleNoteTask:Task<Void,Never>?
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Picker(selection: Binding(get: { model.performance.mode }, set: { mode in
                    if mode == .play { model.showTakeover = true } else { model.performance.mode = mode }
                })) { ForEach(PerformanceMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } } label: { EmptyView() }
                .pickerStyle(.segmented)
                .accessibilityLabel("Performance mode")
                .frame(maxWidth: 220)
                Spacer()
                Button("Assignments", systemImage: "arrow.up.left.and.arrow.down.right") { model.showAssignments = true }.labelStyle(.iconOnly).help("Assign performance controls")
                Button("Hold", systemImage: model.performance.held ? "pause.circle.fill" : "pause.circle") { model.performance.held.toggle() }
                    .labelStyle(.iconOnly).help("Hold the current performance values")
            }
            ZStack {
                GridArtwork()
                if model.performance.method == .hands && model.hands.running && model.showCameraPreview && !model.showHandsPanel {
                    CameraPreview(session:model.hands.captureSession,portrait:model.hands.portrait).opacity(0.3).allowsHitTesting(false).accessibilityHidden(true)
                }
                Canvas { context, size in
                    for contact in model.performance.contacts {
                        let point = CGPoint(x: contact.x * size.width, y: contact.y * size.height)
                        let colour = Design.tracks[model.session.selectedTrack]
                        context.fill(Path(ellipseIn: CGRect(x: point.x-22,y: point.y-22,width:44,height:44)), with: .color(colour.opacity(0.09)))
                        context.fill(Path(ellipseIn: CGRect(x: point.x-7,y: point.y-7,width:14,height:14)), with: .color(colour))
                        context.stroke(Path(ellipseIn: CGRect(x: point.x-9,y: point.y-9,width:18,height:18)), with: .color(.white), lineWidth: 1.5)
                    }
                }.allowsHitTesting(false).accessibilityHidden(true)
                VStack {
                    HStack {
                        Text(model.performance.mode == .play ? "Velocity" : model.performance.mapping.y.target.rawValue).font(.caption2)
                        Spacer()
                        if model.performance.held { Image(systemName: "pause.fill").accessibilityLabel("Holding") }
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        Text(model.performance.mode == .play ? "Pitch →" : model.performance.mapping.x.target.rawValue + " →").font(.caption2)
                    }
                }.padding(12).foregroundStyle(.secondary).allowsHitTesting(false)
                TouchSurface { model.performance.update($0) }
            }
            .frame(height: 145)
            .clipShape(.rect(cornerRadius: 12))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Performance surface")
            .accessibilityHint("Adjust the assigned parameters using these controls.")
        .accessibilityRepresentation {
            VStack {
                if model.performance.mode == .play {
                    Stepper("Note degree \(accessibleDegree+1)",value:$accessibleDegree,in:0...13)
                    Button("Play selected note") { playAccessibleNote() }
                } else { Group {
                Slider(value: $accessibleX, in: 0...1) { Text("\(model.performance.mapping.x.target.rawValue)") }.onChange(of: accessibleX) { _, value in
                    let axis = model.performance.mapping.x; let (cc,channel) = axis.target.control(track: model.session.selectedTrack)
                    model.session.setControl(cc, value: Int(axis.mapped(value)*127), channel: channel)
                }
                Slider(value: $accessibleY, in: 0...1) { Text("\(model.performance.mapping.y.target.rawValue)") }.onChange(of: accessibleY) { _, value in
                    let axis = model.performance.mapping.y; let (cc,channel) = axis.target.control(track: model.session.selectedTrack)
                    model.session.setControl(cc, value: Int(axis.mapped(value)*127), channel: channel)
                }
                } }
            }
        }
            .contextMenu {
                Button("Release All Notes") { model.performance.cancel(); model.session.releaseAll() }
            }
            HStack {
                Picker(selection: Binding(get: { model.performance.method }, set: { model.changeInput($0) })) {
                    Text("Touch").tag(InputMethod.touch)
                    Text("Hands").tag(InputMethod.hands)
                    if model.motion.available { Text("Motion").tag(InputMethod.motion) }
                } label: { EmptyView() }
                .pickerStyle(.segmented)
                .accessibilityLabel("Input method")
                .frame(maxWidth: 260)
                Spacer(minLength: 8)
                if model.performance.method == .hands {
                    Button("Camera Controls", systemImage: "pip") {
                        model.showHandsPanel = true
                        #if os(macOS)
                        openWindow(id: "hands")
                        #endif
                    }.labelStyle(.iconOnly).help("Open movable camera controls")
                }
                if model.performance.method != .touch {
                    Button(model.performance.armed ? "Disarm" : "Arm", systemImage: model.performance.armed ? "stop.circle" : "hand.raised") { model.arm(!model.performance.armed) }.buttonStyle(.bordered)
                    if model.performance.method == .motion { Button("Calibrate", systemImage: "scope") { model.motion.calibrate() }.labelStyle(.iconOnly) }
                }
            }
            if let error = model.hands.error, model.performance.method == .hands { Text(error).font(.caption).foregroundStyle(.secondary) }

        }
        .instrumentPanel()

        .onKeyPress(characters: CharacterSet(charactersIn: "awsedftgyhujk"), phases: [.down,.up]) { press in
            guard model.performance.mode == .play, let char = press.characters.first,
                  let step = Array("awsedftgyhujk").firstIndex(of: char) else { return .ignored }
            let snapshot = model.session.snapshot
            let intervals = RNDProtocolCodec.intervals[snapshot.scale ?? 0]
            let note = ((snapshot.octave+1)*12+(snapshot.root ?? 0)+intervals[step % intervals.count]+12*(step / intervals.count)).clamped(0...127)
            model.session.note(source: "key-\(char)", note: press.phase == .up ? nil : note, track: model.session.selectedTrack)
            return .handled
        }
        .focusable()
        .onDisappear { accessibleNoteTask?.cancel(); model.session.note(source:"accessibility",note:nil,track:model.session.selectedTrack) }
        .disabled(!model.session.canEdit || model.session.recalling)
    }
    private func playAccessibleNote() {
        accessibleNoteTask?.cancel()
        let snapshot=model.session.snapshot
        let intervals=RNDProtocolCodec.intervals[snapshot.scale ?? 0]
        let note=((snapshot.octave+1)*12+(snapshot.root ?? 0)+intervals[accessibleDegree % intervals.count]+12*(accessibleDegree / intervals.count)).clamped(0...127)
        model.session.note(source:"accessibility",note:nil,track:model.session.selectedTrack)
        model.session.note(source:"accessibility",note:note,track:model.session.selectedTrack)
        accessibleNoteTask=Task { @MainActor in
            try? await Task.sleep(for:.milliseconds(250))
            guard !Task.isCancelled else { return }
            model.session.note(source:"accessibility",note:nil,track:model.session.selectedTrack)
        }
    }

}
struct GridArtwork: View {
    var body: some View {
        Canvas { context,size in
            var grid = Path()
            for x in stride(from: 0.0, through: size.width, by: 24) { grid.move(to: CGPoint(x:x,y:0)); grid.addLine(to: CGPoint(x:x,y:size.height)) }
            for y in stride(from: 0.0, through: size.height, by: 24) { grid.move(to: CGPoint(x:0,y:y)); grid.addLine(to: CGPoint(x:size.width,y:y)) }
            context.stroke(grid, with: .color(.primary.opacity(0.035)), lineWidth: 0.5)
            var axes = Path(); axes.move(to: CGPoint(x:size.width/2,y:0)); axes.addLine(to: CGPoint(x:size.width/2,y:size.height)); axes.move(to: CGPoint(x:0,y:size.height/2)); axes.addLine(to: CGPoint(x:size.width,y:size.height/2))
            context.stroke(axes, with: .color(.primary.opacity(0.1)), lineWidth: 0.5)
        }.background(.primary.opacity(0.018)).accessibilityHidden(true)
    }
}
