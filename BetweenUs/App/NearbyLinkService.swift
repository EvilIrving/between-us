import CoreMotion
import Foundation
import NearbyInteraction
import OSLog
import simd

/// 两台手机之间那点空间关系。
///
/// 蓝牙负责把两台设备拉到一起、把发现令牌递过去；令牌换到之后由 UWB 给出距离和方位。
/// 这一层只回答两个问题：**有多近**、**在哪一侧**。
/// 方位拿到之后不直接交给界面：先按可信度加权——手机在晃、角度接近垂直、或者刚断过，
/// 权重就快速落到零，界面退回均匀的光。指错方向比不指方向糟得多。
@MainActor
final class NearbyLinkService: NSObject, ObservableObject {

    static let shared = NearbyLinkService()

    enum Support: Equatable {
        case unknown
        /// 这台设备没有 UWB，或者系统版本不够。
        case unsupported
        /// 有 UWB。方位能不能用还要看 `hasDirection`。
        case ready

        var canMeasureDistance: Bool { self == .ready }
    }

    // MARK: - 对外读数

    /// 对方离得多近，米。没有会话时为空。
    @Published private(set) var distance: Double?
    /// 屏幕坐标系下的偏心方向：单位向量乘上权重 0…1。方向不可信时为零。
    @Published private(set) var bias: CGVector = .zero
    @Published private(set) var support: Support = .unknown
    @Published private(set) var isRunning = false

    /// 本机令牌要交给对方时调用。由蓝牙通道送出。
    var onTokenReady: ((Data) -> Void)?

    /// 上机校准用：UWB 的方向轴系与机身轴系之间的偏转（弧度）。
    /// 纯 UWB 会话的方位参考系由芯片给出，真机上跑一次就能定下来。
    static var frameAlignment: Double = 0

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BetweenUs",
        category: "Nearby"
    )

    private var session: NISession?
    private var peerToken: NIDiscoveryToken?
    private var didHandOverToken = false

    private var latestDirection: simd_float3?
    private var latestDirectionAt: Date?
    private var latestDistanceAt: Date?
    private var smoothedDirection: simd_float2 = .zero
    /// 方向权重：上来得慢，掉得快。
    private var confidence: Double = 0
    private var smoothedDistance: Double?

    private let motion = CMMotionManager()
    private var rotationRate: Double = 0
    private var ticker: Task<Void, Never>?

    private override init() {
        super.init()
    }

    // MARK: - 生命周期

    func start() {
        guard !isRunning else { return }
        isRunning = true

        guard NISession.isSupported else {
            support = .unsupported
            Self.logger.info("Nearby Interaction is not supported on this device")
            return
        }
        support = .ready
        startMotion()

        let session = NISession()
        session.delegate = self
        let capability = NISession.deviceCapabilities
        Self.logger.info(
            "Nearby capability: distance \(Int(capability.supportsPreciseDistanceMeasurement ? 1 : 0), privacy: .public), direction \(Int(capability.supportsDirectionMeasurement ? 1 : 0), privacy: .public)"
        )
        self.session = session

        if let peerToken {
            run(with: peerToken)
        } else {
            publishToken(from: session)
        }
        startTicker()
    }

    func stop() {
        isRunning = false
        ticker?.cancel()
        ticker = nil
        session?.invalidate()
        session = nil
        peerToken = nil
        didHandOverToken = false
        motion.stopDeviceMotionUpdates()
        rotationRate = 0
        distance = nil
        smoothedDistance = nil
        bias = .zero
        confidence = 0
        latestDirection = nil
        latestDirectionAt = nil
        latestDistanceAt = nil
        smoothedDirection = .zero
    }

    /// 对方把令牌送过来了：有会话就直接跑，没有就等会话建好。
    func receivePeerToken(_ data: Data) {
        guard
            let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data)
        else {
            Self.logger.error("Peer token could not be decoded")
            return
        }
        peerToken = token
        guard let session, session.discoveryToken != nil else { return }
        run(with: token)
    }

    // MARK: - 会话

    private func publishToken(from session: NISession) {
        guard !didHandOverToken, let token = session.discoveryToken else { return }
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            Self.logger.error("Local token could not be encoded")
            return
        }
        didHandOverToken = true
        onTokenReady?(data)
    }

    private func run(with token: NIDiscoveryToken) {
        guard let session else { return }
        let configuration = NINearbyPeerConfiguration(peerToken: token)
        // 相机辅助能让方位更稳，但要相机权限、要人走动去收敛。
        // 这一屏的方位本来就只在「两个人都在动」的几秒里有意义，先不开。
        configuration.isCameraAssistanceEnabled = false
        session.run(configuration)
        publishToken(from: session)
    }

    // MARK: - 姿态

    /// 手机自身的转动速度。手在晃的时候方位不可信，用它把权重压下去。
    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 20.0
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let rate = motion.rotationRate
            self?.rotationRate = (rate.x * rate.x + rate.y * rate.y + rate.z * rate.z).squareRoot()
        }
    }

    /// 可信度是逐帧算出来的，所以这里自己走一条很轻的节拍。
    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(90))
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    // MARK: - 读数

    fileprivate func ingest(distance meters: Float?, direction: simd_float3?) {
        let now = Date()

        if let meters, meters.isFinite, meters > 0 {
            let previous = smoothedDistance ?? Double(meters)
            smoothedDistance = previous + (Double(meters) - previous) * 0.35
            distance = smoothedDistance
            latestDistanceAt = now
        }

        guard let direction, direction.x.isFinite, direction.y.isFinite else { return }
        latestDirection = direction
        latestDirectionAt = now
        smoothedDirection += (simd_float2(direction.x, direction.y) - smoothedDirection) * 0.14
    }

    /// 每帧调用一次：把方位读数按可信度折成界面要的偏心量，过期的读数直接丢掉。
    func tick() {
        let now = Date()

        if let latestDistanceAt, now.timeIntervalSince(latestDistanceAt) > 2.2 {
            self.latestDistanceAt = nil
            smoothedDistance = nil
            distance = nil
        }

        let isFresh = latestDirectionAt.map { now.timeIntervalSince($0) < 0.9 } ?? false
        let planar = simd_length(smoothedDirection)
        let isSteady = rotationRate < 1.1

        // 角度太接近屏幕法线时，投到屏幕上没有意义。
        let target = (isFresh && isSteady && planar > 0.22) ? min(1, Double(planar) / 0.55) : 0

        if target <= 0 {
            confidence = 0
        } else if target > confidence {
            confidence = min(target, confidence + 0.045)
        } else {
            confidence = target
        }

        guard confidence > 0.001, planar > 0.0001 else {
            if bias != .zero { bias = .zero }
            return
        }

        let angle = atan2(Double(smoothedDirection.y), Double(smoothedDirection.x)) + Self.frameAlignment
        bias = CGVector(dx: cos(angle) * confidence, dy: sin(angle) * confidence)
    }
}

extension NearbyLinkService: @preconcurrency NISessionDelegate {

    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let object = nearbyObjects.first else { return }
        let direction = object.direction
        Task { @MainActor [weak self] in
            self?.ingest(distance: object.distance, direction: direction)
        }
    }

    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        Task { @MainActor [weak self] in
            guard let self, self.isRunning else { return }
            self.smoothedDistance = nil
            self.distance = nil
            self.bias = .zero
            self.confidence = 0
        }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {
        Task { @MainActor [weak self] in
            guard let self, self.isRunning else { return }
            self.bias = .zero
            self.confidence = 0
        }
    }

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        Task { @MainActor [weak self] in
            guard let self, self.isRunning, let peerToken = self.peerToken else { return }
            self.run(with: peerToken)
        }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.isRunning else { return }
            Self.logger.info("Nearby session ended: \(error.localizedDescription, privacy: .public)")
            guard let peerToken = self.peerToken else { return }
            // 会话失效是一次性的，重新起一次；拿不到就安静地退回只有距离的状态。
            let fresh = NISession()
            fresh.delegate = self
            self.session = fresh
            self.run(with: peerToken)
        }
    }
}
