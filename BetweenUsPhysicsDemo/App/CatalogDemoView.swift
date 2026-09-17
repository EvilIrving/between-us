import SwiftUI
import Combine

@MainActor
final class CatalogDemoModel: ObservableObject {
    let scenes: [String: VesselPhysicsScene]
    @Published private(set) var statuses: [String: VesselStatus] = [:]
    @Published var notice = "正常模式下实体落入桶、盒后被遮住，内部仍继续碰撞。"

    init() {
        scenes = Dictionary(uniqueKeysWithValues:ResourceCatalog.all.map {
            ($0.id,VesselPhysicsScene(recipe:$0))
        })
        for (id,scene) in scenes {
            scene.onStatusChanged = { [weak self] status in
                DispatchQueue.main.async { [weak self] in self?.statuses[id] = status }
            }
            scene.onTokenTapped = { [weak self] id in
                DispatchQueue.main.async { [weak self] in
                    self?.notice = "已命中实体 \(id.uuidString.prefix(8))；业务层可从回调进入取出仪式。"
                }
            }
        }
    }
    func save(id: String) {
        guard let scene = scenes[id] else { return }
        do {
            let data = try JSONEncoder().encode(scene.makeSnapshot())
            UserDefaults.standard.set(data,forKey:"vessel.demo.snapshot.\(id).v1")
            notice = "当前实体、位置、角度和速度已保存。"
        } catch { notice = "保存失败：\(error.localizedDescription)" }
    }
    func restore(id: String) {
        guard let scene = scenes[id],
              let data = UserDefaults.standard.data(forKey:"vessel.demo.snapshot.\(id).v1") else {
            notice = "此容器尚未保存现场。"; return
        }
        do {
            try scene.restore(JSONDecoder().decode(VesselSnapshot.self,from:data))
            notice = "现场已恢复；接触关系由物理引擎重新建立。"
        } catch { notice = "恢复失败：\(error.localizedDescription)" }
    }
    func suspendAll() { scenes.values.forEach { $0.prepareForSuspension() } }
}

@MainActor
struct CatalogDemoView: View {
    @StateObject private var model = CatalogDemoModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = ResourceCatalog.starJar.id
    @State private var geometry = false
    @State private var xRay = false

    var body: some View {
        VStack(spacing:10) {
            Text("容器物理试验").font(.headline)
            Picker("容器",selection:$selection) {
                ForEach(ResourceCatalog.all) { recipe in Text(recipe.title).tag(recipe.id) }
            }
            .pickerStyle(.segmented)
            if let scene = model.scenes[selection] {
                GeometryReader { proxy in
                    let ratio = scene.size.width / scene.size.height
                    let width = min(proxy.size.width,proxy.size.height*ratio)
                    PhysicsSceneView(scene:scene,isPaused:scenePhase != .active,
                                     showGeometry:geometry,xRay:xRay)
                        .frame(width:width,height:width/ratio)
                        .position(x:proxy.size.width/2,y:proxy.size.height/2)
                }
                HStack {
                    Button("放入一颗") {
                        if !scene.queueToken() { model.notice = "已达到当前容量，或标识不允许重复。" }
                    }
                    Button("填满容量") { scene.fillToCapacity() }
                    Button("重新试验") { scene.resetDemo() }
                }.buttonStyle(.bordered)
                HStack {
                    Toggle("碰撞轮廓",isOn:$geometry)
                    Toggle("透视内部",isOn:$xRay)
                }.font(.footnote)
                HStack {
                    Button("保存现场") { model.save(id:selection) }
                    Button("恢复现场") { model.restore(id:selection) }
                    Spacer()
                    Text("上限 \(scene.recipe.policy.capacity)")
                }.font(.footnote)
                let status = model.statuses[selection] ?? VesselStatus()
                Text("实体 \(status.active)　休眠 \(status.resting)　排队 \(status.waiting)　回收 \(status.recoveries)")
                    .font(.caption.monospacedDigit())
                Text(status.error ?? (status.spawnBlocked ? "投放区被占用，队列等待，不会强行穿透。" : model.notice))
                    .font(.caption).foregroundStyle(status.error == nil ? .secondary : .primary)
                    .frame(maxWidth:.infinity,alignment:.leading).lineLimit(3)
                    .frame(minHeight:42,alignment:.topLeading)
            }
        }
        .padding(12)
        .background(.white)
        .onChange(of:scenePhase) { _,phase in
            if phase != .active { model.suspendAll() }
        }
        .onDisappear { model.suspendAll() }
    }
}
