// Packages/CameraKit/Sources/CameraKit/CameraManager.swift
import Foundation
import AVFoundation
import CoreImage
import AppKit
import Observation

public enum CameraClipShape: String, CaseIterable, Sendable {
    case circle
    case roundedRect
}

public enum CameraPosition: String, CaseIterable, Sendable {
    case bottomLeft
    case bottomRight
    case topLeft
    case topRight
}

public enum CameraError: Error, LocalizedError, Equatable {
    case permissionDenied
    /// The chosen camera is gone (unplugged) or can't be used right now (audit R8).
    case deviceUnavailable

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera access is required. Grant permission in System Settings → Privacy & Security → Camera."
        case .deviceUnavailable:
            return "The selected camera isn't available."
        }
    }
}

public struct CameraDevice: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let isBuiltIn: Bool

    public init(from device: AVCaptureDevice) {
        self.id = device.uniqueID
        self.name = device.localizedName
        self.isBuiltIn = device.deviceType == .builtInWideAngleCamera
    }
}

@MainActor
@Observable
public final class CameraManager {
    public private(set) var isRunning = false
    public private(set) var availableDevices: [CameraDevice] = []
    public private(set) var currentFrame: CGImage?

    public var selectedDeviceID: String?
    public var shape: CameraClipShape = .circle
    public var position: CameraPosition = .bottomRight

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var frameDelegate: CameraFrameDelegate?
    /// startRunning/stopRunning block for hundreds of ms; Apple asks to keep them off the
    /// main thread (audit R9, 21.11.).
    private let sessionQueue = DispatchQueue(label: "dev.mwlr.knippi.camera.session")

    public init() {}

    public func refreshDevices() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        availableDevices = discoverySession.devices.map { CameraDevice(from: $0) }
        if selectedDeviceID == nil {
            selectedDeviceID = availableDevices.first?.id
        }
    }

    /// Request camera permission (if not yet determined) and start the
    /// capture session. Shows the system prompt on first use. Throws
    /// ``CameraError/permissionDenied`` if the user declines or has
    /// previously denied access.
    public func requestAccessAndStart() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { throw CameraError.permissionDenied }
        default:
            throw CameraError.permissionDenied
        }
        try start()
    }

    public func start() throws {
        guard !isRunning else { return }
        // Fail loudly: returning silently left an empty camera bubble in the recording (audit R8).
        guard let deviceID = selectedDeviceID,
              let device = AVCaptureDevice(uniqueID: deviceID) else { throw CameraError.deviceUnavailable }

        let session = AVCaptureSession()
        session.sessionPreset = .medium

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.deviceUnavailable }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let delegate = CameraFrameDelegate { [weak self] image in
            Task { @MainActor in
                // stopRunning now runs off the main thread: frames still in flight must not
                // bring back an old picture after stop() (audit follow-up R9).
                guard let self, self.isRunning else { return }
                self.currentFrame = image
            }
        }
        output.setSampleBufferDelegate(delegate, queue: DispatchQueue(label: "dev.mwlr.knippi.camera"))
        guard session.canAddOutput(output) else { throw CameraError.deviceUnavailable }
        session.addOutput(output)

        captureSession = session
        videoOutput = output
        frameDelegate = delegate
        sessionQueue.async { session.startRunning() }
        isRunning = true
    }

    public func stop() {
        if let session = captureSession {
            sessionQueue.async { session.stopRunning() }
        }
        captureSession = nil
        videoOutput = nil
        frameDelegate = nil
        currentFrame = nil
        isRunning = false
    }
}

private final class CameraFrameDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let onFrame: (CGImage) -> Void
    private static let context = CIContext()

    init(onFrame: @escaping (CGImage) -> Void) {
        self.onFrame = onFrame
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        // One context for all frames: creating one per frame (~30/s) is expensive (audit R9).
        guard let cgImage = Self.context.createCGImage(ciImage, from: ciImage.extent) else { return }
        onFrame(cgImage)
    }
}
