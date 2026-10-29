import SwiftUI
@preconcurrency import AVFoundation

#if os(iOS)
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var portrait=true
    func makeUIView(context:Context) -> CameraPreviewView { let view=CameraPreviewView(); view.preview.session=session; view.portrait=portrait; return view }
    func updateUIView(_ view:CameraPreviewView,context:Context) { view.preview.session=session; view.portrait=portrait; view.setNeedsLayout() }
}
final class CameraPreviewView: UIView {
    var portrait=true
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override func layoutSubviews() {
        super.layoutSubviews(); preview.videoGravity = .resizeAspectFill
        if let connection=preview.connection {
            connection.automaticallyAdjustsVideoMirroring=false
            if connection.isVideoMirroringSupported { connection.isVideoMirrored=true }
            let angle:CGFloat = portrait ? 90 : 0
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle=angle }
        }
    }
}
#else
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    var portrait=true
    func makeNSView(context:Context) -> CameraPreviewView { let view=CameraPreviewView(); view.preview.session=session; return view }
    func updateNSView(_ view:CameraPreviewView,context:Context) { view.preview.session=session; view.needsLayout=true }
}
final class CameraPreviewView: NSView {
    let preview=AVCaptureVideoPreviewLayer()
    override init(frame:NSRect) { super.init(frame:frame); wantsLayer=true; layer=preview; preview.videoGravity = .resizeAspectFill }
    required init?(coder:NSCoder) { nil }
    override func layout() {
        super.layout(); preview.frame=bounds
        if let connection=preview.connection,connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring=false; connection.isVideoMirrored=true }
    }
}
#endif
