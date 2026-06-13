@preconcurrency import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct Options {
    var listDevices = false
    var device = "0"
    var output = ""
    var timeout = 10.0
    var size = "1280x720"
    var format = "jpeg"
    var warmupFrames = 3
    var exposureBias: Float?
    var exposurePoint: CGPoint?
    var focusPoint: CGPoint?
}

private enum SnapshotError: Error, CustomStringConvertible {
    case usage(String)
    case cameraDenied
    case noDevices
    case deviceNotFound(String)
    case cannotAddInput
    case cannotAddOutput
    case timedOut
    case invalidImage
    case invalidPoint(String)
    case saveFailed(String)

    var description: String {
        switch self {
        case .usage(let message):
            return message
        case .cameraDenied:
            return "Camera permission was denied. Grant camera access to the calling terminal/Codex app and retry."
        case .noDevices:
            return "No video capture devices were found."
        case .deviceNotFound(let value):
            return "No camera matched device selector: \(value)"
        case .cannotAddInput:
            return "Could not add the selected camera as an AVCapture input."
        case .cannotAddOutput:
            return "Could not add video frame output to the capture session."
        case .timedOut:
            return "Timed out before a camera frame was captured."
        case .invalidImage:
            return "Captured frame could not be converted to an image."
        case .invalidPoint(let value):
            return "Point values must be normalized as x,y between 0.0 and 1.0: \(value)"
        case .saveFailed(let path):
            return "Could not save camera frame to \(path)."
        }
    }
}

@main
private struct CameraSnapshot {
    static func main() {
        do {
            let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
            let devices = discoverDevices()

            if options.listDevices {
                printDeviceList(devices)
                return
            }

            guard !options.output.isEmpty else {
                throw SnapshotError.usage("Missing --output <path>.")
            }

            try requestCameraAccess()
            let device = try selectDevice(options.device, from: devices)
            if options.exposureBias != nil {
                fputs(
                    "CameraSnapshot: --exposure-bias is not supported by macOS AVFoundation; use --exposure-point plus OCR preprocessing controls.\n",
                    stderr
                )
            }
            let capturer = FrameCapturer(device: device, options: options)
            let image = try capturer.capture()
            try save(image: image, to: options.output, format: options.format)
            print("camera_snapshot output=\(options.output) device=\(device.localizedName) size=\(image.width)x\(image.height)")
        } catch {
            fputs("CameraSnapshot: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func parseOptions(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0
        while index < arguments.count {
            let arg = arguments[index]
            switch arg {
            case "--list":
                options.listDevices = true
            case "--device":
                index += 1
                guard index < arguments.count else { throw SnapshotError.usage("Missing value for --device.") }
                options.device = arguments[index]
            case "--output":
                index += 1
                guard index < arguments.count else { throw SnapshotError.usage("Missing value for --output.") }
                options.output = arguments[index]
            case "--timeout":
                index += 1
                guard index < arguments.count, let value = Double(arguments[index]), value > 0 else {
                    throw SnapshotError.usage("--timeout requires a positive number of seconds.")
                }
                options.timeout = value
            case "--size":
                index += 1
                guard index < arguments.count else { throw SnapshotError.usage("Missing value for --size.") }
                options.size = arguments[index]
            case "--format":
                index += 1
                guard index < arguments.count else { throw SnapshotError.usage("Missing value for --format.") }
                options.format = arguments[index].lowercased()
            case "--warmup-frames":
                index += 1
                guard index < arguments.count, let value = Int(arguments[index]), value >= 0 else {
                    throw SnapshotError.usage("--warmup-frames requires a non-negative integer.")
                }
                options.warmupFrames = value
            case "--exposure-bias":
                index += 1
                guard index < arguments.count, let value = Float(arguments[index]) else {
                    throw SnapshotError.usage("--exposure-bias requires a numeric EV value, for example -2.0.")
                }
                options.exposureBias = value
            case "--exposure-point":
                index += 1
                guard index < arguments.count else { throw SnapshotError.usage("Missing value for --exposure-point.") }
                options.exposurePoint = try parseNormalizedPoint(arguments[index])
            case "--focus-point":
                index += 1
                guard index < arguments.count else { throw SnapshotError.usage("Missing value for --focus-point.") }
                options.focusPoint = try parseNormalizedPoint(arguments[index])
            case "--help", "-h":
                printUsage()
                exit(0)
            default:
                throw SnapshotError.usage("Unknown argument: \(arg)")
            }
            index += 1
        }
        return options
    }

    private static func parseNormalizedPoint(_ value: String) throws -> CGPoint {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let x = Double(parts[0]),
              let y = Double(parts[1]),
              (0.0...1.0).contains(x),
              (0.0...1.0).contains(y) else {
            throw SnapshotError.invalidPoint(value)
        }
        return CGPoint(x: x, y: y)
    }

    private static func printUsage() {
        print("""
        Usage:
          CameraSnapshot --list
          CameraSnapshot --device 0 --output /tmp/frame.jpg [--timeout 10] [--size 1280x720]

        Device can be a numeric index, uniqueID, or localized name substring.
        On macOS, prefer --exposure-point 0.5,0.5 for bright OLED/AMOLED targets.
        """)
    }

    private static func requestCameraAccess() throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            let result = CameraAccessResult()
            AVCaptureDevice.requestAccess(for: .video) { value in
                result.granted = value
                semaphore.signal()
            }
            semaphore.wait()
            if !result.granted {
                throw SnapshotError.cameraDenied
            }
        default:
            throw SnapshotError.cameraDenied
        }
    }

    private static func discoverDevices() -> [AVCaptureDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        return session.devices
    }

    private static func printDeviceList(_ devices: [AVCaptureDevice]) {
        if devices.isEmpty {
            print("No video capture devices found.")
            return
        }
        for (index, device) in devices.enumerated() {
            print(
                "\(index)\t\(device.localizedName)\t\(device.uniqueID)"
                    + "\tconnected=\(device.isConnected ? 1 : 0)"
                    + "\tsuspended=\(device.isSuspended ? 1 : 0)"
                    + "\tin_use=\(device.isInUseByAnotherApplication ? 1 : 0)"
            )
        }
    }

    private static func selectDevice(_ selector: String, from devices: [AVCaptureDevice]) throws -> AVCaptureDevice {
        guard !devices.isEmpty else { throw SnapshotError.noDevices }
        if let index = Int(selector), devices.indices.contains(index) {
            return devices[index]
        }
        if let exact = devices.first(where: { $0.uniqueID == selector }) {
            return exact
        }
        if let named = devices.first(where: { $0.localizedName.localizedCaseInsensitiveContains(selector) }) {
            return named
        }
        throw SnapshotError.deviceNotFound(selector)
    }

    private static func save(image: CGImage, to path: String, format: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let type: CFString
        switch format {
        case "png":
            type = UTType.png.identifier as CFString
        case "jpeg", "jpg":
            type = UTType.jpeg.identifier as CFString
        default:
            throw SnapshotError.usage("--format must be jpeg or png.")
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw SnapshotError.saveFailed(path)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw SnapshotError.saveFailed(path)
        }
    }
}

private final class CameraAccessResult: @unchecked Sendable {
    var granted = false
}

private final class FrameCapturer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let device: AVCaptureDevice
    private let options: Options
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera-snapshot.frames")
    private let semaphore = DispatchSemaphore(value: 0)
    private let ciContext = CIContext()
    private var frameCount = 0
    private var capturedImage: CGImage?
    private var captureError: Error?

    init(device: AVCaptureDevice, options: Options) {
        self.device = device
        self.options = options
        super.init()
    }

    func capture() throws -> CGImage {
        try configureSession()
        session.startRunning()
        defer {
            session.stopRunning()
        }

        let deadline = Date().addingTimeInterval(options.timeout)
        var signaled = false
        while Date() < deadline {
            if semaphore.wait(timeout: .now() + 0.05) == .success {
                signaled = true
                break
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        guard signaled else {
            throw SnapshotError.timedOut
        }
        if let captureError {
            throw captureError
        }
        guard let capturedImage else {
            throw SnapshotError.invalidImage
        }
        return capturedImage
    }

    private func configureSession() throws {
        try configureDevice()

        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: queue)

        session.beginConfiguration()
        session.sessionPreset = preset(for: options.size)
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw SnapshotError.cannotAddInput
        }
        session.addInput(input)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw SnapshotError.cannotAddOutput
        }
        session.addOutput(output)
        session.commitConfiguration()
    }

    private func configureDevice() throws {
        guard options.exposureBias != nil || options.exposurePoint != nil || options.focusPoint != nil else {
            return
        }

        try device.lockForConfiguration()
        defer {
            device.unlockForConfiguration()
        }

        if let point = options.exposurePoint, device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = point
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
        }

        if let point = options.focusPoint, device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = point
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
        }

        // macOS AVFoundation exposes exposure/focus metering points, but not EV bias
        // or custom exposure duration/ISO for this capture path.
    }

    private func preset(for size: String) -> AVCaptureSession.Preset {
        switch size {
        case "640x480":
            return .vga640x480
        case "1920x1080":
            return .hd1920x1080
        case "3840x2160":
            return .hd4K3840x2160
        default:
            return .hd1280x720
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frameCount += 1
        guard frameCount > options.warmupFrames else {
            return
        }

        guard capturedImage == nil else {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            captureError = SnapshotError.invalidImage
            semaphore.signal()
            return
        }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            captureError = SnapshotError.invalidImage
            semaphore.signal()
            return
        }

        capturedImage = cgImage
        semaphore.signal()
    }
}
