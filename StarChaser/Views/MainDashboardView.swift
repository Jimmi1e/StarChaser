//
//  MainDashboardView.swift
//  StarChaser
//
//  Created by Jiaxi on 2026/6/11.
//

import SwiftUI
import MapLibre
import CoreLocation

// 首页主控制台
struct MainDashboardView: View {
    @StateObject private var locationManager = LocationManager()
    
    @AppStorage("isFirstLaunch") private var isFirstLaunch: Bool = true
    
    @State private var moonData: MoonResult?
    @State private var isShowingDetail = false
    @State private var isShowingFullScreenMap = false
    @State private var isShowingCameraMeter = false
    @State private var isShowingSettings = false
    @State private var isShowingSkyForecast = false
    
    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(T("星空追随者", "Star Chaser"))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                            if let loc = locationManager.location {
                                Label(
                                    "\(String(format: "%.2f", loc.latitude)), \(String(format: "%.2f", loc.longitude))",
                                    systemImage: "location.fill"
                                )
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.secondary)
                            } else {
                                Label(T("正在获取位置", "Getting location"), systemImage: "location")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Button(action: { isShowingSettings = true }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.primary.opacity(0.8))
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.top, 8)
                    
                    if locationManager.location != nil {
                        MapLibreView(
                            coordinate: locationManager.location,
                            defaultZoom: 11.5,
                            trackingMode: .constant(.none),
                            isLightPollutionLayerActive: false,
                            tappedCoordinate: .constant(nil),
                            showLegendCard: .constant(false),
                            viewportRequest: .constant(nil)
                        )
                        .frame(height: 235)
                        .overlay {
                            ZStack(alignment: .bottomLeading) {
                                Color.white.opacity(0.001)
                                    .onTapGesture {
                                        isShowingFullScreenMap = true
                                    }

                                Label(T("查看全国光污染地图", "Open Light Pollution Map"), systemImage: "map.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(.black.opacity(0.58), in: Capsule())
                                    .padding(14)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
                    } else {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color(UIColor.secondarySystemBackground))
                            .frame(height: 235)
                            .overlay {
                                VStack(spacing: 10) {
                                    ProgressView()
                                    Text(T("正在准备观测地图", "Preparing observing map"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                    }

                    Button {
                        isShowingSkyForecast = true
                    } label: {
                        SkyForecastWidgetView(coordinate: locationManager.location)
                    }
                    .buttonStyle(.plain)

                    Button {
                        isShowingCameraMeter = true
                    } label: {
                        CameraMeterWidgetView()
                    }
                    .buttonStyle(.plain)

                    if let data = moonData {
                        Button {
                            isShowingDetail = true
                        } label: {
                            MoonWidgetView(data: data)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .sheet(isPresented: $isShowingDetail) { if let data = moonData { MoonDetailView(initialData: data, location: locationManager) } }
        .sheet(isPresented: $isShowingSettings) { QuickSettingsView() }
        .fullScreenCover(isPresented: $isShowingSkyForecast) {
            SkyForecastDetailView(coordinate: locationManager.location)
        }
        .fullScreenCover(isPresented: $isShowingCameraMeter) {
            NavigationStack {
                CameraMeterView()
            }
        }
        .fullScreenCover(isPresented: $isFirstLaunch) { OnboardingView(isFirstLaunch: $isFirstLaunch) }
        .fullScreenCover(isPresented: $isShowingFullScreenMap) {
            FullScreenMapView(isPresented: $isShowingFullScreenMap, coordinate: $locationManager.location)
        }
        .onAppear { refreshData() }
        .onChange(of: locationManager.location) { _, _ in refreshData() }
    }
    
    private func refreshData() {
        guard let loc = locationManager.location else { return }
        self.moonData = AstroCalculator.calculate(at: loc, hoursOffset: 0)
    }
}

// 独立设置面板
struct QuickSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("themePreference") private var themePref: ThemePreference = .system
    @AppStorage("languagePreference") private var langPref: LanguagePreference = .system
    @AppStorage("showLightPollution") private var showLP: Bool = true
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(T("偏好设置", "Preferences"))) {
                    Picker(T("语言", "Language"), selection: $langPref) {
                        ForEach(LanguagePreference.allCases, id: \.self) {
                            Text($0.displayTitle).tag($0)
                        }
                    }
                    Picker(T("主题", "Theme"), selection: $themePref) {
                        ForEach(ThemePreference.allCases, id: \.self) {
                            Text($0.displayTitle).tag($0)
                        }
                    }
                }
                
                Section(header: Text(T("天文观测", "Observing"))) {
                    Toggle(T("默认开启光污染图层", "Enable light pollution layer by default"), isOn: $showLP)
                }
            }
            .navigationTitle(T("设置", "Settings"))
            .navigationBarItems(trailing: Button(T("完成", "Done")) { dismiss() })
        }
    }
}

// ==========================================
// 全屏交互式观测地图 (集成光污染控件)
// ==========================================
struct FullScreenMapView: View {
    @Binding var isPresented: Bool
    @Binding var coordinate: CLLocationCoordinate2D?
    
    @State private var trackingMode: MLNUserTrackingMode = .follow
    @AppStorage("showLightPollution") private var isLightPollutionActive = true
    @State private var tappedCoordinate: CLLocationCoordinate2D? = nil
    @State private var showLegendCard = false
    @State private var viewportRequest: MapViewportRequest?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            MapLibreView(
                coordinate: coordinate,
                defaultZoom: 7.2,
                trackingMode: $trackingMode,
                isLightPollutionLayerActive: isLightPollutionActive,
                tappedCoordinate: $tappedCoordinate,
                showLegendCard: $showLegendCard,
                viewportRequest: $viewportRequest
            )
            .ignoresSafeArea()
            
            VStack {
                HStack(alignment: .top) {
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.gray.opacity(0.8))
                    }
                    
                    Spacer()

                    Text(T("点击地图查看污染等级", "Tap the map to inspect light pollution"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule())
                    
                    Spacer()

                    VStack(spacing: 20) {
                        LightPollutionSideControl(isLayerActive: $isLightPollutionActive)
                        
                        Button {
                            trackingMode = .none
                            viewportRequest = .china
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "globe.asia.australia.fill")
                                    .font(.system(size: 18))
                                Text(T("全国", "China"))
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(11)
                            .background(Color.indigo.opacity(0.88))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.2), radius: 5)
                        }

                        Button {
                            trackingMode = .follow
                            viewportRequest = .userLocation
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .padding(14)
                                .background(Color.blue.opacity(0.85))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.2), radius: 5)
                        }
                    }
                }
                .padding()
                
                Spacer()

                if isLightPollutionActive && !showLegendCard {
                    LightPollutionScaleBar()
                        .padding(.horizontal, 54)
                        .padding(.bottom, 12)
                }

                if showLegendCard {
                    LightPollutionLegendCard(coordinate: tappedCoordinate, isPresented: $showLegendCard)
                        .padding(.horizontal, 15)
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showLegendCard)
                }
            }
        }
    }
}

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
#Preview {
    MainDashboardView()
}
