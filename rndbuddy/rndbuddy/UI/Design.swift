import SwiftUI

enum Design {
    static let accent = Color(red: 0.96, green: 0.28, blue: 0.10)
    static let tracks: [Color] = [accent, Color(red: 0.43, green: 0.49, blue: 0.73), Color(red: 0.57, green: 0.58, blue: 0.37), Color(red: 0.59, green: 0.44, blue: 0.60)]
    static func background(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 0.09,green: 0.09,blue: 0.085) : Color(red: 0.96,green: 0.95,blue: 0.93) }
    // Stage: visuals stay monochrome, controls carry track colour. Tracks 2 and 4 are lifted for the dark stage.
    static let stageTracks: [Color] = [accent, Color(red: 0.49, green: 0.55, blue: 0.80), Color(red: 0.64, green: 0.65, blue: 0.42), Color(red: 0.66, green: 0.50, blue: 0.68)]
    static let stageInk = Color(red: 0.95, green: 0.95, blue: 0.93)
    static let stageBackground = Color(red: 0.07, green: 0.07, blue: 0.067)
    static let scrim = Color(red: 0.05, green: 0.05, blue: 0.043).opacity(0.58)
    static let stageLine = Color.white.opacity(0.14)
    static func panel(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(red: 0.13,green: 0.13,blue: 0.12) : Color(red: 0.99,green: 0.98,blue: 0.96) }
}
struct PanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View { content.padding(20).background(Design.panel(scheme), in: .rect(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.08), lineWidth: 1)) }
}
extension View { func instrumentPanel() -> some View { modifier(PanelModifier()) } }
