//
//  AppConfig.swift
//  StarChaser
//
//  Created by Jiaxi on 2026/6/11.
//

import SwiftUI

// 主题配置枚举
enum ThemePreference: String, CaseIterable {
    case system = "跟随系统"
    case light = "浅色模式"
    case dark = "深色模式"
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// 语言配置枚举
enum LanguagePreference: String, CaseIterable {
    case zh = "中文"
    case en = "English"
    
    var mapField: String {
        switch self {
        case .zh: return "{name:zh}" // MapLibre 中文标签字段
        case .en: return "{name:en}" // MapLibre 英文标签字段
        }
    }
}
