//
//  MoonComponents.swift
//  StarChaser
//
//  Created by Jiaxi on 2026/6/11.
//

import SwiftUI

// ==========================================
// 🌟 终极版纯数学几何渲染引擎 (已修复角度编译报错)
// ==========================================
struct RealisticMoonView: View {
    let phaseProgress: Double
    let phaseName: String
    
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let isNewMoon = phaseName == "新月"
            
            ZStack {
                // 1. 暗部底座（永远是不发光的深灰色）
                Circle()
                    .fill(Color(white: 0.15))
                
                // 2. 光影动态切割层（只框选发光面积，永远填充满暖黄色）
                TerminatorShape(phaseProgress: phaseProgress)
                    .fill(isNewMoon ? Color.clear : Color.yellow)
                    .shadow(color: isNewMoon ? .clear : .yellow.opacity(0.3), radius: size * 0.08)
                
                // 3. 逼真陨石坑层（纯代码，制造不平整质感与凸起）
                MoonCartoonCratersLayer(size: size)
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

// 🌟 无懈可击的数学连续路径生成器（已采用安全的 CGFloat.pi 显式计算，杜绝编译报错）
struct TerminatorShape: Shape {
    var phaseProgress: Double
    
    var animatableData: Double {
        get { phaseProgress }
        set { phaseProgress = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2.0
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let steps = 40
        
        if phaseProgress <= 0.5 {
            // 盈月阶段：亮部在右侧
            // 1. 画出右半圆
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let angle = (CGFloat.pi * t) - (CGFloat.pi / 2.0)
                let x = center.x + radius * cos(angle)
                let y = center.y + radius * sin(angle)
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            // 2. 沿着光影边界（余弦投影）闭合回去
            let a = radius * CGFloat(1.0 - 4.0 * phaseProgress)
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let angle = (CGFloat.pi / 2.0) - (CGFloat.pi * t)
                let x = center.x + a * cos(angle)
                let y = center.y + radius * sin(angle)
                path.addLine(to: CGPoint(x: x, y: y))
            }
        } else {
            // 亏月阶段（如残月）：亮部在左侧
            // 1. 画出左半圆
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let angle = (CGFloat.pi * t) - (CGFloat.pi / 2.0)
                let x = center.x - radius * cos(angle)
                let y = center.y + radius * sin(angle)
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            // 2. 沿着光影边界闭合回去
            let a = radius * CGFloat(4.0 * phaseProgress - 3.0)
            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let angle = (CGFloat.pi / 2.0) - (CGFloat.pi * t)
                let x = center.x - a * cos(angle)
                let y = center.y + radius * sin(angle)
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }
}

// 纯原生代码卡通质感陨石坑
struct MoonCartoonCratersLayer: View {
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // 内部主体坑洼
            CartoonCrater(x: 0.32, y: 0.28, scale: 0.16, totalSize: size)
            CartoonCrater(x: 0.72, y: 0.40, scale: 0.20, totalSize: size)
            CartoonCrater(x: 0.42, y: 0.68, scale: 0.24, totalSize: size)
            CartoonCrater(x: 0.22, y: 0.58, scale: 0.12, totalSize: size)
            
            // 制造边缘凹凸不平的小错觉
            CartoonCrater(x: 0.05, y: 0.45, scale: 0.11, totalSize: size)
            CartoonCrater(x: 0.94, y: 0.52, scale: 0.09, totalSize: size)
            CartoonCrater(x: 0.52, y: 0.94, scale: 0.12, totalSize: size)
            CartoonCrater(x: 0.65, y: 0.06, scale: 0.08, totalSize: size)
        }
    }
}

struct CartoonCrater: View {
    let x: CGFloat
    let y: CGFloat
    let scale: CGFloat
    let totalSize: CGFloat
    
    var body: some View {
        let cSize = totalSize * scale
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.15))
            Circle()
                .strokeBorder(Color.black.opacity(0.18), lineWidth: max(1.5, cSize * 0.12))
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: max(1.0, cSize * 0.06))
                .offset(x: cSize * 0.05, y: cSize * 0.05)
        }
        .frame(width: cSize, height: cSize)
        .position(x: totalSize * x, y: totalSize * y)
    }
}

// ==========================================
// 首页方块 Widget (全面适配浅色/深色主题)
// ==========================================
struct MoonWidgetView: View {
    let data: MoonResult
    
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 12) {
                Text(data.phaseName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("照射范围").foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(data.illumination * 100))%").foregroundColor(.primary)
                    }
                    HStack {
                        Text("下次月出").foregroundColor(.secondary)
                        Spacer()
                        Text(formatTime(data.moonrise)).foregroundColor(.primary)
                    }
                    HStack {
                        Text("下次满月").foregroundColor(.secondary)
                        Spacer()
                        Text("\(data.daysToFullMoon) 天").foregroundColor(.primary)
                    }
                }
                .font(.system(size: 15))
                .frame(width: 160)
            }
            
            Spacer()
            
            RealisticMoonView(phaseProgress: data.phaseProgress, phaseName: data.phaseName)
                .frame(width: 90, height: 90)
        }
        .padding(20)
        .background(.regularMaterial) // 苹果原生材质背景
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
    }
    
    private func formatTime(_ date: Date?) -> String {
        guard let date = date else { return "--:--" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
    }
}

// ==========================================
// 沉浸式观测详情页 (全面适配浅色/深色主题)
// ==========================================
struct MoonDetailView: View {
    @Environment(\.dismiss) var dismiss
    let locationManager: LocationManager
    @State private var currentData: MoonResult
    @State private var timeOffset: Double = 0
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    
    init(initialData: MoonResult, location: LocationManager) {
        _currentData = State(initialValue: initialData)
        self.locationManager = location
    }
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea() // 背景色自适应系统主题
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 25) {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)

                    VStack(spacing: 15) {
                        RealisticMoonView(phaseProgress: currentData.phaseProgress, phaseName: currentData.phaseName)
                            .frame(width: 220, height: 220)
                        
                        Text(currentData.phaseName)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text(formatFullDate(currentData.date))
                            .font(.system(size: 16, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    VStack(spacing: 15) {
                        HStack {
                            Text("时间推演轴").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text(timeOffset == 0 ? "现在" : "\(String(format: "%.1f", timeOffset)) 小时后")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                        .padding(.horizontal)
                        
                        Slider(value: $timeOffset, in: 0...168, step: 0.1)
                            .accentColor(.yellow)
                            .onChange(of: timeOffset) { _, newValue in
                                haptic.impactOccurred()
                                updateData(offset: newValue)
                            }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(15)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                        DetailInfoTile(title: "照射范围", value: "\(Int(currentData.illumination * 100))%")
                        DetailInfoTile(title: "地月距离", value: "\(Int(currentData.distance)) 公里")
                        DetailInfoTile(title: "月出时刻", value: formatTime(currentData.moonrise))
                        DetailInfoTile(title: "月落时刻", value: formatTime(currentData.moonset))
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 15) {
                        Text("未来 14 天真实月相预报").font(.headline).foregroundColor(.primary)
                        let columns = Array(repeating: GridItem(.flexible()), count: 7)
                        
                        LazyVGrid(columns: columns, spacing: 15) {
                            ForEach(currentData.forecast, id: \.self) { dailyPhase in
                                VStack(spacing: 8) {
                                    Text("+\(dailyPhase.dayOffset)天")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    RealisticMoonView(phaseProgress: dailyPhase.phaseProgress, phaseName: dailyPhase.phaseName)
                                        .frame(width: 26, height: 26)
                                    Text(dailyPhase.phaseName)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(15)
                    .padding(.horizontal)
                }
                .padding(.bottom, 50)
            }
        }
    }
    
    private func updateData(offset: Double) {
        guard let loc = locationManager.location else { return }
        let newData = AstroCalculator.calculate(at: loc, hoursOffset: offset)
        withAnimation(.easeInOut(duration: 0.05)) {
            self.currentData = newData
        }
    }
    
    private func formatFullDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M月d日 EEEE HH:mm"
        return f.string(from: date)
    }
    
    private func formatTime(_ date: Date?) -> String {
        guard let date = date else { return "--:--" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

struct DetailInfoTile: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(size: 18, weight: .medium)).foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}
