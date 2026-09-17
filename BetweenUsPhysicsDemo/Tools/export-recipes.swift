import Foundation

// 从同一份强类型配置导出只读检查数据，不维护第二套参数来源。
@main
struct ExportRecipes {
    static func main() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        let data = try encoder.encode(ResourceCatalog.all)
        if CommandLine.arguments.count > 1 {
            try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]),options:.atomic)
        } else { FileHandle.standardOutput.write(data) }
    }
}
