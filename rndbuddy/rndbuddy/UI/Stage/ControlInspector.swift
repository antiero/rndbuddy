import SwiftUI

struct ControlInspector: View {
    @Bindable var model: AppModel
    let editor: StageEditor
    let control: ControlSpec
    var body: some View {
        Section("Selected control") {
            TextField("Title", text: field(\.title))
            if control.kind == .trigger {
                Picker("Action", selection: Binding(get: { control.action ?? .hold }, set: { value in var copy = control; copy.action = value; editor.update(model, control: copy) })) {
                    ForEach(TriggerAction.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
            }
            if control.kind == .keys || control.kind == .xy {
                Picker("Play expression", selection: Binding(get: { control.playYAxis ?? .volume }, set: { value in var copy = control; copy.playYAxis = value; editor.update(model, control: copy) })) {
                    ForEach(PlayYAxis.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
            if let reason = FirmwareCapabilities.reason(control, firmware: model.session.snapshot.firmware) { Text(reason).foregroundStyle(.secondary) }
        }
        ForEach(control.bindings.indices, id: \.self) { index in
            Section(control.bindings.count == 2 ? (index == 0 ? "Horizontal" : "Vertical") : "Binding") {
                let binding = control.bindings[index]
                Picker("Target", selection: bindingField(index, \.target)) {
                    ForEach(MappingTarget.allCases) { target in
                        Text(target.rawValue).tag(target)
                            .disabled(!FirmwareCapabilities.supports(target, firmware: model.session.snapshot.firmware))
                    }
                }
                Picker("Track", selection: bindingField(index, \.scope)) {
                    Text("Selected").tag(TrackScope.selected)
                    ForEach(0..<4, id: \.self) { Text("Track \($0 + 1)").tag(TrackScope.fixed($0)) }
                }
                Picker("Curve", selection: bindingField(index, \.curve)) {
                    ForEach(ResponseCurve.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Slider(value: bindingField(index, \.axis.minimum), in: 0...1) { Text("Minimum") }
                Slider(value: bindingField(index, \.axis.maximum), in: 0...1) { Text("Maximum") }
                Toggle("Invert", isOn: bindingField(index, \.axis.inverted))
                Slider(value: bindingField(index, \.axis.smoothing), in: 0...0.95) { Text("Smoothing") }
                Slider(value: bindingField(index, \.axis.deadZone), in: 0...0.1) { Text("Dead zone") }
                DisclosureGroup("Input sources") {
                    ForEach(InputSource.allCases.filter { $0 != .touch && $0 != .keys }, id: \.self) { source in
                        Toggle(source.title, isOn: Binding(get: { binding.sources.contains(source) }, set: { on in
                            var copy = control
                            if on { copy.bindings[index].sources.insert(source) } else { copy.bindings[index].sources.remove(source) }
                            editor.update(model, control: copy)
                        }))
                    }
                }
                if duplicate(binding) { Label("Another control uses this target", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary) }
            }
        }
        Section("Position and size") {
            let placement = PerformanceLayout.flow(model.performance.page, in: model.stageLayout).placements.first { $0.controlID == control.id }
            if let placement {
                Stepper("Column: \(placement.column + 1)", value: position(placement, \.column), in: 0...(model.stageLayout.grid.columns - placement.width))
                Stepper("Row: \(placement.row + 1)", value: position(placement, \.row), in: 0...(model.stageLayout.grid.rows - placement.height))
                Stepper("Width: \(placement.width)", value: position(placement, \.width), in: 1...(model.stageLayout.grid.columns - placement.column))
                Stepper("Height: \(placement.height)", value: position(placement, \.height), in: 1...(model.stageLayout.grid.rows - placement.row))
            }
            Button("Duplicate Control") {
                let copy = ControlSpec(kind: control.kind, title: control.title, bindings: control.bindings, action: control.action, playYAxis: control.playYAxis)
                editor.change(model) { $0[model.performance.pageIndex].controls.append(copy) }; editor.selection = copy.id
            }.disabled(model.performance.page.controls.count >= PerformancePage.maxControls)
            Button("Delete Control", role: .destructive) {
                editor.change(model) { pages in
                    let p = model.performance.pageIndex
                    pages[p].controls.removeAll { $0.id == control.id }
                    pages[p].placements = pages[p].placements.mapValues { $0.filter { $0.controlID != control.id } }
                }; editor.selection = nil
            }
        }
    }
    private func field<T>(_ path: WritableKeyPath<ControlSpec, T>) -> Binding<T> {
        Binding(get: { control[keyPath: path] }, set: { value in var copy = control; copy[keyPath: path] = value; editor.update(model, control: copy) })
    }
    private func bindingField<T>(_ index: Int, _ path: WritableKeyPath<ControlBinding, T>) -> Binding<T> {
        Binding(get: { control.bindings[index][keyPath: path] }, set: { value in
            var copy = control; copy.bindings[index][keyPath: path] = value
            copy.bindings[index].axis.target = copy.bindings[index].target
            editor.update(model, control: copy)
        })
    }
    private func position(_ placement: Placement, _ path: WritableKeyPath<Placement, Int>) -> Binding<Int> {
        Binding(get: { placement[keyPath: path] }, set: { value in var copy = placement; copy[keyPath: path] = value; editor.place(model, copy) })
    }
    private func duplicate(_ binding: ControlBinding) -> Bool {
        let target = binding.control(selectedTrack: model.session.selectedTrack)
        return model.performance.page.controls.filter { $0.id != control.id }.contains { other in
            other.bindings.contains { $0.control(selectedTrack: model.session.selectedTrack) == target }
        }
    }
}
extension InputSource {
    var title: String {
        switch self {
        case .touch: "Touch"
        case .hands: "Hands · pinch XY"
        case .motion: "Motion · XY"
        case .keys: "Keyboard"
        case .rightPalmX: "Right palm · horizontal"
        case .rightPalmY: "Right palm · vertical"
        case .leftPalmX: "Left palm · horizontal"
        case .leftPalmY: "Left palm · vertical"
        case .rightHeight: "Right hand · height"
        case .leftHeight: "Left hand · height"
        case .rightPinch: "Right hand · pinch"
        case .leftPinch: "Left hand · pinch"
        case .motionPitch: "Motion · pitch"
        case .motionRoll: "Motion · roll"
        }
    }
}
