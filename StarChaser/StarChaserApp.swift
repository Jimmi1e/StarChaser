//
//  StarChaserApp.swift
//  StarChaser
//
//  Created by Jiaxi on 2026/6/11.
//

import SwiftUI

@main
struct StarChaserApp: App {
    // 监听本地存储的主题设置
    @AppStorage("themePreference") private var themePref: ThemePreference = .system
    
    var body: some Scene {
        WindowGroup {
            SplashView()
                // 🌟 【核心修复】强制整个应用全局覆盖主题色
                .preferredColorScheme(themePref.colorScheme)
        }
    }
}
