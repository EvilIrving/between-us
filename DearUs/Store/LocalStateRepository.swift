import Foundation

struct LocalStateRepository: Sendable {
    private let fileURL: URL

    init(filename: String = "dear-us-v1.json") {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directoryURL = baseURL.appendingPathComponent("DearUs", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        self.fileURL = directoryURL.appendingPathComponent(filename)
    }

    func load() -> AppData {
        guard let data = try? Data(contentsOf: fileURL) else { return AppData() }
        do {
            return try JSONDecoder().decode(AppData.self, from: data)
        } catch {
            return AppData()
        }
    }

    func save(_ state: AppData) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func reset() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
