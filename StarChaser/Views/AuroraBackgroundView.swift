//
//  AuroraBackgroundView.swift
//  StarChaser
//
//  Created by Jiaxi on 2026/6/11.
//

import Foundation
import SwiftUI

struct AuroraBackgroundView: View {
    // 状态变量：控制动画的起始点和终止点
    @State private var isAnimating = false
    
    var body: some View {
        // 创建一个线性渐变
        LinearGradient(
            colors: [
                Color(red: 0.1, green: 0.0, blue: 0.2), // 深邃暗紫
                Color(red: 0.2, green: 0.1, blue: 0.5), // 星云亮紫
                Color(red: 0.0, green: 0.3, blue: 0.4), // 极光暗青
                Color.black // 宇宙纯黑
            ],
            // 核心：根据状态变量，让渐变的起点和终点发生位移，产生“滑动”感
            startPoint: isAnimating ? .topLeading : .bottomLeading,
            endPoint: isAnimating ? .bottomTrailing : .topTrailing
        )
        .ignoresSafeArea() // 铺满全屏
        .onAppear {
            // 当视图出现时，启动一个永不停止、平滑往复的动画
            withAnimation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}
