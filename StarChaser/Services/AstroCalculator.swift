//
//  AstroCalculator.swift
//  StarChaser
//
//  Created by Jiaxi on 2026/6/11.
//

import Foundation
import CoreLocation
import SwiftAA

struct DailyMoonPhase: Hashable {
    let dayOffset: Int
    let date: Date
    let phaseName: String
    let phaseProgress: Double // 用于连续动画
    let illumination: Double
}

class MoonResult {
    let date: Date
    let phaseName: String
    let illumination: Double
    let phaseProgress: Double // 🌟 0.0(新月)->0.5(满月)->1.0(新月) 完美动画轴
    let moonrise: Date?
    let moonset: Date?
    let distance: Double
    let altitude: Double
    let azimuth: Double
    let daysToFullMoon: Int
    let forecast: [DailyMoonPhase]
    
    init(date: Date, moon: Moon, coords: GeographicCoordinates) {
        self.date = date
        let frac = moon.illuminatedFraction()
        self.illumination = frac
        self.distance = moon.distance.value
        
        let riseSet = moon.riseTransitSetTimes(for: coords)
        self.moonrise = riseSet.riseTime?.date
        self.moonset = riseSet.setTime?.date
        
        let horizontal = moon.apparentEquatorialCoordinates.makeHorizontalCoordinates(for: coords, at: JulianDay(date))
        self.altitude = horizontal.altitude.value
        self.azimuth = horizontal.azimuth.value
        
        let nextMoon = Moon(julianDay: JulianDay(date.addingTimeInterval(3600)), highPrecision: false)
        let isWaxing = nextMoon.illuminatedFraction() > frac
        
        // 生成连续的动画时间轴
        self.phaseProgress = isWaxing ? (frac * 0.5) : (0.5 + (1.0 - frac) * 0.5)
        
        if frac < 0.05 { self.phaseName = "新月" }
        else if frac < 0.45 { self.phaseName = isWaxing ? "峨眉月" : "残月" }
        else if frac < 0.55 { self.phaseName = isWaxing ? "上弦月" : "下弦月" }
        else if frac < 0.95 { self.phaseName = isWaxing ? "盈凸月" : "亏凸月" }
        else { self.phaseName = "满月" }
        
        self.daysToFullMoon = isWaxing ? Int((1.0 - frac) * 14.76) : Int(frac * 14.76 + 14.76)
        
        var tempForecast: [DailyMoonPhase] = []
        for i in 1...14 {
            let futureDate = date.addingTimeInterval(Double(i) * 86400)
            let fMoon = Moon(julianDay: JulianDay(futureDate), highPrecision: false)
            let fFrac = fMoon.illuminatedFraction()
            let fNext = Moon(julianDay: JulianDay(futureDate.addingTimeInterval(3600)), highPrecision: false)
            let fIsWaxing = fNext.illuminatedFraction() > fFrac
            let fProgress = fIsWaxing ? (fFrac * 0.5) : (0.5 + (1.0 - fFrac) * 0.5)
            
            var fName = "新月"
            if fFrac < 0.05 { fName = "新月" }
            else if fFrac < 0.45 { fName = fIsWaxing ? "峨眉月" : "残月" }
            else if fFrac < 0.55 { fName = fIsWaxing ? "上弦月" : "下弦月" }
            else if fFrac < 0.95 { fName = fIsWaxing ? "盈凸月" : "亏凸月" }
            else { fName = "满月" }
            
            tempForecast.append(DailyMoonPhase(dayOffset: i, date: futureDate, phaseName: fName, phaseProgress: fProgress, illumination: fFrac))
        }
        self.forecast = tempForecast
    }
}

class AstroCalculator {
    static func calculate(at coordinate: CLLocationCoordinate2D, hoursOffset: Double) -> MoonResult {
        let targetDate = Date().addingTimeInterval(hoursOffset * 3600)
        let geo = GeographicCoordinates(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        let moon = Moon(julianDay: JulianDay(targetDate), highPrecision: true)
        return MoonResult(date: targetDate, moon: moon, coords: geo)
    }
}
