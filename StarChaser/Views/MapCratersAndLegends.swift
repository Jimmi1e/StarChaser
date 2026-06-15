//
//  MapCratersAndLegends.swift
//  StarChaser
//
//  Created by Jiaxi on 2026/6/11.
//

import SwiftUI
import CoreLocation

// ==========================================
// 地图侧边悬浮图层选择器（毛玻璃质感）
// ==========================================
struct LightPollutionSideControl: View {
    @Binding var isLayerActive: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            Text("图层")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.primary.opacity(0.7))
                .padding(.top, 8)
            
            Divider().padding(.horizontal, 8)
            
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isLayerActive.toggle()
                }
            }) {
                VStack(spacing: 6) {
                    Image(systemName: isLayerActive ? "light.switch.off.fill" : "light.switch.on.fill")
                        .font(.system(size: 22))
                        .foregroundColor(isLayerActive ? .yellow : .primary.opacity(0.8))
                    
                    Text("光害")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isLayerActive ? .yellow : .primary.opacity(0.8))

                    Text("2025")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .background(isLayerActive ? Color.yellow.opacity(0.15) : Color.clear)
                .cornerRadius(12)
            }
        }
        .frame(width: 55)
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

struct LightPollutionScaleBar: View {
    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text("暗空")
                Spacer()
                Text("光污染严重")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                ForEach(BortleClass.allCases, id: \.rawValue) { item in
                    item.color
                        .frame(height: 9)
                }
            }
            .clipShape(Capsule())

            HStack {
                Text("绿 / 青")
                Spacer()
                Text("黄")
                Spacer()
                Text("橙 / 红")
                Spacer()
                Text("紫")
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
    }
}

// ==========================================
// 光污染详情底部卡片（包含异步真实卫星测算）
// ==========================================
struct LightPollutionLegendCard: View {
    let coordinate: CLLocationCoordinate2D?
    @Binding var isPresented: Bool
    
    @State private var reading: LightPollutionReading?
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 16) {
            if isLoading {
                VStack(spacing: 15) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("正在读取 2025 天空亮度...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(height: 190)
                
            } else if let reading {
                let data = reading.bortleClass
                
                HStack {
                    Circle()
                        .fill(data.color)
                        .frame(width: 14, height: 14)
                        .shadow(color: data.color.opacity(0.5), radius: 4)
                    
                    Text(data.title)
                        .font(.title3.bold())
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }

                VStack(spacing: 8) {
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(BortleClass.allCases, id: \.rawValue) { bClass in
                            let isCurrent = bClass == data
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(bClass.color)
                                    .frame(height: isCurrent ? 34 : 20)
                                    .opacity(isCurrent ? 1 : 0.55)
                                
                                Text("\(bClass.rawValue)")
                                    .font(.system(size: 9, weight: isCurrent ? .bold : .regular))
                                    .foregroundColor(isCurrent ? .primary : .secondary)
                            }
                        }
                    }
                    HStack {
                        Text("极佳暗空")
                        Spacer()
                        Text("污染最严重")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 15)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)

                HStack {
                    Label(reading.source.title, systemImage: reading.source == .satellite2025 ? "sparkles" : "wifi.slash")
                    Spacer()
                    Text("SQM \(data.approximateSQM)")
                }
                .font(.caption)
                .foregroundStyle(reading.source == .satellite2025 ? Color.secondary : Color.orange)

                VStack(spacing: 14) {
                    ObservationAdviceRow(icon: "camera.aperture", title: "星空摄影评价", text: data.astrophotographyAdvice)
                    Divider()
                    ObservationAdviceRow(icon: "eye", title: "肉眼银河观测", text: data.milkyWayVisibility)
                }
                .padding(15)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(16)
                
                if let coord = coordinate {
                    Text("采样坐标 \(String(format: "%.4f", coord.latitude)), \(String(format: "%.4f", coord.longitude))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(20)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(28)
        .shadow(color: .black.opacity(0.15), radius: 30)
        .task(id: coordinate.map { "\($0.latitude),\($0.longitude)" }) {
            await fetchData(for: coordinate)
        }
    }
    
    private func fetchData(for coord: CLLocationCoordinate2D?) async {
        guard let coord = coord else { return }
        isLoading = true
        reading = nil

        let result = await LightPollutionService.fetchReading(for: coord)
        guard !Task.isCancelled else { return }
        reading = result
        isLoading = false
    }
}

// 辅助组件：观测建议行
struct ObservationAdviceRow: View {
    let icon: String
    let title: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.blue)
                .frame(width: 25)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                Text(text)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
