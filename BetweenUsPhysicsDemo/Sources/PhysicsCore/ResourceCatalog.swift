import Foundation

// 唯一的产品目录：增加皮肤只登记映射，增加物件只登记新配方。
// 星星条目逐项保留上传版本的几何、尺寸、质量、重力、投放和拖拽参数。
enum ResourceCatalog {
    static let all: [VesselRecipe] = [starJar, capsuleBox, paperBin]
    static func recipe(id: String) -> VesselRecipe? { all.first { $0.id == id } }

    private static let starWall: [CGPoint] = [
        .init(x: 238, y: 155), .init(x: 237, y: 180),
        .init(x: 239, y: 211), .init(x: 232, y: 229),
        .init(x: 215, y: 249), .init(x: 201, y: 272),
        .init(x: 192, y: 303), .init(x: 189, y: 344),
        .init(x: 189, y: 566), .init(x: 192, y: 608),
        .init(x: 201, y: 637), .init(x: 219, y: 656),
        .init(x: 247, y: 670), .init(x: 283, y: 679),
        .init(x: 323, y: 683), .init(x: 366, y: 684),
        .init(x: 409, y: 683), .init(x: 451, y: 677),
        .init(x: 486, y: 667), .init(x: 513, y: 651),
        .init(x: 530, y: 630), .init(x: 538, y: 602),
        .init(x: 541, y: 563), .init(x: 541, y: 342),
        .init(x: 536, y: 302), .init(x: 525, y: 273),
        .init(x: 509, y: 249), .init(x: 493, y: 230),
        .init(x: 487, y: 213), .init(x: 491, y: 181),
        .init(x: 493, y: 155)
    ]
    private static let starPieces: [[CGPoint]] = [
        [.init(x: 85, y: 90), .init(x: 168, y: 75),
         .init(x: 204, y: 137), .init(x: 146, y: 196), .init(x: 74, y: 169)],
        [.init(x: 85, y: 90), .init(x: 101, y: 44),
         .init(x: 114, y: 33), .init(x: 131, y: 36), .init(x: 168, y: 75)],
        [.init(x: 168, y: 75), .init(x: 218, y: 73),
         .init(x: 231, y: 79), .init(x: 233, y: 93), .init(x: 204, y: 137)],
        [.init(x: 204, y: 137), .init(x: 219, y: 187),
         .init(x: 218, y: 198), .init(x: 209, y: 205), .init(x: 146, y: 196)],
        [.init(x: 146, y: 196), .init(x: 105, y: 226),
         .init(x: 80, y: 226), .init(x: 76, y: 214), .init(x: 74, y: 169)],
        [.init(x: 74, y: 169), .init(x: 34, y: 143), .init(x: 26, y: 133),
         .init(x: 27, y: 122), .init(x: 33, y: 116), .init(x: 85, y: 90)]
    ]

    private static let starLip = MaskPath(commands: [
        .move(.init(x:224,y:153)),
        .cubic(to:.init(x:506,y:153), control1:.init(x:263,y:184), control2:.init(x:465,y:184)),
        .line(.init(x:520,y:185)),
        .quad(to:.init(x:499,y:217), control:.init(x:530,y:205)),
        .line(.init(x:493,y:237)),
        .quad(to:.init(x:239,y:237), control:.init(x:367,y:252)),
        .line(.init(x:231,y:216)),
        .quad(to:.init(x:215,y:183), control:.init(x:204,y:202)), .close
    ])

    static let starJar = VesselRecipe(
        id: "star-jar", title: "星星瓶",
        container: ContainerProfile(
            id:"glass-jar",
            mapping: ArtworkMapping(sourceSize:.init(width:724,height:724),
                                    sceneSize:.init(width:500,height:724), origin:.init(x:-112,y:0)),
            innerWall:starWall,
            mouth:[.init(x:238,y:155), .init(x:493,y:155)],
            wallFriction:0.5, wallRestitution:0.08,
            layers:[
                RenderLayer(asset:"StarJar_Body", depth:0),
                RenderLayer(asset:"StarJar_Body", depth:20, opacity:0.10, isForeground:true),
                RenderLayer(asset:"StarJar_Body", depth:30, mask:starLip, isForeground:true)
            ]),
        entity: EntityProfile(
            id:"rounded-star",
            geometry:TokenGeometry(referenceFrame:.init(x:0,y:0,width:256,height:256),
                                   displaySize:.init(width:108,height:108),
                                   pieces:starPieces.map { .convexPolygon($0) }),
            material:BodyMaterial(mass:0.03,friction:0.55,restitution:0.12,
                                  linearDamping:0.22,angularDamping:0.35)),
        skins:[SkinProfile(id:"star-gift-love",entityID:"rounded-star",asset:"StarCharm_Gift_Love",
                           sourceSize:.init(width:256,height:256),
                           contentRect:.init(x:0,y:0,width:256,height:256))],
        policy:SimulationPolicy(
            gravity:.init(x:0,y:-2.4),capacity:10,initialCount:8,
            maximumLinearSpeed:550,maximumAngularSpeed:7,
            spawn:SpawnPolicy(center:.init(x:250,y:662),jitterX:45,
                              initialRotation:-0.4...0.4,initialVelocityX:-12...12,
                              interval:0.65,clearanceHalfSize:.init(width:82,height:82)),
            drag:DragPolicy(springFrequency:5,springDamping:0.85,maximumStretch:36,maximumHandleSpeed:480)))

    // 开盖盒子：前壁以真实贴图遮挡，隐藏区域仍有完整的侧壁、内底和胶囊间碰撞。
    // 手工标定的是二维内腔截面，不把图中透视当成三维碰撞。
    static let capsuleBox = VesselRecipe(
        id:"capsule-box",title:"胶囊盒",
        container:ContainerProfile(
            id:"open-keepsake-box",
            mapping:ArtworkMapping(sourceSize:.init(width:724,height:724),
                                   sceneSize:.init(width:700,height:800),origin:.init(x:-12,y:0)),
            innerWall:[
                .init(x:68,y:365),.init(x:65,y:397),.init(x:66,y:470),.init(x:70,y:550),
                .init(x:77,y:574),.init(x:96,y:586),.init(x:144,y:594),.init(x:260,y:609),
                .init(x:375,y:624),.init(x:441,y:632),.init(x:461,y:630),.init(x:482,y:619),
                .init(x:552,y:576),.init(x:600,y:544),.init(x:612,y:528),.init(x:620,y:503),
                .init(x:623,y:420),.init(x:623,y:329)
            ],
            mouth:[.init(x:68,y:365),.init(x:216,y:299),.init(x:623,y:329),.init(x:495,y:410)],
            wallFriction:0.48,wallRestitution:0.06,
            layers:[
                RenderLayer(asset:"Capsule_Open_04",depth:0),
                RenderLayer(asset:"Capsule_Open_04",depth:30,
                    mask:.polygon([.init(x:0,y:374),.init(x:43,y:374),.init(x:496,y:413),
                                   .init(x:650,y:324),.init(x:724,y:324),
                                   .init(x:724,y:724),.init(x:0,y:724)]),
                    isForeground:true,blocksHitTesting:true)
            ]),
        entity:EntityProfile(
            id:"capsule",
            geometry:TokenGeometry(referenceFrame:.init(x:95,y:11,width:75,height:228),
                                   displaySize:.init(width:36.62,height:111.34),
                                   pieces:[.capsule(frame:.init(x:98,y:16,width:69,height:218))]),
            material:BodyMaterial(mass:0.022,friction:0.4,restitution:0.08,
                                  linearDamping:0.24,angularDamping:0.28)),
        skins:[SkinProfile(id:"capsule-red-green",entityID:"capsule",asset:"Capsule_Closed",
                           sourceSize:.init(width:256,height:256),
                           contentRect:.init(x:95,y:11,width:75,height:228))],
        policy:SimulationPolicy(
            gravity:.init(x:0,y:-2.4),capacity:10,initialCount:8,
            maximumLinearSpeed:520,maximumAngularSpeed:8,
            spawn:SpawnPolicy(center:.init(x:333,y:522),jitterX:82,
                              initialRotation:-0.65...0.65,initialVelocityX:-15...15,
                              interval:0.75,clearanceHalfSize:.init(width:76,height:95)),
            drag:DragPolicy(springFrequency:5,springDamping:0.88,maximumStretch:32,maximumHandleSpeed:440)))

    static let paperBin = VesselRecipe(
        id:"paper-bin",title:"纸团桶",
        container:ContainerProfile(
            id:"red-paper-bin",
            mapping:ArtworkMapping(sourceSize:.init(width:724,height:724),
                                   sceneSize:.init(width:560,height:860),origin:.init(x:-80,y:0)),
            innerWall:[
                .init(x:166,y:118),.init(x:170,y:170),.init(x:179,y:260),.init(x:190,y:390),
                .init(x:202,y:531),.init(x:212,y:623),.init(x:219,y:642),.init(x:232,y:655),
                .init(x:269,y:663),.init(x:333,y:672),.init(x:402,y:681),.init(x:435,y:683),
                .init(x:455,y:677),.init(x:482,y:658),.init(x:505,y:632),.init(x:516,y:604),
                .init(x:528,y:507),.init(x:542,y:367),.init(x:552,y:245),.init(x:560,y:148),
                .init(x:562,y:94)
            ],
            mouth:[.init(x:166,y:111),.init(x:279,y:72),.init(x:562,y:91),.init(x:476,y:136)],
            wallFriction:0.62,wallRestitution:0.06,
            layers:[
                RenderLayer(asset:"PaperBin_Body",depth:0),
                RenderLayer(asset:"PaperBin_Body",depth:30,
                    mask:.polygon([.init(x:0,y:118),.init(x:128,y:118),.init(x:477,y:141),
                                   .init(x:604,y:80),.init(x:724,y:80),
                                   .init(x:724,y:724),.init(x:0,y:724)]),
                    isForeground:true,blocksHitTesting:true)
            ]),
        entity:EntityProfile(
            id:"paper-ball",
            geometry:TokenGeometry(referenceFrame:.init(x:32,y:32,width:192,height:192),
                                   displaySize:.init(width:88,height:88),
                                   pieces:[.circle(center:.init(x:128,y:129),radius:82)]),
            material:BodyMaterial(mass:0.012,friction:0.74,restitution:0.08,
                                  linearDamping:0.38,angularDamping:0.65)),
        skins:[SkinProfile(id:"paper-blue-sad",entityID:"paper-ball",asset:"PaperBall_10",
                           sourceSize:.init(width:256,height:256),
                           contentRect:.init(x:32,y:32,width:192,height:192))],
        policy:SimulationPolicy(
            gravity:.init(x:0,y:-2.4),capacity:10,initialCount:8,
            maximumLinearSpeed:500,maximumAngularSpeed:7,
            spawn:SpawnPolicy(center:.init(x:275,y:748),jitterX:60,
                              initialRotation:-0.4...0.4,initialVelocityX:-12...12,
                              interval:0.6,clearanceHalfSize:.init(width:70,height:70)),
            drag:DragPolicy(springFrequency:5,springDamping:0.9,maximumStretch:32,maximumHandleSpeed:420)))
}
