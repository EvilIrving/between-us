import SwiftUI

struct ContainerDetailShell<Content: View>: View {
    let kind: ContainerKind
    let title: String
    let subtitle: String
    let content: Content

    @Environment(\.dismiss) private var dismiss

    init(
        kind: ContainerKind,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ZStack {
            AmbientRoomBackground(kind: kind)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack {
                        SceneCloseControl(label: "回到共同房间") {
                            dismiss()
                        }
                        Spacer()
                        RitualObjectGlyph(kind: kind, size: 44, filled: true)
                            .opacity(0.66)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 9)

                    VStack(spacing: 7) {
                        Text(title)
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.76))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 30)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    content
                        .padding(.horizontal, 20)
                        .padding(.bottom, 34)
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
