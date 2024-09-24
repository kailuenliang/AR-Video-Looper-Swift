import UIKit
import ARKit
import AVFoundation

class ViewController: UIViewController, ARSCNViewDelegate {

    @IBOutlet var sceneView: ARSCNView!
    var player: AVPlayer?
    var instructionLabel: UILabel!
    var detectionTimer: Timer?
    
    var isTargetDetected: Bool = false  // Track whether the target is currently detected

    override func viewDidLoad() {
        super.viewDidLoad()

        // Set up the instruction label
        setupInstructionLabel()

        // Set the view's delegate
        sceneView.delegate = self

        // Create a new scene
        let scene = SCNScene()
        sceneView.scene = scene

        // Show the instruction label initially
        instructionLabel.text = "Point the camera at the book"
        instructionLabel.isHidden = false
        print("App loaded, instruction label displayed.")
    }

    func setupInstructionLabel() {
        // Initialize and configure the instruction label
        instructionLabel = UILabel()
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.textColor = .white
        instructionLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0
        instructionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)

        // Add the label to the view
        view.addSubview(instructionLabel)

        // Add constraints to center the label
        NSLayoutConstraint.activate([
            instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            instructionLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -50),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Create a session configuration
        let configuration = ARImageTrackingConfiguration()

        // Reference the AR Resource Group
        if let trackingImages = ARReferenceImage.referenceImages(inGroupNamed: "ARResources", bundle: nil) {
            configuration.trackingImages = trackingImages
            configuration.maximumNumberOfTrackedImages = 1
        }

        // Run the view's session
        sceneView.session.run(configuration)

        // Start a timer to check for the target every 2 seconds
        startDetectionTimer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Remove the observer for AVPlayerItem playback finish
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)

        // Pause the session and invalidate the timer
        sceneView.session.pause()
        detectionTimer?.invalidate()
        detectionTimer = nil
    }

    func startDetectionTimer() {
        detectionTimer?.invalidate() // Invalidate any previous timer
        detectionTimer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(checkTargetDetection), userInfo: nil, repeats: true)
    }

    @objc func checkTargetDetection() {
        // If the target is not detected after 2 seconds, show the instruction label again
        if !isTargetDetected {
            DispatchQueue.main.async {
                print("Timer: Target not detected. Showing instruction label.")
                self.instructionLabel.isHidden = false
            }
        } else {
            print("Timer: Target detected.")
        }
    }

    // MARK: - ARSCNViewDelegate Methods

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let imageAnchor = anchor as? ARImageAnchor else { return nil }

        // Set target detected to true and hide the instruction label
        isTargetDetected = true
        DispatchQueue.main.async {
            print("Renderer: Target detected. Hiding instruction label.")
            self.instructionLabel.isHidden = true  // Ensure label is hidden on the main thread
        }

        // Create a 3D plane geometry based on the detected image's size
        let referenceImage = imageAnchor.referenceImage
        let size = referenceImage.physicalSize

        // Calculate the aspect ratio of the video (e.g., 800x1080)
        let videoAspectRatio = 1100.0 / 1600.0
        let planeWidth = size.width * 1.2  // Increase width by 1.2 times to make it larger
        let planeHeight = planeWidth / videoAspectRatio

        // Create a plane to display the video
        let plane = SCNPlane(width: planeWidth, height: planeHeight)

        // Create an AVPlayer to play the video
        guard let url = Bundle.main.url(forResource: "getty", withExtension: "mov") else {
            print("Video file not found.")
            return nil
        }

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)

        // Assign the AVPlayer output directly to the plane's material
        let material = plane.firstMaterial
        material?.diffuse.contents = player
        material?.isDoubleSided = true

        // Enable alpha blending
        material?.blendMode = .alpha

        // Shader modifier to ensure transparency is handled properly
        let transparencyShader = """
        #pragma transparent
        #pragma body
        if (_surface.diffuse.a < 0.01) {
            discard_fragment();  // Discard completely transparent pixels
        } else {
            _output.color.a = _surface.diffuse.a;  // Use alpha from the video texture
        }
        """
        material?.shaderModifiers = [.fragment: transparencyShader]

        // Create a node with the plane geometry
        let videoNode = SCNNode(geometry: plane)
        videoNode.eulerAngles.x = -.pi / 2  // Rotate to lay flat on the detected image

        // Move the video node up by 10 cm (0.1 meters)
        videoNode.position = SCNVector3(0, 0.03, 0)

        // Optionally, you can scale the video node to make it larger
        videoNode.scale = SCNVector3(1.0, 1.0, 1.0)

        // Create a root node that will be returned (the parent node for the anchor)
        let rootNode = SCNNode()

        // Add the video node to the root node
        rootNode.addChildNode(videoNode)

        // Add observer to handle video loop
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        NotificationCenter.default.addObserver(self, selector: #selector(restartVideo), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)

        // Start the video playback from the beginning
        player?.seek(to: CMTime.zero)
        player?.play()

        // Return the root node, which ARKit will place at the position of the image anchor
        return rootNode
    }

    // Restart the video when the target is detected again or if it ends
    @objc func restartVideo() {
        player?.seek(to: CMTime.zero)
        player?.play()
    }

    // Update anchor status, including losing tracking
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let imageAnchor = anchor as? ARImageAnchor else { return }

        if imageAnchor.isTracked {
            // Target is still tracked, keep video playing
            if !isTargetDetected {
                isTargetDetected = true
                DispatchQueue.main.async {
                    print("Renderer: Target re-detected, playing video.")
                    self.player?.play() // Resume playback if video was paused
                    self.instructionLabel.isHidden = true  // Ensure label is hidden again if re-detected
                }
            }
        } else {
            // Target lost, pause video and show instructions
            if isTargetDetected {
                isTargetDetected = false
                DispatchQueue.main.async {
                    print("Renderer: Target lost, showing instruction label.")
                    self.instructionLabel.isHidden = false
                    self.player?.pause()
                    self.player?.seek(to: CMTime.zero)
                }
            }
        }
    }
}
