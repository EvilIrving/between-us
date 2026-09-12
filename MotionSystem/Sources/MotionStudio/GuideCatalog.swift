import Foundation

struct GuideChapter: Identifiable {
    var id: String
    var title: String
    var question: String
    var sections: [GuideSection]
    var code: String
    var exercise: String
}
struct GuideSection {
    var title: String
    var text: String
    init(_ title: String,_ text: String) { self.title = title; self.text = text }
}

enum GuideCatalog {
    static let chapters: [GuideChapter] = [
        .init(id: "state",title: "动画到底在改变什么",question: "把“做个动效”拆成可以实现的状态变化。",sections: [
            .init("三种不同的值","业务目标是最终希望到达的状态，显示值是屏幕此刻的状态，速度是显示值正在变化的速率。用户改目标时，业务目标可以立即改变，显示值不能突然跳过去。MotionDriver 同时保存显示值和速度。"),
            .init("连续数据与离散数据","数值、位置、尺寸、角度、颜色分量可以用连续向量表示。Bool、文字、数组结构、视图身份不能自然地插值；先选择中间表示。例如“关闭 → 打开”映射到 progress 0…1，文字切换映射到两份文字的透明度，列表重排保留元素身份后改变布局。"),
            .init("一个数据源可以驱动多个属性","让进度 p 同时驱动 x、scale 和 opacity，能保证它们共享同一时间。但这也意味着它们共享过冲；如果透明度不该回弹，就把它拆到独立轨道。模型与显示映射应分开，不要让 view 每帧反过来覆盖业务状态。")
        ],code: """
        // MotionCore 只关心值与时间，不要求值来自 View。
        let motion = MotionTrajectory<Double>.transition(
            from: 0, to: 100,
            model: .spring(.init(response: 0.55, dampingRatio: 0.9))
        )
        let snapshot = motion.sample(at: 0.25)
        // snapshot.value 是当前值。
        // snapshot.velocity[0] 的单位是“数值单位 / 秒”。
        """,exercise: "先只动画一个数字。确认你能分别指出目标值、显示值和速度，再把它映射成宽度或角度。"),
        .init(id: "timing",title: "时间曲线：决定什么时候快",question: "Bézier、线性、正弦与多项式如何选择。",sections: [
            .init("基本关系","把时间归一化为 u = t / duration，曲线得到进度 p = f(u)，数值再通过 x = A + (B−A)p 插值。速度是 (B−A)f′(u)/duration。因此同样的曲线和时长，移动 400pt 会比移动 40pt 快十倍。"),
            .init("三次贝塞尔必须解横坐标","贝塞尔有内部参数 s，时间是 x(s)，进度是 y(s)。给定时间 u，需要先找到 x(s)=u 的 s，再取 y(s)。直接把 u 填进 y(s) 会画出另一条曲线。编辑器通过二分求解横坐标，端点斜率决定开始与结束时的速度。"),
            .init("该选哪条","线性适合持续的匀速过程，端点速度会突变。easeOut 适合即时响应后减速。easeInOut 适合完整的移场，开始较慢。Smoothstep 让端点速度为零；Smootherstep 还让端点加速度为零。阶梯刻意制造离散变化，不能要求连续速度。"),
            .init("不要让数字遮住表达","“高级感”不是某四个控制点的名称。先确定操作频率和空间关系，再选速度分布。高频点击反馈不应有一段长长的慢启动。")
        ],code: """
        // SwiftUI：布局状态插值。
        withAnimation(.timingCurve(0.2, 0, 0.2, 1, duration: 0.45)) {
            expanded = true
        }
        // MotionCore：数据插值，同一控制点体系。
        driver.animate(to: 240, model: .tween(
            duration: 0.45, curve: .bezier(CubicBezier(0.2, 0, 0.2, 1))
        ))
        """,exercise: "保存 easeInOut 为对照，仅换成 easeOut。观察前 20% 时间经过的距离，再单独改变总时长。"),
        .init(id: "spring",title: "弹簧：先定节奏，再定回弹",question: "response、阻尼比、刚度和质量分别是什么。",sections: [
            .init("物理模型","弹簧满足 m·x″ + c·x′ + k·(x−target)=0。自然角频率 ω₀=√(k/m)，阻尼比 ζ=c/(2√km)。这里使用 response=2π/ω₀ 表达节奏。response 小，运动更快；它不是“刚好在这段时间结束”的承诺。"),
            .init("三个阻尼区域","静止释放时，ζ<1 可能越过目标并振荡；ζ=1 在不振荡的模型中较快靠近；ζ>1 逐渐趋近，通常更迟缓。带初速度的情况不能只凭阻尼比断言绝无越界。先设 ζ=1 找节奏，再逐步降低一点加入弹性。"),
            .init("质量不是独立的重量感滑杆","固定 response 与阻尼比时，增加质量会同比调整刚度和阻尼系数，归一化运动不变。只有保持其他物理参数不变，改变质量才会改变频率和阻尼比。重量感还来自接触、阴影、距离与拖动阻力。"),
            .init("SwiftUI 的另一套参数","duration / bounce 用感知参数表达手感；response / dampingFraction 更接近这里的物理模型。不要把同一个数从 duration 复制进 response，就期待逐帧一致。自有采样器与 SwiftUI 系统动画也不保证完全重合。")
        ],code: """
        let spring = SpringConfiguration(response: 0.55, dampingRatio: 0.9)
        // 理想模型对应值：
        let k = spring.stiffness
        let c = spring.damping
        // SwiftUI 原生：
        withAnimation(.spring(response: 0.55, dampingFraction: 0.9)) {
            expanded.toggle()
        }
        // 数据驱动，自动保留当前速度：
        driver.animate(to: target, model: .spring(spring))
        """,exercise: "把阻尼比设为 1，调好 response 后固定它，再比较 0.65、0.85 和 1.15。"),
        .init(id: "continuity",title: "中断：位置连续还不够",question: "C0、C1 和 Hermite 为什么与手感有关。",sections: [
            .init("C0 是值不跳，C1 是速度不跳","从当前显示位置开始新动画，解决的是位置连续。如果新动画的起始速度突然变为零，手感仍可能像撞了一下。继续使用当前速度，才能避免这一类断点。加速度连续属于更高要求，普通 UI 不必一律追求。"),
            .init("弹簧改目标","弹簧求解器接收当前 x、当前 v 和新 target。往右快速运动时，把目标改到左侧，物件可能先继续向右一点，再转身。这是保留惯性的结果，不是错误。"),
            .init("固定时长也能接住速度","Hermite 使用起终点、起终点速度和时长定义多项式，适合明确截止时间的运动。它能够匹配端点速度，但初速度过大或时长太长时，也可能越界；它不是自动限制范围的弹簧替代品。"),
            .init("动画目标不等于呈现位置","普通 SwiftUI @State 经常保存终点，屏幕还在中途。MotionDriver 直接持有显示值，避免这一误用；UIKit 则可读取 presentation layer。不要把 model layer 的终点当作手势重新抓取的位置。")
        ],code: """
        // 手势或新数据到来时，从显示状态续接。
        driver.animate(to: nextTarget,
                       model: .spring(.init(response: 0.5, dampingRatio: 0.9)),
                       interruption: .preserveVelocity)

        // 必须在 0.4 秒后到达，并以零速度结束：
        driver.animate(to: nextTarget, model: .hermite(duration: 0.4))
        """,exercise: "用 0.9 秒的响应慢放，在运动一半时返回。分别选择“续接值与速度”和“只续接值”，看速度曲线的接点。"),
        .init(id: "coordinates",title: "坐标、布局与锚点",question: "怎样可靠地从一个位置移到另一个位置。",sections: [
            .init("先确定同一个空间","A 和 B 必须属于同一坐标空间。列表行里的局部坐标不能直接与屏幕坐标相减。安全区、滚动偏移和嵌套布局都会改变原点。优先使用共同的命名坐标空间，或让 matchedGeometryEffect 关联两个布局。"),
            .init("position、offset 和 frame","position 设置中心在父空间中的位置；offset 只在布局结果上附加视觉位移，不改变原占位；frame 参与布局尺寸。先确定想改变哪件事，再选择 API。将绝对 B 坐标误用作 offset，会把布局位置加两遍。"),
            .init("缩放锚点","围绕中心缩放适合物件靠近；从角落展开需要 anchor。锚点改变后，相同 scale 的边缘轨迹也改变。MotionPose 当前采用中心锚点；自定义锚点可以由 view 修饰符实现，不能当成中心缩放的同义参数。"),
            .init("响应式布局","工作台使用 340×280pt 教学坐标。进入产品后，从 GeometryReader 或 anchor preference 获取舞台尺寸与物件锚点，再构造配方。不要把教学坐标作为所有 iPhone 的最终布局。")
        ],code: """
        // 布局片段：两个锚点必须来自同一空间。
        ZStack { content }
            .coordinateSpace(name: "stage")

        // 子视图 GeometryReader 中：
        let frame = proxy.frame(in: .named("stage"))
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let delta = CGSize(width: B.x - A.x, height: B.y - A.y)
        // delta 用于 offset；B 用于 position。
        """,exercise: "只显示起终点标记，不播放。先判断这两个点是不是正确，再加入动画。"),
        .init(id: "path",title: "空间路径：直线、弧线与必经点",question: "控制路线和控制速度为什么要分开。",sections: [
            .init("路径 P 与时间进度 f","运动位置是 P(f(t))。二次贝塞尔有一个控制点，三次贝塞尔有两个控制点。控制点改变切线与弯曲，不一定是物件会经过的位置。必须经过瓶口时，把瓶口作为两段曲线的接点。"),
            .init("贝塞尔参数不等于路程","在内部参数上匀速，实际路程可能忽快忽慢。MotionPath 建立长度表，再按路程比例反查参数，使匀速时间曲线接近匀速路程。长度表是近似，曲率很高时需要提高采样密度。"),
            .init("路径接缝","两段曲线端点重合只保证位置连续。如果接点两侧切线方向不一致，物件会突然转向。弧长模式可以改善速度大小，不能修复尖角或断开的路径。"),
            .init("弹簧越界","用弹簧驱动进度，p 可能小于 0 或大于 1。沿端点切线延伸能保持空间方向；硬裁剪保持范围但会丢掉速度。按产品场景选择，不要在背后偷偷 clamp 然后声称完全连续。")
        ],code: """
        let path = MotionPath(segments: [
            .init(start: MotionPoint(40, 220),
                  control1: MotionPoint(70, 40),
                  control2: MotionPoint(250, 40),
                  end: MotionPoint(290, 100))
        ])
        let progress = MotionTrajectory<Double>.transition(
            from: 0, to: 1, model: .tween(duration: 0.8, curve: .linear)
        )
        let motion = path.trajectory(progress: progress, mode: .arcLength)
        // motion.sample(at: t).velocity 已包含路径切线 × 进度速度。
        """,exercise: "选线性时间曲线，只切换“贝塞尔参数”和“近似弧长”。打开等时采样点，对比点之间的距离。"),
        .init(id: "gesture",title: "手势是一段生命周期",question: "跟手、阻力、预测与吸附怎么衔接。",sections: [
            .init("按下与跟随","按下时抓住显示值，拖动过程中直接跟随，不再加一条动画去追手指。已建立的交互不应该因为手指离开物件边缘就失效。界面还需要按钮提供同等操作，不把功能藏在手势里。"),
            .init("越界映射","边界内位移一比一；越界后使用 Ld/(L+|d|) 一类函数，越拉越难。释放时从映射后的显示位置开始回弹，速度也应对应映射后的显示运动。再次抓住越界物件时，用逆映射避免重复施加阻力导致跳变。"),
            .init("目标与速度分开","吸附先用位置和速度预测停点，再选合法目标；随后弹簧接管。predictedEndTranslation 是预测位移，不是每秒速度。SwiftUI 手势示例可以据此选目标；精确初速度要使用速度采样或相应 API。"),
            .init("取消也是完整结果","系统取消、离开页面、减少动态或再次按下都可能打断。决定停在当前值、回到起点还是完成目标，避免半透明半展开的悬空状态。")
        ],code: """
        driver.beginDragging()
        driver.updateDragging(value: displayed,
                              velocity: tracker.velocity(at: now, dimensions: 1))
        let snap = SnapConfiguration(points: [0, 110, 220])
        let target = snap.target(position: driver.value, velocity: driver.velocity[0])
        driver.animate(to: target, model: .spring(.init()))
        """,exercise: "拖过边界后松手，再在回弹一半时抓住。若有跳变，先检查显示值与原始手势值，而不是调阻尼。"),
        .init(id: "decay",title: "惯性与衰减",question: "为什么不同屏幕刷新率不应该改变手感。",sections: [
            .init("连续时间模型","v(t)=v₀e^(−λt)，位移是 v₀(1−e^(−λt))/λ，自然停点是 x₀+v₀/λ。λ 单位是 1/s。与“每帧乘 0.95”不同，它不会因为 60Hz 变成 120Hz 而加倍衰减。"),
            .init("滚动与到达目标不同","衰减从释放速度决定去向，没有预先指定终点；弹簧围绕目标收敛。想吸附到固定卡片，应先预测停点并选卡片，再把释放速度交给弹簧。"),
            .init("边界不是免费获得的","纯衰减轨迹不会自动碰撞、反弹或停在屏幕里。应由业务选择边界策略。多个物体的碰撞需要共享物理世界，不能指望把若干独立插值器摆在一起就发生碰撞。")
        ],code: """
        let decay = DecayConfiguration(rate: 5)
        let motion = MotionTrajectory<Double>.transition(
            from: 80, to: 80, velocity: MotionVector([600]), model: .decay(decay)
        )
        // to 在衰减模式不参与终点计算；自然停点为 80 + 600/5 = 200。
        """,exercise: "从相同位置用不同速度释放，再固定速度改变 λ。分清哪个参数改变了起步，哪个改变了减速。"),
        .init(id: "timeline",title: "多通道与阶段编排",question: "怎样让多个变化服务于同一个动作。",sections: [
            .init("一条进度与多条轨道","同一进度适合整体移动、旋转和靠近；独立轨道适合位置有弹性、透明度无回弹，以及先到达再打开的分阶段动作。少量有因果的先后关系，比所有属性一起热闹更易理解。"),
            .init("时间轴与任务不同","不要用许多不能取消的 asyncAfter 堆叠阶段。MotionTrack 和 PoseTimeline 把阶段放在同一个可采样时间轴里；播放、暂停、观察某一时刻都不会留下旧闭包继续改状态。SwiftUI 原生也可以用 keyframeAnimator 描述轨道。"),
            .init("完成与停稳","某条轨道平台区的速度为零，并不意味着整段动作完成。位移到达后，内容可能还在淡入。驱动器依据全局时间窗口完成，业务提交不得仅凭画面暂时不动。"),
            .init("反向不是撤销业务","倒放视觉时间轴不等于撤销已提交数据。删除、购买或共享状态有自己的业务生命周期；动画只呈现状态，不决定交易是否完成。")
        ],code: """
        let timeline = PoseTimeline(initial: start, tracks: [
            .x: MotionTrack(initial: start.x)
                .then(to: end.x, model: .tween(duration: 0.5, curve: .bezier(.easeOut))),
            .opacity: MotionTrack(initial: 0)
                .then(to: 1, model: .tween(duration: 0.2, curve: .linear), after: 0.55)
        ])
        driver.play(timeline.trajectory)
        """,exercise: "在时间轴模式把透明度开始时间从 0 调到 0.6 秒。观察更清楚还是更拖沓，避免把停顿当成默认高级感。"),
        .init(id: "native",title: "原生 API 与自有驱动怎么选",question: "不要为了动画库放弃系统能力。",sections: [
            .init("优先用简单原生能力","普通布局状态变化优先 withAnimation。两个布局中同一物件的空间迁移使用 matchedGeometryEffect。独立任务继续使用系统 sheet 或导航。图片视频显示、可访问性和焦点管理沿用系统习惯。"),
            .init("什么时候值得用这套驱动","当你需要自定义数据模型、任意时间采样、速度观察、精确续接、多通道配方，或者想让同一个模型驱动不止一个 SwiftUI 属性时，自有 MotionDriver 才更有价值。它不替代所有 SwiftUI 动画。"),
            .init("不要双重平滑","driver 已经每帧生成显示值。如果再对 View 加 .animation，它会追赶已经在变化的目标，出现迟滞。MotionPoseModifier 关闭了自己子树的隐式插值。"),
            .init("UI 决定什么","姿态输出是几何数据，不负责导航、焦点、点击区域、文字重排和媒体生命周期。opacity 为 0 不代表操作自动不可用；宿主要根据状态设置 hit testing、可访问性隐藏或焦点。")
        ],code: """
        @StateObject private var driver = MotionDriver(initial: CGPoint.zero)
        // body 内：
        AnimatedMotionValue(driver: driver) { point in
            Circle().fill(.green).frame(width: 40, height: 40)
                .position(point)
        }
        // AnimatedMotionValue 处理减少动态、退后台和离开页面。
        """,exercise: "如果目标只是一行设置展开，先试系统 withAnimation；只有需要观察数据或续接速度时再引入驱动器。"),
        .init(id: "color",title: "颜色、角度与数据的边界",question: "并非所有分量都适合直接相减。",sections: [
            .init("角度先展开","350° 到 10° 可以绕 -340°，也可以绕 +20°。选择最近等价角后再动画；不要让系统猜。需要连续转多圈时保留展开后的角度，不要每帧取模导致值跳变。"),
            .init("颜色选择空间","直接在 sRGB 编码值中插值，与在线性光强中插值，视觉亮度不同。MotionRGBA 显式采用线性 RGB。色相角还有跨 0° 的问题；需要感知均匀的颜色过渡时可增加其他色彩空间映射。"),
            .init("显示约束与物理值","透明度限制在 0…1，尺寸与模糊半径不应为负。显示时 clamp 可以保护合法范围，但也会改变观察到的运动。如果某通道不能过冲，优先选择不会过冲的模型，而不是到处隐藏裁剪。")
        ],code: """
        let start = MotionAngle(degrees: 350)
        let target = MotionAngle(degrees: 10).nearestEquivalent(to: start)
        // target 为接近起点的连续角度，再进行插值。
        let color = MotionRGBA(sRGBRed: 0.2, green: 0.4, blue: 0.3)
        // color.motionVector 在 linear RGB 中，不是原始 sRGB 编码值。
        """,exercise: "先把角度设为跨越 360° 的一对值，再确认你要的是最近方向还是完整绕圈。"),
        .init(id: "custom",title: "把自己的数学模型接进来",question: "从公式到轨迹，不局限于内置效果。",sections: [
            .init("有解析式就直接采样","知道 x(t) 时，构造 MotionTrajectory 的采样闭包。最好同时给出 x′(t)，这样新目标才能继承速度。没有准确导数时可以用数值差分，但应意识到误差与计算成本。"),
            .init("只有方程就积分","摆锤、非线性弹簧与耦合运动可以写成位置和速度的一阶系统。DifferentialSystem 使用固定步长 RK4 生成有限窗口，再用 Hermite 插值采样。它是用于原型的数值方法，不是万能物理引擎。"),
            .init("定义适用边界","强刚性、约束碰撞、接触摩擦、流体或刚体堆积可能需要专用求解器。选择建模方法要看产品真实需要，不要为了“任何数据都能动画”承诺任何数学方程都能可靠运行。"),
            .init("有限窗口不是平衡","一段 10 秒积分到头时，系统可能仍有速度。区分“观察窗口完成”和“系统物理停稳”；续接时使用窗口末端速度，减少动态则直接选择产品目标。")
        ],code: """
        let motion = MotionCookbook.orbit(center: MotionPoint(160, 140), radius: 60)
        // 或实现自己的一条轨迹：
        let wave = MotionTrajectory<Double>(duration: 2, start: 0, end: 0) { t in
            if t >= 2 { return .resting(0) }
            let value = sin(.pi * t)
            let speed = .pi * cos(.pi * t)
            return MotionSample(value: value, velocity: MotionVector([speed]))
        }
        // 此正弦在窗口末端有速度，强制静止会不连续；应按用途接下一段或改包络。
        """,exercise: "写一个衰减振荡 x(t)=e^(−2t)sin(8t)，同时写出导数，再映射成角度与位置。"),
        .init(id: "quality",title: "把“不好看”说成具体问题",question: "怎样定位问题，而不是盲调所有参数。",sections: [
            .init("先看空间，再看时间","先固定动作到 0%、50%、100%，判断起点、遮挡、终点是否成立。空间正确后再观察启动、途中和停下。路线错误时调时长没有帮助。"),
            .init("常见症状","漂浮：缺少接触和落点，或回弹过多。迟钝：启动有延迟、easeIn 太长或双重平滑。撞墙：结束速度不为零、硬裁剪或过早移除视图。跳变：身份变化、坐标不同、把目标当成显示值。忙乱：太多属性同时强调，阶段之间没有因果。"),
            .init("一次只改一组原因","先调 response，再调 damping；先改路径，再改速度；先移动，再加尺寸，最后旋转。保存对照是为了知道哪个改变产生了结果，不是追求某个固定最优数值。"),
            .init("性能与手感","解析模型不受积分帧率影响，但 UI 仍受绘制成本影响。大范围模糊、复杂遮罩、大图和布局重排都可能卡顿。减小受更新影响的 View 子树，把图表等静态采样与每帧显示游标分开。")
        ],code: """
        // 一帧只把求得的显示值映射到真正需要更新的部件。
        // 业务状态、媒体加载和持久化不要放进每帧回调。
        driver.onCompletion = {
            // 更新视觉阶段。业务提交由自己的可靠流程管理。
        }
        // 页面退出：
        driver.detach()
        """,exercise: "选一个最不满意的动作，用一句话指出问题发生在开始、途中、停下还是再次操作；不要同时改三个原因。"),
        .init(id: "accessibility",title: "减少动态与完整状态",question: "让可取消、可恢复成为模型的一部分。",sections: [
            .init("减少动态保留结果","减少动态不是关闭功能。完成目标或回到起点要与产品语义一致。原生工作台默认遵循系统偏好，也可以额外模拟。不要允许测试开关关闭用户已经启用的减少动态。"),
            .init("替代路径","拖动和仪式手势要有按钮或无障碍 action。结果不只靠运动表达；VoiceOver 应能理解打开、关闭、进行中和失败。装饰性轨迹无需让读屏逐点朗读。"),
            .init("完整状态图","至少想清楚 idle、active、dragging、settling、completed、cancelled。退后台时暂停，离开页面释放时钟，旧 completion 不应越权修改新动作。失败与恢复属于业务状态，不应留下半完成的视觉承诺。")
        ],code: """
        // 原生 View 生命周期片段：
        .onChange(of: reducedMotion) { _, enabled in
            driver.reduceMotion = enabled
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { driver.pause() }
        }
        .onDisappear { driver.detach() }
        """,exercise: "在开始前和运动中分别开启减少动态，确认得到的是同一个可理解的产品结果。由使用者实际查看，不把代码推断当成效果结论。")
    ]
}
