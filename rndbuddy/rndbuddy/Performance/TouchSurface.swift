import SwiftUI

#if os(iOS)
struct TouchSurface: UIViewRepresentable {
    var onChange: ([Contact]) -> Void
    func makeUIView(context: Context) -> ContactView { let view = ContactView(); view.onChange = onChange; return view }
    func updateUIView(_ view: ContactView, context: Context) { view.onChange = onChange }
    static func dismantleUIView(_ view: ContactView, coordinator: ()) { view.cancelAll() }
}
final class ContactView: UIView {
    var onChange: (([Contact]) -> Void)?
    private var contacts: [ObjectIdentifier: Contact] = [:]
    override init(frame: CGRect) {
        super.init(frame: frame); isMultipleTouchEnabled = true; backgroundColor = .clear
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { nil }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { remove(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { remove(touches) }
    private func update(_ touches: Set<UITouch>) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            guard contacts[key] != nil || contacts.count < 4 else { continue }
            let point = touch.location(in: self)
            contacts[key] = Contact(id: contacts[key]?.id ?? UUID().uuidString, x: Double(point.x / max(1,bounds.width)).clamped(0...1), y: Double(point.y / max(1,bounds.height)).clamped(0...1))
        }
        emit()
    }
    private func remove(_ touches: Set<UITouch>) { for touch in touches { contacts[ObjectIdentifier(touch)] = nil }; emit() }
    func cancelAll() { contacts.removeAll(); emit() }
    private func emit() { onChange?(contacts.values.sorted { $0.id < $1.id }) }
}
#else
struct TouchSurface: View {
    var onChange: ([Contact]) -> Void
    var body: some View {
        GeometryReader { geometry in
            Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in
                onChange([Contact(id: "pointer", x: Double(value.location.x / max(1,geometry.size.width)).clamped(0...1), y: Double(value.location.y / max(1,geometry.size.height)).clamped(0...1))])
            }.onEnded { _ in onChange([]) })
        }
    }
}
#endif
