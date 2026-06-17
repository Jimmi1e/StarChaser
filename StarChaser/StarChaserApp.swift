//
//  StarChaserApp.swift
//  StarChaser
//
//  Created by Jiaxi on 2026/6/11.
//

import SwiftUI

@main
struct StarChaserApp: App {
    @AppStorage("themePreference") private var themePref: ThemePreference = .system
    @AppStorage("languagePreference") private var languagePref: LanguagePreference = .system
    
    var body: some Scene {
        WindowGroup {
            SplashView()
                .preferredColorScheme(themePref.colorScheme)
                .environment(\.locale, languagePref.locale)
                .id(languagePref.appLanguageIdentity)
        }
    }
}
