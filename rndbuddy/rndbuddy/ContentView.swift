import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Group {
            #if os(macOS)
            if model.pixels.fullScreen { PixelsFullScreen(host:model.pixels) }
            else { NavigationSplitView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("rndbuddy").font(.title2).bold().padding(.horizontal, 12).padding(.top, 28)
                    List(AppDestination.allCases, selection: $model.destination) { destination in
                        Label(destination.rawValue, systemImage: destination.symbol).tag(destination)
                    }.listStyle(.sidebar)
                    Text("RND companion").font(.caption).foregroundStyle(.secondary).padding(20).accessibilityHidden(true)
                }.navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 220)
            } detail: { destination } }
            #else
            TabView(selection: $model.destination) {
                Tab("Perform", systemImage: "slider.horizontal.3", value: AppDestination.perform) { NavigationStack { performance } }
                Tab("Library", systemImage: "square.stack", value: AppDestination.library) { NavigationStack { LibraryView(model: model) } }
                Tab("Settings", systemImage: "gearshape", value: AppDestination.settings) { NavigationStack { SettingsView(model: model) } }
            }.tabViewStyle(.sidebarAdaptable)
            #endif
        }
        .background(Design.background(scheme))
        .sheet(isPresented: $model.showMixer) { MixerView(session: model.session) }
        .sheet(isPresented: $model.showAssignments) { MappingView(model: model) }
        .sheet(isPresented: $model.showSave) { SavePatchView(model: model) }
        #if os(iOS)
        .fullScreenCover(isPresented: Binding(get:{model.pixels.fullScreen},set:{model.pixels.fullScreen=$0})) { PixelsFullScreen(host:model.pixels) }
        #else
        .onChange(of:model.pixels.fullScreen) { _, value in
            if let window = NSApplication.shared.keyWindow, window.styleMask.contains(.fullScreen) != value { window.toggleFullScreen(nil) }
        }
        .onReceive(NotificationCenter.default.publisher(for:NSWindow.didExitFullScreenNotification)) { _ in model.pixels.fullScreen=false }
        #endif
        .onChange(of: phase) { _, phase in if phase != .active { model.background() } else { model.library?.reload() } }
        .onChange(of: model.session.connectedID) { _, _ in model.background(); model.audio.stop() }
        .onChange(of: model.session.selectedTrack) { _, _ in model.performance.cancel(); model.session.releaseAll() }
        .alert("rndbuddy", isPresented: Binding(get: { model.session.error != nil }, set: { if !$0 { model.session.error = nil } })) {
            Button("OK") { model.session.error = nil }
        } message: { Text(model.session.error ?? "") }
    }
    @ViewBuilder private var destination: some View {
        switch model.destination {
        case .perform: performance
        case .library: LibraryView(model: model)
        case .settings: SettingsView(model: model)
        }
    }
    private var performance: some View {
        PerformView(model: model)
            .navigationTitle("rndbuddy")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button { model.destination = .settings } label: {
                        HStack(spacing: 6) {
                            Circle().fill(model.session.connected ? .green : model.session.demo ? Design.accent : .secondary).frame(width: 6,height: 6)
                            Text(model.session.demo ? "Demo" : model.session.connected ? "RND" : "Connect")
                                .font(.caption)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                    }.buttonStyle(.plain).accessibilityLabel(model.session.displayName)
                }
                ToolbarItemGroup(placement: .automatic) {
                    Button("Save Patch", systemImage: "bookmark") { model.showSave = true }.disabled(model.session.snapshot.seed == nil || model.library == nil)
                    Button("Mixer", systemImage: "slider.vertical.3") { model.showMixer = true }
                }
            }
    }
}
