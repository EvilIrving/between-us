import SwiftUI

enum ContainerKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case star
    case capsule
    case paper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .star: return "星星瓶".localized
        case .capsule: return "胶囊盒".localized
        case .paper: return "纸团篓".localized
        }
    }

    var composeTitle: String {
        switch self {
        case .star: return "折一颗星星".localized
        case .capsule: return "装一颗胶囊".localized
        case .paper: return "揉一个纸团".localized
        }
    }

    var homeActionTitle: String {
        switch self {
        case .star: return "表达喜欢".localized
        case .capsule: return "认真沟通".localized
        case .paper: return "说出烦恼".localized
        }
    }

    var openActionTitle: String {
        switch self {
        case .star: return "按住取出星星".localized
        case .capsule: return "按住打开胶囊".localized
        case .paper: return "按住展开纸团".localized
        }
    }

    var emptyWaitingTitle: String {
        switch self {
        case .star: return "暂无新的星星".localized
        case .capsule: return "暂无新的胶囊".localized
        case .paper: return "暂无新的纸团".localized
        }
    }

    var creditRequirementTitle: String {
        switch self {
        case .star: return "先放入一颗星星".localized
        case .capsule: return "先放入一颗胶囊".localized
        case .paper: return "先放入一个纸团".localized
        }
    }

    var placeholder: String {
        switch self {
        case .star: return "写下喜欢、感谢或想分享的事".localized
        case .capsule: return "写下建议、鼓励或需要认真说的事".localized
        case .paper: return "写下让你委屈、生气或不开心的事".localized
        }
    }

    var depositButtonTitle: String {
        switch self {
        case .star: return "折好，放进瓶子".localized
        case .capsule: return "封好，放进盒子".localized
        case .paper: return "揉好，放进纸篓".localized
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
