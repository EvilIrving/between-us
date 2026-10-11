import Combine
import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case en
    case ja
    case ko

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return T("跟随系统")
        case .zhHans: return "简体中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        }
    }

    fileprivate var localeIdentifier: String? {
        switch self {
        case .system: return nil
        case .zhHans: return "zh-Hans"
        case .en: return "en"
        case .ja: return "ja"
        case .ko: return "ko"
        }
    }
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published private(set) var currentLanguage: AppLanguage
    @Published private(set) var currentLocale: Locale

    private nonisolated static let defaultsKey = "settings.appLanguage"

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? AppLanguage.system.rawValue
        let language = AppLanguage(rawValue: saved) ?? .system
        currentLanguage = language
        currentLocale = Self.locale(for: language)
    }

    func setLanguage(_ language: AppLanguage) {
        guard language != currentLanguage else { return }
        UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
        currentLanguage = language
        currentLocale = Self.locale(for: language)
        Self.bundleCache.invalidate()
    }

    // 视图每次求值都会调用 T，逐次读偏好设置并新建 Bundle 是白付的开销。
    // 语言包解析结果按当前语言缓存，切语言时失效。
    nonisolated static func resolvedBundle() -> Bundle? {
        let saved = UserDefaults.standard.string(forKey: defaultsKey) ?? AppLanguage.system.rawValue
        let language = AppLanguage(rawValue: saved) ?? .system
        guard let identifier = language.localeIdentifier,
              let path = Bundle.main.path(forResource: identifier, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    nonisolated static var currentLanguageKey: String {
        UserDefaults.standard.string(forKey: defaultsKey) ?? AppLanguage.system.rawValue
    }

    private nonisolated static let bundleCache = LanguageBundleCache()

    nonisolated static func resolvedLocale() -> Locale {
        let saved = UserDefaults.standard.string(forKey: defaultsKey) ?? AppLanguage.system.rawValue
        return locale(for: AppLanguage(rawValue: saved) ?? .system)
    }

    nonisolated private static func locale(for language: AppLanguage) -> Locale {
        language.localeIdentifier.map(Locale.init(identifier:)) ?? .current
    }
}

private final class LanguageBundleCache: @unchecked Sendable {
    private let lock = NSLock()
    private var languageKey: String?
    private var cachedBundle: Bundle?

    func bundle() -> Bundle? {
        let key = LocalizationManager.currentLanguageKey
        lock.lock()
        defer { lock.unlock() }
        if languageKey == key { return cachedBundle }
        let resolved = LocalizationManager.resolvedBundle()
        languageKey = key
        cachedBundle = resolved
        return resolved
    }

    func invalidate() {
        lock.lock()
        languageKey = nil
        cachedBundle = nil
        lock.unlock()
    }
}

/// 本地化入口。
///
/// key 写成字面量时 Xcode 会把它提取进 `Localizable.xcstrings`；传运行时字符串不会被提取，
/// 需要保证该 key 已经在 catalog 里。带参数时按格式串处理，保留 `%d`、`%@` 写法。
func T(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
    let locale = LocalizationManager.resolvedLocale()
    let text = String(localized: key, bundle: LocalizationManager.resolvedBundle(), locale: locale)
    guard !arguments.isEmpty else { return text }
    return String(format: text, locale: locale, arguments: arguments)
}

/// 运行时 key 的本地化入口。
///
/// 用于 key 来自变量、不是字面量的场合（Xcode 提取不到）。传入的文本如果本身已经是
/// 本地化结果，查不到会原样返回，不会出错。
func T(key: String) -> String {
    guard let bundle = LocalizationManager.resolvedBundle() else {
        return NSLocalizedString(key, comment: "")
    }
    return bundle.localizedString(forKey: key, value: key, table: nil)
}
