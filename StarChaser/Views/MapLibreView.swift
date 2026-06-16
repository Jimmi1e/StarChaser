//
//  MapLibreView.swift
//  StarChaser
//
//  Created by Jiaxi on 2026/6/11.
//

import SwiftUI
import MapLibre
import CoreLocation

enum MapViewportRequest: Equatable {
    case china
    case userLocation
}

struct MapLibreView: UIViewRepresentable {
    var coordinate: CLLocationCoordinate2D?
    var defaultZoom: Double
    @Binding var trackingMode: MLNUserTrackingMode
    var isLightPollutionLayerActive: Bool
    @Binding var tappedCoordinate: CLLocationCoordinate2D?
    @Binding var showLegendCard: Bool
    @Binding var viewportRequest: MapViewportRequest?
    
    @AppStorage("themePreference") private var themePref: ThemePreference = .system
    @AppStorage("languagePreference") private var langPref: LanguagePreference = .system
    @Environment(\.colorScheme) var systemScheme
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: MapLibreView
        var selectedAnnotation: MLNPointAnnotation?
        var didSetInitialViewport = false
        
        init(_ parent: MapLibreView) { self.parent = parent }
        
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            parent.updateMapLanguage(style: style)

            let sourceID = "light_pollution_source"
            let source = MLNRasterTileSource(
                identifier: sourceID,
                tileURLTemplates: [LightPollutionService.tileURLTemplate],
                options: [
                    .minimumZoomLevel: 0,
                    .maximumZoomLevel: LightPollutionService.maximumZoom,
                    .tileSize: 256,
                    .tileCoordinateSystem: 1,
                    .attributionHTMLString: "Sky brightness © LightPollutionMap.info"
                ]
            )
            style.addSource(source)
            
            let layer = MLNRasterStyleLayer(identifier: "light_pollution_layer", source: source)
            layer.rasterOpacity = NSExpression(forConstantValue: 0.72)
            layer.rasterFadeDuration = NSExpression(forConstantValue: 0)
            layer.rasterResamplingMode = NSExpression(
                forConstantValue: MLNRasterResamplingMode.linear.rawValue
            )
            layer.isVisible = parent.isLightPollutionLayerActive
            
            if let labelLayer = style.layers.last(where: { $0.identifier.contains("label") || $0.identifier.contains("text") }) {
                style.insertLayer(layer, below: labelLayer)
            } else {
                style.addLayer(layer)
            }
        }
        
        // 监听用户的点击交互，并反算出真实地理坐标
        @objc func handleMapTap(gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MLNMapView else { return }
            let location = gesture.location(in: mapView)
            let coord = mapView.convert(location, toCoordinateFrom: mapView)

            if let selectedAnnotation {
                mapView.removeAnnotation(selectedAnnotation)
            }
            let annotation = MLNPointAnnotation()
            annotation.coordinate = coord
            annotation.title = T("光污染采样点", "Light Pollution Sample")
            mapView.addAnnotation(annotation)
            selectedAnnotation = annotation

            DispatchQueue.main.async {
                self.parent.tappedCoordinate = coord
                self.parent.showLegendCard = true

                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
            }
        }

        func applyViewportRequest(_ request: MapViewportRequest, to mapView: MLNMapView) {
            switch request {
            case .china:
                mapView.setCenter(
                    CLLocationCoordinate2D(latitude: 35.5, longitude: 104.5),
                    zoomLevel: 3.4,
                    animated: true
                )
            case .userLocation:
                guard let coordinate = parent.coordinate else { return }
                mapView.setCenter(coordinate, zoomLevel: 7.2, animated: true)
            }
        }
    }
    
    func makeUIView(context: Context) -> MLNMapView {
        let isDark = (themePref.colorScheme ?? systemScheme) == .dark
        let styleStr = isDark ?
            "https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json" :
            "https://basemaps.cartocdn.com/gl/positron-gl-style/style.json"
        
        let mapView = MLNMapView(frame: .zero, styleURL: URL(string: styleStr))
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.compassView.isHidden = true
        mapView.logoView.isHidden = true
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        
        // 添加点击手势识别器
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleMapTap(gesture:)))
        tapGesture.delegate = context.coordinator
        mapView.addGestureRecognizer(tapGesture)
        
        return mapView
    }
    
    func updateUIView(_ uiView: MLNMapView, context: Context) {
        context.coordinator.parent = self

        let isDark = (themePref.colorScheme ?? systemScheme) == .dark
        let targetStyle = isDark ?
            "https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json" :
            "https://basemaps.cartocdn.com/gl/positron-gl-style/style.json"
        
        if uiView.styleURL?.absoluteString != targetStyle {
            uiView.styleURL = URL(string: targetStyle)
        }
        
        if let style = uiView.style {
            updateMapLanguage(style: style)

            if let lpLayer = style.layer(withIdentifier: "light_pollution_layer") as? MLNRasterStyleLayer {
                lpLayer.isVisible = isLightPollutionLayerActive
            }
        }
        
        if uiView.userTrackingMode != trackingMode {
            uiView.setUserTrackingMode(trackingMode, animated: true, completionHandler: nil)
            DispatchQueue.main.async { self.trackingMode = .none }
        }

        if !context.coordinator.didSetInitialViewport, let coordinate {
            uiView.setCenter(coordinate, zoomLevel: defaultZoom, animated: false)
            context.coordinator.didSetInitialViewport = true
        }

        if let viewportRequest {
            context.coordinator.applyViewportRequest(viewportRequest, to: uiView)
            DispatchQueue.main.async {
                self.viewportRequest = nil
                self.trackingMode = .none
            }
        }
    }
    
    func updateMapLanguage(style: MLNStyle) {
        let localizedTextField = langPref.mapField
        for layer in style.layers {
            if let symbolLayer = layer as? MLNSymbolStyleLayer {
                let newExpr = NSExpression(forConstantValue: localizedTextField)
                if symbolLayer.text != newExpr {
                    symbolLayer.text = newExpr
                }
            }
        }
    }
}
