import SwiftUI
import SpriteKit
import CoreMotion

struct StarPhysicsView: View {
    let starCount: Int

    var body: some View {
        SpriteView(
            scene: StarPhysicsScene(size: CGSize(width: 320, height: 360), starCount: min(starCount, 36)),
            options: [.allowsTransparency]
        )
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
        .overlay {
            BottleOverlay()
                .allowsHitTesting(false)
        }
    }
}

private struct BottleOverlay: View {
    var body: some View {
        ZStack(alignment: .top) {
            ProfiledShape(profile: ParametricPreset.bottleProfile, tension: 0.73)
                .fill(
                    LinearGradient(
                        colors: [ContainerKind.star.tint.opacity(0.18), Color.brown.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    ProfiledShape(profile: ParametricPreset.bottleProfile, tension: 0.73)
                        .stroke(ContainerKind.star.tint.opacity(0.54), lineWidth: 2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 18)

            SuperellipseShape(exponent: ParametricPreset.keepsakeBoxExponent)
                .fill(Color(red: 0.55, green: 0.38, blue: 0.23))
                .frame(width: 126, height: 42)
                .padding(.top, 8)
        }
    }
}

private final class StarPhysicsScene: SKScene {
    private let motionManager = CMMotionManager()
    private let targetCount: Int
    private var didPopulate = false

    init(size: CGSize, starCount: Int) {
        self.targetCount = starCount
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        physicsWorld.gravity = CGVector(dx: 0, dy: -2.2)
    }

    required init?(coder aDecoder: NSCoder) {
        return nil
    }

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        view.allowsTransparency = true
        configureBoundary()
        populateIfNeeded()
        startMotion()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        configureBoundary()
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }

    private func configureBoundary() {
        childNode(withName: "boundary")?.removeFromParent()
        let boundary = SKNode()
        boundary.name = "boundary"
        let insetFrame = CGRect(x: 22, y: 18, width: max(10, size.width - 44), height: max(10, size.height - 70))
        let bottlePath = ParametricGeometry.mirroredProfile(
            in: insetFrame,
            profile: ParametricPreset.bottleProfile,
            tension: 0.73
        )
        boundary.physicsBody = SKPhysicsBody(edgeLoopFrom: bottlePath.cgPath)
        boundary.physicsBody?.friction = 0.4
        boundary.physicsBody?.restitution = 0.34
        addChild(boundary)
    }

    private func populateIfNeeded() {
        guard !didPopulate else { return }
        didPopulate = true

        for index in 0..<targetCount {
            let radius: CGFloat = 13 + CGFloat(index % 4)
            let path = starPath(radius: radius)
            let node = SKShapeNode(path: path)
            node.fillColor = index.isMultiple(of: 3)
                ? UIColor(red: 0.96, green: 0.72, blue: 0.34, alpha: 1)
                : UIColor(red: 0.90, green: 0.58, blue: 0.23, alpha: 1)
            node.strokeColor = UIColor.white.withAlphaComponent(0.30)
            node.lineWidth = 1
            node.position = CGPoint(
                x: 55 + CGFloat((index * 47) % 210),
                y: 76 + CGFloat((index * 37) % 210)
            )
            node.zRotation = CGFloat(index) * 0.41

            let body = SKPhysicsBody(circleOfRadius: radius * 0.76)
            body.friction = 0.45
            body.restitution = 0.26
            body.linearDamping = 0.52
            body.angularDamping = 0.45
            node.physicsBody = body
            addChild(node)
        }
    }

    private func startMotion() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            self.physicsWorld.gravity = CGVector(dx: CGFloat(gravity.x * 7.0), dy: CGFloat(gravity.y * 7.0))
        }
    }

    private func starPath(radius: CGFloat) -> CGPath {
        ParametricGeometry.roundedStar(
            in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2),
            innerRatio: ParametricPreset.starInnerRatio,
            roundness: ParametricPreset.starRoundness
        ).cgPath
    }
}
