//
//  SkyForecastView.swift
//  StarChaser
//
//  Created by Codex on 2026/6/16.
//

import CoreLocation
import SwiftUI

struct SkyForecastWidgetView: View {
    let coordinate: CLLocationCoordinate2D?

    @State private var snapshot: SkyForecastSnapshot?
    @State private var errorText: String?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(T("观星预测", "Sky Forecast"))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(T("附近暗空推荐 · 未来 5 天", "Nearby dark-sky picks · next 5 days"))
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.72))
                }

                Spacer()

                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.cyan, Color.indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Group {
                if let coordinate {
                    content(for: coordinate)
                } else {
                    loadingState(
                        title: T("等待定位", "Waiting for location"),
                        detail: T("定位成功后会显示附近观测推荐。", "Nearby observing recommendations appear after location is ready.")
                    )
                }
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.16),
                    Color(red: 0.08, green: 0.15, blue: 0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .task(id: widgetTaskID) {
            guard let coordinate else { return }
            await refresh(for: coordinate)
        }
    }

    private var widgetTaskID: String {
        guard let coordinate else { return "no-location" }
        return cacheKey(for: coordinate)
    }

    @ViewBuilder
    private func content(for coordinate: CLLocationCoordinate2D) -> some View {
        if isLoading && snapshot == nil {
            loadingState(
                title: T("正在评估附近夜空", "Evaluating nearby night skies"),
                detail: T("综合天气、月相和光污染计算最佳地点。", "Combining weather, moonlight, and light pollution to rank nearby spots.")
            )
        } else if let best = snapshot?.bestRecommendation, let bestDay = best.bestDay {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(T("今晚最佳", "Best Pick"))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.72))
                        Text(best.name)
                            .font(.title3.bold())
                            .foregroundColor(.white)
                        Text(best.subtitle)
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.66))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        scoreBadge(best.overallScore)
                        Text(best.bortleClass.title)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.white.opacity(0.72))
                    }
                }

                HStack(spacing: 10) {
                    metricPill(systemName: "arrow.triangle.swap", text: best.distanceText)
                    metricPill(systemName: "moon.stars.fill", text: bestDay.recommendationLabel)
                    metricPill(systemName: "cloud.fill", text: TF("云量 %d%%", "Cloud %d%%", bestDay.cloudCover))
                }

                Text(best.shortReason)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.84))
                    .lineSpacing(4)

                HStack(spacing: 8) {
                    ForEach(Array(best.days.prefix(3))) { day in
                        dayChip(day)
                    }
                }
            }
        } else if let errorText {
            loadingState(
                title: T("暂未生成推荐", "Forecast unavailable"),
                detail: errorText
            )
        } else {
            loadingState(
                title: T("准备预测中", "Preparing forecast"),
                detail: T("正在整理附近候选观测点。", "Gathering nearby candidate observing spots.")
            )
        }
    }

    private func refresh(for coordinate: CLLocationCoordinate2D) async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            snapshot = try await SkyForecastService.fetchSnapshot(for: coordinate, radius: .km100)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        "\(coordinate.latitude.rounded(toPlaces: 3))-\(coordinate.longitude.rounded(toPlaces: 3))"
    }

    private func scoreBadge(_ score: Int) -> some View {
        Text("\(score)")
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.14), in: Capsule())
    }

    private func metricPill(systemName: String, text: String) -> some View {
        Label(text, systemImage: systemName)
            .font(.caption.weight(.semibold))
            .foregroundColor(.white.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.10), in: Capsule())
    }

    private func dayChip(_ day: SkyForecastDay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.date, format: .dateTime.month().day())
                .font(.caption2.weight(.semibold))
                .foregroundColor(.white.opacity(0.7))
            Text("\(day.score)")
                .font(.headline.weight(.bold))
                .foregroundColor(.white)
            Text(day.recommendationLabel)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.68))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func loadingState(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLoading {
                ProgressView()
                    .tint(.white)
            }
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Text(detail)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.72))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

struct SkyForecastDetailView: View {
    let coordinate: CLLocationCoordinate2D?

    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: SkyForecastSnapshot?
    @State private var errorText: String?
    @State private var isLoading = false
    @State private var activeRequestID = UUID()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 18) {
                        headlineCard
                        statusCard

                        if let recommendations = snapshot?.recommendations, !recommendations.isEmpty {
                            ForEach(recommendations) { recommendation in
                                recommendationCard(recommendation)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle(T("观星预测", "Sky Forecast"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(T("关闭", "Close")) { dismiss() }
                }
            }
            .task(id: requestKey) {
                await refresh()
            }
        }
    }

    private var requestKey: String {
        let coordText: String
        if let coordinate {
            coordText = "\(coordinate.latitude.rounded(toPlaces: 3))-\(coordinate.longitude.rounded(toPlaces: 3))"
        } else {
            coordText = "no-location"
        }
        return "100-\(coordText)"
    }

    private var headlineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(T("附近暗空推荐", "Nearby Dark-Sky Picks"))
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(T("基于 5 天天气、月相干扰和光污染等级，为你筛选附近更适合的观测地点。默认重点看未来 3 天，后两天作为延伸参考。", "Ranks nearby observing spots using a 5-day forecast, moonlight interference, and local light pollution. The first 3 days are emphasized, with days 4-5 as extended guidance."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineSpacing(4)

            if let best = snapshot?.bestRecommendation, let day = best.bestDay {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(T("当前最佳", "Current Best"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(best.name)
                            .font(.title3.bold())
                        Text(TF("%@ · %@ · %@", "%@ · %@ · %@", best.distanceText, best.bortleClass.title, day.recommendationLabel))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(best.overallScore)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var statusCard: some View {
        if isLoading {
            HStack(spacing: 12) {
                ProgressView()
                Text(
                    T("正在更新 100 km 范围推荐...", "Refreshing 100 km recommendations...")
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else if let errorText {
            Text(errorText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else if snapshot?.recommendations.isEmpty == true {
            Text(
                T("100 km 内暂无理想观测点。", "No strong observing spot within 100 km.")
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func recommendationCard(_ recommendation: SkyForecastRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recommendation.name)
                        .font(.title3.bold())
                    Text(recommendation.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(recommendation.shortReason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(recommendation.overallScore)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(recommendation.bortleClass.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                detailPill(systemName: "location.fill", text: recommendation.distanceText)
                detailPill(systemName: "sparkles", text: recommendation.confidenceLabel)
                detailPill(systemName: "light.max", text: recommendation.bortleClass.description)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recommendation.days) { day in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(day.date, format: .dateTime.month().day().weekday(.abbreviated))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("\(day.score)")
                                .font(.title3.bold())
                            Text(day.recommendationLabel)
                                .font(.caption)
                                .foregroundStyle(.primary)
                            Text(day.weatherLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                            Divider()
                            Text(TF("风 %.0f km/h", "Wind %.0f km/h", day.windSpeed))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(TF("降水概率 %d%%", "Rain chance %d%%", day.precipitationProbability))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 170, alignment: .leading)
                        .padding(12)
                        .background(Color(UIColor.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
        }
        .padding(18)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func detailPill(systemName: String, text: String) -> some View {
        Label(text, systemImage: systemName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(UIColor.systemBackground), in: Capsule())
    }

    private func refresh() async {
        guard let coordinate else {
            errorText = T("请先开启定位权限，再生成附近观测推荐。", "Enable location access first to generate nearby observing recommendations.")
            snapshot = nil
            return
        }

        let requestID = UUID()
        activeRequestID = requestID
        isLoading = true
        errorText = nil
        snapshot = nil

        defer {
            if activeRequestID == requestID {
                isLoading = false
            }
        }

        do {
            let newSnapshot = try await SkyForecastService.fetchSnapshot(
                for: coordinate,
                radius: .km100
            )

            guard !Task.isCancelled, activeRequestID == requestID else { return }
            snapshot = newSnapshot
        } catch is CancellationError {
            guard activeRequestID == requestID else { return }
        } catch {
            guard !Task.isCancelled, activeRequestID == requestID else { return }
            errorText = error.localizedDescription
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

#Preview {
    SkyForecastWidgetView(
        coordinate: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
    )
    .padding()
}
