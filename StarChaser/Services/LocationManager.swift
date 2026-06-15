//
//  LocationManager.swift
//  StarChaser
//
//  Created by Jiaxi on 2026/6/11.
//

import Foundation
import CoreLocation
import Combine
// 使用 ObservableObject 让 SwiftUI 能够监听到数据的变化
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    // @Published 会在数据更新时自动刷新界面
    @Published var location: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 500
        manager.requestWhenInUseAuthorization()
        requestLocationIfAuthorized()
    }
    
    // Delegate 回调：当获取到新位置时触发
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
        DispatchQueue.main.async {
            self.location = loc.coordinate
        }
        manager.stopUpdatingLocation()
    }
    
    // Delegate 回调：当权限状态改变时触发
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
        }
        requestLocationIfAuthorized()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard (error as? CLError)?.code != .locationUnknown else { return }
    }

    func refreshLocation() {
        requestLocationIfAuthorized()
    }

    private func requestLocationIfAuthorized() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .notDetermined:
            break
        case .denied, .restricted:
            manager.stopUpdatingLocation()
        @unknown default:
            break
        }
    }
}
