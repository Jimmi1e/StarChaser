@preconcurrency import AVFoundation
import Combine
import SwiftUI
import UIKit

enum CameraSensorFormat: String, CaseIterable, Identifiable {
    case fullFrame = "全画幅"
    case apsc = "APS-C"
    case microFourThirds = "M4/3"

    var id: String { rawValue }

    var cropFactor: Double {
        switch self {
        case .fullFrame: 1
        case .apsc: 1.5
        case .microFourThirds: 2
        }
    }
}

private enum ExposureAutoParameter: String, CaseIterable, Identifiable {
    case iso = "自动 ISO"
    case shutter = "自动快门"

    var id: String { rawValue }
}

private struct ExposureDialValue: Identifiable {
    let id: Int
    let value: Double
    let label: String
    let tickLabel: String?
}

private enum ExposureScales {
    static let apertures = makeScale(
        values: [1.2, 1.4, 1.6, 1.8, 2, 2.2, 2.5, 2.8, 3.2, 3.5, 4, 4.5, 5, 5.6, 6.3, 7.1, 8, 9, 10, 11, 13, 14, 16],
        label: { String(format: "f/%.1f", $0) },
        tickEvery: 3
    )

    static let isos = makeScale(
        values: [50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000, 10000, 12800, 16000, 20000, 25600],
        label: { "ISO \(Int($0))" },
        tickEvery: 3
    )

    static let shutters = makeScale(
        values: [
            1.0 / 8000, 1.0 / 6400, 1.0 / 5000, 1.0 / 4000, 1.0 / 3200,
            1.0 / 2500, 1.0 / 2000, 1.0 / 1600, 1.0 / 1250, 1.0 / 1000,
            1.0 / 800, 1.0 / 640, 1.0 / 500, 1.0 / 400, 1.0 / 320,
            1.0 / 250, 1.0 / 200, 1.0 / 160, 1.0 / 125, 1.0 / 100,
            1.0 / 80, 1.0 / 60, 1.0 / 50, 1.0 / 40, 1.0 / 30,
            1.0 / 25, 1.0 / 20, 1.0 / 15, 1.0 / 13, 1.0 / 10,
            1.0 / 8, 1.0 / 6, 1.0 / 5, 1.0 / 4, 1.0 / 3,
            0.4, 0.5, 0.6, 0.8, 1, 1.3, 1.6, 2, 2.5, 3.2,
            4, 5, 6, 8, 10, 13, 15, 20, 25, 30
        ],
        label: { CameraExposureCalculator.shutterText($0) },
        tickEvery: 4
    )

    static let focalLengths = makeScale(
        values: [12, 14, 16, 18, 20, 24, 28, 35, 40, 50, 70, 85, 100, 135, 200],
        label: { "\(Int($0))mm" },
        tickEvery: 2
    )

    static let compensation = makeScale(
        values: stride(from: -3.0, through: 3.001, by: 1.0 / 3.0).map { $0 },
        label: { String(format: "%+.1f EV", $0) },
        tickEvery: 3
    )

    static let manualEV = makeScale(
        values: stride(from: -10.0, through: 4.001, by: 1.0 / 3.0).map { $0 },
        label: { String(format: "%.1f EV", $0) },
        tickEvery: 3
    )

    static func nearestIndex(in scale: [ExposureDialValue], to value: Double) -> Int {
        scale.indices.min {
            abs(scale[$0].value - value) < abs(scale[$1].value - value)
        } ?? 0
    }

    private static func makeScale(
        values: [Double],
        label: (Double) -> String,
        tickEvery: Int
    ) -> [ExposureDialValue] {
        values.enumerated().map { index, value in
            let text = label(value)
            return ExposureDialValue(
                id: index,
                value: value,
                label: text,
                tickLabel: index.isMultiple(of: tickEvery) ? text : nil
            )
        }
    }
}

private struct CameraExposureSolution {
    let aperture: Double
    let iso: Int
    let shutterSeconds: Double
    let targetEV100: Double
    let exposureErrorEV: Double
    let starSafeShutter: Double
    let stackCount: Int

    var isStarSafe: Bool {
        shutterSeconds <= starSafeShutter * 1.05
    }
}

private enum CameraExposureCalculator {
    static func solve(
        targetEV100: Double,
        aperture: Double,
        iso: Int,
        shutterSeconds: Double,
        autoParameter: ExposureAutoParameter,
        focalLength: Double,
        sensor: CameraSensorFormat
    ) -> CameraExposureSolution {
        var resolvedISO = iso
        var resolvedShutter = shutterSeconds

        switch autoParameter {
        case .iso:
            let exactISO = 100 * aperture * aperture
                / (shutterSeconds * pow(2, targetEV100))
            let index = ExposureScales.nearestIndex(in: ExposureScales.isos, to: exactISO)
            resolvedISO = Int(ExposureScales.isos[index].value)
        case .shutter:
            let exactShutter = aperture * aperture
                / (pow(2, targetEV100) * (Double(iso) / 100))
            let index = ExposureScales.nearestIndex(in: ExposureScales.shutters, to: exactShutter)
            resolvedShutter = ExposureScales.shutters[index].value
        }

        let actualEV100 = log2(aperture * aperture / resolvedShutter)
            - log2(Double(resolvedISO) / 100)
        let safeShutter = min(30, max(0.25, 300 / (focalLength * sensor.cropFactor)))

        let baseStackCount: Int
        switch resolvedISO {
        case ...800: baseStackCount = 8
        case ...1600: baseStackCount = 12
        case ...3200: baseStackCount = 20
        case ...6400: baseStackCount = 30
        default: baseStackCount = 48
        }

        let error = actualEV100 - targetEV100
        let extraFrames = error > 0.35 ? Int(ceil(error * 6)) : 0

        return CameraExposureSolution(
            aperture: aperture,
            iso: resolvedISO,
            shutterSeconds: resolvedShutter,
            targetEV100: targetEV100,
            exposureErrorEV: error,
            starSafeShutter: safeShutter,
            stackCount: min(64, baseStackCount + extraFrames)
        )
    }

    static func shutterText(_ seconds: Double) -> String {
        if seconds >= 1 {
            if seconds.rounded() == seconds {
                return "\(Int(seconds))秒"
            }
            return String(format: "%.1f秒", seconds)
        }

        let denominator = Int((1 / seconds).rounded())
        return "1/\(denominator)秒"
    }
}

@MainActor
final class CameraMeterController: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var measuredEV100: Double?
    @Published private(set) var isRunning = false
    @Published private(set) var isAdjustingExposure = false
    @Published private(set) var exposureTargetOffsetEV = 0.0

    nonisolated(unsafe) let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.starchaser.camera-meter")
    private var observationTimer: Timer?
    private var recentEVSamples: [Double] = []

    var canUseCamera: Bool {
        authorizationStatus == .authorized
    }

    func start() {
        switch authorizationStatus {
        case .authorized:
            configureAndStartSession()
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
                if granted {
                    configureAndStartSession()
                }
            }
        default:
            break
        }
    }

    func stop() {
        observationTimer?.invalidate()
        observationTimer = nil
        recentEVSamples.removeAll()
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
            Task { @MainActor in
                self.isRunning = false
            }
        }
    }

    private func configureAndStartSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.session.inputs.isEmpty {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo

                guard
                    let camera = AVCaptureDevice.default(
                        .builtInWideAngleCamera,
                        for: .video,
                        position: .back
                    ),
                    let input = try? AVCaptureDeviceInput(device: camera),
                    self.session.canAddInput(input)
                else {
                    self.session.commitConfiguration()
                    return
                }

                self.session.addInput(input)
                self.session.commitConfiguration()
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }

            Task { @MainActor in
                self.isRunning = true
                self.startObservation()
            }
        }
    }

    private func startObservation() {
        observationTimer?.invalidate()
        observationTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            guard
                let self,
                let cameraInput = self.session.inputs.first as? AVCaptureDeviceInput
            else { return }

            let camera = cameraInput.device
            let iso = max(Double(camera.iso), 1)
            let duration = max(CMTimeGetSeconds(camera.exposureDuration), 1.0 / 100_000)
            let aperture = max(Double(camera.lensAperture), 0.7)
            let targetOffset = Double(camera.exposureTargetOffset)
            let correctedEV100 = log2(aperture * aperture / duration)
                - log2(iso / 100)
                + targetOffset

            Task { @MainActor in
                self.recentEVSamples.append(correctedEV100)
                if self.recentEVSamples.count > 5 {
                    self.recentEVSamples.removeFirst()
                }
                self.measuredEV100 = self.recentEVSamples.reduce(0, +)
                    / Double(self.recentEVSamples.count)
                self.isAdjustingExposure = camera.isAdjustingExposure
                self.exposureTargetOffsetEV = targetOffset
            }
        }
    }
}

struct CameraMeterWidgetView: View {
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [.indigo, .purple, .cyan.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 76, height: 76)

                Image(systemName: "camera.metering.center.weighted")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("星空相机参数")
                    .font(.headline)
                Text("手机测光 · 无反相机曝光参考")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label("ISO、快门与堆栈建议", systemImage: "slider.horizontal.3")
                    .font(.caption)
                    .foregroundStyle(.indigo)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }
}

struct CameraMeterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var meter = CameraMeterController()

    @State private var sensor: CameraSensorFormat = .fullFrame
    @State private var autoParameter: ExposureAutoParameter = .iso
    @State private var apertureIndex = 7
    @State private var isoIndex = 15
    @State private var shutterIndex = 48
    @State private var focalLengthIndex = 5
    @State private var compensationIndex = 9
    @State private var manualEVIndex = 18
    @State private var lockedMeterEV100: Double?
    @State private var isApertureLocked = false
    @State private var isCompensationLocked = false

    private var measuredEV100: Double {
        lockedMeterEV100 ?? meter.measuredEV100 ?? ExposureScales.manualEV[manualEVIndex].value
    }

    private var targetEV100: Double {
        measuredEV100 + ExposureScales.compensation[compensationIndex].value
    }

    private var solution: CameraExposureSolution {
        CameraExposureCalculator.solve(
            targetEV100: targetEV100,
            aperture: ExposureScales.apertures[apertureIndex].value,
            iso: Int(ExposureScales.isos[isoIndex].value),
            shutterSeconds: ExposureScales.shutters[shutterIndex].value,
            autoParameter: autoParameter,
            focalLength: ExposureScales.focalLengths[focalLengthIndex].value,
            sensor: sensor
        )
    }

    private var accentColor: Color {
        Color.indigo
    }

    var body: some View {
        ZStack {
            themeBackground

            ScrollView {
                VStack(spacing: 18) {
                    meterCard
                    exposureTriangleCard
                    cameraSetupCard
                    recommendationCard
                    stackCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
        }
        .navigationTitle("相机测光")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("关闭")
            }
        }
        .onAppear {
            meter.start()
            recalculateAutomaticParameter()
        }
        .onDisappear {
            meter.stop()
        }
        .onChange(of: meter.measuredEV100) { _, _ in
            guard lockedMeterEV100 == nil else { return }
            recalculateAutomaticParameter()
        }
        .onChange(of: autoParameter) { _, _ in
            recalculateAutomaticParameter()
        }
    }

    @ViewBuilder
    private var themeBackground: some View {
        if colorScheme == .light {
            LinearGradient(
                colors: [
                    Color(uiColor: .systemGroupedBackground),
                    Color(uiColor: .secondarySystemBackground).opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(uiColor: .systemBackground),
                        Color(uiColor: .secondarySystemBackground),
                        Color(uiColor: .systemBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(accentColor.opacity(0.14))
                    .frame(width: 300)
                    .blur(radius: 70)
                    .offset(x: 150, y: -300)
            }
            .ignoresSafeArea()
        }
    }

    private var meterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("手机实时测光", systemImage: "viewfinder")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(meterStatusColor)
                        .frame(width: 7, height: 7)
                    Text(meterStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if meter.canUseCamera {
                CameraPreview(session: meter.session)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .center) {
                        Image(systemName: "plus")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .overlay(alignment: .bottomLeading) {
                        HStack(spacing: 8) {
                            Text(String(format: "EV100 %.1f", measuredEV100))
                            if lockedMeterEV100 != nil {
                                Label("已锁定", systemImage: "lock.fill")
                            }
                        }
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(12)
                    }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(accentColor)
                    Text(cameraUnavailableText)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .background(Color(uiColor: .secondarySystemBackground).opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            if meter.canUseCamera {
                Button {
                    toggleMeterLock()
                } label: {
                    Label(
                        lockedMeterEV100 == nil ? "锁定当前亮度" : "重新实时测光",
                        systemImage: lockedMeterEV100 == nil ? "lock.open" : "arrow.clockwise"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(lockedMeterEV100 == nil ? .white : accentColor)
                    .background(
                        lockedMeterEV100 == nil
                            ? accentColor
                            : accentColor.opacity(0.14)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(meter.measuredEV100 == nil)
            } else {
                HorizontalExposureDial(
                    title: "手动场景亮度",
                    subtitle: "无相机权限时用于模拟手机测光",
                    options: ExposureScales.manualEV,
                    selectedIndex: manualEVIndex,
                    tint: accentColor,
                    isAutomatic: false
                ) { newIndex in
                    manualEVIndex = newIndex
                    recalculateAutomaticParameter()
                }
            }

            Text("把手机对准要拍摄的天空，等待亮度稳定后锁定。读数已包含手机曝光目标偏移修正，并会作为无反相机曝光计算的基准。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .meterPanel()
    }

    private var exposureTriangleCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("曝光三角联动")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("拨动 ISO 会自动计算快门；拨动快门会自动计算 ISO。光圈变化由当前自动项补偿。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("自动补偿项", selection: $autoParameter) {
                ForEach(ExposureAutoParameter.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            HorizontalExposureDial(
                title: "光圈",
                subtitle: "镜头实际使用光圈",
                options: ExposureScales.apertures,
                selectedIndex: apertureIndex,
                tint: accentColor,
                isAutomatic: false,
                isLocked: isApertureLocked,
                onLockToggle: {
                    isApertureLocked.toggle()
                    DialHaptics.shared.impact()
                }
            ) { newIndex in
                apertureIndex = newIndex
                recalculateAutomaticParameter()
            }

            HorizontalExposureDial(
                title: "ISO",
                subtitle: autoParameter == .iso ? "根据手机亮度和当前快门自动计算" : "拨动后由快门自动补偿",
                options: ExposureScales.isos,
                selectedIndex: isoIndex,
                tint: accentColor,
                isAutomatic: autoParameter == .iso
            ) { newIndex in
                isoIndex = newIndex
                if autoParameter == .iso {
                    autoParameter = .shutter
                } else {
                    recalculateAutomaticParameter()
                }
            }

            HorizontalExposureDial(
                title: "快门",
                subtitle: autoParameter == .shutter ? "根据手机亮度和当前 ISO 自动计算" : "拨动后由 ISO 自动补偿",
                options: ExposureScales.shutters,
                selectedIndex: shutterIndex,
                tint: accentColor,
                isAutomatic: autoParameter == .shutter
            ) { newIndex in
                shutterIndex = newIndex
                if autoParameter == .shutter {
                    autoParameter = .iso
                } else {
                    recalculateAutomaticParameter()
                }
            }

            HorizontalExposureDial(
                title: "曝光修正",
                subtitle: "负值压暗天空，正值提升暗部",
                options: ExposureScales.compensation,
                selectedIndex: compensationIndex,
                tint: accentColor,
                isAutomatic: false,
                isLocked: isCompensationLocked,
                onLockToggle: {
                    isCompensationLocked.toggle()
                    DialHaptics.shared.impact()
                }
            ) { newIndex in
                compensationIndex = newIndex
                recalculateAutomaticParameter()
            }
        }
        .meterPanel()
    }

    private var cameraSetupCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("相机与镜头")
                .font(.headline)
                .foregroundStyle(.primary)

            Picker("画幅", selection: $sensor) {
                ForEach(CameraSensorFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)

            HorizontalExposureDial(
                title: "镜头焦距",
                subtitle: "用于估算星点不拖线的最长快门",
                options: ExposureScales.focalLengths,
                selectedIndex: focalLengthIndex,
                tint: accentColor,
                isAutomatic: false
            ) { newIndex in
                focalLengthIndex = newIndex
            }
        }
        .meterPanel()
    }

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("当前曝光参考")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text(autoParameter.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(accentColor.opacity(0.14))
                    .clipShape(Capsule())
            }

            HStack(spacing: 10) {
                exposureResultTile(
                    title: "光圈",
                    value: String(format: "f/%.1f", solution.aperture),
                    icon: "camera.aperture"
                )
                exposureResultTile(
                    title: "ISO",
                    value: "\(solution.iso)",
                    icon: "circle.lefthalf.filled"
                )
                exposureResultTile(
                    title: "快门",
                    value: CameraExposureCalculator.shutterText(solution.shutterSeconds),
                    icon: "timer"
                )
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: exposureStatusIcon)
                    .foregroundStyle(exposureStatusColor)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(exposureStatusTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(exposureStatusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(exposureStatusColor.opacity(0.11))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .meterPanel()
    }

    private var stackCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("堆栈建议", systemImage: "square.stack.3d.up")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("建议拍摄 \(solution.stackCount) 张 RAW，每张 \(CameraExposureCalculator.shutterText(solution.shutterSeconds))，间隔 1 秒。另拍 8 到 12 张暗场。")
                .font(.subheadline)
                .foregroundStyle(.primary)

            Text(solution.isStarSafe
                 ? "当前快门在估算的不拖线范围内。堆栈可降低高 ISO 噪点并保留星点。"
                 : "当前快门超过约 \(CameraExposureCalculator.shutterText(solution.starSafeShutter)) 的星点安全值，建议提高 ISO、开大光圈或使用赤道仪。")
                .font(.caption)
                .foregroundStyle(solution.isStarSafe ? Color.secondary : Color.orange)
        }
        .meterPanel()
    }

    private func exposureResultTile(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(accentColor)
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var meterStatusColor: Color {
        if lockedMeterEV100 != nil { return accentColor }
        if meter.isAdjustingExposure || abs(meter.exposureTargetOffsetEV) > 0.5 { return .orange }
        return meter.isRunning ? .green : .gray
    }

    private var meterStatusText: String {
        if lockedMeterEV100 != nil { return "亮度已锁定" }
        if meter.isAdjustingExposure { return "测光稳定中" }
        if abs(meter.exposureTargetOffsetEV) > 0.5 {
            return String(format: "暗场修正 %+.1f EV", meter.exposureTargetOffsetEV)
        }
        return meter.isRunning ? "实时测光" : "未启动"
    }

    private var cameraUnavailableText: String {
        switch meter.authorizationStatus {
        case .denied, .restricted:
            return "未获得相机权限，可先用下方 EV 拨轮手动估算。"
        default:
            return "正在准备相机测光，也可先手动估算。"
        }
    }

    private var exposureStatusTitle: String {
        if abs(solution.exposureErrorEV) < 0.2 {
            return "与手机测光基本一致"
        }
        if solution.exposureErrorEV > 0 {
            return String(format: "当前组合偏暗 %.1f EV", solution.exposureErrorEV)
        }
        return String(format: "当前组合偏亮 %.1f EV", abs(solution.exposureErrorEV))
    }

    private var exposureStatusDetail: String {
        if abs(solution.exposureErrorEV) < 0.2 {
            return String(format: "目标 EV100 %.1f，离散档位误差小于 0.2 档。", solution.targetEV100)
        }
        return autoParameter == .iso
            ? "ISO 已到可选档位边界，可调整快门或光圈继续匹配。"
            : "快门已到可选档位边界，可调整 ISO 或光圈继续匹配。"
    }

    private var exposureStatusIcon: String {
        abs(solution.exposureErrorEV) < 0.2 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var exposureStatusColor: Color {
        abs(solution.exposureErrorEV) < 0.2 ? .green : .orange
    }

    private func toggleMeterLock() {
        if lockedMeterEV100 == nil {
            lockedMeterEV100 = meter.measuredEV100
        } else {
            lockedMeterEV100 = nil
        }
        DialHaptics.shared.impact()
        recalculateAutomaticParameter()
    }

    private func recalculateAutomaticParameter() {
        let newSolution = solution
        switch autoParameter {
        case .iso:
            isoIndex = ExposureScales.nearestIndex(
                in: ExposureScales.isos,
                to: Double(newSolution.iso)
            )
        case .shutter:
            shutterIndex = ExposureScales.nearestIndex(
                in: ExposureScales.shutters,
                to: newSolution.shutterSeconds
            )
        }
    }
}

private struct HorizontalExposureDial: View {
    let title: String
    let subtitle: String
    let options: [ExposureDialValue]
    let selectedIndex: Int
    let tint: Color
    let isAutomatic: Bool
    let isLocked: Bool
    let onLockToggle: (() -> Void)?
    let onSelectionChanged: (Int) -> Void

    @State private var dragStartIndex: Int?
    private let tickWidth: CGFloat = 22

    init(
        title: String,
        subtitle: String,
        options: [ExposureDialValue],
        selectedIndex: Int,
        tint: Color,
        isAutomatic: Bool,
        isLocked: Bool = false,
        onLockToggle: (() -> Void)? = nil,
        onSelectionChanged: @escaping (Int) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.options = options
        self.selectedIndex = selectedIndex
        self.tint = tint
        self.isAutomatic = isAutomatic
        self.isLocked = isLocked
        self.onLockToggle = onLockToggle
        self.onSelectionChanged = onSelectionChanged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))

                        if isAutomatic {
                            Text("AUTO")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(tint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(tint.opacity(0.14))
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 9) {
                    Text(options[selectedIndex].label)
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(tint)

                    if let onLockToggle {
                        Button(action: onLockToggle) {
                            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isLocked ? tint : .secondary)
                                .frame(width: 28, height: 28)
                                .background(
                                    isLocked ? tint.opacity(0.14) : Color.primary.opacity(0.06),
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isLocked ? "解锁\(title)" : "锁定\(title)")
                    }
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.primary.opacity(0.045))

                    HStack(spacing: 0) {
                        ForEach(options) { option in
                            dialTick(option)
                                .frame(width: tickWidth)
                        }
                    }
                    .offset(
                        x: proxy.size.width / 2
                            - tickWidth / 2
                            - CGFloat(selectedIndex) * tickWidth
                    )
                    .animation(.snappy(duration: 0.14), value: selectedIndex)
                    .opacity(isLocked ? 0.55 : 1)

                    LinearGradient(
                        colors: [.black.opacity(0.18), .clear, .clear, .black.opacity(0.18)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .allowsHitTesting(false)
                }
                .clipped()
                .contentShape(Rectangle())
                .allowsHitTesting(!isLocked)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            if dragStartIndex == nil {
                                dragStartIndex = selectedIndex
                                DialHaptics.shared.prepare()
                            }

                            guard let start = dragStartIndex else { return }
                            let stepDelta = Int((-value.translation.width / tickWidth).rounded())
                            let nextIndex = min(max(start + stepDelta, 0), options.count - 1)

                            guard nextIndex != selectedIndex else { return }
                            onSelectionChanged(nextIndex)
                            DialHaptics.shared.selection()
                        }
                        .onEnded { _ in
                            dragStartIndex = nil
                        }
                )
            }
            .frame(height: 72)
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(options[selectedIndex].label)
        .accessibilityAdjustableAction { direction in
            guard !isLocked else { return }
            switch direction {
            case .increment:
                onSelectionChanged(min(selectedIndex + 1, options.count - 1))
            case .decrement:
                onSelectionChanged(max(selectedIndex - 1, 0))
            @unknown default:
                break
            }
            DialHaptics.shared.selection()
        }
    }

    private func dialTick(_ option: ExposureDialValue) -> some View {
        let isSelected = option.id == selectedIndex
        let isMajor = option.tickLabel != nil

        return VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(isSelected ? tint : Color.secondary.opacity(isMajor ? 0.75 : 0.38))
                .frame(width: isSelected ? 3 : 1, height: isSelected ? 31 : (isMajor ? 24 : 15))

            if let tickLabel = option.tickLabel {
                Text(tickLabel)
                    .font(.system(size: 8, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? tint : .secondary)
                    .fixedSize()
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

@MainActor
private final class DialHaptics {
    static let shared = DialHaptics()

    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)

    func prepare() {
        selectionGenerator.prepare()
    }

    func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    func impact() {
        impactGenerator.impactOccurred()
        impactGenerator.prepare()
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

private extension View {
    func meterPanel() -> some View {
        padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
    }
}
