import SwiftUI

struct CameraSettingsButton: View {
    @Environment(\.openURL) private var openURL
    var body: some View {
        Button("Camera Settings", systemImage: "gearshape") {
            #if os(iOS)
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            #else
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
            #endif
        }
    }
}
