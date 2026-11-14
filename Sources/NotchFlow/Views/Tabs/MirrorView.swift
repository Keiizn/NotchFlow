import SwiftUI
import AVFoundation

/// Miroir : aperçu de la caméra FaceTime, pratique avant un appel visio.
@MainActor
struct MirrorView: View {
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        Group {
            switch status {
            case .authorized:
                CameraPreview()
                    .frame(width: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            case .notDetermined:
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Vérifiez votre tête avant une visio")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Activer la caméra") {
                        AVCaptureDevice.requestAccess(for: .video) { _ in
                            Task { @MainActor in
                                status = AVCaptureDevice.authorizationStatus(for: .video)
                            }
                        }
                    }
                    .buttonStyle(PillButtonStyle(tint: .blue))
                }
            default:
                VStack(spacing: 8) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Accès à la caméra refusé")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Ouvrir les réglages") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(PillButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.start()
        return view
    }

    func updateNSView(_ nsView: CameraPreviewView, context: Context) {}

    static func dismantleNSView(_ nsView: CameraPreviewView, coordinator: ()) {
        nsView.stop()
    }
}

final class CameraPreviewView: NSView {
    private let session: AVCaptureSession
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let queue = DispatchQueue(label: "app.notchflow.camera")

    override init(frame frameRect: NSRect) {
        let session = AVCaptureSession()
        session.sessionPreset = .medium
        self.session = session
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: frameRect)

        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1)) // effet miroir
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) n'est pas pris en charge")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.bounds = bounds
        previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    func start() {
        let session = self.session
        queue.async {
            if session.inputs.isEmpty,
               let device = AVCaptureDevice.default(for: .video),
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.beginConfiguration()
                session.addInput(input)
                session.commitConfiguration()
            }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        let session = self.session
        queue.async {
            if session.isRunning { session.stopRunning() }
        }
    }
}
