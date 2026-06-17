//
//  AppConfig.swift
//  StarChaser
//
//  Created by Jiaxi on 2026/6/11.
//

import SwiftUI

enum ThemePreference: String, CaseIterable {
    case system = "跟随系统"
    case light = "浅色模式"
    case dark = "深色模式"

    nonisolated var displayTitle: String {
        switch self {
        case .system: return T("跟随系统", "System")
        case .light: return T("浅色模式", "Light")
        case .dark: return T("深色模式", "Dark")
        }
    }
    
    nonisolated var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum LanguagePreference: String, CaseIterable {
    case system = "system"
    case zh = "中文"
    case en = "English"

    nonisolated static var current: LanguagePreference {
        guard let stored = UserDefaults.standard.string(forKey: "languagePreference") else {
            return .system
        }

        switch stored {
        case "system": return .system
        case "中文", "zh": return .zh
        case "English", "en": return .en
        default: return LanguagePreference(rawValue: stored) ?? .system
        }
    }

    nonisolated var displayTitle: String {
        switch self {
        case .system: return T("跟随系统", "System")
        case .zh: return T("中文", "Chinese")
        case .en: return T("英语", "English")
        }
    }

    nonisolated var prefersChinese: Bool {
        switch self {
        case .zh:
            return true
        case .en:
            return false
        case .system:
            return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        }
    }

    nonisolated var localeIdentifier: String {
        switch self {
        case .system:
            return Locale.autoupdatingCurrent.identifier
        case .zh:
            return "zh-Hans"
        case .en:
            return "en"
        }
    }

    nonisolated var locale: Locale {
        Locale(identifier: localeIdentifier)
    }

    nonisolated var appLanguageIdentity: String {
        prefersChinese ? "zh" : "en"
    }

    nonisolated var mapField: String {
        prefersChinese ? "{name:zh}" : "{name:en}"
    }
}
