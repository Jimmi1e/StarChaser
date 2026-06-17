//
//  AppSecrets.swift
//  StarChaser
//
//  Created by Codex on 2026/6/16.
//

import Foundation

enum AppSecrets {
    private static let fileName = "APIKeys"

    private static let values: [String: Any] = {
        guard
            let url = Bundle.main.url(forResource: fileName, withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dictionary = plist as? [String: Any]
        else {
            return [:]
        }

        return dictionary
    }()

    static var aMapWebServiceKey: String {
        string(for: "AMapWebServiceKey")
    }

    private static func string(for key: String) -> String {
        (values[key] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
