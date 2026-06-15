//
//  LightPollutionService.swift
//  StarChaser
//
//  Created by Jiaxi on 2026/6/11.
//

import CoreLocation
import SwiftUI
import UIKit

enum BortleClass: Int, CaseIterable, Sendable {
    case class1 = 1
    case class2 = 2
    case class3 = 3
    case class4 = 4
    case class5 = 5
    case class6 = 6
    case class7 = 7
    case class8 = 8
    case class9 = 9

    var color: Color {
        switch self {
        case .class1: return Color(red: 0.03, green: 0.05, blue: 0.10)
        case .class2: return Color(red: 0.08, green: 0.25, blue: 0.56)
        case .class3: return Color(red: 0.00, green: 0.58, blue: 0.72)
        case .class4: return Color(red: 0.18, green: 0.66, blue: 0.18)
        case .class5: return Color(red: 0.96, green: 0.88, blue: 0.05)
        case .class6: return Color(red: 1.00, green: 0.54, blue: 0.04)
        case .class7: return Color(red: 1.00, green: 0.20, blue: 0.04)
        case .class8: return Color(red: 0.92, green: 0.02, blue: 0.08)
        case .class9: return Color(red: 0.72, green: 0.08, blue: 0.92)
        }
    }

    var title: String { "Bortle \(rawValue) 级 · \(description)" }

    var description: String {
        switch self {
        case .class1: return "极佳暗空"
        case .class2: return "典型暗空"
        case .class3: return "乡村星空"
        case .class4: return "乡村/郊区过渡"
        case .class5: return "郊区星空"
        case .class6: return "明亮郊区"
        case .class7: return "城市边缘"
        case .class8: return "城市星空"
        case .class9: return "市中心"
        }
    }

    var approximateSQM: String {
        switch self {
        case .class1: return "约 21.9–22.0"
        case .class2: return "约 21.7–21.9"
        case .class3: return "约 21.3–21.7"
        case .class4: return "约 20.4–21.3"
        case .class5: return "约 19.5–20.4"
        case .class6: return "约 18.9–19.5"
        case .class7: return "约 18.3–18.9"
        case .class8: return "约 17.5–18.3"
        case .class9: return "低于 17.5"
        }
    }

    var astrophotographyAdvice: String {
        switch self {
        case .class1, .class2:
            return "理想环境。适合银河、星野与深空目标，可延长单张曝光并减少堆栈张数。"
        case .class3, .class4:
            return "良好环境。银河主体清晰，注意避开地平线方向的城市光穹。"
        case .class5, .class6:
            return "光害明显。建议缩短单张曝光、增加堆栈，并在后期做渐变与色偏校正。"
        case .class7, .class8, .class9:
            return "背景天光很亮。优先拍摄月亮、行星或亮星团；深空摄影建议使用窄带滤镜。"
        }
    }

    var milkyWayVisibility: String {
        switch self {
        case .class1: return "非常清晰，可见复杂暗星云结构。"
        case .class2: return "清晰，夏季银河核心层次丰富。"
        case .class3: return "清晰，但近地平线细节开始减弱。"
        case .class4: return "天顶可见，内部结构较少。"
        case .class5: return "仅在通透无月夜的天顶方向隐约可见。"
        case .class6: return "很难辨认，需要优秀天气与暗适应。"
        case .class7, .class8, .class9: return "通常无法用肉眼辨认。"
        }
    }
}

struct LightPollutionReading: Sendable {
    enum Source: Sendable {
        case satellite2025
        case offlineEstimate

        var title: String {
            switch self {
            case .satellite2025: return "2025 天空亮度图"
            case .offlineEstimate: return "离线城市距离估算"
            }
        }
    }

    let bortleClass: BortleClass
    let source: Source
}

enum LightPollutionService {
    static let maximumZoom = 9

    static let tileURLTemplate =
        "https://www.lightpollutionmap.info/geoserver/gwc/service/tms/1.0.0/" +
        "PostGIS%3ASB_2025@EPSG%3A900913@png/{z}/{x}/{y}.png"

    private static let sampleZoom = 8
    private static let tileCache = NSCache<NSString, UIImage>()
    private static let primaryHost = "www.lightpollutionmap.info"
    private static let backupHost = "www2.lightpollutionmap.info"

    static func fetchReading(for coordinate: CLLocationCoordinate2D) async -> LightPollutionReading {
        let position = tilePosition(for: coordinate, zoom: sampleZoom)

        do {
            try Task.checkCancellation()
            let image = try await fetchTile(x: position.x, y: position.y, zoom: sampleZoom)
            try Task.checkCancellation()

            guard let color = pixelColor(
                image: image,
                x: position.pixelX,
                y: position.pixelY
            ) else {
                throw URLError(.cannotDecodeContentData)
            }

            return LightPollutionReading(
                bortleClass: mapColorToBortle(color),
                source: .satellite2025
            )
        } catch is CancellationError {
            return LightPollutionReading(
                bortleClass: calculateBortleClassFallback(for: coordinate),
                source: .offlineEstimate
            )
        } catch {
            return LightPollutionReading(
                bortleClass: calculateBortleClassFallback(for: coordinate),
                source: .offlineEstimate
            )
        }
    }

    private static func fetchTile(x: Int, y: Int, zoom: Int) async throws -> UIImage {
        let cacheKey = "\(zoom)/\(x)/\(y)" as NSString
        if let cached = tileCache.object(forKey: cacheKey) {
            return cached
        }

        var lastError: Error = URLError(.cannotLoadFromNetwork)
        for host in [primaryHost, backupHost] {
            guard let url = tileURL(host: host, x: x, y: y, zoom: zoom) else { continue }

            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 6
                request.cachePolicy = .returnCacheDataElseLoad
                request.setValue("StarChaser/1.0 iOS", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await URLSession.shared.data(for: request)
                guard
                    let httpResponse = response as? HTTPURLResponse,
                    httpResponse.statusCode == 200,
                    let image = UIImage(data: data)
                else {
                    throw URLError(.badServerResponse)
                }

                tileCache.setObject(image, forKey: cacheKey, cost: data.count)
                return image
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    private static func tileURL(host: String, x: Int, y: Int, zoom: Int) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        let tmsY = (1 << zoom) - 1 - y
        components.percentEncodedPath =
            "/geoserver/gwc/service/tms/1.0.0/" +
            "PostGIS%3ASB_2025@EPSG%3A900913@png/\(zoom)/\(x)/\(tmsY).png"
        return components.url
    }

    private static func tilePosition(
        for coordinate: CLLocationCoordinate2D,
        zoom: Int
    ) -> (x: Int, y: Int, pixelX: Int, pixelY: Int) {
        let tileCount = pow(2.0, Double(zoom))
        let longitude = min(max(coordinate.longitude, -180), 180)
        let latitude = min(max(coordinate.latitude, -85.05112878), 85.05112878)
        let latitudeRadians = latitude * .pi / 180

        let exactX = tileCount * ((longitude + 180) / 360)
        let exactY = tileCount * (1 - asinh(tan(latitudeRadians)) / .pi) / 2
        let x = min(max(Int(floor(exactX)), 0), Int(tileCount) - 1)
        let y = min(max(Int(floor(exactY)), 0), Int(tileCount) - 1)

        return (
            x,
            y,
            min(max(Int((exactX - floor(exactX)) * 256), 0), 255),
            min(max(Int((exactY - floor(exactY)) * 256), 0), 255)
        )
    }

    private static func pixelColor(image: UIImage, x: Int, y: Int) -> UIColor? {
        guard
            let cgImage = image.cgImage,
            x >= 0, x < cgImage.width,
            y >= 0, y < cgImage.height,
            let pixel = cgImage.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))
        else {
            return nil
        }

        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &bytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let alpha = max(CGFloat(bytes[3]) / 255, 0.001)
        return UIColor(
            red: min(CGFloat(bytes[0]) / 255 / alpha, 1),
            green: min(CGFloat(bytes[1]) / 255 / alpha, 1),
            blue: min(CGFloat(bytes[2]) / 255 / alpha, 1),
            alpha: alpha
        )
    }

    private static func mapColorToBortle(_ color: UIColor) -> BortleClass {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        if alpha < 0.05 {
            return .class1
        }

        let saturation = max(red, green, blue) - min(red, green, blue)
        if saturation < 0.09 {
            let brightness = (red + green + blue) / 3
            if brightness > 0.78 { return .class9 }
            if brightness > 0.36 { return .class2 }
            return .class1
        }

        let palette: [(BortleClass, CGFloat, CGFloat, CGFloat)] = [
            (.class1, 0.02, 0.02, 0.03),
            (.class2, 0.12, 0.18, 0.45),
            (.class3, 0.00, 0.55, 0.78),
            (.class4, 0.16, 0.62, 0.04),
            (.class5, 0.93, 0.88, 0.00),
            (.class6, 1.00, 0.48, 0.00),
            (.class7, 1.00, 0.16, 0.00),
            (.class8, 0.92, 0.00, 0.03),
            (.class9, 0.84, 0.18, 0.92)
        ]

        return palette.min { lhs, rhs in
            colorDistance(red: red, green: green, blue: blue, target: lhs)
                < colorDistance(red: red, green: green, blue: blue, target: rhs)
        }?.0 ?? .class5
    }

    private static func colorDistance(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        target: (BortleClass, CGFloat, CGFloat, CGFloat)
    ) -> CGFloat {
        let redDelta = red - target.1
        let greenDelta = green - target.2
        let blueDelta = blue - target.3
        return redDelta * redDelta + greenDelta * greenDelta + blueDelta * blueDelta
    }

    private static let majorCities: [CLLocationCoordinate2D] = [
        .init(latitude: 39.9042, longitude: 116.4074), // 北京
        .init(latitude: 31.2304, longitude: 121.4737), // 上海
        .init(latitude: 23.1291, longitude: 113.2644), // 广州
        .init(latitude: 22.5431, longitude: 114.0579), // 深圳
        .init(latitude: 39.3434, longitude: 117.3616), // 天津
        .init(latitude: 29.5630, longitude: 106.5516), // 重庆
        .init(latitude: 30.5728, longitude: 104.0668), // 成都
        .init(latitude: 30.5928, longitude: 114.3055), // 武汉
        .init(latitude: 34.3416, longitude: 108.9398), // 西安
        .init(latitude: 34.7466, longitude: 113.6253), // 郑州
        .init(latitude: 30.2741, longitude: 120.1551), // 杭州
        .init(latitude: 32.0603, longitude: 118.7969), // 南京
        .init(latitude: 31.2989, longitude: 120.5853), // 苏州
        .init(latitude: 28.2282, longitude: 112.9388), // 长沙
        .init(latitude: 36.0671, longitude: 120.3826), // 青岛
        .init(latitude: 36.6512, longitude: 117.1201), // 济南
        .init(latitude: 41.8057, longitude: 123.4315), // 沈阳
        .init(latitude: 38.9140, longitude: 121.6147), // 大连
        .init(latitude: 45.8038, longitude: 126.5349), // 哈尔滨
        .init(latitude: 43.8171, longitude: 125.3235), // 长春
        .init(latitude: 25.0389, longitude: 102.7183), // 昆明
        .init(latitude: 26.6470, longitude: 106.6302), // 贵阳
        .init(latitude: 22.8170, longitude: 108.3669), // 南宁
        .init(latitude: 26.0745, longitude: 119.2965), // 福州
        .init(latitude: 24.4798, longitude: 118.0894), // 厦门
        .init(latitude: 31.8206, longitude: 117.2272), // 合肥
        .init(latitude: 28.6820, longitude: 115.8579), // 南昌
        .init(latitude: 38.0428, longitude: 114.5149), // 石家庄
        .init(latitude: 37.8706, longitude: 112.5489), // 太原
        .init(latitude: 40.8426, longitude: 111.7492), // 呼和浩特
        .init(latitude: 43.8256, longitude: 87.6168),  // 乌鲁木齐
        .init(latitude: 36.0611, longitude: 103.8343), // 兰州
        .init(latitude: 36.6171, longitude: 101.7782), // 西宁
        .init(latitude: 38.4872, longitude: 106.2309), // 银川
        .init(latitude: 29.6520, longitude: 91.1721),  // 拉萨
        .init(latitude: 20.0440, longitude: 110.1999)  // 海口
    ]

    static func calculateBortleClassFallback(
        for coordinate: CLLocationCoordinate2D
    ) -> BortleClass {
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let minimumDistance = majorCities.reduce(CLLocationDistance.greatestFiniteMagnitude) {
            min(
                $0,
                target.distance(
                    from: CLLocation(latitude: $1.latitude, longitude: $1.longitude)
                )
            )
        }

        if minimumDistance < 12_000 { return .class9 }
        if minimumDistance < 25_000 { return .class8 }
        if minimumDistance < 45_000 { return .class7 }
        if minimumDistance < 70_000 { return .class6 }
        if minimumDistance < 105_000 { return .class5 }
        if minimumDistance < 160_000 { return .class4 }
        if minimumDistance < 240_000 { return .class3 }
        if minimumDistance < 360_000 { return .class2 }
        return .class1
    }
}
