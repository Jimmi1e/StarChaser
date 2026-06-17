//
//  SkyForecastService.swift
//  StarChaser
//
//  Created by Codex on 2026/6/16.
//

import CoreLocation
import Foundation

enum SkyForecastRadius: Int, CaseIterable, Identifiable {
    case km100 = 100

    var id: Int { rawValue }

    var meters: Int {
        rawValue * 1_000
    }

    var title: String {
        "\(rawValue) km"
    }
}

struct SkyForecastSnapshot: Sendable {
    let radius: SkyForecastRadius
    let generatedAt: Date
    let recommendations: [SkyForecastRecommendation]

    var bestRecommendation: SkyForecastRecommendation? {
        recommendations.max(by: { $0.overallScore < $1.overallScore })
    }

    var hasRecommendations: Bool {
        !recommendations.isEmpty
    }
}

struct SkyForecastRecommendation: Identifiable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: Double
    let bortleClass: BortleClass
    let overallScore: Int
    let confidenceLabel: String
    let shortReason: String
    let days: [SkyForecastDay]

    var distanceText: String {
        if distanceMeters >= 10_000 {
            return TF("%.0f km", "%.0f km", distanceMeters / 1_000)
        } else {
            return TF("%.1f km", "%.1f km", distanceMeters / 1_000)
        }
    }

    var bestDay: SkyForecastDay? {
        days.max(by: { $0.score < $1.score })
    }
}

struct SkyForecastDay: Identifiable, Sendable {
    let id: String
    let date: Date
    let score: Int
    let weatherLabel: String
    let recommendationLabel: String
    let cloudCover: Int
    let humidity: Int
    let visibilityKilometers: Double
    let windSpeed: Double
    let precipitationProbability: Int
    let moonIllumination: Int
    let moonPenalty: Int
}

enum SkyForecastServiceError: LocalizedError {
    case missingAMapKey
    case noCandidateSpots
    case invalidWeatherData
    case forecastUnavailable

    var errorDescription: String? {
        switch self {
        case .missingAMapKey:
            return T("缺少高德 Web 服务 Key。", "Missing the AMap Web Service key.")
        case .noCandidateSpots:
            return T("当前范围内未找到合适的观测候选地。", "No suitable observing spots were found in the selected range.")
        case .invalidWeatherData:
            return T("天气数据暂时不可用，请稍后重试。", "Weather data is temporarily unavailable. Please try again later.")
        case .forecastUnavailable:
            return T("附近候选地的数据获取超时，请稍后重试。", "Nearby forecast data timed out. Please try again in a moment.")
        }
    }
}

enum SkyForecastService {
    private static let primaryPOIKeywords = ["观景台", "景区", "露营地"]
    private static let fallbackPOIKeywords = ["山顶", "森林公园", "湖"]
    private static let masterSearchRadius: SkyForecastRadius = .km100
    private static let masterCandidatePoolCount = 72
    private static let fallbackCandidateTriggerCount = 36
    private static let weatherEvaluationCount = 12
    private static let poiPageCount = 2
    private static let poiPageOffset = 20
    private static let forecastDays = 5
    private static let snapshotCacheTTL: TimeInterval = 15 * 60
    private static let poiCacheTTL: TimeInterval = 30 * 60
    private static let weatherCacheTTL: TimeInterval = 20 * 60
    private static let lightPollutionCacheTTL: TimeInterval = 6 * 60 * 60
    private static let cacheStore = SkyForecastCacheStore()

    static func fetchSnapshot(
        for coordinate: CLLocationCoordinate2D,
        radius: SkyForecastRadius
    ) async throws -> SkyForecastSnapshot {
        try Task.checkCancellation()
        _ = radius

        let key = AppSecrets.aMapWebServiceKey
        guard !key.isEmpty else {
            throw SkyForecastServiceError.missingAMapKey
        }

        return try await fetchMasterSnapshot(
            coordinate: coordinate,
            key: key
        )
    }

    private static func fetchMasterSnapshot(
        coordinate: CLLocationCoordinate2D,
        key: String
    ) async throws -> SkyForecastSnapshot {
        let snapshotCacheKey = cacheKey(for: coordinate, radius: masterSearchRadius)
        if let cachedSnapshot = await cacheStore.snapshot(for: snapshotCacheKey) {
            return cachedSnapshot
        }

        let pois = await fetchCandidatePOIs(
            coordinate: coordinate,
            key: key
        )
        try Task.checkCancellation()

        guard !pois.isEmpty else {
            throw SkyForecastServiceError.noCandidateSpots
        }

        let shortlistedCandidates = await shortlistCandidatesForWeather(
            pois,
            radius: masterSearchRadius
        )
        try Task.checkCancellation()

        var recommendations: [SkyForecastRecommendation] = []

        await withTaskGroup(of: SkyForecastRecommendation?.self) { group in
            for poi in shortlistedCandidates {
                group.addTask {
                    guard !Task.isCancelled else { return nil }

                    let reading = await fetchLightPollutionReading(for: poi.coordinate)
                    guard let weather = try? await fetchWeatherForecast(for: poi.coordinate) else {
                        return nil
                    }
                    guard !Task.isCancelled else { return nil }

                    return buildRecommendation(
                        poi: poi,
                        lightPollution: reading,
                        weather: weather
                    )
                }
            }

            for await recommendation in group {
                guard let recommendation else { continue }
                recommendations.append(recommendation)
            }
        }

        guard !recommendations.isEmpty else {
            throw SkyForecastServiceError.forecastUnavailable
        }

        recommendations.sort { lhs, rhs in
            if lhs.overallScore == rhs.overallScore {
                return lhs.distanceMeters < rhs.distanceMeters
            }
            return lhs.overallScore > rhs.overallScore
        }

        let snapshot = SkyForecastSnapshot(
            radius: masterSearchRadius,
            generatedAt: Date(),
            recommendations: recommendations
        )

        await cacheStore.storeSnapshot(
            snapshot,
            for: snapshotCacheKey,
            ttl: snapshotCacheTTL
        )

        return snapshot
    }

    private static func fetchCandidatePOIs(
        coordinate: CLLocationCoordinate2D,
        key: String
    ) async -> [SkyForecastPOI] {
        let masterPOICacheKey = cacheKey(for: coordinate, radius: masterSearchRadius)
        if let cachedMasterPOIs = await cacheStore.pois(for: masterPOICacheKey) {
            return cachedMasterPOIs
        }

        let fetchedMasterPOIs = await fetchMasterCandidatePOIs(
            coordinate: coordinate,
            key: key
        )
        await cacheStore.storePOIs(
            fetchedMasterPOIs,
            for: masterPOICacheKey,
            ttl: poiCacheTTL
        )
        return fetchedMasterPOIs
    }

    private static func fetchMasterCandidatePOIs(
        coordinate: CLLocationCoordinate2D,
        key: String
    ) async -> [SkyForecastPOI] {
        var collected = await fetchPOIs(
            for: primaryPOIKeywords,
            coordinate: coordinate,
            radius: masterSearchRadius,
            key: key
        )

        var deduped = dedupeAndSortPOIs(collected)
        if deduped.count < fallbackCandidateTriggerCount {
            let fallbackPOIs = await fetchPOIs(
                for: fallbackPOIKeywords,
                coordinate: coordinate,
                radius: masterSearchRadius,
                key: key
            )
            collected.append(contentsOf: fallbackPOIs)
            deduped = dedupeAndSortPOIs(collected)
        }

        return Array(deduped.prefix(masterCandidatePoolCount))
    }

    private static func fetchPOIs(
        for keywords: [String],
        coordinate: CLLocationCoordinate2D,
        radius: SkyForecastRadius,
        key: String
    ) async -> [SkyForecastPOI] {
        var collected: [SkyForecastPOI] = []

        await withTaskGroup(of: [SkyForecastPOI].self) { group in
            for keyword in keywords {
                for page in 1...poiPageCount {
                    group.addTask {
                        guard !Task.isCancelled else { return [] }
                        return (try? await fetchAroundPOIs(
                            coordinate: coordinate,
                            radius: radius,
                            keyword: keyword,
                            page: page,
                            key: key
                        )) ?? []
                    }
                }
            }

            for await result in group {
                collected.append(contentsOf: result)
            }
        }

        return collected
    }

    private static func fetchAroundPOIs(
        coordinate: CLLocationCoordinate2D,
        radius: SkyForecastRadius,
        keyword: String,
        page: Int,
        key: String
    ) async throws -> [SkyForecastPOI] {
        var components = URLComponents(string: "https://restapi.amap.com/v3/place/around")!
        components.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(
                name: "location",
                value: String(format: "%.6f,%.6f", coordinate.longitude, coordinate.latitude)
            ),
            URLQueryItem(name: "radius", value: "\(radius.meters)"),
            URLQueryItem(name: "keywords", value: keyword),
            URLQueryItem(name: "offset", value: "\(poiPageOffset)"),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "extensions", value: "all")
        ]

        let request = URLRequest(url: components.url!, timeoutInterval: 8)
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(AMapPOIAroundResponse.self, from: data)

        let isSuccess = response.status == "1" || response.infocode == "10000"
        guard isSuccess else {
            return []
        }

        return response.pois.compactMap { poi in
            guard
                let coordinate = poi.locationCoordinate,
                let distance = Double(poi.distance ?? "")
            else {
                return nil
            }

            return SkyForecastPOI(
                id: poi.id ?? UUID().uuidString,
                name: poi.name ?? "",
                subtitle: [poi.cityname, poi.adname].compactMap { $0 }.joined(separator: " · "),
                adcode: poi.adcode ?? "",
                coordinate: coordinate,
                distanceMeters: distance
            )
        }
    }

    private static func fetchWeatherForecast(
        for coordinate: CLLocationCoordinate2D
    ) async throws -> OpenMeteoForecastResponse {
        try Task.checkCancellation()

        let weatherCacheKey = cacheKey(for: coordinate)
        if let cachedWeather = await cacheStore.weather(for: weatherCacheKey) {
            return cachedWeather
        }

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: "\(coordinate.latitude)"),
            URLQueryItem(name: "longitude", value: "\(coordinate.longitude)"),
            URLQueryItem(
                name: "hourly",
                value: [
                    "cloud_cover",
                    "relative_humidity_2m",
                    "visibility",
                    "wind_speed_10m",
                    "precipitation_probability",
                    "weather_code",
                    "is_day"
                ].joined(separator: ",")
            ),
            URLQueryItem(name: "forecast_days", value: "\(forecastDays)"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        let request = URLRequest(url: components.url!, timeoutInterval: 8)
        let (data, _) = try await URLSession.shared.data(for: request)
        do {
            let weather = try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: data)
            await cacheStore.storeWeather(
                weather,
                for: weatherCacheKey,
                ttl: weatherCacheTTL
            )
            return weather
        } catch {
            throw SkyForecastServiceError.invalidWeatherData
        }
    }

    private static func fetchLightPollutionReading(
        for coordinate: CLLocationCoordinate2D
    ) async -> LightPollutionReading {
        let lightPollutionCacheKey = cacheKey(for: coordinate, precision: 4)
        if let cachedReading = await cacheStore.lightPollution(for: lightPollutionCacheKey) {
            return cachedReading
        }

        let reading = await LightPollutionService.fetchReading(for: coordinate)
        await cacheStore.storeLightPollution(
            reading,
            for: lightPollutionCacheKey,
            ttl: lightPollutionCacheTTL
        )
        return reading
    }

    private static func buildRecommendation(
        poi: SkyForecastPOI,
        lightPollution: LightPollutionReading,
        weather: OpenMeteoForecastResponse
    ) -> SkyForecastRecommendation {
        let forecastTimeZone = TimeZone(identifier: weather.timezone) ?? .autoupdatingCurrent
        let calendar = Calendar.autoupdatingCurrent
        let groupedHours = Dictionary(grouping: zipHourlyForecast(weather.hourly, timeZone: forecastTimeZone)) {
            calendar.startOfDay(for: $0.time)
        }

        let dailyForecasts = groupedHours.keys.sorted().prefix(forecastDays).compactMap { date in
            buildDayForecast(
                date: date,
                hours: groupedHours[date] ?? [],
                coordinate: poi.coordinate,
                bortle: lightPollution.bortleClass
            )
        }

        let scoreTotal = dailyForecasts.reduce(0) { partialResult, day in
            partialResult + day.score
        }
        let scoreCount = max(dailyForecasts.count, 1)
        let overallScore = Int(round(Double(scoreTotal) / Double(scoreCount)))
        let confidenceLabel = T("5 天预报", "5-day forecast")
        let shortReason = buildShortReason(
            bortle: lightPollution.bortleClass,
            bestDay: dailyForecasts.max(by: { $0.score < $1.score })
        )

        return SkyForecastRecommendation(
            id: poi.id,
            name: poi.name,
            subtitle: poi.subtitle,
            coordinate: poi.coordinate,
            distanceMeters: poi.distanceMeters,
            bortleClass: lightPollution.bortleClass,
            overallScore: overallScore,
            confidenceLabel: confidenceLabel,
            shortReason: shortReason,
            days: dailyForecasts
        )
    }

    private static func buildDayForecast(
        date: Date,
        hours: [OpenMeteoHourlyPoint],
        coordinate: CLLocationCoordinate2D,
        bortle: BortleClass
    ) -> SkyForecastDay {
        let nightHours = hours.filter { point in
            point.isDay == 0
        }
        let workingHours = nightHours.isEmpty ? hours : nightHours

        let cloud = average(of: workingHours.map(\.cloudCover))
        let humidity = average(of: workingHours.map(\.humidity))
        let visibilityMeters = average(of: workingHours.map(\.visibility))
        let windSpeed = average(of: workingHours.map(\.windSpeed))
        let rainProbability = average(of: workingHours.map(\.precipitationProbability))

        let moon = AstroCalculator.calculate(
            at: coordinate,
            hoursOffset: hoursOffset(from: date)
        )
        let moonIllumination = Int((moon.illumination * 100).rounded())
        let moonPenalty = moonPenalty(illumination: moonIllumination, altitude: moon.altitude)

        let darknessScore = max(0, 100 - (bortle.rawValue - 1) * 10)
        let cloudScore = max(0, 100 - cloud)
        let humidityScore = max(0, 100 - max(humidity - 38, 0))
        let visibilityScore = min(100, Int((visibilityMeters / 18_000) * 100))
        let windScore = max(0, 100 - Int(windSpeed * 4))
        let rainScore = max(0, 100 - rainProbability)
        let lunarScore = max(0, 100 - moonPenalty)

        let weightedScore = Double(darknessScore) * 0.48
            + Double(cloudScore) * 0.22
            + Double(lunarScore) * 0.16
            + Double(humidityScore) * 0.06
            + Double(visibilityScore) * 0.04
            + Double(windScore) * 0.04
            + Double(rainScore) * 0.00

        let finalScore = max(1, min(99, Int(weightedScore.rounded())))
        let label = nightlyLabel(score: finalScore)
        let weatherLabel = weatherSummary(
            cloud: cloud,
            humidity: humidity,
            visibilityMeters: visibilityMeters,
            moonIllumination: moonIllumination
        )

        return SkyForecastDay(
            id: ISO8601DateFormatter().string(from: date),
            date: date,
            score: finalScore,
            weatherLabel: weatherLabel,
            recommendationLabel: label,
            cloudCover: cloud,
            humidity: humidity,
            visibilityKilometers: visibilityMeters / 1_000,
            windSpeed: windSpeed,
            precipitationProbability: rainProbability,
            moonIllumination: moonIllumination,
            moonPenalty: moonPenalty
        )
    }

    private static func zipHourlyForecast(
        _ hourly: OpenMeteoHourlyResponse,
        timeZone: TimeZone
    ) -> [OpenMeteoHourlyPoint] {
        hourly.time.indices.compactMap { index in
            guard let parsedTime = parseOpenMeteoDate(hourly.time[index], timeZone: timeZone) else {
                return nil
            }

            return OpenMeteoHourlyPoint(
                time: parsedTime,
                cloudCover: safeInt(hourly.cloudCover, index: index),
                humidity: safeInt(hourly.relativeHumidity2M, index: index),
                visibility: safeDouble(hourly.visibility, index: index),
                windSpeed: safeDouble(hourly.windSpeed10M, index: index),
                precipitationProbability: safeInt(hourly.precipitationProbability, index: index),
                weatherCode: safeInt(hourly.weatherCode, index: index),
                isDay: safeInt(hourly.isDay, index: index)
            )
        }
    }

    private static func parseOpenMeteoDate(_ rawValue: String, timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.date(from: rawValue)
    }

    private static func shortlistCandidatesForWeather(
        _ candidates: [SkyForecastPOI],
        radius: SkyForecastRadius
    ) async -> [SkyForecastPOI] {
        await withTaskGroup(of: (SkyForecastPOI, Double)?.self, returning: [SkyForecastPOI].self) { group in
            for candidate in candidates {
                group.addTask {
                    guard !Task.isCancelled else { return nil }
                    let reading = await fetchLightPollutionReading(for: candidate.coordinate)
                    let score = preliminaryCandidateScore(
                        poi: candidate,
                        bortleClass: reading.bortleClass,
                        radius: radius
                    )
                    return (candidate, score)
                }
            }

            var ranked: [(SkyForecastPOI, Double)] = []
            for await result in group {
                guard let result else { continue }
                ranked.append(result)
            }

            ranked.sort { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.distanceMeters < rhs.0.distanceMeters
                }
                return lhs.1 > rhs.1
            }

            return Array(ranked.prefix(weatherEvaluationCount).map(\.0))
        }
    }

    private static func preliminaryCandidateScore(
        poi: SkyForecastPOI,
        bortleClass: BortleClass,
        radius: SkyForecastRadius
    ) -> Double {
        let darknessScore = max(0, 100 - (bortleClass.rawValue - 1) * 12)
        let normalizedDistance = min(max(poi.distanceMeters / Double(radius.meters), 0), 1)
        let distanceScore = max(0, 100 - Int(normalizedDistance * 45))
        return Double(darknessScore) * 0.78 + Double(distanceScore) * 0.22
    }

    private static func dedupeAndSortPOIs(_ pois: [SkyForecastPOI]) -> [SkyForecastPOI] {
        var deduped: [String: SkyForecastPOI] = [:]
        for poi in pois {
            let stableID = poi.id.isEmpty ? "\(poi.name)-\(poi.coordinate.latitude)-\(poi.coordinate.longitude)" : poi.id
            if let existing = deduped[stableID] {
                if poi.distanceMeters < existing.distanceMeters {
                    deduped[stableID] = poi
                }
            } else {
                deduped[stableID] = poi
            }
        }

        return deduped.values
            .filter { !$0.name.isEmpty }
            .sorted(by: { $0.distanceMeters < $1.distanceMeters })
    }

    private static func safeInt(_ values: [Int], index: Int) -> Int {
        guard values.indices.contains(index) else { return 0 }
        return values[index]
    }

    private static func safeDouble(_ values: [Double], index: Int) -> Double {
        guard values.indices.contains(index) else { return 0 }
        return values[index]
    }

    private static func average(of values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        return Int(round(Double(values.reduce(0, +)) / Double(values.count)))
    }

    private static func average(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func hoursOffset(from date: Date) -> Double {
        date.timeIntervalSinceNow / 3600
    }

    private static func moonPenalty(illumination: Int, altitude: Double) -> Int {
        let altitudeFactor = altitude > 5 ? 1.0 : 0.45
        return Int(Double(illumination) * altitudeFactor)
    }

    private static func nightlyLabel(score: Int) -> String {
        switch score {
        case 82...:
            return T("强烈推荐", "Highly Recommended")
        case 68...81:
            return T("推荐观测", "Recommended")
        case 52...67:
            return T("条件一般", "Moderate")
        default:
            return T("今晚不建议", "Not Recommended")
        }
    }

    private static func weatherSummary(
        cloud: Int,
        humidity: Int,
        visibilityMeters: Double,
        moonIllumination: Int
    ) -> String {
        TF(
            "云量 %d%% · 湿度 %d%% · 能见度 %.0f km · 月相 %d%%",
            "Cloud %d%% · Humidity %d%% · Visibility %.0f km · Moon %d%%",
            cloud,
            humidity,
            visibilityMeters / 1_000,
            moonIllumination
        )
    }

    private static func buildShortReason(
        bortle: BortleClass,
        bestDay: SkyForecastDay?
    ) -> String {
        guard let bestDay else {
            return bortle.title
        }

        return TF(
            "%@，%@。%@",
            "%@ with %@. %@",
            bortle.title,
            bestDay.weatherLabel,
            forecastAdvice(for: bortle)
        )
    }

    private static func forecastAdvice(for bortle: BortleClass) -> String {
        switch bortle {
        case .class1:
            return T(
                "极适合银河、星野和深空目标，可优先安排长时间拍摄。",
                "Excellent for the Milky Way, wide-field stars, and deep-sky targets; prioritize longer sessions."
            )
        case .class2:
            return T(
                "非常适合银河和星野，夏季银河核心细节通常会很丰富。",
                "Very good for Milky Way and wide-field work; the summer core should show strong structure."
            )
        case .class3:
            return T(
                "适合银河主体和星野，建议避开低空城市光穹方向。",
                "Good for the main Milky Way band and wide-field shots; avoid low urban skyglow."
            )
        case .class4:
            return T(
                "可拍银河和星野，但细节会下降，建议选择无月夜并增加堆栈。",
                "Usable for Milky Way and wide-field shots, but detail drops; choose moonless nights and stack more frames."
            )
        case .class5:
            return T(
                "光害明显，银河只适合通透无月夜尝试；更适合星座、星轨和亮目标。",
                "Noticeable light pollution; try the Milky Way only on transparent moonless nights. Constellations, star trails, and bright targets are safer."
            )
        case .class6:
            return T(
                "不建议作为银河主拍地点，适合月亮、行星、亮星团或城市星轨。",
                "Not recommended as a primary Milky Way location; better for the Moon, planets, bright clusters, or urban star trails."
            )
        case .class7:
            return T(
                "银河通常很难呈现，推荐值主要代表天气可用；建议转向月亮、行星和亮目标。",
                "The Milky Way is usually hard to render; the score mostly means the weather is usable. Favor the Moon, planets, and bright targets."
            )
        case .class8:
            return T(
                "城市天光很强，不推荐银河或普通星野；可考虑月亮、行星和城市夜景星轨。",
                "Urban skyglow is strong; avoid Milky Way and general wide-field work. Consider the Moon, planets, or city star trails."
            )
        case .class9:
            return T(
                "市中心级光害，不适合银河和星野观测，推荐仅作为亮目标拍摄参考。",
                "City-center light pollution; not suitable for Milky Way or wide-field observing, useful mainly for bright-target planning."
            )
        }
    }

    private static func cacheKey(
        for coordinate: CLLocationCoordinate2D,
        radius: SkyForecastRadius? = nil,
        precision: Int = 3
    ) -> String {
        let coordinateKey = [
            coordinate.latitude.rounded(toPlaces: precision),
            coordinate.longitude.rounded(toPlaces: precision)
        ]
        .map { String($0) }
        .joined(separator: ",")

        if let radius {
            return "\(radius.rawValue)-\(coordinateKey)"
        }
        return coordinateKey
    }
}

private struct SkyForecastPOI: Sendable {
    let id: String
    let name: String
    let subtitle: String
    let adcode: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: Double
}

private struct OpenMeteoHourlyPoint: Sendable {
    let time: Date
    let cloudCover: Int
    let humidity: Int
    let visibility: Double
    let windSpeed: Double
    let precipitationProbability: Int
    let weatherCode: Int
    let isDay: Int
}

private struct AMapPOIAroundResponse: Decodable {
    let status: String?
    let infocode: String?
    let pois: [AMapPOI]

    enum CodingKeys: String, CodingKey {
        case status
        case infocode
        case pois
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        infocode = try container.decodeIfPresent(String.self, forKey: .infocode)
        pois = try container.decodeIfPresent([AMapPOI].self, forKey: .pois) ?? []
    }
}

private struct AMapPOI: Decodable {
    let id: String?
    let name: String?
    let adcode: String?
    let adname: String?
    let cityname: String?
    let location: String?
    let distance: String?

    var locationCoordinate: CLLocationCoordinate2D? {
        guard let location else { return nil }
        let components = location.split(separator: ",")
        guard components.count == 2,
              let longitude = Double(components[0]),
              let latitude = Double(components[1]) else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct OpenMeteoForecastResponse: Decodable, Sendable {
    let timezone: String
    let hourly: OpenMeteoHourlyResponse
}

private struct OpenMeteoHourlyResponse: Decodable, Sendable {
    let time: [String]
    let cloudCover: [Int]
    let relativeHumidity2M: [Int]
    let visibility: [Double]
    let windSpeed10M: [Double]
    let precipitationProbability: [Int]
    let weatherCode: [Int]
    let isDay: [Int]

    enum CodingKeys: String, CodingKey {
        case time
        case cloudCover = "cloud_cover"
        case relativeHumidity2M = "relative_humidity_2m"
        case visibility
        case windSpeed10M = "wind_speed_10m"
        case precipitationProbability = "precipitation_probability"
        case weatherCode = "weather_code"
        case isDay = "is_day"
    }
}

private actor SkyForecastCacheStore {
    private struct CacheEntry<Value> {
        let value: Value
        let expiryDate: Date

        var isValid: Bool {
            expiryDate > Date()
        }
    }

    private var snapshots: [String: CacheEntry<SkyForecastSnapshot>] = [:]
    private var poiCollections: [String: CacheEntry<[SkyForecastPOI]>] = [:]
    private var weatherForecasts: [String: CacheEntry<OpenMeteoForecastResponse>] = [:]
    private var lightPollutionReadings: [String: CacheEntry<LightPollutionReading>] = [:]

    func snapshot(for key: String) -> SkyForecastSnapshot? {
        value(for: key, storage: &snapshots)
    }

    func storeSnapshot(_ snapshot: SkyForecastSnapshot, for key: String, ttl: TimeInterval) {
        snapshots[key] = CacheEntry(value: snapshot, expiryDate: Date().addingTimeInterval(ttl))
    }

    func pois(for key: String) -> [SkyForecastPOI]? {
        value(for: key, storage: &poiCollections)
    }

    func storePOIs(_ pois: [SkyForecastPOI], for key: String, ttl: TimeInterval) {
        poiCollections[key] = CacheEntry(value: pois, expiryDate: Date().addingTimeInterval(ttl))
    }

    func weather(for key: String) -> OpenMeteoForecastResponse? {
        value(for: key, storage: &weatherForecasts)
    }

    func storeWeather(_ weather: OpenMeteoForecastResponse, for key: String, ttl: TimeInterval) {
        weatherForecasts[key] = CacheEntry(value: weather, expiryDate: Date().addingTimeInterval(ttl))
    }

    func lightPollution(for key: String) -> LightPollutionReading? {
        value(for: key, storage: &lightPollutionReadings)
    }

    func storeLightPollution(_ reading: LightPollutionReading, for key: String, ttl: TimeInterval) {
        lightPollutionReadings[key] = CacheEntry(value: reading, expiryDate: Date().addingTimeInterval(ttl))
    }

    private func value<Value>(
        for key: String,
        storage: inout [String: CacheEntry<Value>]
    ) -> Value? {
        guard let entry = storage[key] else { return nil }
        guard entry.isValid else {
            storage[key] = nil
            return nil
        }
        return entry.value
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
