import SwiftUI
import WebKit
import Observation
import CoreAudio

@MainActor @Observable final class PixelsHost: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    static weak var active: PixelsHost?
    let session: DeviceSession
    private(set) var webView: WKWebView!
    private(set) var loading = false
    private(set) var error: String?
    private(set) var external = false
    var fullScreen = false
    var permission: Bool { UserDefaults.standard.bool(forKey: "rndbuddy.pixelsPermission") }
    private var sends: [UUID: Task<Void, Never>] = [:]
    private var inputGranted = false
    private var sysexGranted = false
    #if os(macOS)
    private var outputWindow: NSWindow?
    private var externalKeys: Any?
    private let windowDelegate = PixelsWindowDelegate()
    private(set) var externalPresentation = ExternalPresentation.fillScreen
    private var screenObserver: NSObjectProtocol?
    private var externalScreenNumber: Int?
    #else
    weak var externalScene: UIWindowScene?
    private var outputWindow: UIWindow?
    #endif
    var placementChanged: (() -> Void)?

    init(session: DeviceSession) {
        self.session = session; super.init()
        Self.active = self
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(source: WebMIDIPolyfill.source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController.add(WeakScriptHandler(self), name: "rndmidi")
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self; webView.uiDelegate = self
        #if os(iOS)
        webView.isInspectable = false
        #endif
        session.onEvent = { [weak self] event in self?.receive(event) }
        session.onNativeEvent = { [weak self] event in self?.receive(event) }
        session.onConnectionChanged = { [weak self] in self?.pushPorts() }
        #if os(macOS)
        screenObserver = NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.external, let number = self.externalScreenNumber else { return }
                if !NSScreen.screens.contains(where:{ ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue == number }) { self.returnToApp() }
                else if self.externalPresentation == .fillScreen, let screen = self.outputWindow?.screen {
                    self.outputWindow?.setFrame(screen.frame, display: true)
                }
            }
        }
        #else
        externalScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.session.role == .windowExternalDisplayNonInteractive }
        #endif
    }
    func allow() { UserDefaults.standard.set(true, forKey: "rndbuddy.pixelsPermission"); load() }
    func revoke() {
        if external { returnToApp() }; fullScreen=false
        UserDefaults.standard.set(false, forKey: "rndbuddy.pixelsPermission"); inputGranted = false
        for task in sends.values { task.cancel() }; sends.removeAll()
        session.releaseNotes(prefix:"pixels-")
        webView.stopLoading(); webView.loadHTMLString("", baseURL: nil)
    }
    func load() {
        guard permission else { return }
        error = nil; inputGranted = false; sysexGranted = false; loading = true
        webView.load(URLRequest(url: URL(string: "https://pixels.cymaforma.com")!))
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let url = action.request.url
        if url?.scheme == "https", url?.host == "pixels.cymaforma.com", url?.port == nil || url?.port == 443 { decisionHandler(.allow) }
        else { decisionHandler(.cancel) }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        session.releaseNotes(prefix:"pixels-")
        inputGranted = false; sysexGranted = false; for task in sends.values { task.cancel() }; sends.removeAll()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false; error = nil; pushPorts() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loading = false; self.error = "Pixels couldn’t load. Native controls are still available." }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loading = false; self.error = "Pixels lost its connection. Try reloading." }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { loading = false; inputGranted = false; sysexGranted = false; error = "Pixels paused. Reload to continue." }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) {
        // Camera belongs to native Hands; audio monitoring belongs to AudioMonitor.
        decisionHandler(.deny)
    }
    private var portID: String { session.demo ? "rndbuddy-demo" : "rnd-\(session.connectedID ?? 0)" }
    private var ports: [String: [[String: String]]] {
        let port = ["id": portID, "name": session.demo ? "RND Demo" : session.displayName]
        return ["inputs": session.connected || session.demo ? [port] : [], "outputs": session.connected || session.demo ? [port] : []]
    }
    func pushPorts() {
        guard permission else { return }
        evaluate("window.__rndbuddy?.ports(ports)", ["ports": ports])
    }
    private func evaluate(_ script: String, _ arguments: [String: Any]) {
        // Public Objective-C entry point (NS_REFINED_FOR_SWIFT). Avoids a strong
        // dependency on the newer SDK's Swift overlay on iOS 18/macOS 15.
        webView.__callAsyncJavaScript(script,arguments:arguments,inFrame:nil,in:.page,completionHandler:nil)
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame, origin.protocol == "https", origin.host == "pixels.cymaforma.com", origin.port == 443 || origin.port == 0,
              permission, let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "access", let id = body["id"] as? String {
            inputGranted = true
            sysexGranted = sysexGranted || (body["sysex"] as? Bool ?? false)
            evaluate("window.__rndbuddy?.access(id,true,sysex,ports)", ["id": id, "sysex": body["sysex"] as? Bool ?? false, "ports": ports])
        } else if type == "clear" {
            session.releaseNotes(prefix:"pixels-")
            for task in sends.values { task.cancel() }; sends.removeAll()
        } else if type == "send", inputGranted, body["port"] as? String == portID,
                  let raw = body["data"] as? [Int], raw.count <= MIDIStreamParser.maxSysEx,
                  raw.allSatisfy({ (0...255).contains($0) }), sends.count < 256 {
            let bytes = raw.map(UInt8.init)
            guard MIDIStreamParser.valid(bytes), bytes.first != 0xF0 || sysexGranted else { return }
            let delay = (body["delay"] as? Double ?? 0)
            guard delay.isFinite, delay <= 10_000 else { return }
            let id = UUID()
            sends[id] = Task { [weak self] in
                if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
                guard !Task.isCancelled, let self else { return }
                self.forward(bytes); self.sends[id] = nil
            }
        }
    }
    private func forward(_ bytes: [UInt8]) {
        if session.demo {
            if bytes == RNDProtocolCodec.message(0x19) { receive(MIDIEvent(bytes:RNDProtocolCodec.message(0x23,[1,3]),hostTime:mach_absolute_time())) }
            if bytes == RNDProtocolCodec.message(0x18) { publishDemoSnapshot() }
            return
        }
        if session.snapshot.firmware == .jg023 {
            if bytes.starts(with: RNDProtocolCodec.header) {
                // Pixels expects official opcodes. Never forward its official engine,
                // lock/reset or tempo commands to conflicting JG handlers.
                if bytes == RNDProtocolCodec.message(0x19) {
                    receive(MIDIEvent(bytes: RNDProtocolCodec.message(0x23,[1,3]), hostTime: mach_absolute_time()))
                    return
                }
                guard bytes[4] == 0x10 || bytes[4] == 0x18 else { return }
            } else if bytes.count == 3, bytes[0] == 0xB0, bytes[1] == 14 { return }
        }
        if session.snapshot.firmware == .unknown {
            guard bytes == RNDProtocolCodec.message(0x18) else { return }
        }
        session.receiveWeb(bytes)
    }
    private func publishDemoSnapshot() {
        let s = session.snapshot
        var messages: [[UInt8]] = [RNDProtocolCodec.message(0x23,[1,3])]
        if let seed = s.seed { messages.append(RNDProtocolCodec.message(0x10,RNDProtocolCodec.packed(seed))) }
        messages.append(RNDProtocolCodec.message(0x20))
        let bpm = s.tempo ?? 108
        messages.append(RNDProtocolCodec.message(0x21,[UInt8(s.type ?? 0),UInt8(bpm & 127),UInt8(bpm >> 7),UInt8(s.root ?? 0),UInt8(s.scale ?? 0)]))
        for track in s.tracks { messages.append(RNDProtocolCodec.message(0x22,[UInt8(track.id),0,0]+Array((track.engine ?? "FM").utf8)+[0])) }
        for message in messages { receive(MIDIEvent(bytes:message,hostTime:mach_absolute_time())) }
    }
    private func receive(_ event: MIDIEvent) {
        guard permission, inputGranted else { return }
        var info = mach_timebase_info_data_t(); mach_timebase_info(&info)
        let now = mach_absolute_time()
        let age = now >= event.hostTime ? Double(now-event.hostTime) * Double(info.numer) / Double(info.denom) / 1e6 : 0
        evaluate("window.__rndbuddy?.receive(id,data,age)", ["id": portID, "data": event.bytes.map(Int.init), "age": age])
    }
    func toggleExternal() {
        if external { returnToApp(); return }
        #if os(macOS)
        guard let screen = NSScreen.screens.dropFirst().first else { error = "Connect a second display for visual output."; return }
        showExternal(on: screen, presentation: .fillScreen)
        #else
        guard let scene = externalScene else { error = "Connect an external display to send Pixels out."; return }
        webView.removeFromSuperview()
        let controller = UIViewController()
        controller.view.backgroundColor = .black
        controller.view.addSubview(webView)
        webView.frame = controller.view.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let window = UIWindow(windowScene: scene); window.rootViewController = controller; window.isHidden = false; outputWindow = window
        external = true; placementChanged?()
        #endif
    }
    #if os(macOS)
    enum ExternalPresentation: String { case fillScreen, floating }
    var externalDisplays: [NSScreen] { NSScreen.screens.filter { $0 != NSScreen.screens.first } }
    func setExternalPresentation(_ presentation: ExternalPresentation) {
        guard let window = outputWindow, let screen = window.screen else { return }
        showExternal(on: screen, presentation: presentation)
    }
    func showExternal(on screen: NSScreen, presentation: ExternalPresentation) {
        fullScreen = false
        webView.removeFromSuperview()
        outputWindow?.orderOut(nil)
        externalPresentation = presentation
        externalScreenNumber = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue
        let style: NSWindow.StyleMask = presentation == .fillScreen ? [.borderless] : [.titled, .closable, .miniaturizable, .resizable]
        let window = PixelsOutputWindow(contentRect: .zero, styleMask: style, backing: .buffered, defer: false, screen: screen)
        window.title = "RND pixels"
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.level = presentation == .fillScreen ? .mainMenu + 1 : .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let container = NSView()
        window.contentView = container
        let frame = presentation == .fillScreen ? screen.frame : screen.visibleFrame.insetBy(dx: screen.visibleFrame.width * 0.1, dy: screen.visibleFrame.height * 0.1)
        window.setFrame(frame, display: true)
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
        windowDelegate.onClose = { [weak self] in self?.returnToApp() }
        window.delegate = windowDelegate
        outputWindow = window
        external = true
        window.orderFrontRegardless()
        if externalKeys == nil {
            externalKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handleExternalEscape(keyCode: event.keyCode, mouseLocation: NSEvent.mouseLocation) ? nil : event
            }
        }
        placementChanged?()
    }
    @discardableResult func handleExternalEscape(keyCode: UInt16, mouseLocation: NSPoint) -> Bool {
        guard keyCode == 53, external, externalPresentation == .fillScreen,
              let window = outputWindow, window.frame.contains(mouseLocation) else { return false }
        setExternalPresentation(.floating)
        return true
    }
    #endif
    func returnToApp() {
        guard external else { return }
        webView.removeFromSuperview()
        #if os(macOS)
        outputWindow?.orderOut(nil)
        if let externalKeys { NSEvent.removeMonitor(externalKeys); self.externalKeys = nil }
        #else
        outputWindow?.isHidden = true; outputWindow?.rootViewController = nil
        #endif
        outputWindow = nil; external = false; placementChanged?()
    }
}
@MainActor private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var owner: PixelsHost?
    init(_ owner: PixelsHost) { self.owner = owner }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) { owner?.userContentController(controller, didReceive: message) }
}
#if os(macOS)
private final class PixelsOutputWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
private final class PixelsWindowDelegate: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    func windowShouldClose(_ sender: NSWindow) -> Bool { onClose?(); return false }
}
struct PixelsWebView: NSViewRepresentable {
    let host: PixelsHost
    func makeNSView(context: Context) -> NSView { let container = NSView(); mount(container); return container }
    func updateNSView(_ view: NSView, context: Context) { mount(view) }
    private func mount(_ view: NSView) {
        guard !host.external else { return }
        if host.webView.superview !== view { host.webView.removeFromSuperview(); view.addSubview(host.webView) }
        host.webView.frame = view.bounds; host.webView.autoresizingMask = [.width,.height]
    }
}
#else
struct PixelsWebView: UIViewRepresentable {
    let host: PixelsHost
    func makeUIView(context: Context) -> UIView { let container = UIView(); mount(container); return container }
    func updateUIView(_ view: UIView, context: Context) { mount(view) }
    private func mount(_ view: UIView) {
        guard !host.external else { return }
        if host.webView.superview !== view { host.webView.removeFromSuperview(); view.addSubview(host.webView) }
        host.webView.frame = view.bounds; host.webView.autoresizingMask = [.flexibleWidth,.flexibleHeight]
    }
}
final class ExternalDisplayDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }; PixelsHost.active?.externalScene = scene
    }
    func sceneDidDisconnect(_ scene: UIScene) { PixelsHost.active?.returnToApp(); PixelsHost.active?.externalScene = nil }
}
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        if session.role == .windowExternalDisplayNonInteractive { configuration.delegateClass = ExternalDisplayDelegate.self }
        return configuration
    }
}
#endif
