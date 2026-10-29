import SwiftUI

/// Multi-touch XY field. Modulate: first contact drives both bindings. Play: each contact is a note.
struct FieldControl: View {
    @Bindable var model: AppModel
    let control: ControlSpec
    @State private var accessibleX = 0.5
    @State private var accessibleY = 0.5
    var body: some View {
        let performance = model.performance
        let selected = model.session.selectedTrack
        let contacts = performance.touches[control.id] ?? []
        let tint = performance.mode == .play ? Design.stageTracks[selected] : StageText.colour(control.bindings.first, selected: selected)
        ZStack {
            FieldGrid()
            Canvas { context, size in
                for contact in contacts {
                    let point = CGPoint(x: contact.x * size.width, y: contact.y * size.height)
                    func circle(_ radius: CGFloat) -> Path { Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)) }
                    context.fill(circle(30), with: .color(tint.opacity(0.16)))
                    context.stroke(circle(28), with: .color(tint), lineWidth: 1)
                    context.fill(circle(11), with: .color(.white))
                    context.fill(circle(9), with: .color(tint))
                }
            }
            .allowsHitTesting(false)
            VStack {
                HStack {
                    Text(yLabel(selected) + " ↑")
                    Spacer()
                    if performance.held { Image(systemName: "pause.fill").accessibilityLabel("Holding") }
                }
                Spacer()
                HStack { Spacer(); Text(xLabel(selected) + " →") }
            }
            .font(.caption).foregroundStyle(Design.stageInk.opacity(0.75))
            .padding(14).allowsHitTesting(false)
            TouchSurface { performance.update(control.id, $0) }
        }
        .clipShape(.rect(cornerRadius: 20))
        .stageSurface(active: !contacts.isEmpty, tint: tint, radius: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(control.title) field")
        .accessibilityRepresentation { accessibleSliders(selected) }
        .contextMenu { Button("Release All Notes") { performance.cancel(); model.session.releaseAll() } }
    }
    private func xLabel(_ selected: Int) -> String {
        model.performance.mode == .play ? "Pitch" : StageText.label(control.bindings[0], selected: selected)
    }
    private func yLabel(_ selected: Int) -> String {
        model.performance.mode == .play ? (control.playYAxis ?? .volume).rawValue : StageText.label(control.bindings[1], selected: selected)
    }
    @ViewBuilder private func accessibleSliders(_ selected: Int) -> some View {
        let performance = model.performance
        VStack {
            Slider(value: $accessibleX, in: 0...1) { Text(xLabel(selected)) }
                .onChange(of: accessibleX) { _, x in
                    guard performance.mode == .modulate else { return }
                    performance.update(control.id, [Contact(id: "accessibility", x: x, y: 1 - accessibleY)]); performance.update(control.id, [])
                }
            Slider(value: $accessibleY, in: 0...1) { Text(yLabel(selected)) }
                .onChange(of: accessibleY) { _, y in
                    guard performance.mode == .modulate else { return }
                    performance.update(control.id, [Contact(id: "accessibility", x: accessibleX, y: 1 - y)]); performance.update(control.id, [])
                }
        }
    }
}

struct FieldGrid: View {
    var body: some View {
        Canvas { context, size in
            var grid = Path()
            for x in stride(from: 0.0, through: size.width, by: 32) { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)) }
            for y in stride(from: 0.0, through: size.height, by: 32) { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)) }
            context.stroke(grid, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
            var axes = Path()
            axes.move(to: CGPoint(x: size.width / 2, y: 0)); axes.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            axes.move(to: CGPoint(x: 0, y: size.height / 2)); axes.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(axes, with: .color(.white.opacity(0.2)), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}
