import UIKit
import ARKit
import SceneKit
import AVFoundation

class PhotoScannerViewController: UIViewController, ARSCNViewDelegate {
    private var sceneView: ARSCNView!
    private var videoPlayer: AVPlayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupAR()
    }
    
    private func setupUI() {
        view.backgroundColor = .black
        
        // Setup AR Scene View
        sceneView = ARSCNView()
        sceneView.delegate = self
        sceneView.automaticallyUpdatesLighting = true
        sceneView.scene = SCNScene()
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sceneView)
        
        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupAR() {
        // Check ARKit availability
        guard ARWorldTrackingConfiguration.isSupported else {
            print("ARWorldTracking is not supported on this device.")
            return
        }
        
        // Load reference images
        guard let referenceImages = ARReferenceImage.referenceImages(
            inGroupNamed: "AR Resources",
            bundle: nil
        ) else {
            print("❌ No AR Reference Images found in the asset catalog group named 'AR Resources'.")
            return
        }
        
        print("✅ Successfully loaded \(referenceImages.count) reference images")
        for image in referenceImages {
            print("📸 Reference image name: \(String(describing: image.name))")
            print("📏 Physical size: \(String(format: "%.3f", image.physicalSize.width))m x \(String(format: "%.3f", image.physicalSize.height))m")
        }
        
        // Configure AR session
        let configuration = ARWorldTrackingConfiguration()
        configuration.detectionImages = referenceImages
        configuration.maximumNumberOfTrackedImages = 1
        
        // Run AR session
        sceneView.session.run(configuration, options: [.removeExistingAnchors, .resetTracking])
        print("🚀 AR session started")
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
        videoPlayer?.pause()
        
        // Remove observers
        if let playerItem = videoPlayer?.currentItem {
            playerItem.removeObserver(self, forKeyPath: "status")
        }
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - ARSCNViewDelegate
extension PhotoScannerViewController {
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        print("🔍 AR renderer called with anchor")
        
        guard let imageAnchor = anchor as? ARImageAnchor else {
            print("❌ Anchor is not an image anchor")
            return
        }
        
        // Get the detected image name
        let detectedImage = imageAnchor.referenceImage
        let imageName = detectedImage.name ?? "Unknown"
        
        print("✅ Detected image: \(imageName)")
        
        // Create a square plane geometry
        // Use the smaller dimension to ensure it fits within the image
        let size = min(CGFloat(detectedImage.physicalSize.width), CGFloat(detectedImage.physicalSize.height))
        let plane = SCNPlane(width: size, height: size)
        
        // Load and setup video
        guard let videoURL = Bundle.main.url(forResource: imageName, withExtension: "mov") else {
            print("❌ No matching video found for image name: \(imageName)")
            return
        }
        
        // Create video asset and get video track
        let asset = AVURLAsset(url: videoURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            print("❌ No video track found in asset")
            return
        }
        
        // Check video orientation
        let transform = videoTrack.preferredTransform
        let isPortrait = transform.a == 0 && abs(transform.b) == 1 && abs(transform.c) == 1 && transform.d == 0
        
        // Create composition
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            print("❌ Failed to create composition track")
            return
        }
        
        do {
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: asset.duration),
                of: videoTrack,
                at: .zero
            )
        } catch {
            print("❌ Failed to insert time range: \(error)")
            return
        }
        
        // Create video composition for orientation correction
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        
        // Set render size based on orientation
        if isPortrait {
            // For portrait videos, swap width and height
            videoComposition.renderSize = CGSize(
                width: videoTrack.naturalSize.height,
                height: videoTrack.naturalSize.width
            )
        } else {
            videoComposition.renderSize = videoTrack.naturalSize
        }
        
        // Create transform instruction
        let transformInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
        
        // Apply transform based on orientation
        if isPortrait {
            // For portrait videos, rotate 90 degrees clockwise
            transformInstruction.setTransform(
                CGAffineTransform(rotationAngle: .pi / 2)
                    .translatedBy(x: 0, y: -videoTrack.naturalSize.width),
                at: .zero
            )
        }
        
        // Create main instruction
        let mainInstruction = AVMutableVideoCompositionInstruction()
        mainInstruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        mainInstruction.layerInstructions = [transformInstruction]
        
        videoComposition.instructions = [mainInstruction]
        
        // Create player item with composition
        let playerItem = AVPlayerItem(asset: composition)
        playerItem.videoComposition = videoComposition
        
        // Add observers for player item status
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.videoPlayer?.seek(to: .zero)
            self?.videoPlayer?.play()
        }
        
        // Add observer for player item status
        playerItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        
        // Create player
        let player = AVPlayer(playerItem: playerItem)
        self.videoPlayer = player
        
        // Setup video material
        let videoMaterial = SCNMaterial()
        videoMaterial.diffuse.contents = player
        
        // Configure video material to maintain aspect ratio
        videoMaterial.diffuse.wrapS = .clamp
        videoMaterial.diffuse.wrapT = .clamp
        videoMaterial.diffuse.magnificationFilter = .linear
        videoMaterial.diffuse.minificationFilter = .linear
        
        plane.materials = [videoMaterial]
        
        // Create and position the plane node
        let planeNode = SCNNode(geometry: plane)
        planeNode.eulerAngles.x = -.pi / 2  // Rotate to lay flat on the image
        
        // Center the square video on the image
        let offsetX = (CGFloat(detectedImage.physicalSize.width) - size) / 2
        let offsetY = (CGFloat(detectedImage.physicalSize.height) - size) / 2
        planeNode.position = SCNVector3(offsetX, offsetY, 0)
        
        // Add the plane node to the anchor's node
        node.addChildNode(planeNode)
        
        print("▶️ Video setup complete for image: \(imageName)")
    }
    
    // Add observer method for video status
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status", let playerItem = object as? AVPlayerItem {
            switch playerItem.status {
            case .readyToPlay:
                print("✅ Video is ready to play")
                videoPlayer?.play()
            case .failed:
                print("❌ Video failed to load: \(String(describing: playerItem.error))")
            case .unknown:
                print("⚠️ Video status is unknown")
            @unknown default:
                break
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        print("❌ Image anchor removed")
        videoPlayer?.pause()
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("❌ AR session failed with error: \(error.localizedDescription)")
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        print("⚠️ AR session was interrupted")
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        print("✅ AR session interruption ended")
    }
} 