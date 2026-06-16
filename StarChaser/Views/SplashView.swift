//
//  SplashView.swift
//  StarChaser
//
//  Created by Jiaxi on 2026/6/11.
//

import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @State private var hasStarted = false
    @State private var shootingProgress: CGFloat = 0
    @State private var shootingOpacity = 0.0
    @State private var shootingFlashOpacity = 0.0
    @State private var skyReveal = 0.0
    @State private var milkyWayOpacity = 0.0
    @State private var titleOpacity = 0.0
    @State private var titleScale: CGFloat = 0.92

    var body: some View {
        ZStack {
            if isActive {
                MainDashboardView()
                    .transition(.opacity)
            } else {
                entranceScene
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.95), value: isActive)
        .task {
            await runEntranceAnimation()
        }
    }

    private var entranceScene: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.indigo.opacity(0.22 * milkyWayOpacity),
                    Color.purple.opacity(0.10 * milkyWayOpacity),
                    Color.black
                ],
                center: .center,
                startRadius: 40,
                endRadius: 520
            )
            .ignoresSafeArea()

            PremiumStarsBackgroundView(reveal: skyReveal)

            SplashMilkyWayView(opacity: milkyWayOpacity)

            ShootingStarView(
                progress: shootingProgress,
                opacity: shootingOpacity,
                flashOpacity: shootingFlashOpacity
            )

            SplashTitleView(opacity: titleOpacity, scale: titleScale)
                .padding(.horizontal, 28)
                .offset(y: 8)
        }
        .ignoresSafeArea()
    }

    @MainActor
    private func runEntranceAnimation() async {
        guard !hasStarted else { return }
        hasStarted = true

        withAnimation(.easeOut(duration: 0.18)) {
            shootingOpacity = 1
        }

        withAnimation(.timingCurve(0.16, 0.82, 0.18, 1.0, duration: 1.35)) {
            shootingProgress = 1
        }

        try? await Task.sleep(nanoseconds: 520_000_000)

        withAnimation(.easeInOut(duration: 1.25)) {
            skyReveal = 1
            milkyWayOpacity = 1
        }

        try? await Task.sleep(nanoseconds: 280_000_000)

        withAnimation(.spring(response: 0.72, dampingFraction: 0.78)) {
            titleOpacity = 1
            titleScale = 1
        }

        try? await Task.sleep(nanoseconds: 430_000_000)

        withAnimation(.easeOut(duration: 0.10)) {
            shootingFlashOpacity = 1
        }

        withAnimation(.easeOut(duration: 0.18)) {
            shootingOpacity = 0
        }

        try? await Task.sleep(nanoseconds: 170_000_000)

        withAnimation(.easeOut(duration: 0.22)) {
            shootingFlashOpacity = 0
        }

        try? await Task.sleep(nanoseconds: 1_470_000_000)

        withAnimation(.easeInOut(duration: 0.95)) {
            isActive = true
        }
    }
}

private struct ShootingStarView: View {
    let progress: CGFloat
    let opacity: Double
    let flashOpacity: Double

    var body: some View {
        GeometryReader { geo in
            let p = min(max(progress, 0), 1)
            let start = CGPoint(x: -geo.size.width * 0.12, y: geo.size.height * 0.86)
            let control = CGPoint(x: geo.size.width * 0.42, y: geo.size.height * 0.38)
            let end = CGPoint(x: geo.size.width * 1.06, y: geo.size.height * 0.16)
            let oneMinusP = 1 - p
            let x = oneMinusP * oneMinusP * start.x
                + 2 * oneMinusP * p * control.x
                + p * p * end.x
            let y = oneMinusP * oneMinusP * start.y
                + 2 * oneMinusP * p * control.y
                + p * p * end.y
            let starSize = 54 - 45 * p
            let trailWidth = max(geo.size.width * (0.56 - 0.34 * p), 82)
            let trailHeight = max(1.4, 7.0 - 5.4 * p)
            let travelOpacity = opacity * Double(1 - max(0, (p - 0.88) / 0.12))

            ZStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.cyan.opacity(0.12),
                                Color.blue.opacity(0.34),
                                Color.white.opacity(0.92)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: trailWidth, height: trailHeight)
                    .offset(x: -trailWidth * 0.50)
                    .blur(radius: 0.4)
                    .opacity(travelOpacity)

                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white,
                                Color(red: 0.74, green: 0.88, blue: 1.0).opacity(0.82),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: starSize * 0.62
                        )
                    )
                    .frame(width: starSize * 1.42, height: starSize * 0.88)
                    .blur(radius: 0.45 + 0.9 * p)
                    .opacity(travelOpacity)

                Circle()
                    .fill(.white)
                    .frame(width: starSize * 0.30, height: starSize * 0.30)
                    .shadow(color: .white.opacity(0.92), radius: 14 - 7 * p)
                    .shadow(color: Color(red: 0.62, green: 0.82, blue: 1.0).opacity(0.78), radius: 30 - 18 * p)
                    .opacity(travelOpacity)

                Circle()
                    .strokeBorder(.white.opacity(0.92), lineWidth: 1.4)
                    .frame(width: 48 + 24 * flashOpacity, height: 48 + 24 * flashOpacity)
                    .blur(radius: 0.2)
                    .opacity(flashOpacity)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white,
                                Color.cyan.opacity(0.80),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 44
                        )
                    )
                    .frame(width: 104, height: 104)
                    .scaleEffect(0.72 + 0.36 * flashOpacity)
                    .opacity(flashOpacity)
            }
            .rotationEffect(.degrees(-25))
            .position(x: x, y: y)
        }
        .allowsHitTesting(false)
    }
}

struct PremiumStarsBackgroundView: View {
    let reveal: Double
    @State private var twinkle = false

    init(reveal: Double = 1) {
        self.reveal = reveal
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(SplashSkyData.stars) { star in
                    Circle()
                        .fill(star.tint)
                        .frame(width: star.size, height: star.size)
                        .shadow(color: star.tint.opacity(0.75), radius: star.size * 1.6)
                        .position(
                            x: geo.size.width * star.x,
                            y: geo.size.height * star.y
                        )
                        .opacity(reveal * (twinkle ? star.brightOpacity : star.dimOpacity))
                        .animation(
                            .easeInOut(duration: star.twinkleDuration)
                            .delay(star.twinkleDelay)
                            .repeatForever(autoreverses: true),
                            value: twinkle
                        )
                }
            }
            .drawingGroup()
        }
        .onAppear { twinkle = true }
        .allowsHitTesting(false)
    }
}

private struct SplashMilkyWayView: View {
    let opacity: Double
    @State private var drift = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                galaxyGlow(in: geo.size)

                ForEach(SplashSkyData.galaxyDust) { dust in
                    Circle()
                        .fill(dust.tint)
                        .frame(width: dust.size, height: dust.size)
                        .blur(radius: dust.blur)
                        .position(
                            x: geo.size.width * (-0.12 + 1.24 * dust.t),
                            y: geo.size.height * (0.70 - 0.42 * dust.t)
                                + geo.size.height * 0.24 * (dust.spread - 0.5)
                        )
                        .opacity(dust.opacity)
                }
            }
            .scaleEffect(drift ? 1.028 : 1.0)
            .offset(x: drift ? 8 : -8, y: drift ? -6 : 6)
            .opacity(opacity)
            .animation(.easeInOut(duration: 5.2).repeatForever(autoreverses: true), value: drift)
            .onAppear { drift = true }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
    }

    private func galaxyGlow(in size: CGSize) -> some View {
        ZStack {
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.indigo.opacity(0.08),
                            Color.cyan.opacity(0.20),
                            Color.white.opacity(0.18),
                            Color.purple.opacity(0.20),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: size.width * 1.42, height: size.height * 0.24)
                .blur(radius: 18)
                .rotationEffect(.degrees(-22))

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.10),
                            Color.cyan.opacity(0.24),
                            Color.pink.opacity(0.16),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: size.width * 1.18, height: size.height * 0.10)
                .blur(radius: 9)
                .rotationEffect(.degrees(-22))

            Ellipse()
                .stroke(
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.38),
                            Color.cyan.opacity(0.26),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1.4
                )
                .frame(width: size.width * 1.12, height: size.height * 0.08)
                .blur(radius: 1.5)
                .rotationEffect(.degrees(-22))
        }
        .position(x: size.width * 0.54, y: size.height * 0.50)
    }
}

private struct SplashTitleView: View {
    let opacity: Double
    let scale: CGFloat
    @State private var shimmerOffset: CGFloat = -280
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                titleText
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.white,
                                Color(red: 0.83, green: 0.90, blue: 1.0),
                                Color(red: 0.60, green: 0.72, blue: 0.88),
                                Color.white.opacity(0.92)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: .white.opacity(pulse ? 0.30 : 0.14), radius: pulse ? 12 : 7)
                    .shadow(color: .cyan.opacity(pulse ? 0.34 : 0.16), radius: pulse ? 24 : 14)

                GeometryReader { proxy in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    Color.white.opacity(0.72),
                                    Color(red: 0.70, green: 0.84, blue: 1.0).opacity(0.46),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(proxy.size.width * 0.18, 62))
                        .offset(x: shimmerOffset)
                        .mask(
                            titleText
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        )
                }
                .allowsHitTesting(false)

                TitleSparkleCluster(isLit: pulse)
            }
            .frame(height: 72)

            Text(T("追随暗夜，找到银河", "Follow the Dark, Find the Milky Way"))
                .font(.system(size: 12, weight: .medium, design: .default))
                .tracking(2.8)
                .foregroundStyle(Color(red: 0.78, green: 0.86, blue: 0.96).opacity(0.70))
                .opacity(pulse ? 0.86 : 0.58)
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.linear(duration: 1.75).repeatForever(autoreverses: false)) {
                shimmerOffset = 280
            }

            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Star Chaser")
    }

    private var titleText: some View {
        Text("Star Chaser")
            .font(.custom("Avenir Next", size: 48).weight(.semibold))
            .tracking(5.4)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }
}

private struct TitleSparkleCluster: View {
    let isLit: Bool

    var body: some View {
        ZStack {
            ForEach(SplashSkyData.titleSparkles) { sparkle in
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: sparkle.size * 0.24, height: sparkle.size * 0.24)
                    Capsule()
                        .fill(.white.opacity(0.78))
                        .frame(width: sparkle.size, height: 1)
                    Capsule()
                        .fill(.white.opacity(0.62))
                        .frame(width: 1, height: sparkle.size * 0.72)
                }
                    .shadow(color: Color(red: 0.60, green: 0.78, blue: 1.0).opacity(0.62), radius: 8)
                    .offset(x: sparkle.x, y: sparkle.y)
                    .opacity(isLit ? sparkle.brightOpacity : sparkle.dimOpacity)
                    .scaleEffect(isLit ? sparkle.scale : 0.72)
                    .animation(
                        .easeInOut(duration: sparkle.duration)
                        .delay(sparkle.delay)
                        .repeatForever(autoreverses: true),
                        value: isLit
                    )
            }
        }
    }
}

private struct SplashStarSpec: Identifiable {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let tint: Color
    let dimOpacity: Double
    let brightOpacity: Double
    let twinkleDelay: Double
    let twinkleDuration: Double
}

private struct SplashDustSpec: Identifiable {
    let id: Int
    let t: CGFloat
    let spread: CGFloat
    let size: CGFloat
    let blur: CGFloat
    let opacity: Double
    let tint: Color
}

private struct TitleSparkleSpec: Identifiable {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let scale: CGFloat
    let dimOpacity: Double
    let brightOpacity: Double
    let delay: Double
    let duration: Double
}

private enum SplashSkyData {
    static let stars: [SplashStarSpec] = (0..<165).map { index in
        let coolTint = Color(red: 0.78, green: 0.92, blue: 1.0)
        let warmTint = Color(red: 1.0, green: 0.90, blue: 0.72)
        let neutralTint = Color.white
        let colorPick = unit(index * 31 + 3)

        return SplashStarSpec(
            id: index,
            x: unit(index * 17 + 5),
            y: unit(index * 29 + 11),
            size: 0.8 + unit(index * 23 + 7) * 2.3,
            tint: colorPick < 0.18 ? warmTint : (colorPick > 0.78 ? coolTint : neutralTint),
            dimOpacity: 0.12 + Double(unit(index * 19 + 13)) * 0.28,
            brightOpacity: 0.52 + Double(unit(index * 37 + 17)) * 0.46,
            twinkleDelay: Double(unit(index * 43 + 19)) * 1.6,
            twinkleDuration: 1.45 + Double(unit(index * 47 + 23)) * 2.4
        )
    }

    static let galaxyDust: [SplashDustSpec] = (0..<110).map { index in
        let colorPick = unit(index * 53 + 9)
        let tint: Color = if colorPick < 0.24 {
            Color.cyan.opacity(0.92)
        } else if colorPick > 0.78 {
            Color.purple.opacity(0.86)
        } else {
            Color.white
        }

        return SplashDustSpec(
            id: index,
            t: unit(index * 41 + 2),
            spread: unit(index * 67 + 4),
            size: 0.8 + unit(index * 71 + 6) * 3.6,
            blur: unit(index * 73 + 8) * 1.3,
            opacity: 0.30 + Double(unit(index * 79 + 10)) * 0.48,
            tint: tint
        )
    }

    static let titleSparkles: [TitleSparkleSpec] = [
        TitleSparkleSpec(id: 0, x: -136, y: -28, size: 13, scale: 1.14, dimOpacity: 0.18, brightOpacity: 0.90, delay: 0.08, duration: 0.95),
        TitleSparkleSpec(id: 1, x: -72, y: 29, size: 9, scale: 1.22, dimOpacity: 0.12, brightOpacity: 0.72, delay: 0.28, duration: 1.10),
        TitleSparkleSpec(id: 2, x: 6, y: -34, size: 11, scale: 1.18, dimOpacity: 0.16, brightOpacity: 0.82, delay: 0.00, duration: 1.25),
        TitleSparkleSpec(id: 3, x: 106, y: -23, size: 15, scale: 1.24, dimOpacity: 0.20, brightOpacity: 0.95, delay: 0.18, duration: 1.05),
        TitleSparkleSpec(id: 4, x: 145, y: 24, size: 8, scale: 1.20, dimOpacity: 0.10, brightOpacity: 0.70, delay: 0.36, duration: 1.18)
    ]

    private static func unit(_ seed: Int) -> CGFloat {
        let raw = sin(Double(seed) * 12.9898) * 43_758.5453
        return CGFloat(raw - floor(raw))
    }
}

#Preview {
    SplashView()
}
