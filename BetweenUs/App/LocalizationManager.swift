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
        case .system: return "跟随系统".localized
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

    private static let defaultsKey = "settings.appLanguage"

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
    }

    nonisolated static func localizedString(_ key: String) -> String {
        let saved = UserDefaults.standard.string(forKey: defaultsKey) ?? AppLanguage.system.rawValue
        let language = AppLanguage(rawValue: saved) ?? .system

        guard let identifier = language.localeIdentifier,
              let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(key, comment: "")
        }

        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    nonisolated static func localizedString(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localizedString(key), locale: resolvedLocale(), arguments: arguments)
    }

    nonisolated static func resolvedLocale() -> Locale {
        let saved = UserDefaults.standard.string(forKey: defaultsKey) ?? AppLanguage.system.rawValue
        return locale(for: AppLanguage(rawValue: saved) ?? .system)
    }

    nonisolated private static func locale(for language: AppLanguage) -> Locale {
        language.localeIdentifier.map(Locale.init(identifier:)) ?? .current
    }
}

extension String {
    var localized: String {
        LocalizationManager.localizedString(self)
    }

    func localized(_ arguments: CVarArg...) -> String {
        LocalizationManager.localizedString(self, arguments)
    }
}
