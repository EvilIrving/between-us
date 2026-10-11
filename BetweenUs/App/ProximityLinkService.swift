import CloudKit
import CoreBluetooth
import Foundation
import OSLog

/// 面对面把两台手机连起来。
///
/// 蓝牙只做两件事：把信号强度读成「离得多近」，以及在相认完成时把邀请链接递过去。
/// 没有「允许」这个动作——空间建好之后授权就已经给出去了，创建者可以锁屏、把手机放桌上，
/// 不需要在对方靠近的那一刻看着屏幕。
///
/// 加入者侧也不需要按钮：对方在附近时光会亮起来，手机贴着不动约两秒，
/// 光从瓶底涨到瓶口就是相认完成。整个过程唯一的操作是「把手机放近」。
@MainActor
final class ProximityLinkService: NSObject, ObservableObject {

    static let shared = ProximityLinkService()

    /// 蓝牙只求稳不求准：够近才允许相认，走开立刻退回去，
    /// 中间留一段滞回，两个人并排站着不会来回抖。
    enum Signal {
        static let strongest: Double = -45
        static let weakest: Double = -92
        /// 进入「够近」的信号强度。
        static let enter: Double = -58
        /// 退出「够近」的信号强度。
        static let leave: Double = -68
        /// 平滑系数：越大跟手越快，越小越稳。
        static let smoothing: Double = 0.32
        /// 超过这么久没有收到信号，就当对方不在了。
        static let stale: TimeInterval = 2.2
    }

    /// 这台手机在配对里的位置。位置不由按钮决定，由有没有空间决定。
    enum Mode: Equatable {
        case off
        /// 空间已经建好，等对方靠近。
        case waiting
        /// 还没有空间，正在找对方的空间。
        case seeking
    }

    enum Availability: Equatable {
        case unknown
        case ready
        case unavailable
    }

    /// 相认需要贴着不动多久。
    static let claimDuration: TimeInterval = 2.0
    /// 走开之后光退回去要多久。退得比涨得快。
    private static let releaseDuration: TimeInterval = 0.55
    /// 一次相认没成功，隔这么久再试，不会贴着不停重试。
    private static let retryCooldown: TimeInterval = 20

    @Published private(set) var mode: Mode = .off
    @Published private(set) var availability: Availability = .unknown
    /// 对方有多近，0…1。两台手机都读这个值，所以两个人的屏幕会一起亮起来。
    @Published private(set) var approach: Double = 0
    /// 近到可以相认了。
    @Published private(set) var isNear = false
    /// 相认进度 0…1：光从瓶底涨到瓶口。
    @Published private(set) var claim: Double = 0
    /// 正在把链接取过来。
    @Published private(set) var isJoining = false
    /// 刚刚连上，留给界面收尾。
    @Published private(set) var didConnect = false

    /// 加入者拿到邀请链接。
    var onLink: ((URL) -> Void)?
    /// 创建者交出邀请链接。
    var linkProvider: (() async -> URL?)?
    /// 创建者已经把链接递出去了：这一刻两个人开始真正连接。
    var onLinkServed: (() -> Void)?

    // 两台设备各自只认对方那一种广播：等着的手机认加入者的信标，加入者认对方的服务。
    private static let hostServiceID = CBUUID(string: "B4E7C1A2-5F3D-4E8B-9C6A-1D2F3E4A5B60")
    private static let requestID = CBUUID(string: "B4E7C1A2-5F3D-4E8B-9C6A-1D2F3E4A5B61")
    private static let responseID = CBUUID(string: "B4E7C1A2-5F3D-4E8B-9C6A-1D2F3E4A5B62")
    private static let beaconID = CBUUID(string: "B4E7C1A2-5F3D-4E8B-9C6A-1D2F3E4A5B63")
    private static let beaconMarkerID = CBUUID(string: "B4E7C1A2-5F3D-4E8B-9C6A-1D2F3E4A5B64")
    /// UWB 的发现令牌走这两条：加入者写进来，等着的手机发出去。
    private static let tokenInID = CBUUID(string: "B4E7C1A2-5F3D-4E8B-9C6A-1D2F3E4A5B65")
    private static let tokenOutID = CBUUID(string: "B4E7C1A2-5F3D-4E8B-9C6A-1D2F3E4A5B66")

    private static let joinPayload = Data("join".utf8)
    private static let grantPrefix = "ok\n"
    private static let emptyPayload = Data("no".utf8)
    private static let restorationID = "com.betweenus.proximity-peripheral"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BetweenUs",
        category: "Proximity"
    )

    private var peripheral: CBPeripheralManager?
    private var requestCharacteristic: CBMutableCharacteristic?
    private var responseCharacteristic: CBMutableCharacteristic?
    private var tokenInCharacteristic: CBMutableCharacteristic?
    private var tokenOutCharacteristic: CBMutableCharacteristic?
    private var advertisedServiceID: CBUUID?
    private var didPublishServices = false
    private var pendingResponse: (data: Data, central: CBCentral)?

    private var central: CBCentralManager?
    private var scanTargetID: CBUUID?
    private var candidate: CBPeripheral?
    private var target: CBPeripheral?
    private var peerTokenIn: CBCharacteristic?
    private var peerTokenOut: CBCharacteristic?

    /// 本机 UWB 令牌：等对方来取，或者主动写过去。
    private var localToken: Data?
    private var pendingTokenChunks: [Data] = []
    private var tokenAssembler = ChunkAssembler()

    private var latestSignal: Double = Signal.weakest
    private var lastSignalAt: Date?
    private var ticker: Task<Void, Never>?
    private var attemptTimeout: Task<Void, Never>?
    private var cooldownUntil: Date?
    private var didStartManagers = false

    private override init() {
        super.init()
    }

    // MARK: - 生命周期

    /// 空间已经建好、对方还没进来：广播邀请，等对方靠近。
    func startWaiting() {
        begin(as: .waiting)
    }

    /// 还没有空间：找对方的空间，靠近就相认。
    func startSeeking() {
        begin(as: .seeking)
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        attemptTimeout?.cancel()
        attemptTimeout = nil
        peripheral?.stopAdvertising()
        peripheral?.removeAllServices()
        peripheral = nil
        central?.stopScan()
        if let target {
            central?.cancelPeripheralConnection(target)
        }
        central = nil
        target = nil
        candidate = nil
        requestCharacteristic = nil
        responseCharacteristic = nil
        tokenInCharacteristic = nil
        tokenOutCharacteristic = nil
        peerTokenIn = nil
        peerTokenOut = nil
        localToken = nil
        pendingTokenChunks = []
        tokenAssembler = ChunkAssembler()
        didPublishServices = false
        pendingResponse = nil
        didStartManagers = false
        latestSignal = Signal.weakest
        lastSignalAt = nil
        approach = 0
        isNear = false
        claim = 0
        isJoining = false
        didConnect = false
        mode = .off
    }

    private func begin(as mode: Mode) {
        guard self.mode != mode else { return }
        if self.mode != .off {
            stop()
        }
        self.mode = mode
        peripheral = CBPeripheralManager(
            delegate: self,
            queue: .main,
            options: [CBPeripheralManagerOptionRestoreIdentifierKey: Self.restorationID]
        )
        central = CBCentralManager(delegate: self, queue: .main)
        scanTargetID = mode == .waiting ? Self.beaconID : Self.hostServiceID
        didStartManagers = true
        // 距离和方位由 UWB 负责，令牌从这条蓝牙通道进出。
        NearbyLinkService.shared.onTokenReady = { [weak self] data in
            self?.queueToken(data)
        }
        startTicker()
    }

    /// 回到前台时把广播和扫描补回来：退到后台时系统会把它们停掉。
    func resume() {
        guard mode != .off else { return }
        startAdvertising()
        startScanning()
    }

    /// 相认已经完成，界面收尾之后回到安静状态。
    func noteConnected() {
        didConnect = true
        latestSignal = Signal.weakest
        approach = 0
        isNear = false
        claim = 0
        peripheral?.stopAdvertising()
        central?.stopScan()
    }

    /// 这一次相认没有连上：退回去，隔一会儿再试。
    func noteAttemptFailed() {
        isJoining = false
        claim = 0
        didConnect = false
        cooldownUntil = Date().addingTimeInterval(Self.retryCooldown)
        if let target {
            central?.cancelPeripheralConnection(target)
        }
        target = nil
        if mode == .seeking {
            startScanning()
        }
    }

    // MARK: - 信号与相认

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            var last = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard let self, !Task.isCancelled else { return }
                let now = Date()
                let dt = min(max(now.timeIntervalSince(last), 0.01), 0.25)
                last = now
                self.tick(dt: dt, now: now)
            }
        }
    }

    private func tick(dt: TimeInterval, now: Date) {
        decayIfStale(now: now)

        guard mode == .seeking, !isJoining, !didConnect else { return }
        let canClaim = isNear && (cooldownUntil.map { now >= $0 } ?? true)

        if canClaim {
            claim = min(1, claim + dt / Self.claimDuration)
            if claim >= 1, !isJoining {
                requestLink()
            }
        } else if claim > 0 {
            claim = max(0, claim - dt / Self.releaseDuration)
        }
    }

    private func ingest(signal rssi: Double, from peripheral: CBPeripheral?) {
        let clamped = min(max(rssi, Signal.weakest), Signal.strongest)
        if let peripheral, candidate?.identifier != peripheral.identifier {
            // 换一台：只有原来那台走开之后才认新的，免得在两台之间跳。
            if let lastSignalAt, Date().timeIntervalSince(lastSignalAt) < Signal.stale { return }
            candidate = peripheral
            latestSignal = clamped
        } else {
            latestSignal += (clamped - latestSignal) * Signal.smoothing
        }
        lastSignalAt = Date()
        approach = (latestSignal - Signal.weakest) / (Signal.strongest - Signal.weakest)
        let wasNear = isNear
        isNear = isNear ? latestSignal > Signal.leave : latestSignal > Signal.enter
        if isNear, !wasNear {
            RitualHaptics.soft()
        }
    }

    private func decayIfStale(now: Date) {
        // 已经拿到链接或正在相认时，距离不再有用，不要把画面调暗。
        guard !isJoining, !didConnect else { return }
        guard let lastSignalAt, now.timeIntervalSince(lastSignalAt) > Signal.stale else { return }
        latestSignal = Signal.weakest
        approach = 0
        isNear = false
        if mode == .seeking {
            candidate = nil
        }
    }

    // MARK: - 加入者：拿到链接

    private func requestLink() {
        guard mode == .seeking, !isJoining, let central, let candidate else { return }
        isJoining = true
        claim = 1
        central.stopScan()
        target = candidate
        candidate.delegate = self
        central.connect(candidate, options: nil)

        attemptTimeout?.cancel()
        attemptTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, !Task.isCancelled, self.isJoining, self.didConnect == false else { return }
            Self.logger.info("Proximity link request timed out")
            self.noteAttemptFailed()
        }
    }

    private func deliver(_ payload: Data) {
        let text = String(decoding: payload, as: UTF8.self)
        guard text.hasPrefix(Self.grantPrefix) else { return }
        let raw = String(text.dropFirst(Self.grantPrefix.count))
        guard let url = URL(string: raw) else {
            Self.logger.error("Proximity grant carried an unusable link")
            noteAttemptFailed()
            return
        }
        attemptTimeout?.cancel()
        attemptTimeout = nil
        isJoining = false
        claim = 0
        // 链接到手就是相认完成：光停在满处，等 CloudKit 把空间真正接上。
        didConnect = true
        // 蓝牙先留着：UWB 的发现令牌还要从这条连接上换过去，换完为止。
        Self.logger.info("Proximity link received")
        onLink?(url)
    }

    // MARK: - 创建者：把链接递出去

    private func serveLink(to central: CBCentral) {
        guard mode == .waiting else { return }
        guard let linkProvider else {
            send(Self.emptyPayload, to: central)
            return
        }
        Task { @MainActor [weak self] in
            let url = await linkProvider()
            guard let self else { return }
            guard let url else {
                self.send(Self.emptyPayload, to: central)
                return
            }
            self.send(Data((Self.grantPrefix + url.absoluteString).utf8), to: central)
            // 链接交出去的那一刻，两个人开始连接。同步的是这一刻，不是谁先按下了什么。
            self.onLinkServed?()
            self.flushTokenChunks()
        }
    }

    private func send(_ data: Data, to central: CBCentral) {
        guard let responseCharacteristic else { return }
        responseCharacteristic.value = data
        let accepted = peripheral?.updateValue(
            data,
            for: responseCharacteristic,
            onSubscribedCentrals: [central]
        )
        // 发送队列满了就留着，等 peripheralManagerIsReady 再补发；对方也能直接读到。
        pendingResponse = accepted == true ? nil : (data, central)
    }

    // MARK: - UWB 令牌

    /// 本机令牌准备好：等对方来取，或者直接写过去。
    private func queueToken(_ data: Data) {
        localToken = data
        pendingTokenChunks = ChunkFramer.encode(data)
        flushTokenChunks()
    }

    private func flushTokenChunks() {
        guard !pendingTokenChunks.isEmpty else { return }
        switch mode {
        case .off:
            return
        case .waiting:
            guard let tokenOutCharacteristic,
                  let peripheral,
                  peripheral.state == .poweredOn else { return }
            while let chunk = pendingTokenChunks.first {
                tokenOutCharacteristic.value = chunk
                let accepted = peripheral.updateValue(
                    chunk,
                    for: tokenOutCharacteristic,
                    onSubscribedCentrals: nil
                )
                guard accepted else { return }
                pendingTokenChunks.removeFirst()
            }
        case .seeking:
            guard let target, let peerTokenIn else { return }
            let chunks = pendingTokenChunks
            pendingTokenChunks = []
            for chunk in chunks {
                target.writeValue(chunk, for: peerTokenIn, type: .withResponse)
            }
        }
    }

    /// 收到对方的一段令牌：拼完整了才交给 UWB。
    private func ingestTokenChunk(_ chunk: Data) {
        guard let complete = tokenAssembler.append(chunk) else { return }
        tokenAssembler = ChunkAssembler()
        Self.logger.info("UWB discovery token received")
        NearbyLinkService.shared.receivePeerToken(complete)
    }

    // MARK: - 广播与扫描

    private func startScanning() {
        guard let central, central.state == .poweredOn, let scanTargetID,
              !central.isScanning else { return }
        central.scanForPeripherals(
            withServices: [scanTargetID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    private func startAdvertising() {
        guard
            let peripheral,
            peripheral.state == .poweredOn,
            !peripheral.isAdvertising,
            let advertisedServiceID
        else { return }
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [advertisedServiceID]])
    }

    private func publishServices() {
        guard let peripheral, peripheral.state == .poweredOn, !didPublishServices else { return }
        didPublishServices = true

        switch mode {
        case .off:
            return
        case .waiting:
            let request = CBMutableCharacteristic(
                type: Self.requestID,
                properties: [.write],
                value: nil,
                permissions: [.writeable]
            )
            let response = CBMutableCharacteristic(
                type: Self.responseID,
                properties: [.read, .notify],
                value: nil,
                permissions: [.readable]
            )
            let tokenIn = CBMutableCharacteristic(
                type: Self.tokenInID,
                properties: [.write],
                value: nil,
                permissions: [.writeable]
            )
            let tokenOut = CBMutableCharacteristic(
                type: Self.tokenOutID,
                properties: [.read, .notify],
                value: nil,
                permissions: [.readable]
            )
            let service = CBMutableService(type: Self.hostServiceID, primary: true)
            service.characteristics = [request, response, tokenIn, tokenOut]
            requestCharacteristic = request
            responseCharacteristic = response
            tokenInCharacteristic = tokenIn
            tokenOutCharacteristic = tokenOut
            peripheral.add(service)
        case .seeking:
            // 加入者只广播自己的存在，让对方的屏幕看见自己越来越近，不带任何内容。
            let beacon = CBMutableService(type: Self.beaconID, primary: true)
            let marker = CBMutableCharacteristic(
                type: Self.beaconMarkerID,
                properties: [.read],
                value: Data("1".utf8),
                permissions: [.readable]
            )
            beacon.characteristics = [marker]
            peripheral.add(beacon)
        }
    }

    /// 蓝牙就绪：把界面从失败态放回来，补上服务，开始扫描。两个管理器各自的就绪都会走到这里。
    private func handleBluetoothReady() {
        availability = .ready
        publishServices()
        startScanning()
    }

    private func handleBluetoothUnavailable() {
        availability = .unavailable
        claim = 0
        isNear = false
        approach = 0
    }
}

// MARK: - CBPeripheralManagerDelegate

extension ProximityLinkService: @preconcurrency CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            handleBluetoothReady()
        case .poweredOff, .unauthorized, .unsupported:
            handleBluetoothUnavailable()
        default:
            break
        }
    }

    /// 系统把后台被唤醒的蓝牙管理器还回来时，接着等对方，不重新走一遍界面。
    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        willRestoreState dict: [String: Any]
    ) {
        let restored = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] ?? []
        if let service = restored.first(where: {
            $0.uuid == Self.hostServiceID || $0.uuid == Self.beaconID
        }) {
            advertisedServiceID = service.uuid
            for characteristic in service.characteristics ?? [] {
                switch characteristic.uuid {
                case Self.requestID:
                    requestCharacteristic = characteristic as? CBMutableCharacteristic
                case Self.responseID:
                    responseCharacteristic = characteristic as? CBMutableCharacteristic
                case Self.tokenInID:
                    tokenInCharacteristic = characteristic as? CBMutableCharacteristic
                case Self.tokenOutID:
                    tokenOutCharacteristic = characteristic as? CBMutableCharacteristic
                default:
                    break
                }
            }
        }
        didPublishServices = true
        startAdvertising()
    }

    func peripheralManager(_ manager: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else {
            Self.logger.error(
                "Failed to publish proximity service: \(error?.localizedDescription ?? "", privacy: .public)"
            )
            handleBluetoothUnavailable()
            return
        }
        advertisedServiceID = service.uuid
        startAdvertising()
    }

    func peripheralManager(_ manager: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard mode == .waiting else {
                manager.respond(to: request, withResult: .requestNotSupported)
                continue
            }
            switch request.characteristic.uuid {
            case Self.requestID:
                manager.respond(to: request, withResult: .success)
                serveLink(to: request.central)
            case Self.tokenInID:
                manager.respond(to: request, withResult: .success)
                if let data = request.value {
                    ingestTokenChunk(data)
                }
                // 对方刚把令牌递上来，说明它已经订上了；这时候把自己的递过去最稳。
                flushTokenChunks()
            default:
                manager.respond(to: request, withResult: .requestNotSupported)
            }
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        if let pendingResponse, let responseCharacteristic {
            let accepted = peripheral.updateValue(
                pendingResponse.data,
                for: responseCharacteristic,
                onSubscribedCentrals: [pendingResponse.central]
            )
            if accepted {
                self.pendingResponse = nil
            }
        }
        flushTokenChunks()
    }
}

// MARK: - CBCentralManagerDelegate

extension ProximityLinkService: @preconcurrency CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            handleBluetoothReady()
        case .poweredOff, .unauthorized, .unsupported:
            handleBluetoothUnavailable()
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let rssi = RSSI.doubleValue
        // 127 是「读数无效」的保留值，不能拿它当距离。
        guard rssi < 0, rssi > -120 else { return }
        ingest(signal: rssi, from: mode == .seeking ? peripheral : nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard mode == .seeking else { return }
        peripheral.discoverServices([Self.hostServiceID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard mode == .seeking, isJoining else { return }
        noteAttemptFailed()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard mode == .seeking, isJoining else { return }
        noteAttemptFailed()
    }
}

// MARK: - CBPeripheralDelegate

extension ProximityLinkService: @preconcurrency CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard mode == .seeking, isJoining else { return }
        guard
            error == nil,
            let service = peripheral.services?.first(where: { $0.uuid == Self.hostServiceID })
        else {
            noteAttemptFailed()
            return
        }
        peripheral.discoverCharacteristics(
            [Self.requestID, Self.responseID, Self.tokenInID, Self.tokenOutID],
            for: service
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard mode == .seeking, isJoining, error == nil else { return }
        let characteristics = service.characteristics ?? []
        guard
            let request = characteristics.first(where: { $0.uuid == Self.requestID }),
            let response = characteristics.first(where: { $0.uuid == Self.responseID })
        else {
            noteAttemptFailed()
            return
        }
        peerTokenIn = characteristics.first(where: { $0.uuid == Self.tokenInID })
        peerTokenOut = characteristics.first(where: { $0.uuid == Self.tokenOutID })
        // 先订上再说话：对方的令牌是发出来的，订晚了就收不到。
        if let peerTokenOut {
            peripheral.setNotifyValue(true, for: peerTokenOut)
        }
        peripheral.setNotifyValue(true, for: response)
        peripheral.writeValue(Self.joinPayload, for: request, type: .withResponse)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard mode == .seeking else { return }
        guard error == nil, let data = characteristic.value else { return }

        switch characteristic.uuid {
        case Self.responseID:
            guard isJoining else { return }
            deliver(data)
        case Self.tokenOutID:
            // 令牌是在链接之后才到的，这时候已经不「正在加入」了。
            ingestTokenChunk(data)
        default:
            break
        }
    }
}

/// UWB 的发现令牌比一条链接长，蓝牙一包写不下，切成小片。
/// 每片带序号和「最后一片」标记：收到错序或断掉的片段就整段作废，不拿半个令牌去开会话。
enum ChunkFramer {
    static let headerSize = 3
    static let payloadSize = 100

    static func encode(_ data: Data) -> [Data] {
        guard !data.isEmpty else { return [] }
        let total = (data.count + payloadSize - 1) / payloadSize
        return (0..<total).map { index in
            let start = index * payloadSize
            let end = min(start + payloadSize, data.count)
            var chunk = Data()
            chunk.append(UInt8((index >> 8) & 0xFF))
            chunk.append(UInt8(index & 0xFF))
            chunk.append(index == total - 1 ? 0x01 : 0x00)
            chunk.append(data[start..<end])
            return chunk
        }
    }
}

struct ChunkAssembler {
    private static let maximumBytes = 4096

    private var buffer = Data()
    private var expectedIndex = 0

    /// 片段拼完整了返回整个载荷，否则返回 nil。
    mutating func append(_ chunk: Data) -> Data? {
        guard chunk.count > ChunkFramer.headerSize else {
            reset()
            return nil
        }
        let index = (Int(chunk[chunk.startIndex]) << 8) | Int(chunk[chunk.startIndex + 1])
        let isLast = chunk[chunk.startIndex + 2] == 0x01
        guard index == expectedIndex, buffer.count < Self.maximumBytes else {
            reset()
            return nil
        }

        buffer.append(chunk.dropFirst(ChunkFramer.headerSize))
        expectedIndex += 1

        guard isLast else { return nil }
        let complete = buffer
        reset()
        return complete
    }

    private mutating func reset() {
        buffer = Data()
        expectedIndex = 0
    }
}
