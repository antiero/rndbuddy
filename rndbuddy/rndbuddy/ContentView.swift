import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var scheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
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
        .sheet(isPresented: $model.showCapture) { CaptureView(model: model) }
        .sheet(isPresented: $model.showMixer) { MixerView(session: model.session) }
        .sheet(isPresented: $model.showAssignments) { MappingView(model: model) }
        .sheet(isPresented: $model.showSave) { SavePatchView(model: model) }
        #if os(iOS)
        .fullScreenCover(isPresented: Binding(get:{model.pixels.fullScreen},set:{model.pixels.fullScreen=$0})) { PixelsFullScreen(host:model.pixels) }
        #else
        .onChange(of:model.pixels.fullScreen) { _, value in
            if let window = NSApplication.shared.keyWindow, window.styleMask.contains(.fullScreen) != value { window.toggleFullScreen(nil) }
        }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didResignActiveNotification)) { _ in model.background() }
        .onReceive(NotificationCenter.default.publisher(for:NSWindow.didExitFullScreenNotification)) { _ in model.pixels.fullScreen=false }
        #endif
        .onChange(of: phase) { _, phase in if phase == .background { model.background() } else { model.library?.reload() } }
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
        StageView(model: model)
            .navigationTitle(showsPagePicker ? model.performance.page.name : "rndbuddy")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if showsPagePicker {
                    ToolbarItem(placement: .principal) {
                        Picker("Page", selection: Binding(get: { model.performance.pageIndex }, set: { model.performance.pageIndex = $0 })) {
                            ForEach(model.performance.pages.indices, id: \.self) { Text(model.performance.pages[$0].name).tag($0) }
                        }.pickerStyle(.segmented).fixedSize()
                    }
                }
                ToolbarItem(placement: .automatic) { connectionButton }
                ToolbarItemGroup(placement: .automatic) {
                    if !model.stageSplit {
                        Menu("Overlay", systemImage: model.overlay == .off ? "square.3.layers.3d.slash" : "square.3.layers.3d") {
                            Picker("Controls over visuals", selection: $model.overlay) {
                                ForEach(OverlayVisibility.allCases) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.inline)
                        }.help("Show, ghost or hide the controls over the visuals")
                    }
                    PerformanceMenu(model: model)
                    if compact {
                        Menu("More", systemImage: "ellipsis.circle") {
                            Button("Mixer", systemImage: "slider.vertical.3") { model.showMixer = true }
                            Button("Capture", systemImage: "waveform") { model.showCapture = true }
                            Button("Save Patch", systemImage: "bookmark") { model.showSave = true }.disabled(model.session.snapshot.seed == nil || model.library == nil)
                            if model.pixels.permission { Section("Visuals") { PixelsMenuItems(model: model) } }
                        }
                    } else {
                        if model.pixels.permission { Menu("Visuals", systemImage: "display") { PixelsMenuItems(model: model) }.help("Pixels display options") }
                        Button("Mixer", systemImage: "slider.vertical.3") { model.showMixer = true }
                        Button("Capture", systemImage: model.audio.recording ? "record.circle.fill" : "waveform") { model.showCapture = true }.help("Monitor and record RND USB audio")
                        Button("Save Patch", systemImage: "bookmark") { model.showSave = true }.disabled(model.session.snapshot.seed == nil || model.library == nil)
                    }
                }
            }
    }
    private var connectionButton: some View {
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
    private var compact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }
    private var showsPagePicker: Bool { !compact && !model.stageSplit }
}

/// Field mode, input method, arming and assignments, kept out of the stage itself.
struct PerformanceMenu: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        let performance = model.performance
        Menu("Performance", systemImage: performance.armed ? "hand.raised.fill" : "hand.raised") {
            Picker("Field", selection: Binding(get: { performance.mode }, set: { mode in
                if mode == .play { model.showTakeover = true } else { performance.mode = mode }
            })) { ForEach(PerformanceMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Picker("Input", selection: Binding(get: { performance.method }, set: { model.changeInput($0) })) {
                Text("Touch").tag(InputMethod.touch)
                Text("Hands").tag(InputMethod.hands)
                if model.motion.available { Text("Motion").tag(InputMethod.motion) }
            }
            if performance.method != .touch {
                Button(performance.armed ? "Disarm" : "Arm", systemImage: performance.armed ? "stop.circle" : "hand.raised") { model.arm(!performance.armed) }
                if performance.method == .motion { Button("Calibrate", systemImage: "scope") { model.motion.calibrate() } }
                if performance.method == .hands {
                    Button("Camera Controls", systemImage: "pip") {
                        model.showHandsPanel = true
                        #if os(macOS)
                        openWindow(id: "hands")
                        #endif
                    }
                }
            }
            Divider()
            Button("Assignments…", systemImage: "slider.horizontal.below.square.and.square.filled") { model.showAssignments = true }
            Button("Release All Notes", systemImage: "speaker.slash") { performance.cancel(); model.session.releaseAll() }
        }
        .help("Field mode, input and assignments")
    }
}
