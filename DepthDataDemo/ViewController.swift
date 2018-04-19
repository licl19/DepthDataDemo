/*
 See LICENSE.txt for this sample’s licensing information.
 
 Abstract:
 View controller for camera interface.
 */

import UIKit
import AVFoundation

class ViewController: UIViewController, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDepthDataOutputDelegate, AVCaptureDataOutputSynchronizerDelegate {
    
    // MARK: - Properties
    private let session = AVCaptureSession()
    
    private let sessionQueue = DispatchQueue(label: "session queue", attributes: [], autoreleaseFrequency: .workItem)
    
    private var videoDeviceInput: AVCaptureDeviceInput!
    
    private let dataOutputQueue = DispatchQueue(label: "video data queue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    private let videoDataOutput = AVCaptureVideoDataOutput()
    
    private let depthDataOutput = AVCaptureDepthDataOutput()
    
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    
    private let photoOutput = AVCapturePhotoOutput()
    
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera,
                                                                                             .builtInDualCamera,
                                                                                             .builtInWideAngleCamera],
                                                                               mediaType: .video,
                                                                               position: .unspecified)
    
    // MARK: - View Controller Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .darkGray
        print((#function))
        
        sessionQueue.async {
            self.configureSession()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        sessionQueue.async {
            self.session.startRunning()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async {
            self.session.stopRunning()
        }
        
        super.viewWillDisappear(animated)
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
    }
    
    private var sessionRunningContext = 0
    
    // MARK: - Session Management
    
    // Call this on the session queue
    private func configureSession() {
        let defaultVideoDevice: AVCaptureDevice? = videoDeviceDiscoverySession.devices.first
        
        guard let videoDevice = defaultVideoDevice else {
            return
        }
        
        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            return
        }
        
        session.beginConfiguration()
        
        session.sessionPreset = AVCaptureSession.Preset.photo
        
        // Add a video input
        guard session.canAddInput(videoDeviceInput) else {
            session.commitConfiguration()
            return
        }
        session.addInput(videoDeviceInput)
        
        // Add a video data output
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            videoDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
        } else {
            session.commitConfiguration()
            return
        }
        
        // Add photo output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            
            photoOutput.isHighResolutionCaptureEnabled = true
            
            photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported
            print(photoOutput.isDepthDataDeliverySupported)
            var capturePhotoSettings = AVCapturePhotoSettings()
            if #available(iOS 11.0, *) {
                if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                    capturePhotoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                }
            }
            capturePhotoSettings.isHighResolutionPhotoEnabled = true
            if !(capturePhotoSettings.__availablePreviewPhotoPixelFormatTypes.isEmpty) {
                capturePhotoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: capturePhotoSettings.__availablePreviewPhotoPixelFormatTypes.first!]
            }
            photoOutput.capturePhoto(with: capturePhotoSettings, delegate: self)
            
        } else {
            session.commitConfiguration()
            return
        }
        
        // Add a depth data output
        if session.canAddOutput(depthDataOutput) {
            session.addOutput(depthDataOutput)
            depthDataOutput.setDelegate(self, callbackQueue: dataOutputQueue)
            depthDataOutput.isFilteringEnabled = false
            if let connection = depthDataOutput.connection(with: .depthData) {
                connection.isEnabled = true
            } else {
                print("No AVCaptureConnection")
            }
        } else {
            session.commitConfiguration()
            return
        }
        
        // Use an AVCaptureDataOutputSynchronizer to synchronize the video data and depth data outputs.
        // The first output in the dataOutputs array, in this case the AVCaptureVideoDataOutput, is the "master" output.
        outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoDataOutput, depthDataOutput])
        outputSynchronizer!.setDelegate(self, queue: dataOutputQueue)
        
        if self.photoOutput.isDepthDataDeliverySupported {
            // Cap the video framerate at the max depth framerate
            if let frameDuration = videoDevice.activeDepthDataFormat?.videoSupportedFrameRateRanges.first?.minFrameDuration {
                do {
                    try videoDevice.lockForConfiguration()
                    videoDevice.activeVideoMinFrameDuration = frameDuration
                    videoDevice.unlockForConfiguration()
                } catch {
                    print("Could not lock device for configuration: \(error)")
                }
            }
        }
        
        session.commitConfiguration()
    }
    
    // MARK: - Video Data Output Delegate
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    }
    
    // MARK: - Depth Data Output Delegate
    
    func depthDataOutput(_ depthDataOutput: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        print((#function))
        print(depthData)
    }
    
    // MARK: - Video + Depth Output Synchronizer Delegate
    
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        
        if let syncedDepthData: AVCaptureSynchronizedDepthData = synchronizedDataCollection.synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData {
            if !syncedDepthData.depthDataWasDropped {
                let depthData = syncedDepthData.depthData
                print((#function))
                print(depthData)
            }
        }
        
        if let syncedVideoData: AVCaptureSynchronizedSampleBufferData = synchronizedDataCollection.synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData {
            if !syncedVideoData.sampleBufferWasDropped {
                print((#function))
            }
        }
    }
    
    // MARK: - Photo Output Delegate
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let depthData = photo.depthData {
            print((#function))
            print(depthData)
        }
    }
}

