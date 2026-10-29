import SwiftUI

@main struct RNDBuddyApp: App {
    @State private var model = AppModel()
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    #endif
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .tint(Design.accent)
                .frame(minWidth: minimumWidth, minHeight: minimumHeight)
        }
        #if os(macOS)
        .defaultSize(width: 1160, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Generate Patch") { model.session.generate() }.keyboardShortcut("g", modifiers: .command).disabled(!model.session.canEdit || model.editingStage)
                Button("Save Patch…") { model.showSave = true }.keyboardShortcut("s", modifiers: .command).disabled(model.session.snapshot.seed == nil)
                Button(model.performance.held ? "Release Hold" : "Hold") { model.performance.held.toggle() }
                    .keyboardShortcut(" ", modifiers: .command).disabled(model.editingStage)
                Button("Edit Layout") { model.editingStage.toggle() }.keyboardShortcut("e", modifiers: .command)
                Divider()
                Button("Fill External Screen") { model.pixels.setExternalPresentation(.fillScreen) }.disabled(!model.pixels.external)
                Button("Floating Visuals Window") { model.pixels.setExternalPresentation(.floating) }.disabled(!model.pixels.external)
                Button("Return Visuals to App") { model.pixels.returnToApp() }.disabled(!model.pixels.external)
                Divider()
                Button("Release All Notes") { model.performance.cancel(); model.session.releaseAll() }.keyboardShortcut(".", modifiers: .command)
            }
        }
        #endif
        #if os(macOS)
        Window("Hands", id: "hands") {
            HandsControls(model: model).tint(Design.accent)
                .frame(minWidth: 280, minHeight: 90)
                .onAppear { model.showHandsPanel = true }
                .onDisappear { model.showHandsPanel = false }
        }
        .defaultSize(width: 360, height: 300)
        .windowLevel(.floating)
        #endif
    }
    private var minimumWidth: CGFloat? {
        #if os(macOS)
        760
        #else
        nil
        #endif
    }
    private var minimumHeight: CGFloat? {
        #if os(macOS)
        600
        #else
        nil
        #endif
    }
}
