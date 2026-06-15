import DecartSDK
import SwiftUI

extension ConnectionQuality {
	var displayColor: Color {
		switch self {
		case .good: return Color(red: 0.30, green: 0.69, blue: 0.31)
		case .fair: return Color(red: 0.79, green: 0.64, blue: 0.15)
		case .poor: return Color(red: 1.0, green: 0.60, blue: 0.0)
		case .critical: return Color(red: 0.96, green: 0.26, blue: 0.21)
		}
	}

	var displayLabel: String { rawValue.uppercased() }
}

/// Live in-session connection-quality badge (mirrors the JS demo's quality badge).
struct ConnectionQualityBadge: View {
	let report: ConnectionQualityReport

	private var detail: String {
		var parts: [String] = []
		if report.limitingFactor != .none, !report.warmingUp { parts.append(report.limitingFactor.rawValue) }
		if let ttff = report.metrics.ttffMs { parts.append("ttff \(String(format: "%.1f", ttff / 1000))s") }
		if let g2g = report.metrics.g2gMs { parts.append("g2g \(Int(g2g))ms") }
		if let rtt = report.metrics.rttMs { parts.append("rtt \(Int(rtt))ms") }
		if let fps = report.metrics.fps { parts.append("\(Int(fps))fps") }
		if let drop = report.metrics.g2gDropRatio { parts.append("drops \(String(format: "%.1f", drop * 100))%") }
		return parts.joined(separator: " · ")
	}

	var body: some View {
		HStack(spacing: 6) {
			Circle().fill(report.quality.displayColor).frame(width: 8, height: 8)
			Text(report.quality.displayLabel + (report.warmingUp ? " · warming up" : ""))
				.font(.caption2)
				.fontWeight(.semibold)
				.foregroundStyle(.white)
			if !detail.isEmpty {
				Text(detail)
					.font(.caption2)
					.foregroundStyle(.white.opacity(0.7))
			}
		}
		.padding(.horizontal, 10)
		.padding(.vertical, 5)
		.background(
			Capsule()
				.fill(report.quality.displayColor.opacity(0.25))
				.overlay(Capsule().stroke(report.quality.displayColor, lineWidth: 1))
		)
	}
}

/// Pre-connect connectivity probe (mirrors the JS demo's preflight panel).
struct ConnectivityPreflightView: View {
	let isChecking: Bool
	let report: ConnectivityReport?
	let debugQuality: Bool
	let onCheck: () -> Void
	let onDeepProbe: () -> Void
	let onToggleDebugQuality: (Bool) -> Void

	var body: some View {
		VStack(alignment: .trailing, spacing: 6) {
			HStack(spacing: 8) {
				probeButton(title: "Check (STUN)", system: "wifi", action: onCheck)
				probeButton(title: "Deep Probe", system: "gauge.with.dots.needle.bottom.50percent", action: onDeepProbe)
			}

			Toggle(isOn: Binding(get: { debugQuality }, set: onToggleDebugQuality)) {
				Text("Measure glass-to-glass (visible marker)")
					.font(.caption2)
					.foregroundStyle(.white.opacity(0.85))
			}
			.toggleStyle(.switch)
			.tint(Color(red: 0.4, green: 0.3, blue: 1.0))

			if let report {
				VStack(alignment: .leading, spacing: 3) {
					HStack(spacing: 6) {
						Circle().fill(report.quality.displayColor).frame(width: 8, height: 8)
						Text(headline(for: report))
							.font(.caption2)
							.fontWeight(.semibold)
							.foregroundStyle(.white)
					}
					ForEach(report.reasons, id: \.self) { reason in
						Text(reason)
							.font(.caption2)
							.foregroundStyle(.white.opacity(0.7))
							.fixedSize(horizontal: false, vertical: true)
					}
				}
				.padding(10)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.55)))
			}
		}
	}

	private func headline(for report: ConnectivityReport) -> String {
		var text = "\(report.quality.displayLabel) · \(report.metrics.transport.rawValue)"
		if let ttff = report.metrics.ttffMs { text += " · ttff \(String(format: "%.1f", ttff / 1000))s" }
		if let g2g = report.metrics.g2gMs { text += " · g2g \(Int(g2g))ms" }
		if let rtt = report.metrics.rttMs { text += " · rtt \(rtt)ms" }
		return text
	}

	private func probeButton(title: String, system: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			HStack(spacing: 6) {
				if isChecking {
					ProgressView().controlSize(.mini).tint(.white)
				} else {
					Image(systemName: system)
				}
				Text(title)
			}
			.font(.caption)
			.fontWeight(.medium)
			.foregroundStyle(.white)
			.padding(.horizontal, 12)
			.padding(.vertical, 8)
			.background(
				Capsule()
					.fill(Color.white.opacity(0.15))
					.overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
			)
		}
		.buttonStyle(.plain)
		.disabled(isChecking)
	}
}
