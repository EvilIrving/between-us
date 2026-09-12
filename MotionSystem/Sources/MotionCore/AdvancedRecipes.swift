import Foundation

extension MotionRecipes {
    public static var throughOpening: MotionRecipe {
        var recipe = MotionRecipe(id: "through-opening",name: "穿过入口的两段路径")
        recipe.family = .path; recipe.duration = 1.1
        recipe.curve = .bezier(.easeInOut); recipe.pathMode = .arcLength
        recipe.setPathDocument(PathDocument(knots: [
            .init(point: MotionPoint(55,225),incoming: MotionPoint(55,225),outgoing: MotionPoint(55,155)),
            .init(point: MotionPoint(160,115),incoming: MotionPoint(125,115),outgoing: MotionPoint(195,115),mode: .mirrored),
            .init(point: MotionPoint(275,75),incoming: MotionPoint(235,95),outgoing: MotionPoint(275,75))
        ]))
        recipe.intent.purpose = "让物件经过明确的入口，再到达阅读位置"
        recipe.intent.success = "物件停在阅读位置"
        return recipe
    }
    public static var routeAndReveal: MotionRecipe {
        var recipe = throughOpening
        recipe.id = "route-and-reveal"; recipe.name = "沿路径靠近，再展开"
        recipe.initial.opacity = 0.7
        recipe.keyframeDocument = KeyframeDocument(lanes: [
            KeyframeLane(channel: .scaleX,keyframes: [
                .init(time: 0,value: 1),
                .init(time: 1.1,value: 1,interpolation: .hold),
                .init(time: 1.4,value: 1.7,interpolation: .hermite)
            ]),
            KeyframeLane(channel: .scaleY,keyframes: [
                .init(time: 0,value: 1),
                .init(time: 1.1,value: 1,interpolation: .hold),
                .init(time: 1.4,value: 1.7,interpolation: .hermite)
            ]),
            KeyframeLane(channel: .rotation,keyframes: [
                .init(time: 0,value: -0.18),
                .init(time: 0.5,value: 0.12,tangent: 0,interpolation: .hermite),
                .init(time: 1.1,value: 0,tangent: 0,interpolation: .hermite)
            ]),
            KeyframeLane(channel: .opacity,keyframes: [
                .init(time: 0,value: 0.7),
                .init(time: 1.2,value: 0.7,interpolation: .hold),
                .init(time: 1.45,value: 1,interpolation: .linear)
            ])
        ])
        recipe.intent.purpose = "用路径表达来源，用后续展开表达可以阅读"
        recipe.intent.frequency = "低频打开物件"
        recipe.intent.success = "位移、展开与显现全部完成"
        return recipe
    }
}
