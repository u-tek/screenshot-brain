import CoreGraphics
import CoreMotion

/// The phone's tilt, -1...1 on each axis, read from Core Motion only while something is
/// showing that uses it. One motion manager for the whole app, as Apple recommends.
@MainActor
final class DeviceTilt {
    static let shared = DeviceTilt()

    private let manager = CMMotionManager()
    private var users = 0

    /// x: rolling left and right; y: pitching towards and away. Gently clamped.
    var current: CGSize {
        guard let attitude = manager.deviceMotion?.attitude else { return .zero }
        let roll = max(-1, min(1, attitude.roll / 0.6))
        let pitch = max(-1, min(1, (attitude.pitch - 0.7) / 0.6))
        return CGSize(width: roll, height: pitch)
    }

    func retain() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates()
    }

    func release() {
        users = max(0, users - 1)
        if users == 0 {
            manager.stopDeviceMotionUpdates()
        }
    }
}
