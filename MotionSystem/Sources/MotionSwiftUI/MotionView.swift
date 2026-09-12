import SwiftUI
import MotionCore

public struct MotionPoseModifier: ViewModifier {
    public var pose: MotionPose
    public init(_ pose: MotionPose) { self.pose = pose }
    public func body(content: Content) -> some View {
        content
            .frame(width: max(0,pose.width),height: max(0,pose.height))
            .clipShape(RoundedRectangle(cornerRadius: max(0,pose.cornerRadius)))
            .scaleEffect(x: pose.scaleX,y: pose.scaleY,anchor: .center)
            .rotationEffect(.radians(pose.rotation))
            .opacity(motionClamp(pose.opacity))
            .blur(radius: max(0,pose.blur))
            .position(x: pose.x,y: pose.y)
            // driver 已经逐帧求值，SwiftUI 不应再次插值，避免双重平滑。
            .transaction { $0.animation = nil }
    }
}
extension View {
    public func motionPose(_ pose: MotionPose) -> some View { modifier(MotionPoseModifier(pose)) }
}
extension MotionRGBA {
    public var color: Color {
        Color(.sRGBLinear,red: motionClamp(red),green: motionClamp(green),blue: motionClamp(blue),opacity: motionClamp(alpha))
    }
}

/// 把任意 MotionValue 连到 SwiftUI。Bool、String、集合结构不自动插值，需定义中间表示。
@MainActor
public struct AnimatedMotionValue<Value: MotionValue, Content: View>: View {
    @ObservedObject private var driver: MotionDriver<Value>
    private let content: (Value) -> Content
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduced
    public init(driver: MotionDriver<Value>,@ViewBuilder content: @escaping (Value) -> Content) {
        self.driver = driver; self.content = content
    }
    public var body: some View {
        content(driver.value)
            .transaction { $0.animation = nil }
            .onAppear { driver.reduceMotion = reduced }
            .onChange(of: reduced) { _,value in driver.reduceMotion = value }
            .onChange(of: scenePhase) { _,phase in if phase != .active { driver.pause() } }
            .onDisappear { driver.detach() }
    }
}
