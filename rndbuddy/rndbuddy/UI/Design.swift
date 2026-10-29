import SwiftUI

enum Design {
    static let accent = Color(red: 0.96, green: 0.28, blue: 0.10)
    static let tracks: [Color] = [accent, Color(red: 0.43, green: 0.49, blue: 0.73), Color(red: 0.57, green: 0.58, blue: 0.37), Color(red: 0.59, green: 0.44, blue: 0.60)]
    static func background(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 0.09,green: 0.09,blue: 0.085) : Color(red: 0.96,green: 0.95,blue: 0.93) }
    static func panel(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 0.13,green: 0.13,blue: 0.12) : Color(red: 0.99,green: 0.98,blue: 0.96) }
}
struct PanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View { content.padding(20).background(Design.panel(scheme), in: .rect(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.08), lineWidth: 1)) }
}
extension View { func instrumentPanel() -> some View { modifier(PanelModifier()) } }
