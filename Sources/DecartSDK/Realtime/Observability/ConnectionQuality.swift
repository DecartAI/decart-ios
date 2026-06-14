import Foundation

/// Shared verdict scale for both the pre-connect preflight (`checkConnectivity`)
/// and the in-session connection-quality signal. Ordered worst → best via `rank`
/// (do not rely on enum declaration order).
///
/// Note: on iOS the bandwidth dimension relies on `availableOutgoingBitrate`
/// from the underlying WebRTC stack (LiveKit), which is populated on Apple
/// platforms; the verdict otherwise reflects latency, loss, and fps.
public enum ConnectionQuality: String, Sendable, Equatable {
	case good
	case fair
	case poor
	case critical

	/// Higher is better. Used by the `worst()` comparator and hysteresis logic.
	var rank: Int {
		switch self {
		case .critical: return 0
		case .poor: return 1
		case .fair: return 2
		case .good: return 3
		}
	}
}
