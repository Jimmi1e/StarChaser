//
//  AppLocalization.swift
//  StarChaser
//
//  Created by Jiaxi on 2026/6/16.
//

import Foundation

enum AppLocalizer {
    nonisolated static func text(_ zh: String, _ en: String) -> String {
        LanguagePreference.current.prefersChinese ? zh : en
    }

    nonisolated static func format(_ zh: String, _ en: String, arguments: [CVarArg]) -> String {
        String(format: text(zh, en), arguments: arguments)
    }
}

nonisolated func T(_ zh: String, _ en: String) -> String {
    AppLocalizer.text(zh, en)
}

nonisolated func TF(_ zh: String, _ en: String, _ arguments: CVarArg...) -> String {
    AppLocalizer.format(zh, en, arguments: arguments)
}
