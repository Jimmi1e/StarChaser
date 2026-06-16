//
//  OnboardingView.swift
//  StarChaser
//
//  Created by Jiaxi on 2026/6/11.
//

import SwiftUI

struct OnboardingView: View {
    @AppStorage("themePreference") private var themePref: ThemePreference = .system
    @AppStorage("languagePreference") private var langPref: LanguagePreference = .system
    @Binding var isFirstLaunch: Bool
    
    @State private var contentIsVisible = false
    // 背景渐变动画状态
    @State private var gradientOffset = false
    
    var body: some View {
        ZStack {
            // 🌟 高级流动渐变背景 (无需额外依赖)
            LinearGradient(
                colors: [Color.black, Color.indigo.opacity(0.8), Color.purple.opacity(0.6), Color.black],
                startPoint: gradientOffset ? .topLeading : .bottomTrailing,
                endPoint: gradientOffset ? .bottomTrailing : .topLeading
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 8.0).repeatForever(autoreverses: true), value: gradientOffset)
            .onAppear { gradientOffset.toggle() }
            
            // 星空点缀
            PremiumStarsBackgroundView()
            
            VStack(spacing: 40) {
                Spacer()
                
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.yellow, .white)
                    .shadow(color: .yellow.opacity(0.5), radius: 20)
                    .scaleEffect(contentIsVisible ? 1.0 : 0.8)
                
                Text(T("星空追随者", "Star Chaser"))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                // 🌟 苹果高级质感毛玻璃面板
                VStack(alignment: .leading, spacing: 25) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(T("偏好语言", "Language"))
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        Picker(T("语言", "Language"), selection: $langPref) {
                            ForEach(LanguagePreference.allCases, id: \.self) {
                                Text($0.displayTitle).tag($0)
                            }
                        }.pickerStyle(.segmented)
                    }
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text(T("界面外观", "Appearance"))
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        Picker(T("主题", "Theme"), selection: $themePref) {
                            ForEach(ThemePreference.allCases, id: \.self) {
                                Text($0.displayTitle).tag($0)
                            }
                        }.pickerStyle(.segmented)
                    }
                }
                .padding(25)
                .background(.ultraThinMaterial) // 核心：极致透亮的毛玻璃
                .environment(\.colorScheme, .dark) // 保持卡片处于深色晶莹模式
                .cornerRadius(24)
                .padding(.horizontal, 25)
                .shadow(color: .black.opacity(0.2), radius: 20)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        isFirstLaunch = false
                    }
                }) {
                    Text(T("开启追星之旅", "Start Chasing Stars"))
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.blue.opacity(0.8))
                        .cornerRadius(18)
                        .shadow(color: .blue.opacity(0.4), radius: 10)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
            .offset(y: contentIsVisible ? 0 : 40)
            .opacity(contentIsVisible ? 1 : 0)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                    contentIsVisible = true
                }
            }
        }
    }
}
