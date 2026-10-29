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
                Button("Generate Patch") { model.session.generate() }.keyboardShortcut("g", modifiers: .command).disabled(!model.session.canEdit)
                Button("Save Patch…") { model.showSave = true }.keyboardShortcut("s", modifiers: .command).disabled(model.session.snapshot.seed == nil)
                Divider()
                Button("Release All Notes") { model.performance.cancel(); model.session.releaseAll() }.keyboardShortcut(".", modifiers: .command)
            }
        }
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
