//
//  Camera.swift
//  HeartRateMonitor
//
//  Created by Jason Luo on 7/12/22.
//

import Foundation
import AVFoundation
import SwiftUI
import os.log

fileprivate let logger = Logger(subsystem: "com.personal.HeartRateMonitor", category: "Camera")

final class Camera: NSObject {
    // different states the camera can be in
    public enum Status {
        case uninitialized
        case missingDevice
        case unauthorized
        case running
        case stopped
    }
    
    @Published public private(set) var status: Status = .uninitialized
    public private(set) var framerate: Double = 60
    
    lazy public var previewStream: AsyncStream<CIImage> = AsyncStream { continuation in
        addToStream = { ciImage in continuation.yield(ciImage) }
    }

    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "capture session queue")
    private var deviceInput: AVCaptureDeviceInput?
    private var output: AVCaptureVideoDataOutput?
    private var addToStream: ((CIImage) -> Void)?
    
    override init() {
        super.init()

        // attempt to find a camera to use
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTrueDepthCamera,
            .builtInDualCamera,
            .builtInDualWideCamera,
            .builtInWideAngleCamera,
            .builtInDualWideCamera
        ]
        let captureDevice = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .back)
            .devices
            .filter { $0.isConnected && !$0.isSuspended }
            .filter { $0.hasTorch && $0.isTorchAvailable }
            .filter { $0.isTorchModeSupported(.on) }
            .first
        guard
            let captureDevice = captureDevice,
            let inputDevice = try? AVCaptureDeviceInput(device: captureDevice)
        else {
            logger.error("Failed to obtain capture device.")
            return
        }
        logger.debug("Using capture device: \(captureDevice.localizedName)")
        self.deviceInput = inputDevice
        
        // initialize video output
        self.output = AVCaptureVideoDataOutput()
        
        // configure capture session
        sessionQueue.async { [self] in
            captureSession.beginConfiguration()
            defer { captureSession.commitConfiguration() }
            
            // these are guaranteed to be initialized at this point; unwrap
            let input = self.deviceInput!
            let inputDevice = input.device
            let output = self.output!
            
            guard captureSession.canAddInput(input) else {
                logger.error("Unable to add video capture device input to capture session.")
                return
            }
            guard captureSession.canAddOutput(output) else {
                logger.error("Unable to add video output to capture session.")
                return
            }
            
            // configure capture framerate and resolution
            if let (format, range) = chooseCaptureFormat(from: inputDevice.formats) {
                try? configureCaptureDevice { device in
                    captureSession.sessionPreset = .inputPriority
                    
                    // set active format to lowest specs
                    device.activeFormat = format
                    device.videoZoomFactor = format.videoMaxZoomFactor
                    
                    // set framerate to maximum allowed
                    let duration = range.minFrameDuration
                    device.activeVideoMinFrameDuration = duration
                    device.activeVideoMaxFrameDuration = duration
                    framerate = range.maxFrameRate
                }
            }
            
            // debug information
            logger.debug("Capture device framerate: \(1 / inputDevice.activeVideoMaxFrameDuration.seconds) fps")
            let resolution = inputDevice.activeFormat.formatDescription.dimensions
            logger.debug("Capture device resolution: \(resolution.width)x\(resolution.height)")

            output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "VideoDataOutputQueue"))
            captureSession.addInput(input)
            captureSession.addOutput(output)
        }
    }
    
    func start() async {
        guard await checkAuthorization() else {
            status = .unauthorized
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [self] in
                defer { continuation.resume() }
                
                guard !captureSession.inputs.isEmpty else {
                    status = .missingDevice
                    return
                }
                
                guard !captureSession.isRunning else {
                    return
                }
                
                captureSession.startRunning()
                try? configureCaptureDevice { device in device.torchMode = .on }
                status = .running
            }
        }
    }
    
    func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [self] in
                defer { continuation.resume() }

                guard captureSession.isRunning else {
                    return
                }
                
                try? configureCaptureDevice { device in device.torchMode = .off }
                captureSession.stopRunning()
                status = .stopped
            }
        }
    }
    
    private func checkAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            logger.debug("Camera access authorized.")
            return true
        case .notDetermined:
            logger.debug("Camera access not determined.")
            sessionQueue.suspend()
            let status = await AVCaptureDevice.requestAccess(for: .video)
            sessionQueue.resume()
            return status
        case .denied:
            logger.debug("Camera access denied.")
            return false
        case .restricted:
            logger.debug("Camera library access restricted.")
            return false
        @unknown default:
            return false
        }
    }
    
    private func configureCaptureDevice(_ body: (AVCaptureDevice) -> Void) throws {
        guard let inputDevice = deviceInput?.device else { return }
        do {
            try inputDevice.lockForConfiguration()
            body(inputDevice)
            inputDevice.unlockForConfiguration()
        } catch {
            logger.error("Unable to obtain capture device configuration lock: \(error.localizedDescription)")
            throw error
        }
    }
}

extension Camera: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        addToStream?(CIImage(cvPixelBuffer: pixelBuffer))
    }
}

// choose the lowest resolution format amongst those supporting the highest possible framerate
// want high sampling rate for measurement accuracy, but low picture quality to reduce computational strain
fileprivate func chooseCaptureFormat(from formats: [AVCaptureDevice.Format]) -> (format: AVCaptureDevice.Format, range: AVFrameRateRange)? {
    let validFormats = formats.filter { !$0.videoSupportedFrameRateRanges.isEmpty }
    guard !validFormats.isEmpty else { return nil }
    
    // obtain the framerate range containing the highest framerate for each format
    let framerateRanges = validFormats
        .map { format -> AVFrameRateRange in
            format.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate })!
        }
    let maxFrameRate = framerateRanges
        .map { $0.maxFrameRate }
        .max()!
    
    // determine the lowest resolution format achieving the maximum framerate
    return zip(validFormats, framerateRanges)
        .filter { $0.1.maxFrameRate == maxFrameRate }
        .min(by: { $0.0.formatDescription.dimensions.size < $1.0.formatDescription.dimensions.size })
}

fileprivate extension CMVideoDimensions {
    var size: Int32 { width * height }
}
