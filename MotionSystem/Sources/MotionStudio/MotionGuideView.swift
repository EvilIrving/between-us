import SwiftUI

struct MotionGuideView: View {
    var body: some View {
        List {
            Section {
                Text("按问题查，不必一次读完。每章都有模型边界、Swift 片段和具体观察方法。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(GuideCatalog.chapters + GuideCatalog.authoringChapters) { chapter in
                NavigationLink {
                    GuideChapterView(chapter: chapter)
                } label: {
                    VStack(alignment: .leading,spacing: 6) {
                        Text(chapter.title).font(.headline)
                        Text(chapter.question).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical,5)
                }
            }
            Section("参考与实现边界") {
                Link("GestureGuide · 交互原则",destination: URL(string: "https://github.com/aaaa-zhen/GestureGuide")!)
                Text("参考其空间一致性、释放交接、边界阻力和可访问性原则。此系统独立使用 Swift 编写，没有复制其 Web 渲染架构。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("原生 SwiftUI API、数学采样器、数值积分分别有不同适用范围。这里提供可组合原语和设计依据，不承诺一组参数适合所有产品。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct GuideChapterView: View {
    let chapter: GuideChapter
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 28) {
                Text(chapter.title).font(.largeTitle.bold())
                Text(chapter.question).font(.title3).foregroundStyle(.secondary)
                ForEach(Array(chapter.sections.enumerated()),id: \.offset) { _,section in
                    VStack(alignment: .leading,spacing: 10) {
                        Text(section.title).font(.title3.bold())
                        Text(section.text).font(.body).lineSpacing(6).textSelection(.enabled)
                    }
                }
                CodePanel(code: chapter.code)
                StudioPanel(title: "带着一个问题去调") { Text(chapter.exercise).lineSpacing(5) }
            }.padding(24).frame(maxWidth: 780).frame(maxWidth: .infinity)
        }.background(StudioStyle.paper).navigationBarTitleDisplayMode(.inline)
    }
}
