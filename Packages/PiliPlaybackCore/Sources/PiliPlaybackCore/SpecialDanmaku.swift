import Foundation

/// Bilibili mode-7 array format. Coordinates follow the upstream canvas renderer:
/// fractions are relative, while integer strings/pixels use a 1920 × 1080 canvas.
public struct SpecialDanmaku: Hashable, Sendable {
    public let text: String
    public let duration: Double
    public let startX: Double
    public let startY: Double
    public let endX: Double
    public let endY: Double
    public let alphaFrom: Double
    public let alphaTo: Double
    public let rotationZ: Double
    public let rotationY: Double
    public let moveDuration: Double
    public let moveDelay: Double
    public let stroke: Bool
    public let cubicEasing: Bool

    public init?(json: String) {
        guard json.utf8.count <= 32_768,
              let values = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any],
              values.count >= 5, let text = values[4] as? String, !text.isEmpty, text.count <= 2_000 else { return nil }
        func number(_ i: Int, _ fallback: Double = 0) -> Double {
            guard i < values.count else { return fallback }
            let n = (values[i] as? NSNumber)?.doubleValue ?? (values[i] as? String).flatMap(Double.init)
            return n?.isFinite == true ? n! : fallback
        }
        func coordinate(_ i: Int, canvas: Double, fallback: Double = 0) -> Double {
            guard i < values.count else { return fallback }
            let n = number(i)
            let pixel = abs(n) > 1 || ((values[i] as? String).map { !$0.contains(".") } ?? false)
            return min(10, max(-10, pixel ? n / canvas : n))
        }
        let lifetime = number(3)
        guard lifetime > 0, lifetime <= 120 else { return nil }
        self.text = text.replacingOccurrences(of: "/n", with: "\n")
        duration = lifetime
        startX = coordinate(0, canvas: 1920); startY = coordinate(1, canvas: 1080)
        endX = coordinate(7, canvas: 1920, fallback: startX); endY = coordinate(8, canvas: 1080, fallback: startY)
        let alpha = (values[2] as? String ?? "1-1").split(separator: "-").compactMap { Double($0) }
        alphaFrom = min(1, max(0, alpha.first?.isFinite == true ? alpha[0] : 1))
        alphaTo = min(1, max(0, alpha.last?.isFinite == true ? alpha.last! : 1))
        rotationZ = number(5).truncatingRemainder(dividingBy: 360) * .pi / 180
        rotationY = number(6).truncatingRemainder(dividingBy: 360) * .pi / 180
        moveDuration = min(lifetime, max(0, number(9, lifetime * 1000) / 1000))
        moveDelay = min(lifetime, max(0, number(10) / 1000))
        stroke = number(11) == 1 || (values.count > 11 && values[11] as? String == "true")
        cubicEasing = number(13) == 1
    }
    public func position(at age: Double) -> (x: Double, y: Double, opacity: Double) {
        let time = age.isFinite ? min(max(0, age), duration) : 0
        var progress = time <= moveDelay ? 0 : moveDuration == 0 ? 1 : min(1, (time - moveDelay) / moveDuration)
        if cubicEasing { progress = progress * progress * progress }
        return (startX + (endX - startX) * progress,
                startY + (endY - startY) * progress,
                alphaFrom + (alphaTo - alphaFrom) * time / duration)
    }
}
