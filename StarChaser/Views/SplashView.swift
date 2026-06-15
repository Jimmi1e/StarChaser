//
//  SplashView.swift
//  StarChaser
//
//  Created by Jiaxi on 2026/6/11.
//

import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @State private var earthScale: CGFloat = 0.5
    @State private var earthOpacity: Double = 0.0
    @State private var bgOpacity: Double = 1.0
    
    var body: some View {
        if isActive {
            MainDashboardView()
        } else {
            ZStack {
                // 启动页保持深邃宇宙感
                Color.black.ignoresSafeArea()
                
                // 1. 升级版：繁星璀璨的银河背景
                PremiumStarsBackgroundView()
                
                // 2. 地球逐渐浮现并放大
                Image(systemName: "globe.asia.australia.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.green.opacity(0.8), Color.blue.opacity(0.9))
                    .shadow(color: .blue.opacity(0.6), radius: 30) // 增强光晕
                    .scaleEffect(earthScale)
                    .opacity(earthOpacity)
            }
            .opacity(bgOpacity)
            .onAppear {
                withAnimation(.easeIn(duration: 1.5)) {
                    earthOpacity = 1.0
                    earthScale = 1.0
                }
                withAnimation(.easeInOut(duration: 1.5).delay(1.8)) {
                    earthScale = 60
                    bgOpacity = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                    isActive = true
                }
            }
        }
    }
}

// 🌟 升级版星空：加入发光层、大小错落、数量增加
struct PremiumStarsBackgroundView: View {
    @State private var twinkle = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<200, id: \.self) { _ in
                    let size = CGFloat.random(in: 1...4)
                    Circle()
                        .fill(Color.white)
                        .frame(width: size, height: size)
                        // 核心：添加白色的阴影作为发光层，摆脱灰尘感
                        .shadow(color: .white.opacity(0.8), radius: size * 1.5)
                        .position(
                            x: CGFloat.random(in: 0...geo.size.width),
                            y: CGFloat.random(in: 0...geo.size.height)
                        )
                        .opacity(twinkle ? CGFloat.random(in: 0.4...1.0) : CGFloat.random(in: 0.0...0.2))
                        .animation(
                            .easeInOut(duration: CGFloat.random(in: 1.5...4.0))
                            .repeatForever(autoreverses: true),
                            value: twinkle
                        )
                }
            }
        }
        .onAppear { twinkle = true }
    }
}
