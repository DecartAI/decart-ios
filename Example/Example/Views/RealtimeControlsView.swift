import DecartSDK
import SwiftUI

struct RealtimeControlsView: View {
	let presets: [PromptPreset]
	let connectionState: DecartRealtimeConnectionState
	let onPresetSelected: (PromptPreset) -> Void
	let onSwitchCamera: () -> Void
	let onConnectToggle: () -> Void

	@State private var selectedPresetId: UUID?

	var body: some View {
		VStack(spacing: 16) {
			if connectionState == .error {
				ErrorBanner()
			}

			PresetChipsScrollView(
				presets: presets,
				selectedPresetId: $selectedPresetId,
				onPresetSelected: { preset in
					selectedPresetId = preset.id
					onPresetSelected(preset)
				}
			)

			ControlButtonsRow(
				connectionState: connectionState,
				onSwitchCamera: onSwitchCamera,
				onConnectToggle: onConnectToggle
			)
		}
		.padding(16)
		.background(
			RoundedRectangle(cornerRadius: 20)
				.fill(.ultraThinMaterial)
				.overlay(
					RoundedRectangle(cornerRadius: 20)
						.stroke(
							LinearGradient(
								colors: [
									Color.white.opacity(0.3),
									Color.white.opacity(0.1),
									Color.clear,
								],
								startPoint: .topLeading,
								endPoint: .bottomTrailing
							),
							lineWidth: 1
						)
				)
		)
		.padding(.horizontal, 8)
		.padding(.bottom, 8)
		.onAppear {
			if selectedPresetId == nil, let firstPreset = presets.first {
				selectedPresetId = firstPreset.id
			}
		}
	}
}

private struct ErrorBanner: View {
	var body: some View {
		Text("Connection error. Please try again.")
			.font(.caption)
			.fontWeight(.medium)
			.foregroundStyle(.white)
			.padding(.horizontal, 16)
			.padding(.vertical, 10)
			.background(
				Capsule()
					.fill(Color.red.opacity(0.8))
					.overlay(
						Capsule()
							.stroke(Color.red.opacity(0.5), lineWidth: 1)
					)
			)
	}
}

private struct PresetChipsScrollView: View {
	let presets: [PromptPreset]
	@Binding var selectedPresetId: UUID?
	let onPresetSelected: (PromptPreset) -> Void

	var body: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 10) {
				ForEach(presets) { preset in
					PresetChip(
						preset: preset,
						isSelected: selectedPresetId == preset.id,
						onTap: { onPresetSelected(preset) }
					)
				}
			}
			.padding(.horizontal, 4)
		}
		.frame(height: 44)
	}
}

private struct PresetChip: View {
	let preset: PromptPreset
	let isSelected: Bool
	let onTap: () -> Void

	var body: some View {
		Button(action: onTap) {
			Text(preset.label)
				.font(.subheadline)
				.fontWeight(isSelected ? .semibold : .medium)
				.foregroundStyle(isSelected ? .white : .white.opacity(0.8))
				.padding(.horizontal, 16)
				.padding(.vertical, 10)
				.background(
					Capsule()
						.fill(
							isSelected
								? LinearGradient(
									colors: [
										Color(red: 0.4, green: 0.3, blue: 1.0),
										Color(red: 0.6, green: 0.2, blue: 0.9),
									],
									startPoint: .topLeading,
									endPoint: .bottomTrailing
								)
								: LinearGradient(
									colors: [
										Color.white.opacity(0.15),
										Color.white.opacity(0.08),
									],
									startPoint: .topLeading,
									endPoint: .bottomTrailing
								)
						)
						.overlay(
							Capsule()
								.stroke(
									isSelected
										? Color.white.opacity(0.4)
										: Color.white.opacity(0.2),
									lineWidth: 1
								)
						)
				)
				.shadow(
					color: isSelected ? Color(red: 0.5, green: 0.3, blue: 1.0).opacity(0.5) : .clear,
					radius: 8,
					y: 2
				)
		}
		.buttonStyle(.plain)
		.animation(.easeInOut(duration: 0.2), value: isSelected)
	}
}

private struct ControlButtonsRow: View {
	let connectionState: DecartRealtimeConnectionState
	let onSwitchCamera: () -> Void
	let onConnectToggle: () -> Void

	var body: some View {
		HStack(spacing: 12) {
			CameraSwitchButton(onTap: onSwitchCamera)

			Spacer()

			ConnectButton(connectionState: connectionState, onTap: onConnectToggle)
		}
	}
}

private struct CameraSwitchButton: View {
	let onTap: () -> Void

	var body: some View {
		Button(action: onTap) {
			Image(systemName: "arrow.trianglehead.2.counterclockwise.rotate.90")
				.font(.system(size: 16, weight: .medium))
				.foregroundStyle(.white.opacity(0.8))
				.frame(width: 40, height: 40)
				.background(
					Circle()
						.fill(Color.white.opacity(0.1))
						.overlay(
							Circle()
								.stroke(Color.white.opacity(0.2), lineWidth: 1)
						)
				)
		}
		.buttonStyle(.plain)
	}
}

private struct ConnectButton: View {
	let connectionState: DecartRealtimeConnectionState
	let onTap: () -> Void

	private var buttonGradient: LinearGradient {
		if connectionState.isInSession {
			return LinearGradient(
				colors: [
					Color(red: 0.9, green: 0.2, blue: 0.3),
					Color(red: 0.8, green: 0.1, blue: 0.2),
				],
				startPoint: .topLeading,
				endPoint: .bottomTrailing
			)
		} else {
			return LinearGradient(
				colors: [
					Color(red: 0.2, green: 0.8, blue: 0.4),
					Color(red: 0.1, green: 0.7, blue: 0.3),
				],
				startPoint: .topLeading,
				endPoint: .bottomTrailing
			)
		}
	}

	private var shadowColor: Color {
		connectionState.isInSession
			? Color.red.opacity(0.4)
			: Color.green.opacity(0.4)
	}

	var body: some View {
		Button(action: onTap) {
			Text(connectionState.rawValue)
				.font(.subheadline)
				.fontWeight(.semibold)
				.foregroundStyle(.white)
				.padding(.horizontal, 24)
				.padding(.vertical, 12)
				.background(
					Capsule()
						.fill(buttonGradient)
						.overlay(
							Capsule()
								.stroke(Color.white.opacity(0.3), lineWidth: 1)
						)
				)
				.shadow(color: shadowColor, radius: 8, y: 2)
		}
		.buttonStyle(.plain)
	}
}
