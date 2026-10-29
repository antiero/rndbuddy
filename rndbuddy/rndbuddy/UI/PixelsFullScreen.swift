import SwiftUI

struct PixelsFullScreen: View {
    @Bindable var host: PixelsHost
    var body: some View {
        ZStack(alignment:.topTrailing) {
            PixelsWebView(host:host).ignoresSafeArea()
            Button("Close",systemImage:"xmark") { host.fullScreen=false }
                .labelStyle(.iconOnly).buttonStyle(.bordered).padding(20)
                .keyboardShortcut(.cancelAction)
        }
    }
}
