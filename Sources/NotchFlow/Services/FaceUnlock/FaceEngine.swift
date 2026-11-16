import AVFoundation
import CoreImage
import Vision

/// Une image analysée : empreinte du visage + indices de pose / vivacité.
struct FaceSample: Sendable {
    /// Empreinte normalisée (norme 1) du visage recadré et redressé.
    let embedding: [Float]
    /// Cadre du visage (coordonnées normalisées Vision, origine en bas à gauche).
    let rect: CGRect
    let yaw: Double
    let roll: Double
    let pitch: Double
    /// Ouverture moyenne des yeux (hauteur / largeur de l'œil).
    let eyeOpenness: Double
    /// Décalage horizontal du nez par rapport au milieu des yeux (parallaxe d'un vrai visage en 3D).
    let noseOffset: Double
    /// Un rectangle de type écran / photo encadre le visage.
    let framedByDevice: Bool
    let time: TimeInterval
}

enum FaceMath {
    static func normalize(_ v: [Float]) -> [Float] {
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return v }
        return v.map { $0 / norm }
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        for i in 0..<a.count { dot += a[i] * b[i] }
        return dot
    }

    static func centroid(_ vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first else { return [] }
        var sum = [Float](repeating: 0, count: first.count)
        for v in vectors where v.count == sum.count {
            for i in 0..<v.count { sum[i] += v[i] }
        }
        return normalize(sum)
    }
}

/// Analyse d'une image caméra avec Vision (100 % local, rien n'est conservé).
enum FaceAnalyzer {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func analyze(_ pixelBuffer: CVPixelBuffer, time: TimeInterval) -> FaceSample? {
        let landmarks = VNDetectFaceLandmarksRequest()
        let rectangles = VNDetectRectanglesRequest()
        rectangles.maximumObservations = 6
        rectangles.minimumAspectRatio = 0.3
        rectangles.minimumSize = 0.2
        rectangles.minimumConfidence = 0.6

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do { try handler.perform([landmarks, rectangles]) } catch { return nil }

        // Visage principal : le plus grand, suffisamment proche de la caméra.
        guard let face = (landmarks.results ?? []).max(by: { $0.boundingBox.width < $1.boundingBox.width }),
              face.boundingBox.width >= 0.12 else { return nil }

        let box = face.boundingBox
        let roll = face.roll?.doubleValue ?? 0
        let yaw = face.yaw?.doubleValue ?? 0
        var pitch = 0.0
        if #available(macOS 12.0, *) { pitch = face.pitch?.doubleValue ?? 0 }

        // Écran ou photo tenu devant la caméra : un rectangle serré autour du visage.
        let framed = (rectangles.results ?? []).contains { rect in
            let r = rect.boundingBox
            let area = r.width * r.height
            let faceArea = box.width * box.height
            return r.contains(box) && area < faceArea * 7 && area > faceArea * 1.2
        }

        guard let crop = alignedCrop(pixelBuffer, box: box, roll: roll),
              let embedding = featurePrint(crop) else { return nil }

        return FaceSample(
            embedding: embedding,
            rect: box,
            yaw: yaw, roll: roll, pitch: pitch,
            eyeOpenness: eyeOpenness(face),
            noseOffset: noseOffset(face),
            framedByDevice: framed,
            time: time
        )
    }

    /// Recadre le visage (marge de 12 %) et annule l'inclinaison de la tête.
    private static func alignedCrop(_ buffer: CVPixelBuffer, box: CGRect, roll: Double) -> CGImage? {
        let image = CIImage(cvPixelBuffer: buffer)
        let extent = image.extent
        let faceRect = VNImageRectForNormalizedRect(box, Int(extent.width), Int(extent.height))
        let center = CGPoint(x: faceRect.midX, y: faceRect.midY)
        let side = max(faceRect.width, faceRect.height) * 1.12

        let rotation = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: CGFloat(-roll))
            .translatedBy(x: -center.x, y: -center.y)
        let rotated = image.transformed(by: rotation)
        let cropRect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        let cropped = rotated.cropped(to: cropRect)
        guard !cropped.extent.isEmpty else { return nil }

        // Taille fixe et niveaux de gris : moins sensible à la couleur de l'éclairage.
        let scale = 224 / side
        let normalized = cropped
            .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        return context.createCGImage(normalized, from: CGRect(x: 0, y: 0, width: 224, height: 224))
    }

    private static func featurePrint(_ image: CGImage) -> [Float]? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first else { return nil }
        let data = observation.data
        var values: [Float] = []
        switch observation.elementType {
        case .float:
            values = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(observation.elementCount)) }
        case .double:
            values = data.withUnsafeBytes { $0.bindMemory(to: Double.self).prefix(observation.elementCount).map { Float($0) } }
        default:
            return nil
        }
        return values.isEmpty ? nil : FaceMath.normalize(values)
    }

    private static func center(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
        guard let points = region?.normalizedPoints, !points.isEmpty else { return nil }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private static func noseOffset(_ face: VNFaceObservation) -> Double {
        guard let left = center(face.landmarks?.leftEye),
              let right = center(face.landmarks?.rightEye),
              let nose = center(face.landmarks?.nose) else { return 0 }
        let distance = hypot(right.x - left.x, right.y - left.y)
        guard distance > 0 else { return 0 }
        return Double((nose.x - (left.x + right.x) / 2) / distance)
    }

    private static func eyeOpenness(_ face: VNFaceObservation) -> Double {
        func ratio(_ region: VNFaceLandmarkRegion2D?) -> Double? {
            guard let points = region?.normalizedPoints, points.count >= 4 else { return nil }
            let xs = points.map(\.x), ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(),
                  maxX - minX > 0 else { return nil }
            return Double((maxY - minY) / (maxX - minX))
        }
        let values = [ratio(face.landmarks?.leftEye), ratio(face.landmarks?.rightEye)].compactMap { $0 }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

/// Caméra dédiée au déverrouillage : ~8 images analysées par seconde, en mémoire uniquement.
final class FaceCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// Appelé sur une file d'arrière-plan (nil = aucun visage exploitable).
    var onSample: (@Sendable (FaceSample?) -> Void)?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.notchflow.face", qos: .userInitiated)
    private var configured = false
    private var lastAnalysis: TimeInterval = 0
    private var busy = false

    /// Démarre la caméra. Renvoie false si aucune caméra n'est disponible (capot fermé…).
    func start(completion: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            if !configured {
                guard let device = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    completion(false)
                    return
                }
                session.beginConfiguration()
                if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
                if session.canAddInput(input) { session.addInput(input) }
                let output = AVCaptureVideoDataOutput()
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: queue)
                if session.canAddOutput(output) { session.addOutput(output) }
                session.commitConfiguration()
                configured = true
            }
            if !session.isRunning { session.startRunning() }
            completion(session.isRunning)
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard !busy, now - lastAnalysis >= 0.08,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        busy = true
        lastAnalysis = now
        let sample = FaceAnalyzer.analyze(buffer, time: now)
        busy = false
        onSample?(sample)
    }
}
