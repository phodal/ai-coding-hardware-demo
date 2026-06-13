@preconcurrency import AVFoundation
import CoreImage
import SwiftUI
@preconcurrency import Vision

@main
struct CameraAlignerApp: App {
    @StateObject private var camera = CameraService()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(camera)
                .frame(minWidth: 1120, minHeight: 760)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    camera.start()
                }
                .onDisappear {
                    camera.stop()
                }
        }
    }
}

private struct ContentView: View {
    @EnvironmentObject private var camera: CameraService

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                CameraPreview(session: camera.session)
                    .background(Color.black)
                    .overlay {
                        CropOverlay(rect: camera.cropRect)
                            .stroke(camera.ocrPassed ? Color.green : Color.yellow, lineWidth: 3)
                            .animation(.easeInOut(duration: 0.15), value: camera.cropRect)
                    }

                VStack {
                    HStack {
                        StatusPill(text: camera.ocrPassed ? "OCR PASS" : "ALIGNING",
                                   color: camera.ocrPassed ? .green : .yellow)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(16)
            }
            .frame(minWidth: 740, minHeight: 680)

            Divider()

            ControlPanel()
                .frame(width: 360)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ControlPanel: View {
    @EnvironmentObject private var camera: CameraService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Camera Aligner")
                .font(.title2.weight(.semibold))

            Picker("Device", selection: $camera.selectedDeviceID) {
                ForEach(camera.devices, id: \.uniqueID) { device in
                    Text(device.localizedName).tag(device.uniqueID)
                }
            }
            .onChange(of: camera.selectedDeviceID) { _, _ in
                camera.restart()
            }

            GroupBox("Crop") {
                VStack(spacing: 10) {
                    SliderRow(label: "X", value: $camera.cropX, range: 0...0.95)
                    SliderRow(label: "Y", value: $camera.cropY, range: 0...0.95)
                    SliderRow(label: "W", value: $camera.cropW, range: 0.05...1.0)
                    SliderRow(label: "H", value: $camera.cropH, range: 0.05...1.0)

                    HStack {
                        Button("Center") {
                            camera.centerCrop()
                        }
                        Button("Copy CAMERA_CROP") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(camera.exportEnvironment, forType: .string)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            GroupBox("OCR") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Rotate", selection: $camera.rotationDegrees) {
                        Text("0").tag(0)
                        Text("90").tag(90)
                        Text("180").tag(180)
                        Text("270").tag(270)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Expected")
                        TextField("OK", text: $camera.expectedText)
                            .textFieldStyle(.roundedBorder)
                    }

                    Text(camera.ocrText.isEmpty ? "No OCR yet" : camera.ocrText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text(camera.ocrPassed ? "Matched" : "Not matched")
                        .font(.headline)
                        .foregroundStyle(camera.ocrPassed ? .green : .orange)
                }
                .padding(.vertical, 6)
            }

            GroupBox("Export") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CAMERA_CROP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(camera.exportEnvironment)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Text("Use it with: \(camera.exportEnvironment) make visual-smoke")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Spacer()
        }
        .padding(18)
    }
}

private struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 18, alignment: .leading)
            Slider(value: $value, in: range)
            Text(value, format: .number.precision(.fractionLength(2)))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 42, alignment: .trailing)
        }
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.85))
            .foregroundStyle(.black)
            .clipShape(Capsule())
    }
}

private struct CropOverlay: Shape {
    let rect: CGRect

    func path(in bounds: CGRect) -> Path {
        let crop = CGRect(
            x: bounds.width * rect.origin.x,
            y: bounds.height * rect.origin.y,
            width: bounds.width * rect.width,
            height: bounds.height * rect.height
        )

        var path = Path()
        path.addRect(crop)
        return path
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        nsView.previewLayer.session = session
    }
}

private final class PreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = previewLayer
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer = previewLayer
    }
}

private final class CameraService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    @Published var devices: [AVCaptureDevice] = CameraService.discoverDevices()
    @Published var selectedDeviceID: String = CameraService.discoverDevices().first?.uniqueID ?? ""

    @Published var cropX = 0.30 { didSet { clampCrop() } }
    @Published var cropY = 0.23 { didSet { clampCrop() } }
    @Published var cropW = 0.38 { didSet { clampCrop() } }
    @Published var cropH = 0.42 { didSet { clampCrop() } }

    @Published var rotationDegrees = 0
    @Published var expectedText = "OK"
    @Published private(set) var ocrText = ""
    @Published private(set) var ocrPassed = false

    private let sessionQueue = DispatchQueue(label: "camera-aligner.session")
    private let videoQueue = DispatchQueue(label: "camera-aligner.video")
    private let ciContext = CIContext()
    private var lastOCR = Date.distantPast
    private var isConfigured = false

    var cropRect: CGRect {
        CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
    }

    var ffmpegCropExpression: String {
        let x = String(format: "iw*%.3f", cropX)
        let y = String(format: "ih*%.3f", cropY)
        let w = String(format: "iw*%.3f", cropW)
        let h = String(format: "ih*%.3f", cropH)
        return "\(w):\(h):\(x):\(y)"
    }

    var exportEnvironment: String {
        "CAMERA_CROP='\(ffmpegCropExpression)' OCR_ROTATE=\(rotationDegrees)"
    }

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let service = self else { return }

            guard granted else {
                DispatchQueue.main.async {
                    service.ocrText = "Camera permission denied"
                }
                return
            }

            service.sessionQueue.async {
                service.configureSession()
                service.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async {
            self.session.stopRunning()
        }
    }

    func restart() {
        sessionQueue.async {
            self.session.stopRunning()
            self.isConfigured = false
            self.configureSession()
            self.session.startRunning()
        }
    }

    func centerCrop() {
        cropW = 0.38
        cropH = 0.42
        cropX = (1.0 - cropW) / 2.0
        cropY = (1.0 - cropH) / 2.0
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard Date().timeIntervalSince(lastOCR) > 0.45,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        lastOCR = Date()

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent),
              let cropped = crop(image: cgImage),
              let oriented = rotate(image: cropped, degrees: rotationDegrees) else {
            return
        }

        recognizeText(in: oriented)
    }

    private func configureSession() {
        guard !isConfigured else { return }

        let device = devices.first(where: { $0.uniqueID == selectedDeviceID }) ?? devices.first
        guard let device else { return }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.setSampleBufferDelegate(self, queue: videoQueue)

            session.beginConfiguration()
            session.sessionPreset = .hd1280x720
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }

            if session.canAddInput(input) {
                session.addInput(input)
            }

            if session.canAddOutput(output) {
                session.addOutput(output)
            }

            session.commitConfiguration()
            isConfigured = true
        } catch {
            DispatchQueue.main.async {
                self.ocrText = "Camera setup failed: \(error.localizedDescription)"
            }
        }
    }

    private func crop(image: CGImage) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let rect = CGRect(
            x: width * cropX,
            y: height * cropY,
            width: width * cropW,
            height: height * cropH
        ).integral

        return image.cropping(to: rect)
    }

    private func rotate(image: CGImage, degrees: Int) -> CGImage? {
        guard degrees != 0 else {
            return image
        }

        let ciImage = CIImage(cgImage: image)
        let radians = CGFloat(Double(degrees) * Double.pi / 180.0)
        let rotated = ciImage.transformed(by: CGAffineTransform(rotationAngle: radians))
        let translated = rotated.transformed(by: CGAffineTransform(
            translationX: -rotated.extent.origin.x,
            y: -rotated.extent.origin.y
        ))

        return ciContext.createCGImage(translated, from: translated.extent)
    }

    private func recognizeText(in image: CGImage) {
        let request = VNRecognizeTextRequest { [weak self] request, _ in
            let strings = (request.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string } ?? []
            let text = strings.joined(separator: "\n")
            let passed = Self.normalize(text).contains(Self.normalize(self?.expectedText ?? ""))

            DispatchQueue.main.async {
                self?.ocrText = text
                self?.ocrPassed = passed
            }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0.015

        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            DispatchQueue.main.async {
                self.ocrText = "OCR failed: \(error.localizedDescription)"
                self.ocrPassed = false
            }
        }
    }

    private func clampCrop() {
        cropW = min(max(cropW, 0.05), 1.0)
        cropH = min(max(cropH, 0.05), 1.0)
        cropX = min(max(cropX, 0.0), 1.0 - cropW)
        cropY = min(max(cropY, 0.0), 1.0 - cropH)
    }

    private static func normalize(_ text: String) -> String {
        text.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func discoverDevices() -> [AVCaptureDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        return session.devices
    }
}
