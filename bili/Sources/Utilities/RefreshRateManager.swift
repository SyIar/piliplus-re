import QuartzCore
import UIKit

nonisolated enum PiliRefreshRatePolicy {
    static func preferred(enabled: Bool, active: Bool, maximum: Int, lowPower: Bool, thermal: ProcessInfo.ThermalState) -> Int? {
        guard enabled, active, maximum > 60, !lowPower, thermal == .nominal || thermal == .fair else { return nil }
        return min(maximum, 120)
    }
}

@MainActor
final class RefreshRateManager: NSObject {
    static let shared = RefreshRateManager()
    static let isEnabledKey = "cc.bili.display.force120HzScrollingEnabled.v1"
    private var displayLink: CADisplayLink?
    private var requested = false
    private var active = false
    private var appliedRate: Int?

    private override init() {
        super.init()
        active = UIApplication.shared.applicationState == .active
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(becameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(resignedActive), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(constraintsChanged), name: .NSProcessInfoPowerStateDidChange, object: nil)
        center.addObserver(self, selector: #selector(constraintsChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(constraintsChanged), name: UIScreen.modeDidChangeNotification, object: nil)
    }
    func restorePersistedPreference() {
        setForce120HzEnabled(UserDefaults.standard.bool(forKey: Self.isEnabledKey), persists: false)
    }
    func setForce120HzEnabled(_ enabled: Bool, persists: Bool = true) {
        if persists { UserDefaults.standard.set(enabled, forKey: Self.isEnabledKey) }
        requested = enabled; refresh()
    }
    func enableForce120Hz() { requested = true; refresh() }
    func disableForce120Hz() { requested = false; refresh() }
    @objc private nonisolated func becameActive() {
        Task { @MainActor [weak self] in self?.active = true; self?.refresh() }
    }
    @objc private nonisolated func resignedActive() {
        Task { @MainActor [weak self] in self?.active = false; self?.refresh() }
    }
    @objc private nonisolated func constraintsChanged() {
        Task { @MainActor [weak self] in self?.refresh() }
    }
    private func refresh() {
        let screens = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }
        let maximum = screens.map(\.maximumFramesPerSecond).max() ?? 60
        let rate = PiliRefreshRatePolicy.preferred(enabled: requested, active: active, maximum: maximum,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, thermal: ProcessInfo.processInfo.thermalState)
        guard appliedRate != rate else { return }
        displayLink?.invalidate(); displayLink = nil; appliedRate = rate
        guard let rate else { return }
        let link = CADisplayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: Float(rate), preferred: Float(rate))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }
    @objc private func displayLinkDidFire(_: CADisplayLink) {}
}
