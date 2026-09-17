import SwiftUI

struct TrashBinVisual: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: side * 0.58, height: side * 0.08)
                    .blur(radius: 9)
                    .position(x: side * 0.50, y: side * 0.86)

                Image("PaperBin_Body")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()

                Image("PaperBin_Lid")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
            .frame(width: side, height: side)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
