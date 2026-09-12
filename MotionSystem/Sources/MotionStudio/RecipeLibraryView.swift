import SwiftUI
import UniformTypeIdentifiers
import MotionCore

@MainActor
struct RecipeLibraryView: View {
    @ObservedObject var workspace: StudioWorkspace
    @State private var importing = false
    @State private var exporting = false
    @State private var document: RecipeDocument?
    var body: some View {
        List {
            Section("当前工作配方") {
                TextField("名称",text: $workspace.recipe.name)
                Button("保存到本机配方库",systemImage: "square.and.arrow.down") { workspace.saveRecipe() }
                Button("导出 JSON 配方",systemImage: "square.and.arrow.up") {
                    do { document = RecipeDocument(data: try workspace.recipe.encoded()); exporting = true }
                    catch { workspace.notice = error.localizedDescription }
                }
                Button("导入 JSON 配方",systemImage: "doc.badge.plus") { importing = true }
            }
            Section("内置起点 · 参数是示例，不是统一标准") {
                ForEach(MotionRecipes.all) { recipe in
                    Button { workspace.load(recipe) } label: {
                        HStack {
                            VStack(alignment: .leading,spacing: 5) {
                                Text(recipe.name).foregroundStyle(.primary)
                                Text(recipe.family.rawValue.motionTitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "arrow.up.left")
                        }
                    }
                }
            }
            Section("本机保存") {
                if workspace.library.isEmpty { Text("尚未保存配方。").foregroundStyle(.secondary) }
                ForEach(workspace.library) { recipe in
                    Button(recipe.name) { workspace.load(recipe) }
                        .swipeActions { Button("删除",role: .destructive) { workspace.deleteRecipe(recipe.id) } }
                }
            }
            if let notice = workspace.notice { Section { Text(notice).font(.footnote).foregroundStyle(.secondary) } }
        }
        .onChange(of: workspace.recipe.name) { _,_ in workspace.updateExport() }
        .fileImporter(isPresented: $importing,allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                workspace.importRecipe(try Data(contentsOf: url))
            } catch { workspace.notice = error.localizedDescription }
        }
        .fileExporter(isPresented: $exporting,document: document,contentType: .json,defaultFilename: "motion-recipe") { result in
            switch result {
            case .success: workspace.notice = "配方已导出。"
            case .failure(let error): workspace.notice = error.localizedDescription
            }
        }
    }
}
