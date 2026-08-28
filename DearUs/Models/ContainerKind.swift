import SwiftUI

enum ContainerKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case star
    case capsule
    case paper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .star: return "星星瓶"
        case .capsule: return "胶囊盒"
        case .paper: return "纸团篓"
        }
    }

    var subtitle: String {
        switch self {
        case .star: return "喜欢、感谢，还有没好意思说出口的话"
        case .capsule: return "鼓励、建议，和认真想告诉对方的事"
        case .paper: return "委屈、生气，或需要被好好接住的时刻"
        }
    }

    var composeTitle: String {
        switch self {
        case .star: return "折一颗星星"
        case .capsule: return "装一颗胶囊"
        case .paper: return "揉一个纸团"
        }
    }

    var placeholder: String {
        switch self {
        case .star: return "写下想分享的事"
        case .capsule: return "写下想认真告诉对方的事"
        case .paper: return "发生了什么？你有什么感受？"
        }
    }

    var depositButtonTitle: String {
        switch self {
        case .star: return "折好，放进瓶子"
        case .capsule: return "封好，放进盒子"
        case .paper: return "揉好，放进纸篓"
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
