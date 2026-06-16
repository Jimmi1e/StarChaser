@preconcurrency import AVFoundation
import Combine
import SwiftUI
import UIKit

enum CameraSensorFormat: String, CaseIterable, Identifiable {
    case fullFrame = "全画幅"
    case apsc = "APS-C"
    case microFourThirds = "M4/3"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .fullFrame: return T("全画幅", "Full Frame")
        case .apsc: return "APS-C"
        case .microFourThirds: return "M4/3"
        }
    }

    var cropFactor: Double {
        switch self {
        case .fullFrame: 1
        case .apsc: 1.5
        case .microFourThirds: 2
        }
    }
}

private enum ExposureAutoParameter: String, CaseIterable, Identifiable {
    case iso = "自动 ISO"
    case shutter = "自动快门"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .iso: return T("自动 ISO", "Auto ISO")
        case .shutter: return T("自动快门", "Auto Shutter")
        }
    }
}

private enum CameraCaptureMode: String, CaseIterable, Identifiable {
    case digital = "数码相机"
    case film = "胶片模式"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .digital: "camera.aperture"
        case .film: "film.stack"
        }
    }

    var subtitle: String {
        switch self {
        case .digital: T("ISO / 快门联动", "Linked ISO / Shutter")
        case .film: T("倒易律补偿", "Reciprocity")
        }
    }

    var displayTitle: String {
        switch self {
        case .digital: return T("数码相机", "Digital")
        case .film: return T("胶片模式", "Film")
        }
    }
}

private enum CameraMeterSheet: Identifiable {
    case filmStocks

    var id: String {
        switch self {
        case .filmStocks: "filmStocks"
        }
    }
}

private struct ExposureDialValue: Identifiable {
    let id: Int
    let value: Double
    let label: String
    let tickLabel: String?
}

private struct FilmReciprocityPoint {
    let meteredSeconds: Double
    let correctedSeconds: Double
    let developmentAdjustmentPercent: Double?
}

private struct FilmReciprocityCorrection {
    let correctedSeconds: Double?
    let isWithinOfficialRange: Bool
    let isEstimated: Bool
    let methodText: String
    let warningText: String?
    let developmentText: String?

    init(
        correctedSeconds: Double?,
        isWithinOfficialRange: Bool,
        isEstimated: Bool = false,
        methodText: String,
        warningText: String?,
        developmentText: String?
    ) {
        self.correctedSeconds = correctedSeconds
        self.isWithinOfficialRange = isWithinOfficialRange
        self.isEstimated = isEstimated
        self.methodText = methodText
        self.warningText = warningText
        self.developmentText = developmentText
    }
}

private enum FilmReciprocityModel {
    case ilfordPower(factor: Double)
    case acrosII
    case kodakTable(points: [FilmReciprocityPoint], upperLimit: Double, interpolates: Bool)
    case noPublishedLongExposure(maxVerifiedSeconds: Double)
    case cinestillReference(factor: Double)

    func correction(for meteredSeconds: Double) -> FilmReciprocityCorrection {
        let metered = max(meteredSeconds, 1.0 / 100_000)

        switch self {
        case let .ilfordPower(factor):
            guard metered > 1 else {
                return FilmReciprocityCorrection(
                    correctedSeconds: metered,
                    isWithinOfficialRange: true,
                    methodText: T("官方: 1秒以内无需倒易律补偿", "Official: no reciprocity correction under 1s"),
                    warningText: nil,
                    developmentText: nil
                )
            }

            let corrected = pow(metered, factor)
            return FilmReciprocityCorrection(
                correctedSeconds: corrected,
                isWithinOfficialRange: corrected <= 3600,
                methodText: TF("官方: Tc = Tm^%.2f", "Official: Tc = Tm^%.2f", factor),
                warningText: corrected > 3600 ? T("已进入超长曝光，官方说明此时测光误差和反差变化会变明显；当前结果按通用安全余量显示。", "Ultra-long exposure range. Metering error and contrast changes can become more visible; this result includes a general safety margin.") : nil,
                developmentText: T("长曝反差可能上升，可按场景反差预留约 -5% 到 -10% 的显影调整余量。", "Long exposures can increase contrast; reserve about -5% to -10% development adjustment for high-contrast scenes.")
            )

        case .acrosII:
            if metered < 120 {
                return FilmReciprocityCorrection(
                    correctedSeconds: metered,
                    isWithinOfficialRange: true,
                    methodText: T("官方: 120秒以内无需补偿", "Official: no correction under 120s"),
                    warningText: nil,
                    developmentText: nil
                )
            }

            let corrected = metered * sqrt(2)
            return FilmReciprocityCorrection(
                correctedSeconds: corrected,
                isWithinOfficialRange: metered <= 1000,
                methodText: T("官方: 120-1000秒 +1/2档", "Official: +1/2 stop from 120-1000s"),
                warningText: metered > 1000 ? T("已超过 ACROS II 官方 1000 秒表格范围，显示为延用 +1/2 档的通用估计值。", "Beyond the ACROS II official 1000s table; showing a general estimate by extending +1/2 stop.") : nil,
                developmentText: nil
            )

        case let .kodakTable(points, upperLimit, interpolates):
            guard let first = points.first, let last = points.last else {
                return FilmReciprocityCorrection(
                    correctedSeconds: metered,
                    isWithinOfficialRange: false,
                    methodText: T("缺少胶片表格", "Missing Film Table"),
                    warningText: T("此胶片没有可用倒易律表格。", "No reciprocity table is available for this film."),
                    developmentText: nil
                )
            }

            guard metered <= upperLimit else {
                let corrected = FilmReciprocityModel.logExtrapolatedCorrectedTime(
                    meteredSeconds: metered,
                    points: points
                )
                return FilmReciprocityCorrection(
                    correctedSeconds: corrected,
                    isWithinOfficialRange: false,
                    isEstimated: true,
                    methodText: T("官方表格外: 对数趋势估计", "Outside Official Table: Log-Trend Estimate"),
                    warningText: TF("已超过官方表格最长 %@；这里按表格末段趋势给通用估计值。", "Beyond the official table limit of %@; this uses the last-segment trend as a general estimate.", CameraExposureCalculator.shutterText(upperLimit)),
                    developmentText: nil
                )
            }

            let corrected: Double
            if metered <= first.meteredSeconds {
                corrected = metered * first.correctedSeconds / first.meteredSeconds
            } else if metered >= last.meteredSeconds {
                corrected = metered * last.correctedSeconds / last.meteredSeconds
            } else if interpolates {
                corrected = FilmReciprocityModel.logInterpolatedCorrectedTime(
                    meteredSeconds: metered,
                    points: points
                )
            } else {
                corrected = FilmReciprocityModel.nearestPoint(
                    to: metered,
                    in: points
                ).correctedSeconds
            }

            let developmentText: String?
            if let percent = FilmReciprocityModel.logInterpolatedDevelopmentAdjustment(
                meteredSeconds: metered,
                points: points
            ) {
                developmentText = TF("Kodak 表格建议显影调整约 %+.0f%%。", "Kodak table suggests about %+.0f%% development adjustment.", percent)
            } else {
                developmentText = nil
            }

            return FilmReciprocityCorrection(
                correctedSeconds: corrected,
                isWithinOfficialRange: true,
                methodText: interpolates ? T("官方表格: 表内对数插值", "Official Table: Log Interpolation") : T("官方表格: 最近档位", "Official Table: Nearest Step"),
                warningText: nil,
                developmentText: developmentText
            )

        case let .noPublishedLongExposure(maxVerifiedSeconds):
            if metered <= maxVerifiedSeconds {
                return FilmReciprocityCorrection(
                    correctedSeconds: metered,
                    isWithinOfficialRange: true,
                    methodText: T("官方: 此范围无需补偿", "Official: no correction in this range"),
                    warningText: nil,
                    developmentText: nil
                )
            }

            return FilmReciprocityCorrection(
                    correctedSeconds: pow(metered, 1.3),
                    isWithinOfficialRange: false,
                    isEstimated: true,
                    methodText: T("通用估计: Tc = Tm^1.3", "General Estimate: Tc = Tm^1.3"),
                    warningText: TF("官方只给到 %@ 内无需补偿；更长时间按彩色负片通用倒易律估计。", "Official data only confirms no correction up to %@; longer times use a general color-negative reciprocity estimate.", CameraExposureCalculator.shutterText(maxVerifiedSeconds)),
                    developmentText: T("可预留 +0.5EV 到 +1EV 的安全余量，以应对不同批次、扫描和色偏。", "Reserve +0.5EV to +1EV of safety margin for batch variation, scanning, and color shifts.")
                )

        case let .cinestillReference(factor):
            guard metered > 1 else {
                return FilmReciprocityCorrection(
                    correctedSeconds: metered,
                    isWithinOfficialRange: true,
                    methodText: T("CineStill: 1秒以内按测光值", "CineStill: use metered value under 1s"),
                    warningText: nil,
                    developmentText: nil
                )
            }

            let corrected = pow(metered, factor)
            return FilmReciprocityCorrection(
                correctedSeconds: corrected,
                isWithinOfficialRange: false,
                isEstimated: true,
                methodText: TF("CineStill 参考: Tc = Tm^%.1f", "CineStill Reference: Tc = Tm^%.1f", factor),
                warningText: T("CineStill 官方未发布逐片种倒易律表；此值为官方帮助页给出的低照度通用参考。", "CineStill has not published per-stock reciprocity tables; this follows their general low-light reference."),
                developmentText: T("彩色负片长曝可能出现色偏，可预留 +0.5EV 到 +1EV 的安全余量。", "Color negative long exposures may shift color; reserve +0.5EV to +1EV of safety margin.")
            )
        }
    }

    private static func logInterpolatedCorrectedTime(
        meteredSeconds: Double,
        points: [FilmReciprocityPoint]
    ) -> Double {
        for index in 0..<(points.count - 1) {
            let lower = points[index]
            let upper = points[index + 1]

            guard meteredSeconds >= lower.meteredSeconds,
                  meteredSeconds <= upper.meteredSeconds else {
                continue
            }

            let t = (log(meteredSeconds) - log(lower.meteredSeconds))
                / (log(upper.meteredSeconds) - log(lower.meteredSeconds))
            return exp(log(lower.correctedSeconds)
                + t * (log(upper.correctedSeconds) - log(lower.correctedSeconds)))
        }

        return nearestPoint(to: meteredSeconds, in: points).correctedSeconds
    }

    private static func logExtrapolatedCorrectedTime(
        meteredSeconds: Double,
        points: [FilmReciprocityPoint]
    ) -> Double {
        guard points.count >= 2 else {
            return pow(meteredSeconds, 1.3)
        }

        let lower = points[points.count - 2]
        let upper = points[points.count - 1]
        let denominator = log(upper.meteredSeconds) - log(lower.meteredSeconds)
        guard denominator != 0 else {
            return meteredSeconds * upper.correctedSeconds / upper.meteredSeconds
        }

        let slope = (log(upper.correctedSeconds) - log(lower.correctedSeconds)) / denominator
        let projected = exp(log(upper.correctedSeconds) + slope * (log(meteredSeconds) - log(upper.meteredSeconds)))
        return min(projected, meteredSeconds * 100)
    }

    private static func logInterpolatedDevelopmentAdjustment(
        meteredSeconds: Double,
        points: [FilmReciprocityPoint]
    ) -> Double? {
        let developmentPoints = points.compactMap { point -> (Double, Double)? in
            guard let adjustment = point.developmentAdjustmentPercent else { return nil }
            return (point.meteredSeconds, adjustment)
        }
        guard developmentPoints.count >= 2 else { return developmentPoints.first?.1 }

        if meteredSeconds <= developmentPoints[0].0 {
            return developmentPoints[0].1
        }

        for index in 0..<(developmentPoints.count - 1) {
            let lower = developmentPoints[index]
            let upper = developmentPoints[index + 1]
            guard meteredSeconds >= lower.0, meteredSeconds <= upper.0 else { continue }

            let t = (log(meteredSeconds) - log(lower.0)) / (log(upper.0) - log(lower.0))
            return lower.1 + t * (upper.1 - lower.1)
        }

        return developmentPoints.last?.1
    }

    private static func nearestPoint(
        to meteredSeconds: Double,
        in points: [FilmReciprocityPoint]
    ) -> FilmReciprocityPoint {
        points.min {
            abs($0.meteredSeconds - meteredSeconds) < abs($1.meteredSeconds - meteredSeconds)
        } ?? points[0]
    }
}

private struct FilmStock: Identifiable {
    let id: String
    let name: String
    let shortName: String
    let speedISO: Int
    let type: String
    let reciprocity: FilmReciprocityModel
    let sourceSummary: String
    let accent: Color

    var displayName: String {
        T(name, name.replacingOccurrences(of: " 全能400", with: ""))
    }

    var localizedType: String {
        T(type, FilmStock.englishType(for: type))
    }

    var localizedSourceSummary: String {
        T(sourceSummary, FilmStock.englishSource(for: sourceSummary))
    }

    private static func englishType(for type: String) -> String {
        switch type {
        case "黑白负片": return "Black & White Negative"
        case "彩色负片": return "Color Negative"
        case "彩色负片(日光)": return "Color Negative (Daylight)"
        case "彩色负片(钨丝)": return "Color Negative (Tungsten)"
        default: return type
        }
    }

    private static func englishSource(for source: String) -> String {
        switch source {
        case "Fuji 官方: <120秒免补偿，120-1000秒 +1/2档":
            return "Fuji official: no correction under 120s, +1/2 stop from 120-1000s"
        case "Ilford 官方 P=1.31":
            return "Ilford official P=1.31"
        case "Ilford 官方 P=1.26":
            return "Ilford official P=1.26"
        case "Ilford 官方 P=1.41":
            return "Ilford official P=1.41"
        case "Kodak 官方表: 1-100秒长曝补偿，含显影调整":
            return "Kodak official table: 1-100s long-exposure correction with development adjustment"
        case "Kodak 官方表: 1秒+1/3档，10秒15秒，100秒200秒":
            return "Kodak official table: 1s +1/3 stop, 10s to 15s, 100s to 200s"
        case "Kodak 官方表: 1秒内免补偿，10秒+1/3档，100秒300秒":
            return "Kodak official table: no correction under 1s, 10s +1/3 stop, 100s to 300s"
        case "Kodak 官方: 1/10000-1秒无需补偿，更长用通用估计":
            return "Kodak official: no correction from 1/10000s to 1s; longer times use a general estimate"
        case "CineStill 官方: 无逐片种表，低照度可用 Tm^1.3 参考":
            return "CineStill official: no per-stock table; Tm^1.3 can be used as a low-light reference"
        default:
            return source
        }
    }

    static let catalog: [FilmStock] = [
        FilmStock(
            id: "fuji-acros-ii-100",
            name: "Fujifilm NEOPAN 100 ACROS II",
            shortName: "ACROS II",
            speedISO: 100,
            type: "黑白负片",
            reciprocity: .acrosII,
            sourceSummary: "Fuji 官方: <120秒免补偿，120-1000秒 +1/2档",
            accent: .teal
        ),
        FilmStock(
            id: "ilford-hp5-plus-400",
            name: "Ilford HP5 Plus",
            shortName: "HP5+",
            speedISO: 400,
            type: "黑白负片",
            reciprocity: .ilfordPower(factor: 1.31),
            sourceSummary: "Ilford 官方 P=1.31",
            accent: .indigo
        ),
        FilmStock(
            id: "ilford-fp4-plus-125",
            name: "Ilford FP4 Plus",
            shortName: "FP4+",
            speedISO: 125,
            type: "黑白负片",
            reciprocity: .ilfordPower(factor: 1.26),
            sourceSummary: "Ilford 官方 P=1.26",
            accent: .blue
        ),
        FilmStock(
            id: "ilford-delta-100",
            name: "Ilford Delta 100",
            shortName: "Delta 100",
            speedISO: 100,
            type: "黑白负片",
            reciprocity: .ilfordPower(factor: 1.26),
            sourceSummary: "Ilford 官方 P=1.26",
            accent: .cyan
        ),
        FilmStock(
            id: "ilford-delta-400",
            name: "Ilford Delta 400",
            shortName: "Delta 400",
            speedISO: 400,
            type: "黑白负片",
            reciprocity: .ilfordPower(factor: 1.41),
            sourceSummary: "Ilford 官方 P=1.41",
            accent: .purple
        ),
        FilmStock(
            id: "kodak-trix-400",
            name: "Kodak Tri-X 400",
            shortName: "Tri-X 400",
            speedISO: 400,
            type: "黑白负片",
            reciprocity: .kodakTable(
                points: [
                    FilmReciprocityPoint(meteredSeconds: 1.0 / 100_000, correctedSeconds: 2.0 / 100_000, developmentAdjustmentPercent: 20),
                    FilmReciprocityPoint(meteredSeconds: 1.0 / 10_000, correctedSeconds: sqrt(2) / 10_000, developmentAdjustmentPercent: 15),
                    FilmReciprocityPoint(meteredSeconds: 1.0 / 1000, correctedSeconds: 1.0 / 1000, developmentAdjustmentPercent: 10),
                    FilmReciprocityPoint(meteredSeconds: 1.0 / 100, correctedSeconds: 1.0 / 100, developmentAdjustmentPercent: 0),
                    FilmReciprocityPoint(meteredSeconds: 0.1, correctedSeconds: 0.1, developmentAdjustmentPercent: nil),
                    FilmReciprocityPoint(meteredSeconds: 1, correctedSeconds: 2, developmentAdjustmentPercent: -10),
                    FilmReciprocityPoint(meteredSeconds: 10, correctedSeconds: 50, developmentAdjustmentPercent: -20),
                    FilmReciprocityPoint(meteredSeconds: 100, correctedSeconds: 1200, developmentAdjustmentPercent: -30)
                ],
                upperLimit: 100,
                interpolates: true
            ),
            sourceSummary: "Kodak 官方表: 1-100秒长曝补偿，含显影调整",
            accent: .orange
        ),
        FilmStock(
            id: "kodak-tmax-100",
            name: "Kodak T-MAX 100",
            shortName: "T-MAX 100",
            speedISO: 100,
            type: "黑白负片",
            reciprocity: .kodakTable(
                points: [
                    FilmReciprocityPoint(meteredSeconds: 1.0 / 10_000, correctedSeconds: pow(2, 1.0 / 3.0) / 10_000, developmentAdjustmentPercent: nil),
                    FilmReciprocityPoint(meteredSeconds: 1.0 / 1000, correctedSeconds: 1.0 / 1000, developmentAdjustmentPercent: nil),
                    FilmReciprocityPoint(meteredSeconds: 1.0 / 100, correctedSeconds: 1.0 / 100, developmentAdjustmentPercent: nil),
                    FilmReciprocityPoint(meteredSeconds: 0.1, correctedSeconds: 0.1, developmentAdjustmentPercent: nil),
                    FilmReciprocityPoint(meteredSeconds: 1, correctedSeconds: pow(2, 1.0 / 3.0), developmentAdjustmentPercent: nil),
                    FilmReciprocityPoint(meteredSeconds: 10, correctedSeconds: 15, developmentAdjustmentPercent: nil),
                    FilmReciprocityPoint(meteredSeconds: 100, correctedSeconds: 200, developmentAdjustmentPercent: nil)
                ],
                upperLimit: 100,
                interpolates: true
            ),
            sourceSummary: "Kodak 官方表: 1秒+1/3档，10秒15秒，100秒200秒",
            accent: .mint
        ),
        FilmStock(
            id: "kodak-tmax-400",
            name: "Kodak T-MAX 400",
            shortName: "T-MAX 400",
            speedISO: 400,
            type: "黑白负片",
            reciprocity: .kodakTable(
                points: [
                    FilmReciprocityPoint(meteredSeconds: 1.0 / 10_000, correctedSeconds: 1.0 / 10_000, developmentAdjustmentPercent: nil),
                    FilmReciprocityPoint(meteredSeconds: 1.0 / 1000, correctedSeconds: 1.0 / 1000, developmentAdjustmentPercent: nil),
                    FilmReciprocityPoint(meteredSeconds: 1.0 / 100, correctedSeconds: 1.0 / 100, developmentAdjustmentPercent: nil),
                    FilmReciprocityPoint(meteredSeconds: 0.1, correctedSeconds: 0.1, developmentAdjustmentPercent: nil),
                    FilmReciprocityPoint(meteredSeconds: 1, correctedSeconds: 1, developmentAdjustmentPercent: nil),
                    FilmReciprocityPoint(meteredSeconds: 10, correctedSeconds: 10 * pow(2, 1.0 / 3.0), developmentAdjustmentPercent: nil),
                    FilmReciprocityPoint(meteredSeconds: 100, correctedSeconds: 300, developmentAdjustmentPercent: nil)
                ],
                upperLimit: 100,
                interpolates: true
            ),
            sourceSummary: "Kodak 官方表: 1秒内免补偿，10秒+1/3档，100秒300秒",
            accent: .green
        ),
        FilmStock(
            id: "kodak-portra-400",
            name: "Kodak PORTRA 400",
            shortName: "Portra 400",
            speedISO: 400,
            type: "彩色负片",
            reciprocity: .noPublishedLongExposure(maxVerifiedSeconds: 1),
            sourceSummary: "Kodak 官方: 1/10000-1秒无需补偿，更长用通用估计",
            accent: .pink
        ),
        FilmStock(
            id: "kodak-portra-800",
            name: "Kodak PORTRA 800",
            shortName: "Portra 800",
            speedISO: 800,
            type: "彩色负片",
            reciprocity: .noPublishedLongExposure(maxVerifiedSeconds: 1),
            sourceSummary: "Kodak 官方: 1/10000-1秒无需补偿，更长用通用估计",
            accent: .red
        ),
        FilmStock(
            id: "kodak-ultramax-400",
            name: "Kodak UltraMax 400 全能400",
            shortName: "UltraMax 400",
            speedISO: 400,
            type: "彩色负片",
            reciprocity: .noPublishedLongExposure(maxVerifiedSeconds: 1),
            sourceSummary: "Kodak 官方: 1/10000-1秒无需补偿，更长用通用估计",
            accent: .yellow
        ),
        FilmStock(
            id: "cinestill-400d",
            name: "CineStill 400D",
            shortName: "400D",
            speedISO: 400,
            type: "彩色负片(日光)",
            reciprocity: .cinestillReference(factor: 1.3),
            sourceSummary: "CineStill 官方: 无逐片种表，低照度可用 Tm^1.3 参考",
            accent: .cyan
        ),
        FilmStock(
            id: "cinestill-800t",
            name: "CineStill 800T",
            shortName: "800T",
            speedISO: 800,
            type: "彩色负片(钨丝)",
            reciprocity: .cinestillReference(factor: 1.3),
            sourceSummary: "CineStill 官方: 无逐片种表，低照度可用 Tm^1.3 参考",
            accent: .purple
        )
    ]
}

private struct FilmExposureSolution {
    let stock: FilmStock
    let meteredSeconds: Double
    let correctedSeconds: Double?
    let correctionStops: Double?
    let isWithinOfficialRange: Bool
    let isEstimated: Bool
    let methodText: String
    let warningText: String?
    let developmentText: String?
    let starSafeShutter: Double

    var exceedsStarSafeShutter: Bool {
        guard let correctedSeconds else { return false }
        return correctedSeconds > starSafeShutter * 1.05
    }
}

private enum FilmExposureCalculator {
    static func solve(
        targetEV100: Double,
        aperture: Double,
        focalLength: Double,
        sensor: CameraSensorFormat,
        stock: FilmStock
    ) -> FilmExposureSolution {
        let meteredSeconds = max(
            aperture * aperture / (pow(2, targetEV100) * (Double(stock.speedISO) / 100)),
            1.0 / 100_000
        )
        let correction = stock.reciprocity.correction(for: meteredSeconds)
        let correctionStops = correction.correctedSeconds.map {
            max(0, log2($0 / meteredSeconds))
        }
        let safeShutter = min(30, max(0.25, 300 / (focalLength * sensor.cropFactor)))

        return FilmExposureSolution(
            stock: stock,
            meteredSeconds: meteredSeconds,
            correctedSeconds: correction.correctedSeconds,
            correctionStops: correctionStops,
            isWithinOfficialRange: correction.isWithinOfficialRange,
            isEstimated: correction.isEstimated,
            methodText: correction.methodText,
            warningText: correction.warningText,
            developmentText: correction.developmentText,
            starSafeShutter: safeShutter
        )
    }
}

private enum ExposureScales {
    static let apertures = makeScale(
        values: [1.2, 1.4, 1.6, 1.8, 2, 2.2, 2.5, 2.8, 3.2, 3.5, 4, 4.5, 5, 5.6, 6.3, 7.1, 8, 9, 10, 11, 13, 14, 16],
        label: { String(format: "f/%.1f", $0) },
        tickEvery: 3
    )

    static let isos = makeScale(
        values: [50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000, 10000, 12800, 16000, 20000, 25600],
        label: { "ISO \(Int($0))" },
        tickEvery: 3
    )

    static let shutters = makeScale(
        values: [
            1.0 / 8000, 1.0 / 6400, 1.0 / 5000, 1.0 / 4000, 1.0 / 3200,
            1.0 / 2500, 1.0 / 2000, 1.0 / 1600, 1.0 / 1250, 1.0 / 1000,
            1.0 / 800, 1.0 / 640, 1.0 / 500, 1.0 / 400, 1.0 / 320,
            1.0 / 250, 1.0 / 200, 1.0 / 160, 1.0 / 125, 1.0 / 100,
            1.0 / 80, 1.0 / 60, 1.0 / 50, 1.0 / 40, 1.0 / 30,
            1.0 / 25, 1.0 / 20, 1.0 / 15, 1.0 / 13, 1.0 / 10,
            1.0 / 8, 1.0 / 6, 1.0 / 5, 1.0 / 4, 1.0 / 3,
            0.4, 0.5, 0.6, 0.8, 1, 1.3, 1.6, 2, 2.5, 3.2,
            4, 5, 6, 8, 10, 13, 15, 20, 25, 30
        ],
        label: { CameraExposureCalculator.shutterText($0) },
        tickEvery: 4
    )

    static let focalLengths = makeScale(
        values: [12, 14, 16, 18, 20, 24, 28, 35, 40, 50, 70, 85, 100, 135, 200],
        label: { "\(Int($0))mm" },
        tickEvery: 2
    )

    static let compensation = makeScale(
        values: stride(from: -3.0, through: 3.001, by: 1.0 / 3.0).map { $0 },
        label: { String(format: "%+.1f EV", $0) },
        tickEvery: 3
    )

    static let manualEV = makeScale(
        values: stride(from: -10.0, through: 4.001, by: 1.0 / 3.0).map { $0 },
        label: { String(format: "%.1f EV", $0) },
        tickEvery: 3
    )

    static func nearestIndex(in scale: [ExposureDialValue], to value: Double) -> Int {
        scale.indices.min {
            abs(scale[$0].value - value) < abs(scale[$1].value - value)
        } ?? 0
    }

    private static func makeScale(
        values: [Double],
        label: (Double) -> String,
        tickEvery: Int
    ) -> [ExposureDialValue] {
        values.enumerated().map { index, value in
            let text = label(value)
            return ExposureDialValue(
                id: index,
                value: value,
                label: text,
                tickLabel: index.isMultiple(of: tickEvery) ? text : nil
            )
        }
    }
}

private struct CameraExposureSolution {
    let aperture: Double
    let iso: Int
    let shutterSeconds: Double
    let targetEV100: Double
    let exposureErrorEV: Double
    let starSafeShutter: Double
    let stackCount: Int

    var isStarSafe: Bool {
        shutterSeconds <= starSafeShutter * 1.05
    }
}

private enum CameraExposureCalculator {
    static func solve(
        targetEV100: Double,
        aperture: Double,
        iso: Int,
        shutterSeconds: Double,
        autoParameter: ExposureAutoParameter,
        focalLength: Double,
        sensor: CameraSensorFormat
    ) -> CameraExposureSolution {
        var resolvedISO = iso
        var resolvedShutter = shutterSeconds

        switch autoParameter {
        case .iso:
            let exactISO = 100 * aperture * aperture
                / (shutterSeconds * pow(2, targetEV100))
            let index = ExposureScales.nearestIndex(in: ExposureScales.isos, to: exactISO)
            resolvedISO = Int(ExposureScales.isos[index].value)
        case .shutter:
            let exactShutter = aperture * aperture
                / (pow(2, targetEV100) * (Double(iso) / 100))
            let index = ExposureScales.nearestIndex(in: ExposureScales.shutters, to: exactShutter)
            resolvedShutter = ExposureScales.shutters[index].value
        }

        let actualEV100 = log2(aperture * aperture / resolvedShutter)
            - log2(Double(resolvedISO) / 100)
        let safeShutter = min(30, max(0.25, 300 / (focalLength * sensor.cropFactor)))

        let baseStackCount: Int
        switch resolvedISO {
        case ...800: baseStackCount = 8
        case ...1600: baseStackCount = 12
        case ...3200: baseStackCount = 20
        case ...6400: baseStackCount = 30
        default: baseStackCount = 48
        }

        let error = actualEV100 - targetEV100
        let extraFrames = error > 0.35 ? Int(ceil(error * 6)) : 0

        return CameraExposureSolution(
            aperture: aperture,
            iso: resolvedISO,
            shutterSeconds: resolvedShutter,
            targetEV100: targetEV100,
            exposureErrorEV: error,
            starSafeShutter: safeShutter,
            stackCount: min(64, baseStackCount + extraFrames)
        )
    }

    nonisolated static func shutterText(_ seconds: Double) -> String {
        let isChinese = LanguagePreference.current.prefersChinese

        if seconds >= 3600 {
            let totalSeconds = Int(seconds.rounded())
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            return isChinese
                ? "\(hours)小时\(String(format: "%02d", minutes))分"
                : "\(hours)h \(String(format: "%02d", minutes))m"
        }

        if seconds >= 60 {
            let totalSeconds = Int(seconds.rounded())
            let minutes = totalSeconds / 60
            let remainder = totalSeconds % 60
            return isChinese
                ? "\(minutes)分\(String(format: "%02d", remainder))秒"
                : "\(minutes)m \(String(format: "%02d", remainder))s"
        }

        if seconds >= 1 {
            if seconds.rounded() == seconds {
                return isChinese ? "\(Int(seconds))秒" : "\(Int(seconds))s"
            }
            return isChinese ? String(format: "%.1f秒", seconds) : String(format: "%.1fs", seconds)
        }

        let denominator = Int((1 / seconds).rounded())
        return isChinese ? "1/\(denominator)秒" : "1/\(denominator)s"
    }
}

@MainActor
final class CameraMeterController: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var measuredEV100: Double?
    @Published private(set) var isRunning = false
    @Published private(set) var isAdjustingExposure = false
    @Published private(set) var exposureTargetOffsetEV = 0.0

    nonisolated(unsafe) let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.starchaser.camera-meter")
    private var observationTimer: Timer?
    private var recentEVSamples: [Double] = []

    var canUseCamera: Bool {
        authorizationStatus == .authorized
    }

    func start() {
        switch authorizationStatus {
        case .authorized:
            configureAndStartSession()
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
                if granted {
                    configureAndStartSession()
                }
            }
        default:
            break
        }
    }

    func stop() {
        observationTimer?.invalidate()
        observationTimer = nil
        recentEVSamples.removeAll()
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
            Task { @MainActor in
                self.isRunning = false
            }
        }
    }

    private func configureAndStartSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.session.inputs.isEmpty {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo

                guard
                    let camera = AVCaptureDevice.default(
                        .builtInWideAngleCamera,
                        for: .video,
                        position: .back
                    ),
                    let input = try? AVCaptureDeviceInput(device: camera),
                    self.session.canAddInput(input)
                else {
                    self.session.commitConfiguration()
                    return
                }

                self.session.addInput(input)
                self.session.commitConfiguration()
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }

            Task { @MainActor in
                self.isRunning = true
                self.startObservation()
            }
        }
    }

    private func startObservation() {
        observationTimer?.invalidate()
        observationTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            guard
                let self,
                let cameraInput = self.session.inputs.first as? AVCaptureDeviceInput
            else { return }

            let camera = cameraInput.device
            let iso = max(Double(camera.iso), 1)
            let duration = max(CMTimeGetSeconds(camera.exposureDuration), 1.0 / 100_000)
            let aperture = max(Double(camera.lensAperture), 0.7)
            let targetOffset = Double(camera.exposureTargetOffset)
            let correctedEV100 = log2(aperture * aperture / duration)
                - log2(iso / 100)
                + targetOffset

            Task { @MainActor in
                self.recentEVSamples.append(correctedEV100)
                if self.recentEVSamples.count > 5 {
                    self.recentEVSamples.removeFirst()
                }
                self.measuredEV100 = self.recentEVSamples.reduce(0, +)
                    / Double(self.recentEVSamples.count)
                self.isAdjustingExposure = camera.isAdjustingExposure
                self.exposureTargetOffsetEV = targetOffset
            }
        }
    }
}

struct CameraMeterWidgetView: View {
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [.indigo, .purple, .cyan.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 76, height: 76)

                Image(systemName: "camera.metering.center.weighted")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(T("星空相机参数", "Astro Camera Meter"))
                    .font(.headline)
                Text(T("手机测光 · 无反相机曝光参考", "Phone metering · mirrorless exposure reference"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label(T("数码 / 胶片曝光参考", "Digital / film exposure reference"), systemImage: "film.stack")
                    .font(.caption)
                    .foregroundStyle(.indigo)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }
}

struct CameraMeterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var meter = CameraMeterController()

    @State private var captureMode: CameraCaptureMode = .digital
    @State private var sensor: CameraSensorFormat = .fullFrame
    @State private var autoParameter: ExposureAutoParameter = .iso
    @State private var apertureIndex = 7
    @State private var isoIndex = 15
    @State private var shutterIndex = 48
    @State private var focalLengthIndex = 5
    @State private var compensationIndex = 9
    @State private var manualEVIndex = 18
    @State private var lockedMeterEV100: Double?
    @State private var isApertureLocked = false
    @State private var isCompensationLocked = false
    @State private var filmStockIndex = 0
    @State private var presentedSheet: CameraMeterSheet?

    private var measuredEV100: Double {
        lockedMeterEV100 ?? meter.measuredEV100 ?? ExposureScales.manualEV[manualEVIndex].value
    }

    private var targetEV100: Double {
        measuredEV100 + ExposureScales.compensation[compensationIndex].value
    }

    private var solution: CameraExposureSolution {
        CameraExposureCalculator.solve(
            targetEV100: targetEV100,
            aperture: ExposureScales.apertures[apertureIndex].value,
            iso: Int(ExposureScales.isos[isoIndex].value),
            shutterSeconds: ExposureScales.shutters[shutterIndex].value,
            autoParameter: autoParameter,
            focalLength: ExposureScales.focalLengths[focalLengthIndex].value,
            sensor: sensor
        )
    }

    private var selectedFilmStock: FilmStock {
        FilmStock.catalog[min(max(filmStockIndex, 0), FilmStock.catalog.count - 1)]
    }

    private var filmSolution: FilmExposureSolution {
        FilmExposureCalculator.solve(
            targetEV100: targetEV100,
            aperture: ExposureScales.apertures[apertureIndex].value,
            focalLength: ExposureScales.focalLengths[focalLengthIndex].value,
            sensor: sensor,
            stock: selectedFilmStock
        )
    }

    private var accentColor: Color {
        Color.indigo
    }

    var body: some View {
        ZStack {
            themeBackground

            ScrollView {
                VStack(spacing: 18) {
                    meterCard
                    captureModeCard

                    if captureMode == .digital {
                        exposureTriangleCard
                        cameraSetupCard
                        recommendationCard
                        stackCard
                    } else {
                        filmExposureCard
                        cameraSetupCard
                        filmRecommendationCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
        }
        .navigationTitle(T("相机测光", "Camera Meter"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(T("关闭", "Close"))
            }
        }
        .onAppear {
            meter.start()
            recalculateAutomaticParameter()
        }
        .onDisappear {
            meter.stop()
        }
        .onChange(of: meter.measuredEV100) { _, _ in
            guard lockedMeterEV100 == nil else { return }
            if captureMode == .digital {
                recalculateAutomaticParameter()
            }
        }
        .onChange(of: autoParameter) { _, _ in
            if captureMode == .digital {
                recalculateAutomaticParameter()
            }
        }
        .onChange(of: captureMode) { _, newMode in
            DialHaptics.shared.impact()
            if newMode == .digital {
                recalculateAutomaticParameter()
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .filmStocks:
                FilmStockPickerSheet(selectedIndex: $filmStockIndex)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private var themeBackground: some View {
        if colorScheme == .light {
            LinearGradient(
                colors: [
                    Color(uiColor: .systemGroupedBackground),
                    Color(uiColor: .secondarySystemBackground).opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(uiColor: .systemBackground),
                        Color(uiColor: .secondarySystemBackground),
                        Color(uiColor: .systemBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(accentColor.opacity(0.14))
                    .frame(width: 300)
                    .blur(radius: 70)
                    .offset(x: 150, y: -300)
            }
            .ignoresSafeArea()
        }
    }

    private var meterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(T("手机实时测光", "Live Phone Metering"), systemImage: "viewfinder")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(meterStatusColor)
                        .frame(width: 7, height: 7)
                    Text(meterStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if meter.canUseCamera {
                CameraPreview(session: meter.session)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .center) {
                        Image(systemName: "plus")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .overlay(alignment: .bottomLeading) {
                        HStack(spacing: 8) {
                            Text(String(format: "EV100 %.1f", measuredEV100))
                            if lockedMeterEV100 != nil {
                                Label(T("已锁定", "Locked"), systemImage: "lock.fill")
                            }
                        }
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(12)
                    }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(accentColor)
                    Text(cameraUnavailableText)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .background(Color(uiColor: .secondarySystemBackground).opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            if meter.canUseCamera {
                Button {
                    toggleMeterLock()
                } label: {
                    Label(
                        lockedMeterEV100 == nil ? T("锁定当前亮度", "Lock Current Brightness") : T("重新实时测光", "Resume Live Metering"),
                        systemImage: lockedMeterEV100 == nil ? "lock.open" : "arrow.clockwise"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(lockedMeterEV100 == nil ? .white : accentColor)
                    .background(
                        lockedMeterEV100 == nil
                            ? accentColor
                            : accentColor.opacity(0.14)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(meter.measuredEV100 == nil)
            } else {
                HorizontalExposureDial(
                    title: T("手动场景亮度", "Manual Scene Brightness"),
                    subtitle: T("无相机权限时用于模拟手机测光", "Use this to estimate phone metering without camera access"),
                    options: ExposureScales.manualEV,
                    selectedIndex: manualEVIndex,
                    tint: accentColor,
                    isAutomatic: false
                ) { newIndex in
                    manualEVIndex = newIndex
                    recalculateAutomaticParameter()
                }
            }

            Text(T("把手机对准要拍摄的天空，等待亮度稳定后锁定。读数已包含手机曝光目标偏移修正，并会作为无反相机曝光计算的基准。", "Point the phone at the sky you plan to shoot, wait for brightness to stabilize, then lock it. The reading includes phone exposure-target compensation and becomes the reference for camera exposure."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .meterPanel()
    }

    private var captureModeCard: some View {
        HStack(spacing: 12) {
            ForEach(CameraCaptureMode.allCases) { mode in
                CaptureModeOptionButton(
                    mode: mode,
                    isSelected: captureMode == mode,
                    tint: mode == .film ? selectedFilmStock.accent : accentColor
                ) {
                    captureMode = mode
                }
            }
        }
    }

    private var exposureTriangleCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(T("曝光三角联动", "Linked Exposure Triangle"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(T("拨动 ISO 会自动计算快门；拨动快门会自动计算 ISO。光圈变化由当前自动项补偿。", "Adjusting ISO recalculates shutter; adjusting shutter recalculates ISO. Aperture changes are compensated by the current automatic item."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker(T("自动补偿项", "Auto Compensation"), selection: $autoParameter) {
                ForEach(ExposureAutoParameter.allCases) { item in
                    Text(item.displayTitle).tag(item)
                }
            }
            .pickerStyle(.segmented)

            HorizontalExposureDial(
                title: T("光圈", "Aperture"),
                subtitle: T("镜头实际使用光圈", "Actual lens aperture"),
                options: ExposureScales.apertures,
                selectedIndex: apertureIndex,
                tint: accentColor,
                isAutomatic: false,
                isLocked: isApertureLocked,
                onLockToggle: {
                    isApertureLocked.toggle()
                    DialHaptics.shared.impact()
                }
            ) { newIndex in
                apertureIndex = newIndex
                recalculateAutomaticParameter()
            }

            HorizontalExposureDial(
                title: "ISO",
                subtitle: autoParameter == .iso ? T("根据手机亮度和当前快门自动计算", "Calculated from phone brightness and current shutter") : T("拨动后由快门自动补偿", "Shutter will compensate after adjustment"),
                options: ExposureScales.isos,
                selectedIndex: isoIndex,
                tint: accentColor,
                isAutomatic: autoParameter == .iso
            ) { newIndex in
                isoIndex = newIndex
                if autoParameter == .iso {
                    autoParameter = .shutter
                } else {
                    recalculateAutomaticParameter()
                }
            }

            HorizontalExposureDial(
                title: T("快门", "Shutter"),
                subtitle: autoParameter == .shutter ? T("根据手机亮度和当前 ISO 自动计算", "Calculated from phone brightness and current ISO") : T("拨动后由 ISO 自动补偿", "ISO will compensate after adjustment"),
                options: ExposureScales.shutters,
                selectedIndex: shutterIndex,
                tint: accentColor,
                isAutomatic: autoParameter == .shutter
            ) { newIndex in
                shutterIndex = newIndex
                if autoParameter == .shutter {
                    autoParameter = .iso
                } else {
                    recalculateAutomaticParameter()
                }
            }

            HorizontalExposureDial(
                title: T("曝光修正", "Exposure Compensation"),
                subtitle: T("负值压暗天空，正值提升暗部", "Negative values darken the sky; positive values lift shadows"),
                options: ExposureScales.compensation,
                selectedIndex: compensationIndex,
                tint: accentColor,
                isAutomatic: false,
                isLocked: isCompensationLocked,
                onLockToggle: {
                    isCompensationLocked.toggle()
                    DialHaptics.shared.impact()
                }
            ) { newIndex in
                compensationIndex = newIndex
                recalculateAutomaticParameter()
            }
        }
        .meterPanel()
    }

    private var filmExposureCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(T("胶片曝光计算", "Film Exposure Calculator"), systemImage: "film.stack")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(T("胶片 ISO 固定为所选胶片的 ASA/EI，长曝光按官方表或通用估计补偿。", "Film ISO follows the selected stock's ASA/EI. Long exposures are corrected with official tables or general estimates."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("FILM")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(selectedFilmStock.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(selectedFilmStock.accent.opacity(0.14))
                    .clipShape(Capsule())
            }

            filmStockMenu

            HStack(spacing: 10) {
                filmInfoPill(title: "ASA", value: "\(selectedFilmStock.speedISO)")
                filmInfoPill(title: T("类型", "Type"), value: selectedFilmStock.localizedType)
            }

            Text(selectedFilmStock.localizedSourceSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground).opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HorizontalExposureDial(
                title: T("光圈", "Aperture"),
                subtitle: T("胶片曝光以当前镜头光圈计算", "Film exposure is calculated from the current lens aperture"),
                options: ExposureScales.apertures,
                selectedIndex: apertureIndex,
                tint: selectedFilmStock.accent,
                isAutomatic: false,
                isLocked: isApertureLocked,
                onLockToggle: {
                    isApertureLocked.toggle()
                    DialHaptics.shared.impact()
                }
            ) { newIndex in
                apertureIndex = newIndex
            }

            HorizontalExposureDial(
                title: T("曝光修正", "Exposure Compensation"),
                subtitle: T("用于按天空亮度、冲扫偏好或滤镜微调", "Fine-tune for sky brightness, scanning preference, or filters"),
                options: ExposureScales.compensation,
                selectedIndex: compensationIndex,
                tint: selectedFilmStock.accent,
                isAutomatic: false,
                isLocked: isCompensationLocked,
                onLockToggle: {
                    isCompensationLocked.toggle()
                    DialHaptics.shared.impact()
                }
            ) { newIndex in
                compensationIndex = newIndex
            }
        }
        .meterPanel()
    }

    private var filmStockMenu: some View {
        Button {
            presentedSheet = .filmStocks
            DialHaptics.shared.impact()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    selectedFilmStock.accent,
                                    selectedFilmStock.accent.opacity(0.62),
                                    Color.black.opacity(0.72)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 58, height: 58)

                    Image(systemName: "film.stack.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedFilmStock.shortName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(selectedFilmStock.displayName)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(T("选择胶卷", "Select Film Stock"))
    }

    private var cameraSetupCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(T("相机与镜头", "Camera & Lens"))
                .font(.headline)
                .foregroundStyle(.primary)

            Picker(T("画幅", "Format"), selection: $sensor) {
                ForEach(CameraSensorFormat.allCases) { format in
                    Text(format.displayTitle).tag(format)
                }
            }
            .pickerStyle(.segmented)

            HorizontalExposureDial(
                title: T("镜头焦距", "Focal Length"),
                subtitle: T("用于估算星点不拖线的最长快门", "Used to estimate the longest shutter before star trailing"),
                options: ExposureScales.focalLengths,
                selectedIndex: focalLengthIndex,
                tint: accentColor,
                isAutomatic: false
            ) { newIndex in
                focalLengthIndex = newIndex
            }
        }
        .meterPanel()
    }

    private var filmRecommendationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(T("胶片推荐曝光", "Film Exposure Recommendation"), systemImage: "timer.circle")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text(filmSolution.isWithinOfficialRange ? T("官方范围", "Official Range") : T("通用估计", "General Estimate"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(filmSolution.isWithinOfficialRange ? .green : .orange)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background((filmSolution.isWithinOfficialRange ? Color.green : Color.orange).opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(spacing: 10) {
                exposureResultTile(
                    title: T("测光快门", "Metered Shutter"),
                    value: CameraExposureCalculator.shutterText(filmSolution.meteredSeconds),
                    icon: "camera.metering.center.weighted"
                )
                exposureResultTile(
                    title: T("倒易律后", "After Reciprocity"),
                    value: filmSolution.correctedSeconds.map(CameraExposureCalculator.shutterText) ?? T("通用估计", "General Estimate"),
                    icon: "film"
                )
                exposureResultTile(
                    title: T("补偿", "Correction"),
                    value: filmSolution.correctionStops.map { String(format: "+%.1fEV", $0) } ?? "--",
                    icon: "plusminus.circle"
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                statusRow(
                    icon: filmSolution.isWithinOfficialRange ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                    color: filmSolution.isWithinOfficialRange ? .green : .orange,
                    title: filmSolution.methodText,
                    detail: filmSolution.warningText ?? T("当前值在所选胶片的官方倒易律数据范围内。", "Current value is within the selected film's official reciprocity data range.")
                )

                if let developmentText = filmSolution.developmentText {
                    statusRow(
                        icon: "drop.degreesign.fill",
                        color: selectedFilmStock.accent,
                        title: T("显影提示", "Development Note"),
                        detail: developmentText
                    )
                }

                statusRow(
                    icon: filmSolution.exceedsStarSafeShutter ? "star.slash.fill" : "star.fill",
                    color: filmSolution.exceedsStarSafeShutter ? .orange : .green,
                    title: filmSolution.exceedsStarSafeShutter ? T("可能出现星点拖线", "Star Trailing Possible") : T("星点拖线风险较低", "Low Star-Trailing Risk"),
                    detail: filmSolution.exceedsStarSafeShutter
                        ? TF("当前倒易律后快门超过约 %@ 的估算安全值，胶片星野建议赤道仪或更短焦距。", "The reciprocity-corrected shutter exceeds the estimated safe value of about %@. For film star fields, use a tracker or a shorter focal length.", CameraExposureCalculator.shutterText(filmSolution.starSafeShutter))
                        : T("当前快门在 300 法则估算范围内。胶片长曝会按所选片种给出倒易律后的通用参考值。", "Current shutter is within the 300-rule estimate. Film long exposure uses the selected stock's reciprocity-adjusted reference.")
                )
            }
        }
        .meterPanel()
    }

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(T("当前曝光参考", "Current Exposure Reference"))
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text(autoParameter.displayTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(accentColor.opacity(0.14))
                    .clipShape(Capsule())
            }

            HStack(spacing: 10) {
                exposureResultTile(
                    title: T("光圈", "Aperture"),
                    value: String(format: "f/%.1f", solution.aperture),
                    icon: "camera.aperture"
                )
                exposureResultTile(
                    title: "ISO",
                    value: "\(solution.iso)",
                    icon: "circle.lefthalf.filled"
                )
                exposureResultTile(
                    title: T("快门", "Shutter"),
                    value: CameraExposureCalculator.shutterText(solution.shutterSeconds),
                    icon: "timer"
                )
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: exposureStatusIcon)
                    .foregroundStyle(exposureStatusColor)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(exposureStatusTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(exposureStatusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(exposureStatusColor.opacity(0.11))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .meterPanel()
    }

    private var stackCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(T("堆栈建议", "Stacking Recommendation"), systemImage: "square.stack.3d.up")
                .font(.headline)
                .foregroundStyle(.primary)

            Text(TF("建议拍摄 %d 张 RAW，每张 %@，间隔 1 秒。另拍 8 到 12 张暗场。", "Shoot %d RAW frames at %@ each with a 1s interval. Also capture 8 to 12 dark frames.", solution.stackCount, CameraExposureCalculator.shutterText(solution.shutterSeconds)))
                .font(.subheadline)
                .foregroundStyle(.primary)

            Text(solution.isStarSafe
                 ? T("当前快门在估算的不拖线范围内。堆栈可降低高 ISO 噪点并保留星点。", "Current shutter is within the estimated non-trailing range. Stacking reduces high-ISO noise while preserving star points.")
                 : TF("当前快门超过约 %@ 的星点安全值，建议提高 ISO、开大光圈或使用赤道仪。", "Current shutter exceeds the star-safe value of about %@. Raise ISO, open aperture, or use a tracker.", CameraExposureCalculator.shutterText(solution.starSafeShutter)))
                .font(.caption)
                .foregroundStyle(solution.isStarSafe ? Color.secondary : Color.orange)
        }
        .meterPanel()
    }

    private func exposureResultTile(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(accentColor)
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func filmInfoPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var meterStatusColor: Color {
        if lockedMeterEV100 != nil { return accentColor }
        if meter.isAdjustingExposure || abs(meter.exposureTargetOffsetEV) > 0.5 { return .orange }
        return meter.isRunning ? .green : .gray
    }

    private var meterStatusText: String {
        if lockedMeterEV100 != nil { return T("亮度已锁定", "Brightness Locked") }
        if meter.isAdjustingExposure { return T("测光稳定中", "Stabilizing Meter") }
        if abs(meter.exposureTargetOffsetEV) > 0.5 {
            return TF("暗场修正 %+.1f EV", "Dark Scene Offset %+.1f EV", meter.exposureTargetOffsetEV)
        }
        return meter.isRunning ? T("实时测光", "Live Metering") : T("未启动", "Not Running")
    }

    private var cameraUnavailableText: String {
        switch meter.authorizationStatus {
        case .denied, .restricted:
            return T("未获得相机权限，可先用下方 EV 拨轮手动估算。", "Camera permission is unavailable. Use the EV dial below for a manual estimate.")
        default:
            return T("正在准备相机测光，也可先手动估算。", "Preparing camera metering. You can also estimate manually first.")
        }
    }

    private var exposureStatusTitle: String {
        if abs(solution.exposureErrorEV) < 0.2 {
            return T("与手机测光基本一致", "Matched to Phone Meter")
        }
        if solution.exposureErrorEV > 0 {
            return TF("当前组合偏暗 %.1f EV", "Current combo is %.1f EV dark", solution.exposureErrorEV)
        }
        return TF("当前组合偏亮 %.1f EV", "Current combo is %.1f EV bright", abs(solution.exposureErrorEV))
    }

    private var exposureStatusDetail: String {
        if abs(solution.exposureErrorEV) < 0.2 {
            return TF("目标 EV100 %.1f，离散档位误差小于 0.2 档。", "Target EV100 %.1f, with less than 0.2 stop of discrete-step error.", solution.targetEV100)
        }
        return autoParameter == .iso
            ? T("ISO 已到可选档位边界，可调整快门或光圈继续匹配。", "ISO reached the available range limit. Adjust shutter or aperture to continue matching.")
            : T("快门已到可选档位边界，可调整 ISO 或光圈继续匹配。", "Shutter reached the available range limit. Adjust ISO or aperture to continue matching.")
    }

    private var exposureStatusIcon: String {
        abs(solution.exposureErrorEV) < 0.2 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var exposureStatusColor: Color {
        abs(solution.exposureErrorEV) < 0.2 ? .green : .orange
    }

    private func toggleMeterLock() {
        if lockedMeterEV100 == nil {
            lockedMeterEV100 = meter.measuredEV100
        } else {
            lockedMeterEV100 = nil
        }
        DialHaptics.shared.impact()
        recalculateAutomaticParameter()
    }

    private func recalculateAutomaticParameter() {
        let newSolution = solution
        switch autoParameter {
        case .iso:
            isoIndex = ExposureScales.nearestIndex(
                in: ExposureScales.isos,
                to: Double(newSolution.iso)
            )
        case .shutter:
            shutterIndex = ExposureScales.nearestIndex(
                in: ExposureScales.shutters,
                to: newSolution.shutterSeconds
            )
        }
    }
}

private struct CaptureModeOptionButton: View {
    let mode: CameraCaptureMode
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? tint : Color.primary.opacity(0.07))
                        .frame(width: 40, height: 40)

                    Image(systemName: mode.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(mode.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(isSelected ? tint.opacity(0.15) : Color(uiColor: .secondarySystemBackground).opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.45) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.displayTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct FilmStockPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedIndex: Int

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(FilmStock.catalog.indices, id: \.self) { index in
                            let stock = FilmStock.catalog[index]
                            FilmStockPickerRow(
                                stock: stock,
                                isSelected: index == selectedIndex
                            ) {
                                selectedIndex = index
                                DialHaptics.shared.impact()
                                dismiss()
                            }
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo(selectedIndex, anchor: .center)
                    }
                }
            }
            .navigationTitle(T("选择胶卷", "Select Film Stock"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(T("完成", "Done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct FilmStockPickerRow: View {
    let stock: FilmStock
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    stock.accent,
                                    stock.accent.opacity(0.58),
                                    Color.black.opacity(0.70)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)

                    Image(systemName: "film.stack.fill")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(stock.shortName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("ISO \(stock.speedISO)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(stock.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(stock.accent.opacity(0.14))
                            .clipShape(Capsule())
                    }

                    Text(stock.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(stock.localizedSourceSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? stock.accent : Color.secondary.opacity(0.45))
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? stock.accent.opacity(0.45) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(TF("%@，ISO %d", "%@, ISO %d", stock.displayName, stock.speedISO))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct HorizontalExposureDial: View {
    let title: String
    let subtitle: String
    let options: [ExposureDialValue]
    let selectedIndex: Int
    let tint: Color
    let isAutomatic: Bool
    let isLocked: Bool
    let onLockToggle: (() -> Void)?
    let onSelectionChanged: (Int) -> Void

    @State private var dragStartIndex: Int?
    private let tickWidth: CGFloat = 22

    init(
        title: String,
        subtitle: String,
        options: [ExposureDialValue],
        selectedIndex: Int,
        tint: Color,
        isAutomatic: Bool,
        isLocked: Bool = false,
        onLockToggle: (() -> Void)? = nil,
        onSelectionChanged: @escaping (Int) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.options = options
        self.selectedIndex = selectedIndex
        self.tint = tint
        self.isAutomatic = isAutomatic
        self.isLocked = isLocked
        self.onLockToggle = onLockToggle
        self.onSelectionChanged = onSelectionChanged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))

                        if isAutomatic {
                            Text("AUTO")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(tint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(tint.opacity(0.14))
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 9) {
                    Text(options[selectedIndex].label)
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(tint)

                    if let onLockToggle {
                        Button(action: onLockToggle) {
                            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isLocked ? tint : .secondary)
                                .frame(width: 28, height: 28)
                                .background(
                                    isLocked ? tint.opacity(0.14) : Color.primary.opacity(0.06),
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isLocked ? TF("解锁%@", "Unlock %@", title) : TF("锁定%@", "Lock %@", title))
                    }
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.primary.opacity(0.045))

                    HStack(spacing: 0) {
                        ForEach(options) { option in
                            dialTick(option)
                                .frame(width: tickWidth)
                        }
                    }
                    .offset(
                        x: proxy.size.width / 2
                            - tickWidth / 2
                            - CGFloat(selectedIndex) * tickWidth
                    )
                    .animation(.snappy(duration: 0.14), value: selectedIndex)
                    .opacity(isLocked ? 0.55 : 1)

                    LinearGradient(
                        colors: [.black.opacity(0.18), .clear, .clear, .black.opacity(0.18)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .allowsHitTesting(false)
                }
                .clipped()
                .contentShape(Rectangle())
                .allowsHitTesting(!isLocked)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            if dragStartIndex == nil {
                                dragStartIndex = selectedIndex
                                DialHaptics.shared.prepare()
                            }

                            guard let start = dragStartIndex else { return }
                            let stepDelta = Int((-value.translation.width / tickWidth).rounded())
                            let nextIndex = min(max(start + stepDelta, 0), options.count - 1)

                            guard nextIndex != selectedIndex else { return }
                            onSelectionChanged(nextIndex)
                            DialHaptics.shared.selection()
                        }
                        .onEnded { _ in
                            dragStartIndex = nil
                        }
                )
            }
            .frame(height: 72)
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(options[selectedIndex].label)
        .accessibilityAdjustableAction { direction in
            guard !isLocked else { return }
            switch direction {
            case .increment:
                onSelectionChanged(min(selectedIndex + 1, options.count - 1))
            case .decrement:
                onSelectionChanged(max(selectedIndex - 1, 0))
            @unknown default:
                break
            }
            DialHaptics.shared.selection()
        }
    }

    private func dialTick(_ option: ExposureDialValue) -> some View {
        let isSelected = option.id == selectedIndex
        let isMajor = option.tickLabel != nil

        return VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(isSelected ? tint : Color.secondary.opacity(isMajor ? 0.75 : 0.38))
                .frame(width: isSelected ? 3 : 1, height: isSelected ? 31 : (isMajor ? 24 : 15))

            if let tickLabel = option.tickLabel {
                Text(tickLabel)
                    .font(.system(size: 8, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? tint : .secondary)
                    .fixedSize()
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

@MainActor
private final class DialHaptics {
    static let shared = DialHaptics()

    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)

    func prepare() {
        selectionGenerator.prepare()
    }

    func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    func impact() {
        impactGenerator.impactOccurred()
        impactGenerator.prepare()
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

private extension View {
    func meterPanel() -> some View {
        padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
    }
}
