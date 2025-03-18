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
        
        // Create a plane geometry matching the real-world size of the detected image
        let width = CGFloat(detectedImage.physicalSize.width)
        let height = CGFloat(detectedImage.physicalSize.height)
        let plane = SCNPlane(width: width, height: height)
        
        // Load and setup video
        guard let videoURL = Bundle.main.url(forResource: imageName, withExtension: "mov") else {
            print("❌ No matching video found for image name: \(imageName)")
            return
        }
        
        // Create video player
        let playerItem = AVPlayerItem(url: videoURL)
        let player = AVPlayer(playerItem: playerItem)
        self.videoPlayer = player
        
        // Setup video material
        let videoMaterial = SCNMaterial()
        videoMaterial.diffuse.contents = player
        
        // Setup video looping
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.videoPlayer?.seek(to: .zero)
            self?.videoPlayer?.play()
        }
        
        plane.materials = [videoMaterial]
        
        // Create and position the plane node
        let planeNode = SCNNode(geometry: plane)
        planeNode.eulerAngles.x = -.pi / 2  // Rotate to lay flat on the image
        planeNode.position.z = 0.001  // Slightly above the image to avoid z-fighting
        
        // Add the plane node to the anchor's node
        node.addChildNode(planeNode)
        
        // Start playing the video
        player.play()
        print("▶️ Started playing video for image: \(imageName)")
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