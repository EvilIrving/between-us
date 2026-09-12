import SwiftUI
import MotionCore

@MainActor
struct AgentContractView: View {
    @ObservedObject var workspace: StudioWorkspace
    @State private var copied = false
    private var contract: String {
        let r = workspace.recipe
        return """
        动效任务约定

        用户目的：\(r.intent.purpose)
        操作频率：\(r.intent.frequency)
        触发事件：\(r.intent.trigger.rawValue)
        坐标空间：\(r.intent.coordinateSpace)
        完成结果：\(r.intent.success)
        恢复方式：\(r.intent.recovery)

        技术范围
        使用 Swift，优先复用 MotionCore、MotionSwiftUI；不得把效果改写为 Web、JS 或 GSAP。
        简单原生布局动画仍可用 SwiftUI。需要数据采样、速度续接或自定义模型时使用 MotionDriver。
        仅在用户授权时操作项目；当前任务明确禁止测试、构建、验证或打开页面，不能自行恢复这些步骤。

        当前配方
        名称：\(r.name)
        模型：\(r.family.rawValue)
        起点：\(r.initial.motionVector.components)
        终点：\(r.target.motionVector.components)
        顺序：x, y, scaleX, scaleY, rotation, opacity, blur, cornerRadius, width, height
        单位：pt, pt, ratio, ratio, rad, ratio, pt, pt, pt, pt
        初速度：\(r.velocity.components)，各分量单位均为对应单位/s
        高级路径：\(r.pathDocument?.knots.count ?? 0) 个节点；高级时间轴：\(r.keyframeDocument?.lanes.count ?? 0) 个通道
        中断：\(r.intent.interruption.rawValue)
        取消：\(r.intent.cancellation.rawValue)
        减少动态：\(r.intent.reducedBehavior.rawValue)

        实现约定
        - 先说明哪一个数据在变化，区分业务目标、显示值和速度。
        - 先确定坐标与路径，再选择时间模型；不能用缓动曲线假装空间曲线。
        - 同一个动作的参数集中到 MotionRecipe，不把数值散落到多个视图与延时闭包。
        - 要求速度连续时使用弹簧或 Hermite。普通 tween 只保证从显示值开始，不能声称保留速度。
        - 路径和时间轴的反向、重新规划，需要明确说明接缝和速度；不要套用标量 retarget 的保证。
        - 高级路径以 pathDocument 的节点为准；使用 setPathDocument 同步两端位置。高级时间轴以关键帧为准，不用全局 target 覆盖它们。
        - 路径与时间轴组合时，每个通道必须只有一个写入来源：路径接管 X/Y，关键帧接管指定外观通道；完成时间取所有参与通道的最晚末端。
        - 整体缩放关键帧时间时，同时反向缩放 Hermite 节点速度。删除节点或关键帧会改变相邻区间。
        - 恢复用 MotionSession.bookmark 保存当前运动段；默认恢复为暂停。拖动中的记录不能恢复成仍有手指按住的状态。
        - 透明度、尺寸和颜色的合法范围要在映射中明确；硬裁剪会改变可见速度。
        - 拖动时直接跟随，释放后才进入动力学。当前值来自 driver，不从旧 target 推测。
        - 每个手势有可见替代操作；系统减少动态开启时保留产品结果。
        - 退后台暂停，离开页面 detach。不要让完成回调提交本应由业务流程决定的交易。
        - 交付参数定义、可复用 Swift 入口、状态处理与已知边界。未经运行不得声称效果已确认。

        给执行 harness 的边界
        将这份约定和完整 JSON 配方作为任务输入，而不是只传“更丝滑”。
        harness 负责传递用户约束、目标文件和允许的操作；不修改公式含义、不自动扩展权限。
        Agent 可以修改配方或实现映射；不得把缺失的产品决策藏进随机参数。
        需要对照时保留原配方，以同一单位、同一时钟、同一场景比较；用户自行决定接受结果。
        这是一份执行输入约定，不包含测试 harness、预检或自动验收脚手架。
        """
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 22) {
                Text("先约定动作，再让 Agent 写。").font(.largeTitle.bold())
                Text("把当前工作台的配方与产品意图一起交出去。参数描述怎么动，约定描述为什么动、如何中断和怎样结束。")
                    .foregroundStyle(.secondary)
                StudioPanel(title: "产品意图") {
                    TextField("用户目的",text: $workspace.recipe.intent.purpose,axis: .vertical)
                    TextField("操作频率",text: $workspace.recipe.intent.frequency)
                    TextField("坐标空间",text: $workspace.recipe.intent.coordinateSpace)
                    TextField("成功结果",text: $workspace.recipe.intent.success,axis: .vertical)
                    TextField("恢复方式",text: $workspace.recipe.intent.recovery,axis: .vertical)
                    Picker("触发事件",selection: $workspace.recipe.intent.trigger) {
                        ForEach(MotionTrigger.allCases,id: \.self) { Text($0.rawValue.motionTitle).tag($0) }
                    }
                    Text("触发事件是宿主接线约定。选择“数据变化”不会自动监听任意业务数据；调用方应在更新时发送目标值。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                StudioPanel(title: "可复制的任务输入") {
                    Text(contract).font(.subheadline).lineSpacing(5).textSelection(.enabled)
                    Button(copied ? "约定已复制" : "复制约定") {
                        UIPasteboard.general.string = contract; copied = true
                    }.buttonStyle(.borderedProminent)
                    Button("复制当前 JSON 配方") {
                        do { UIPasteboard.general.string = String(decoding: try workspace.recipe.encoded(),as: UTF8.self) }
                        catch { workspace.notice = error.localizedDescription }
                    }.buttonStyle(.bordered)
                }
                StudioPanel(title: "每次修改先指出原因") {
                    Text("“最后太弹，所以阻尼比从 0.65 改为 0.9”比“优化动效”具体。“起点坐标来自另一个空间”比“换一个 spring”更接近真正原因。配方应保留这些判断，而不只是保存一个好看的最终数字。")
                        .lineSpacing(5)
                }
            }.padding(20).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.background(StudioStyle.paper)
        .onChange(of: workspace.recipe.intent) { _,_ in copied = false; workspace.updateExport() }
    }
}
