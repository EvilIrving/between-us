import SwiftUI

struct StarBottleIllustration: View {
    let count: Int

    private let positions: [CGPoint] = [
        .init(x: 0.28, y: 0.76), .init(x: 0.44, y: 0.79), .init(x: 0.61, y: 0.75), .init(x: 0.72, y: 0.70),
        .init(x: 0.35, y: 0.66), .init(x: 0.53, y: 0.64), .init(x: 0.68, y: 0.59), .init(x: 0.25, y: 0.56),
        .init(x: 0.43, y: 0.53), .init(x: 0.59, y: 0.49), .init(x: 0.74, y: 0.44), .init(x: 0.32, y: 0.43),
        .init(x: 0.49, y: 0.39), .init(x: 0.65, y: 0.34), .init(x: 0.37, y: 0.31), .init(x: 0.54, y: 0.27)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: proxy.size.width * 0.18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.34), Color.white.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: proxy.size.width * 0.18, style: .continuous)
                            .stroke(Color.white.opacity(0.82), lineWidth: 1.8)
                    }
                    .padding(.horizontal, proxy.size.width * 0.14)
                    .padding(.top, proxy.size.height * 0.16)
                    .shadow(color: Color.black.opacity(0.045), radius: 14, y: 8)

                RoundedRectangle(cornerRadius: proxy.size.width * 0.055, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.62, green: 0.44, blue: 0.28),
                                Color(red: 0.43, green: 0.29, blue: 0.20)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: proxy.size.width * 0.42, height: proxy.size.height * 0.135)
                    .offset(y: -proxy.size.height * 0.39)
                    .overlay {
                        RoundedRectangle(cornerRadius: proxy.size.width * 0.055, style: .continuous)
                            .stroke(Color.white.opacity(0.24), lineWidth: 1)
                            .frame(width: proxy.size.width * 0.42, height: proxy.size.height * 0.135)
                            .offset(y: -proxy.size.height * 0.39)
                    }

                ForEach(0..<min(count, positions.count), id: \.self) { index in
                    let p = positions[index]
                    StarShape()
                        .fill(starColor(at: index))
                        .overlay { StarShape().stroke(Color.white.opacity(0.26), lineWidth: 0.8) }
                        .frame(
                            width: proxy.size.width * (index.isMultiple(of: 4) ? 0.13 : 0.115),
                            height: proxy.size.width * (index.isMultiple(of: 4) ? 0.13 : 0.115)
                        )
                        .rotationEffect(.degrees(Double(index * 29 - 18)))
                        .position(x: proxy.size.width * p.x, y: proxy.size.height * p.y)
                        .shadow(color: starColor(at: index).opacity(0.18), radius: 4)
                }

                Capsule()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: proxy.size.width * 0.035, height: proxy.size.height * 0.42)
                    .rotationEffect(.degrees(8))
                    .offset(x: -proxy.size.width * 0.19, y: proxy.size.height * 0.08)
                    .blur(radius: 0.5)
            }
        }
    }

    private func starColor(at index: Int) -> Color {
        switch index % 4 {
        case 0: return Color(red: 0.98, green: 0.76, blue: 0.36)
        case 1: return Color(red: 0.91, green: 0.58, blue: 0.22)
        case 2: return Color(red: 0.96, green: 0.67, blue: 0.29)
        default: return Color(red: 0.86, green: 0.50, blue: 0.20)
        }
    }
}

struct CapsuleBoxIllustration: View {
    let count: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: proxy.size.width * 0.09, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.87, green: 0.90, blue: 0.85).opacity(0.86),
                                Color(red: 0.73, green: 0.79, blue: 0.74).opacity(0.74)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: proxy.size.width * 0.09, style: .continuous)
                            .stroke(Color.white.opacity(0.76), lineWidth: 1.5)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 16)
                    .shadow(color: Color.black.opacity(0.05), radius: 13, y: 8)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 12
                ) {
                    ForEach(0..<12, id: \.self) { index in
                        CapsulePill(filled: index < min(count, 12), index: index)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 34)
            }
        }
    }
}

private struct CapsulePill: View {
    let filled: Bool
    let index: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Capsule()
                    .fill(filled ? Color.white.opacity(0.88) : Color.white.opacity(0.30))
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(filled ? pillColor : Color.white.opacity(0.12))
                    Rectangle()
                        .fill(filled ? Color.white.opacity(0.78) : Color.white.opacity(0.08))
                }
                .clipShape(Capsule())
                Capsule()
                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
                Rectangle()
                    .fill(Color.white.opacity(0.46))
                    .frame(width: 1)
                    .frame(height: proxy.size.height * 0.78)
            }
        }
        .frame(height: 29)
        .rotationEffect(.degrees(index.isMultiple(of: 2) ? -16 : -10))
        .opacity(filled ? 1 : 0.65)
    }

    private var pillColor: Color {
        switch index % 3 {
        case 0: return Color(red: 0.43, green: 0.62, blue: 0.53)
        case 1: return Color(red: 0.55, green: 0.70, blue: 0.61)
        default: return Color(red: 0.37, green: 0.55, blue: 0.49)
        }
    }
}

struct PaperBinIllustration: View {
    let count: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ForEach(0..<min(count, 11), id: \.self) { index in
                    CrumpledPaper(index: index)
                        .frame(width: paperSize(at: index), height: paperSize(at: index))
                        .offset(
                            x: horizontalOffset(at: index),
                            y: verticalOffset(at: index)
                        )
                        .shadow(color: Color.black.opacity(0.055), radius: 4, y: 3)
                }

                BinShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.69, green: 0.66, blue: 0.64).opacity(0.82),
                                Color(red: 0.49, green: 0.47, blue: 0.46).opacity(0.76)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        BinShape().stroke(Color.white.opacity(0.62), lineWidth: 1.5)
                    }
                    .frame(width: proxy.size.width * 0.62, height: proxy.size.height * 0.64)
                    .shadow(color: Color.black.opacity(0.06), radius: 12, y: 9)

                Capsule()
                    .fill(Color.white.opacity(0.32))
                    .frame(width: proxy.size.width * 0.65, height: 8)
                    .offset(y: -proxy.size.height * 0.60)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func paperSize(at index: Int) -> CGFloat {
        34 + CGFloat(index % 3) * 4
    }

    private func horizontalOffset(at index: Int) -> CGFloat {
        let positions: [CGFloat] = [-46, -14, 22, 48, -31, 8, 37, -52, -4, 30, 55]
        return positions[index % positions.count]
    }

    private func verticalOffset(at index: Int) -> CGFloat {
        let row = index / 4
        return -CGFloat(row) * 25 - 30 - CGFloat(index % 2) * 4
    }
}
