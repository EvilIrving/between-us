import SwiftUI

enum ContainerKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case star
    case capsule
    case paper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .star: return T("星星瓶")
        case .capsule: return T("胶囊瓶")
        case .paper: return T("纸团篓")
        }
    }

    var composeTitle: String {
        switch self {
        case .star: return T("折一颗星星")
        case .capsule: return T("装一颗胶囊")
        case .paper: return T("揉一个纸团")
        }
    }

    var homeActionTitle: String {
        switch self {
        case .star: return T("表达喜欢")
        case .capsule: return T("认真沟通")
        case .paper: return T("说出烦恼")
        }
    }

    var openActionTitle: String {
        switch self {
        case .star: return T("点一下取出星星")
        case .capsule: return T("点一下打开胶囊")
        case .paper: return T("点一下展开纸团")
        }
    }

    var emptyWaitingTitle: String {
        switch self {
        case .star: return T("暂无新的星星")
        case .capsule: return T("暂无新的胶囊")
        case .paper: return T("暂无新的纸团")
        }
    }

    var placeholder: String {
        switch self {
        case .star: return T("写下喜欢、感谢或想分享的事")
        case .capsule: return T("写下建议、鼓励或需要认真说的事")
        case .paper: return T("写下让你委屈、生气或不开心的事")
        }
    }

    var depositButtonTitle: String {
        switch self {
        case .star: return T("折好，放进瓶子")
        case .capsule: return T("封好，放进瓶子")
        case .paper: return T("揉好，放进纸篓")
        }
    }

    var tint: Color {
        switch self {
        case .star: return Color(red: 0.90, green: 0.62, blue: 0.26)
        case .capsule: return Color(red: 0.47, green: 0.61, blue: 0.54)
        case .paper: return Color(red: 0.55, green: 0.51, blue: 0.49)
        }
    }
}
