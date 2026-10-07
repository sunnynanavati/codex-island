import Foundation
import CoreGraphics

struct PrimaryTaskSelector: Sendable {
    private(set) var selectedID: String?
    private(set) var selectedAt: Date?
    var minimumHold: TimeInterval = 8

    mutating func select(from tasks: [TaskSnapshot], now: Date) -> String? {
        let active = tasks.filter(\.state.isActive)
        if let selectedID,
           active.contains(where: { $0.id == selectedID }),
           let selectedAt,
           now.timeIntervalSince(selectedAt) < minimumHold {
            return selectedID
        }
        let next = active.sorted {
            if $0.state.needsAttention != $1.state.needsAttention { return $0.state.needsAttention }
            return $0.updatedAt > $1.updatedAt
        }.first?.id ?? tasks.first(where: {
            $0.state == .completed && now.timeIntervalSince($0.updatedAt) >= 0 &&
                now.timeIntervalSince($0.updatedAt) < 3
        })?.id
        if next != selectedID {
            selectedID = next
            selectedAt = now
        }
        return selectedID
    }
}

enum PresentationState: Equatable, Sendable {
    case compact, preview, pinned

    mutating func hover(_ inside: Bool) {
        switch (self, inside) {
        case (.compact, true): self = .preview
        case (.preview, false): self = .compact
        default: break
        }
    }
    mutating func click() {
        self = .pinned
    }
    mutating func dismiss() { self = .compact }
    var isExpanded: Bool { self != .compact }
}

struct Calibration: Codable, Equatable, Sendable {
    var horizontalOffset: Double
    var widthAdjustment: Double
    var shoulderReach: Double
    var adaptiveWidth: Bool
    var waveReach: Double?
    var compactSize: Double

    init(horizontalOffset: Double = 0, widthAdjustment: Double = 0, shoulderReach: Double = 100,
         adaptiveWidth: Bool = true, waveReach: Double? = nil, compactSize: Double = 0) {
        self.horizontalOffset = horizontalOffset
        self.widthAdjustment = widthAdjustment
        self.shoulderReach = shoulderReach
        self.adaptiveWidth = adaptiveWidth
        self.waveReach = waveReach
        self.compactSize = compactSize
    }

    private enum CodingKeys: String, CodingKey {
        case horizontalOffset, widthAdjustment, shoulderReach, adaptiveWidth, waveReach, compactSize
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        horizontalOffset = try values.decodeIfPresent(Double.self, forKey: .horizontalOffset) ?? 0
        widthAdjustment = try values.decodeIfPresent(Double.self, forKey: .widthAdjustment) ?? 0
        shoulderReach = try values.decodeIfPresent(Double.self, forKey: .shoulderReach) ?? 100
        adaptiveWidth = try values.decodeIfPresent(Bool.self, forKey: .adaptiveWidth) ?? true
        waveReach = try values.decodeIfPresent(Double.self, forKey: .waveReach)
        compactSize = try values.decodeIfPresent(Double.self, forKey: .compactSize) ?? 0
    }

    static let defaultsKey = "CodexIsland.calibration"

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    static func load(from defaults: UserDefaults = .standard) -> Calibration {
        guard let data = defaults.data(forKey: defaultsKey),
              let value = try? JSONDecoder().decode(Self.self, from: data)
        else { return .init() }
        return value
    }
}

struct IslandLayout: Equatable, Sendable {
    let compactFrame: CGRect
    let previewFrame: CGRect
    let expandedFrame: CGRect
    let notchGapWidth: CGFloat
    let shoulderReach: CGFloat
    let compactShoulderReach: CGFloat
    let screenMinX: CGFloat
    let screenMaxX: CGFloat
    var railGeometry: RailGeometry? = nil

    func shoulderReach(at progress: Double) -> CGFloat {
        let p = CGFloat(min(1, max(0, progress)))
        return compactShoulderReach + (shoulderReach - compactShoulderReach) * p
    }

    func bodyWidth(at progress: Double) -> CGFloat {
        max(0, frame(at: progress).width - 2 * shoulderReach(at: progress))
    }

    func withCompactWidth(_ width: CGFloat) -> IslandLayout {
        func resized(_ frame: CGRect, width: CGFloat) -> CGRect {
            let width = min(max(0, width), screenMaxX - screenMinX)
            let centeredX = frame.minX + (frame.width - width) / 2
            let x = min(max(centeredX, screenMinX), screenMaxX - width)
            return CGRect(x: x, y: frame.minY, width: width, height: frame.height)
        }
        let compact = resized(compactFrame, width: width)
        let preview = railGeometry == nil
            ? resized(previewFrame, width: previewFrame.width + (width - compactFrame.width) / 2)
            : previewFrame
        return IslandLayout(compactFrame: compact, previewFrame: preview,
                            expandedFrame: expandedFrame, notchGapWidth: notchGapWidth,
                            shoulderReach: shoulderReach, compactShoulderReach: compactShoulderReach, screenMinX: screenMinX,
                            screenMaxX: screenMaxX, railGeometry: railGeometry)
    }

    static func calculate(
        screenFrame: CGRect,
        safeTopInset: CGFloat,
        leftAuxiliaryMaxX: CGFloat?,
        rightAuxiliaryMinX: CGFloat?,
        calibration: Calibration,
        compactWingWidth: CGFloat? = nil,
        railGeometry: RailGeometry? = nil,
        usesWorkingWidth: Bool = true
    ) -> IslandLayout {
        let nativeGap: CGFloat
        if let leftAuxiliaryMaxX, let rightAuxiliaryMinX, rightAuxiliaryMinX > leftAuxiliaryMaxX {
            nativeGap = rightAuxiliaryMinX - leftAuxiliaryMaxX
        } else {
            nativeGap = 180
        }
        let compactHeight = safeTopInset > 0 ? safeTopInset : 32
        // Reserve an enlarged clear gap for position calibration so neither wing
        // can move beneath the physical notch.
        let offset = CGFloat(calibration.horizontalOffset)
        let effectiveGap = nativeGap + (railGeometry == nil ? 0 : 2 * abs(offset))
        let contentWidth = railGeometry.map { effectiveGap + 2 * $0.wingWidth }
            ?? compactWingWidth.map { nativeGap + 2 * (max(22, $0) + CompactRailSizing.railInset) }
        let width = min(screenFrame.width, contentWidth.map {
            if railGeometry != nil {
                return $0 + (usesWorkingWidth && !calibration.adaptiveWidth ? max(0, calibration.widthAdjustment) : 0)
            }
            return max($0, nativeGap + 112 + (calibration.adaptiveWidth ? 0 : calibration.widthAdjustment))
        } ?? max(nativeGap + 144, nativeGap + 226 + calibration.widthAdjustment))
        let shoulderReach = min(max(0, calibration.shoulderReach),
                                max(0, (screenFrame.width - max(456, width)) / 2))
        let requestedWave = calibration.waveReach.map { CGFloat(min(220, max(40, $0))) }
            ?? (shoulderReach > 0 ? max(1.25 * shoulderReach, compactHeight * 4) : 0)
        let compactReach = min(requestedWave, max(0, (screenFrame.width - width) / 2))
        let minimum = min(screenFrame.width, width + 2 * compactReach)
        // Derive the hover target from content, not the slider's value, so the
        // maximum cannot chase itself as the user widens the compact island.
        let hoverWidth = min(screenFrame.width, max(392 + 2 * shoulderReach, minimum + (railGeometry == nil ? 96 : 0)))
        let fraction = CGFloat(usesWorkingWidth ? min(1, max(0, calibration.compactSize)) : 0)
        let compactWidth = minimum + fraction * (hoverWidth - minimum)
        let expandedWidth = min(screenFrame.width, max(456 + 2 * shoulderReach, hoverWidth + 64))
        let top = screenFrame.maxY
        let notchCenter = leftAuxiliaryMaxX.flatMap { left in rightAuxiliaryMinX.map { (left + $0) / 2 } } ?? screenFrame.midX
        func frame(width desiredWidth: CGFloat, height: CGFloat) -> CGRect {
            let width = min(desiredWidth, screenFrame.width)
            let x = min(max(notchCenter - width / 2 + offset,
                            screenFrame.minX), screenFrame.maxX - width)
            let height = min(height, max(compactHeight, screenFrame.height - 24))
            return CGRect(x: x, y: top - height, width: width, height: height)
        }
        return IslandLayout(
            compactFrame: frame(width: compactWidth, height: compactHeight),
            previewFrame: frame(width: hoverWidth, height: compactHeight + 116),
            expandedFrame: frame(width: expandedWidth, height: compactHeight + 442),
            notchGapWidth: effectiveGap, shoulderReach: shoulderReach, compactShoulderReach: compactReach,
            screenMinX: screenFrame.minX, screenMaxX: screenFrame.maxX, railGeometry: railGeometry
        )
    }

    func frame(at progress: Double) -> CGRect {
        let p = min(2, max(0, progress))
        if p == 0 { return compactFrame }
        if p == 1 { return previewFrame }
        if p == 2 { return expandedFrame }
        let height = interpolate(compactFrame.height, previewFrame.height, expandedFrame.height, at: p)
        let width = interpolate(compactFrame.width, previewFrame.width, expandedFrame.width, at: p)
        let x = interpolate(compactFrame.minX, previewFrame.minX, expandedFrame.minX, at: p)
        let upperX = max(screenMinX, (screenMaxX - width).nextDown)
        return CGRect(x: min(max(x, screenMinX), upperX),
                      y: compactFrame.maxY - height,
                      width: width,
                      height: height)
    }

    private func interpolate(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, at p: Double) -> CGFloat {
        let d0 = b - a
        let d1 = c - b
        let midpointTangent: CGFloat = d0 * d1 <= 0 ? 0 : 2 * d0 * d1 / (d0 + d1)
        let v0 = p < 1 ? a : b
        let v1 = p < 1 ? b : c
        let s0 = p < 1 ? d0 : midpointTangent
        let s1 = p < 1 ? midpointTangent : d1
        let t = CGFloat(p < 1 ? p : p - 1)
        let t2 = t * t
        let t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * v0 + (t3 - 2 * t2 + t) * s0
            + (-2 * t3 + 3 * t2) * v1 + (t3 - t2) * s1
    }
}

enum IslandPage: Equatable { case activity, recent, question(String), task(String) }

enum IslandGlyphTheme: String, CaseIterable, Codable { case cube, symbols }

enum CompactRailSizing {
    static let quotaDiameter: CGFloat = 20
    static let statusGap: CGFloat = 9
    static let statusSideInset: CGFloat = 8
    static let railInset: CGFloat = 8

    static func wingWidth(cubeCount: Int, statusTextWidth: CGFloat) -> CGFloat {
        let visible = min(3, max(1, cubeCount))
        let statusWidth = max(0, statusTextWidth) + statusGap + quotaDiameter
            + 2 * statusSideInset
        return max(52, statusWidth) + CGFloat((visible - 1) * 28)
            + (cubeCount > visible ? 29 : 0)
    }
}

struct IslandSpring {
    var value: Double = 0
    var velocity: Double = 0
    var target: Double = 0

    var isSettled: Bool { abs(value - target) < 0.0005 && abs(velocity) < 0.004 }

    mutating func advance(by dt: Double) {
        let omega = target >= value ? 22.0 : 26.0
        let delta = value - target
        let c = velocity + omega * delta
        let decay = exp(-omega * dt)
        value = target + (delta + c * dt) * decay
        velocity = (velocity - omega * c * dt) * decay
        if isSettled { value = target; velocity = 0 }
    }
}

enum IslandContour {
    // Compact S-curves ease horizontally into both edges. Expansion morphs the
    // lower tangent vertically to meet the drawer side without a corner.
    // Share this contour with native hit testing so the clear shoulders pass clicks through.
    static func path(size: CGSize, radius: CGFloat,
                     shoulderReach: CGFloat, shoulderHeight: CGFloat,
                     shoulderBlend: CGFloat) -> CGPath {
        let w = max(0, size.width), h = max(0, size.height)
        let s = min(max(0, shoulderReach), w / 2)
        let r = min(max(0, radius), h, max(0, (w - 2 * s) / 2))
        let d = min(max(0, shoulderHeight), h - r)
        let k: CGFloat = 0.5522847498
        let blend = min(1, max(0, shoulderBlend))
        let path = CGMutablePath()
        // Quintic smoothstep has zero slope and curvature at both ends: a wave,
        // not a rounded corner. Hermite segments preserve its endpoint tangents.
        func shoulder(_ t: CGFloat) -> (point: CGPoint, tangent: CGPoint) {
            let t2 = t * t, t3 = t2 * t
            let wave = t3 * (10 + t * (-15 + 6 * t))
            let waveSlope = 30 * t2 * (1 - t) * (1 - t)
            let u = 1 - t
            let expandedX = 3 * u * u * t * k + 3 * u * t2 + t3
            let expandedY = 3 * u * t2 * (1 - k) + t3
            let dx = 3 * u * u * k + 6 * u * t * (1 - k)
            let dy = 6 * u * t * (1 - k) + 3 * t2 * k
            return (CGPoint(x: w - s * ((1 - blend) * t + blend * expandedX),
                            y: d * ((1 - blend) * wave + blend * expandedY)),
                    CGPoint(x: -s * ((1 - blend) + blend * dx),
                            y: d * ((1 - blend) * waveSlope + blend * dy)))
        }
        func addShoulder(mirrored: Bool) {
            let segments = 8
            for index in 0..<segments {
                let t0 = mirrored ? 1 - CGFloat(index) / CGFloat(segments) : CGFloat(index) / CGFloat(segments)
                let t1 = mirrored ? 1 - CGFloat(index + 1) / CGFloat(segments) : CGFloat(index + 1) / CGFloat(segments)
                let a = shoulder(t0), b = shoulder(t1), step = (t1 - t0) / 3
                func mirror(_ point: CGPoint) -> CGPoint {
                    CGPoint(x: mirrored ? w - point.x : point.x, y: point.y)
                }
                path.addCurve(to: mirror(b.point),
                              control1: mirror(CGPoint(x: a.point.x + a.tangent.x * step, y: a.point.y + a.tangent.y * step)),
                              control2: mirror(CGPoint(x: b.point.x - b.tangent.x * step, y: b.point.y - b.tangent.y * step)))
            }
        }
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: w, y: 0))
        addShoulder(mirrored: false)
        path.addLine(to: CGPoint(x: w - s, y: h - r))
        path.addCurve(to: CGPoint(x: w - s - r, y: h),
                      control1: CGPoint(x: w - s, y: h - r + k * r),
                      control2: CGPoint(x: w - s - r + k * r, y: h))
        path.addLine(to: CGPoint(x: s + r, y: h))
        path.addCurve(to: CGPoint(x: s, y: h - r),
                      control1: CGPoint(x: s + r - k * r, y: h),
                      control2: CGPoint(x: s, y: h - r + k * r))
        path.addLine(to: CGPoint(x: s, y: d))
        addShoulder(mirrored: true)
        path.closeSubpath()
        return path
    }
}

enum IslandHitRegion {
    static func contains(_ point: CGPoint, size: CGSize, radius: CGFloat,
                         shoulderReach: CGFloat, shoulderHeight: CGFloat,
                         shoulderBlend: CGFloat) -> Bool {
        guard CGRect(origin: .zero, size: size).contains(point) else { return false }
        // AppKit uses a bottom origin; the drawing contour uses a top origin.
        return IslandContour.path(size: size, radius: radius,
                                  shoulderReach: shoulderReach, shoulderHeight: shoulderHeight,
                                  shoulderBlend: shoulderBlend)
            .contains(CGPoint(x: point.x, y: size.height - point.y))
    }
}

struct SnapshotKeeper: Sendable {
    private(set) var snapshot = IslandSnapshot.empty
    mutating func accept(_ result: Result<IslandSnapshot, Error>, now: Date = Date()) {
        switch result {
        case let .success(value): snapshot = value
        case let .failure(error):
            snapshot.errorMessage = error.localizedDescription
            snapshot.refreshedAt = now
        }
    }
}
