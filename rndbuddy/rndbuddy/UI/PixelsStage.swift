import SwiftUI

struct PixelsStage: View {
    @Bindable var model: AppModel
    /// Stage mode: edge to edge, options move to the toolbar.
    var fullBleed = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Design.panel(scheme)
            if model.pixels.permission && !model.pixels.external && !model.pixels.fullScreen {
                PixelsWebView(host: model.pixels).accessibilityHidden(true)
                if model.pixels.loading { ProgressView().padding(16).background(.regularMaterial, in: .capsule) }
            } else {
                DotSculpture(activity: model.session.activity).opacity(0.08)
                VStack(spacing: 10) {
                    Spacer()
                    if model.pixels.external {
                        Label("Pixels is on your external display", systemImage: "display").font(.callout)
                        Button("Bring back") { model.pixels.returnToApp() }
                    } else {
//                        Text("RND pixels").font(.headline)
                        Text("Visuals by cyma forma").font(.caption).foregroundStyle(.secondary)
                        Button("Enable Pixels", systemImage: "sparkles") { model.pixels.allow() }.buttonStyle(.borderedProminent)
                            .help("Allow the Pixels website to exchange MIDI and SysEx with your selected RND")
                        if !model.session.connected && !model.session.demo { Button("Explore Demo") { model.startPixelsDemo() }.buttonStyle(.plain).padding(.top,4) }
                    }
                }.padding(24)
            }
            VStack {
                if !fullBleed { HStack {
                    if model.session.demo { Text("DEMO").font(.caption2.monospaced()).tracking(2).padding(8).background(.regularMaterial,in:.capsule) }
                    Spacer()
                    if model.pixels.permission {
                        Menu { PixelsMenuItems(model: model) } label: { Image(systemName: "ellipsis").frame(width: 40,height: 40).background(.regularMaterial, in: .circle) }
                        .accessibilityLabel("Pixels options")
                    }
                } }
                if fullBleed { Spacer().frame(height: 56) } else { Spacer() }
                if let error = model.pixels.error {
                    HStack { Text(error).font(.caption); Button("Reload") { model.pixels.load() } }.padding(12).background(.regularMaterial,in:.rect(cornerRadius:12))
                }
                if fullBleed { Spacer() }
            }.padding(12)
        }.clipShape(.rect(cornerRadius: fullBleed ? 0 : 18)).overlay(RoundedRectangle(cornerRadius:fullBleed ? 0 : 18).stroke(.primary.opacity(fullBleed ? 0 : 0.08),lineWidth:1))
    }
}
struct DotSculpture: View {
    let activity: [Double]
    var body: some View {
        Canvas { context,size in
            let center = CGPoint(x:size.width/2,y:size.height*0.36)
            let radius = min(size.width*0.3,size.height*0.35)
            for row in -10...10 {
                for column in -14...14 {
                    let x = Double(column) * 0.075 + (row % 2 == 0 ? 0 : 0.0375)
                    let y = Double(row)*0.075
                    let distance = x*x + y*y
                    let wave = sin(x*9 + y*6) * cos(y*7-x*5)
                    if distance < 0.85 && wave > -0.38 {
                        let point = CGPoint(x:center.x+x*radius,y:center.y+y*radius)
                        let opacity = 0.15 + 0.6 * (1-distance) + (activity.isEmpty ? 0 : activity[abs(row)%4]*0.1)
                        context.fill(Path(ellipseIn:CGRect(x:point.x-2,y:point.y-2,width:4,height:4)),with:.color(.primary.opacity(opacity)))
                    }
                }
            }
        }.accessibilityHidden(true)
    }
}

struct PixelsMenuItems: View {
    @Bindable var model: AppModel
    var body: some View {
        Button("Full Screen",systemImage:"arrow.up.left.and.arrow.down.right") { if model.pixels.external { model.pixels.returnToApp() }; model.presentStage(.normal); model.pixels.fullScreen = true }
        #if os(macOS)
        if model.pixels.external {
            Button("Fill External Screen", systemImage: "arrow.up.left.and.arrow.down.right") { model.pixels.setExternalPresentation(.fillScreen) }
            Button("Floating Visuals Window", systemImage: "macwindow") { model.pixels.setExternalPresentation(.floating) }
        }
        Menu("External Display") {
            ForEach(model.pixels.externalDisplays, id: \.self) { screen in
                Button(screen.localizedName) { model.pixels.showExternal(on: screen, presentation: .fillScreen) }
            }
        }
        #endif
        Button("Reload Pixels", systemImage: "arrow.clockwise") { model.pixels.load() }
        Button(model.pixels.external ? "Return to App" : "Send to External Display", systemImage: "display") { model.pixels.toggleExternal() }
    }
}
