import CoreMotion
import AppShell

/// Detects phone impacts/slaps and fires motion.shake events to JS.
/// Uses CMDeviceMotion.userAcceleration (gravity already removed by CoreMotion),
/// so a firm slap registers as a clean spike above threshold.
public class MotionAdapter: ShellAdapter {
    private let motion = CMMotionManager()
    private weak var bridge: JSBridge?

    private let cooldown: TimeInterval = 0.75
    private let threshold: Double = 1.5   // g without gravity; hard slap ≈ 3–8g
    private var lastFired: Date = .distantPast

    public init() {}

    public func register(bridge: JSBridge) {
        self.bridge = bridge
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 0.01
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let data = data else { return }
            let u = data.userAcceleration
            let amp = sqrt(u.x * u.x + u.y * u.y + u.z * u.z)
            let now = Date()
            guard amp > self.threshold,
                  now.timeIntervalSince(self.lastFired) > self.cooldown else { return }
            self.lastFired = now
            self.bridge?.sendEvent(name: "motion.shake", data: ["amplitude": amp])
        }
    }
}
