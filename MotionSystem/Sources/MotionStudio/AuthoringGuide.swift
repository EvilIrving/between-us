import Foundation

extension GuideCatalog {
    static let authoringChapters: [GuideChapter] = [
        .init(id: "channel-composition",title: "组合：路径负责位置，时间轴负责外观",question: "怎样让多个数学模型共同驱动一个物件，而不争抢同一属性。",sections: [
            .init("先分清每个通道归谁","路径产生 X 和 Y，关键帧产生缩放、旋转与透明度。最后合并成一个 MotionPose，再由一个 View 显示。不要让两个驱动器同时写同一个 offset 或 scale，后写入者覆盖前写入者会导致难以解释的跳变。"),
            .init("同一时钟，不同结束时间","路径可以在 1.1 秒到达，缩放在 1.4 秒完成，透明度在 1.45 秒完成。位置先到达后保持，其他通道继续变化，整段动作在最晚的通道完成时结束。"),
            .init("配方中的明确规则","当 family 为 path 且存在 keyframeDocument 时，位置仍由路径拥有；关键帧只覆盖启用的外观通道，X/Y 关键帧暂存但不参与这次播放。把位置来源切回时间轴后，X/Y 关键帧才重新生效。"),
            .init("组合不自动解决中断","改变路径目标时，旧的外观时间轴不一定还适用。MotionSession 的目标变化会从当前显示姿态重建到新目标的过渡，不重放旧外观关键帧；如果需要继续某个复杂编排，应由产品明确换入新的配方。")
        ],code: """
        let positionAndPose = routeRecipe.makeTrajectory()
        let appearance = KeyframeDocument(lanes: [
            KeyframeLane(channel: .scaleX, keyframes: [
                .init(time: 0, value: 1),
                .init(time: 1.1, value: 1, interpolation: .hold),
                .init(time: 1.4, value: 1.7, interpolation: .hermite)
            ])
        ]).trajectory(initial: routeRecipe.initial)
        let combined = positionAndPose.overriding([.scaleX], with: appearance)
        driver.play(combined)
        // 配方方式：family = .path，同时设置 keyframeDocument。
        """,exercise: "载入“沿路径靠近，再展开”，先只看位置，再看缩放通道的曲线。把缩放开始时间提到位移中途，比较两种表达。"),
        .init(id: "path-authoring",title: "编辑路径：拆段、手柄与连续性",question: "怎样把“经过这里”变成一个可靠的路径节点。",sections: [
            .init("先放锚点","起点、必经点、终点都应该是曲线上的锚点。控制手柄只决定离开和靠近锚点的方向，不是要求物件经过的地方。要穿过瓶口，就让瓶口成为两段之间的锚点。"),
            .init("三种手柄约束","独立手柄允许接点处转折；共线手柄让两侧朝向一致，但长度可以不同；镜像手柄让方向相反且长度相同。拖动锚点时两侧手柄一起平移，不改变附近曲线的相对形状。"),
            .init("为什么拆段不会改变路线","De Casteljau 在原曲线控制多边形上反复线性插值，得到两段新的控制点。两段拼起来与原曲线相同。只是每段分配的参数范围改变，所以使用“按每段参数均分时间”时，运动节奏可能改变；按弧长走则更接近保留原节奏。"),
            .init("删除没有同样保证","删除内节点后，用前段的出发手柄与后段的到达手柄重连，通常会改变路线。编辑器保留撤销记录，避免你必须手动找回上一次形状。"),
            .init("几何连续与时间连续","共线描述切线方向一致，属于几何连续。若两侧参数速度不同，即使没有尖角，物件的速度大小仍可能突变。先处理路线，再用弧长参数化与时间曲线处理速度。")
        ],code: """
        var document = PathDocument(segment: BezierSegment(
            start: MotionPoint(40, 210),
            control1: MotionPoint(80, 40),
            control2: MotionPoint(250, 40),
            end: MotionPoint(290, 90)
        ))
        let inserted = document.split(segment: 0, at: 0.5)
        if let inserted {
            document.setMode(id: inserted, mode: .aligned)
            document.move(id: inserted, handle: .anchor, to: MotionPoint(170, 110))
        }
        // 使用 setPathDocument 同步配方起终点；避免两份位置互相矛盾。
        recipe.setPathDocument(document)
        """,exercise: "先不移动新节点，只拆分一次，看路线保持不变。再把新节点移到必经位置，分别尝试独立、共线和镜像手柄。"),
        .init(id: "keyframe-authoring",title: "关键帧：值、时间与节点速度",question: "从两个状态扩展到多阶段动作，仍然能说清每个区间。",sections: [
            .init("关键帧记录什么","关键帧有时间、数值、节点速度和进入这一帧的插值方式。时间单位是秒，数值单位来自通道，速度单位为对应单位每秒。X 通道的 120 是点坐标，旋转通道的 120 则是弧度，两者不能因为都是数字就随意复用。"),
            .init("插值属于区间","这里每个关键帧的 interpolation 描述上一帧到当前帧。第一个关键帧没有前一区间。保持插值在区间内维持旧值，到关键帧瞬间换新值，是刻意的不连续变化。"),
            .init("节点速度的作用范围","节点 tangent 只用于 Hermite 区间。如果左右两段都使用 Hermite，共用这个节点速度就能在接点处匹配速度。若另一段是普通 ease，它仍按自己的曲线决定端点速度。最后一帧之后保持静止，若想自然停稳，应让到达末帧的速度接近零。"),
            .init("整体变慢不只是移动时间点","把所有时间乘 1.2，同时把 Hermite tangent 除以 1.2，才保留同样的轨迹形状并整体放慢。只改时间不改速度，会改变多项式形状，甚至引入原先没有的过冲。"),
            .init("配方拥有的目标","启用高级关键帧文档后，各通道最终值来自自己的末帧，不再统一取 recipe.target。未参与编排的通道保持 initial 中的值。新业务目标到来时，需要选择桥接到新状态还是重新编排时间轴。")
        ],code: """
        var document = KeyframeDocument(lanes: [
            KeyframeLane(channel: .x, keyframes: [
                .init(time: 0, value: 40),
                .init(time: 0.5, value: 200, tangent: 80, interpolation: .hermite),
                .init(time: 0.9, value: 270, tangent: 0, interpolation: .hermite)
            ]),
            KeyframeLane(channel: .opacity, keyframes: [
                .init(time: 0, value: 0),
                .init(time: 0.5, value: 0, interpolation: .hold),
                .init(time: 0.8, value: 1, interpolation: .linear)
            ])
        ])
        document.retime(scale: 1.2)
        recipe.keyframeDocument = document
        recipe.family = .timeline
        """,exercise: "把一个中间关键帧的左右区间设为 Hermite，调节它的 tangent。观察速度曲线，再整体放慢，确认你理解速度为什么也需要变化。"),
        .init(id: "resume-authoring",title: "恢复：保存原配方还是当前运动段",question: "为什么中途换过目标后，单独保存原配方不够。",sections: [
            .init("原配方已经不等于当前段","物件原本从 A 去 B，在一半时改去 C。新的弹簧从中间显示位置和中间速度出发。只存 A、B 和总时间，无法重建这段去 C 的运动。MotionSessionLeg 保存新段的起点、目标、初速度与模型。"),
            .init("暂停与取消不同","暂停保留段和时间，继续时沿同一段走；取消并停留清除旧段，之后应等待新目标；取消并返回应回到产品定义的原位置，不能误用最近一次重新定向时的临时起点。"),
            .init("恢复默认不自动开始","应用重新进入前台，用户可能只是回来读内容，不一定希望旧仪式立即继续。恢复记录默认显示保存的位置，宿主明确要求 resume 才播放。系统减少动态的偏好仍然优先。"),
            .init("手指无法被恢复","记录保存于拖动中时，只能恢复当时的显示状态。那根手指已经离开，旧拖动速度也不再代表新的意图。因此恢复为静止状态，等待新手势，而不是继续假装用户仍按着。"),
            .init("视觉恢复不重复业务操作","动画完成、恢复书签和播放日志都是视觉行为。购买、删除、发送与媒体任务必须有自己的业务流程；不能因为恢复了一个动画就再次提交。")
        ],code: """
        let session = MotionSession(recipe: recipe)
        session.send(.play)
        session.send(.targetChanged(newTarget))
        let bookmark = session.bookmark()

        session.send(.leaveScene)
        session.restore(bookmark)               // 停在保存位置
        session.restore(bookmark, resume: true) // 明确继续
        // 可选：用 JSONEncoder 把 bookmark 保存到本机，
        // 恢复前由宿主确认这份记录仍属于当前业务场景。
        """,exercise: "先改一次目标再保存，继续播放一会儿后恢复。重点观察恢复的是新的运动段，而不是原始 A → B。"),
        .init(id: "agent-authoring",title: "让 Agent 修改一个可评判的动作",question: "怎样避免每次需求都变成重新猜一套参数。",sections: [
            .init("输入包括事实与意图","传递原配方、目标位置来源、坐标空间、单位、触发条件、取消策略、减少动态结果和当前症状。“自然一点”没有给出可实现的约束；“到终点后两次回弹，改为一次轻微回弹”更能指导模型选择。"),
            .init("要求说明影响范围","改变一条时间曲线会影响整个区间，移动关键帧会影响相邻区间，移动共线手柄会改变另一侧方向，改变路径节点可能改变总路程。Agent 应说明改变了哪些通道与阶段，不顺手重新设计所有动作。"),
            .init("把交付落在可复用数据上","最终应该能给出 Swift 入口和完整配方，而不是只有一段文字描述。多段路径和多关键帧使用 schemaVersion 2；老的基础配方仍可以读取。导出代码应能直接看见节点和关键帧数值。"),
            .init("harness 负责传递约束","执行环境负责传入用户要求、当前配方与目标文件，不把“可以修改代码”扩大为“可以运行构建或发布”。当前用户没有授权的验证、测试和界面启动，不应被默认工作流自行补上。")
        ],code: """
        // 针对一个症状修改，不覆盖整个配方。
        var edited = original
        edited.spring.dampingRatio = 0.92
        // 或只移动某个通道中的一个关键帧：
        if var document = edited.keyframeDocument,
           let lane = document.lanes.firstIndex(where: { $0.channel == .opacity }) {
            document.lanes[lane].retime(scale: 1, offset: 0.1)
            edited.keyframeDocument = document
        }
        // 交付 edited 与具体修改理由，保留 original 供用户对照。
        """,exercise: "让 Agent 只解决一个已定位的症状，同时写明不该变化的路径、时长或其他通道。用完整配方传递结果，避免跨任务丢失约束。")
    ]
}
