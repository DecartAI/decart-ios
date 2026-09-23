import XCTest
@testable import DecartSDK

final class ModelConfigTests: XCTestCase {
	func testRealtimeModelsMatchJSSDKRegistry() {
		let expectedCases: [RealtimeModel] = [
			.lucy2_1,
			.lucy2_5,
			.lucyVton3_5,
			.lucyRestyle2,
			.lucyLatest,
			.lucyVtonLatest,
			.lucyRestyleLatest,
		]
		XCTAssertEqual(RealtimeModel.allCases, expectedCases)

		assertModel(
			Models.realtime(.lucy2_5),
			name: "lucy-2.5",
			urlPath: "/v1/stream",
			jobsUrlPath: nil,
			fps: 30,
			width: 1280,
			height: 720,
			hasReferenceImage: true,
			supportedSpeeds: [.fast]
		)

		assertModel(
			Models.realtime(.lucyVton3_5),
			name: "lucy-vton-3.5",
			urlPath: "/v1/stream",
			jobsUrlPath: nil,
			fps: 30,
			width: 1280,
			height: 720,
			hasReferenceImage: true,
			supportedSpeeds: [.fast]
		)

		for model in RealtimeModel.allCases {
			// All realtime models run at 30 fps.
			XCTAssertEqual(Models.realtime(model).fps, 30, "\(model.rawValue) realtime fps should match JS SDK")
		}
	}

	func testRealtimeFastSpeedCapabilityMatchesJSSDKRegistry() {
		// Fast mode (`speed: .fast`) is advertised only by lucy-2.5 / lucy-latest and
		// lucy-vton-3.5 / lucy-vton-latest; every other realtime model has no tier.
		let fastModels: Set<RealtimeModel> = [.lucy2_5, .lucyLatest, .lucyVton3_5, .lucyVtonLatest]
		for model in RealtimeModel.allCases {
			let expected: [Speed] = fastModels.contains(model) ? [.fast] : []
			XCTAssertEqual(Models.realtime(model).supportedSpeeds, expected, "\(model.rawValue) supportedSpeeds should match JS SDK")
		}

		// Batch (image/video) models never advertise a realtime speed tier.
		for model in ImageModel.allCases {
			XCTAssertEqual(Models.image(model).supportedSpeeds, [], "\(model.rawValue) should have no speed tiers")
		}
		for model in VideoModel.allCases {
			XCTAssertEqual(Models.video(model).supportedSpeeds, [], "\(model.rawValue) should have no speed tiers")
		}
	}

	func testVideoModelsMatchJSSDKRegistry() {
		let expectedCases: [VideoModel] = [
			.lucyClip,
			.lucy2_1,
			.lucy2_5,
			.lucyVton3_5,
			.lucyRestyle2,
			.lucyLatest,
			.lucyVtonLatest,
			.lucyRestyleLatest,
			.lucyClipLatest,
		]
		XCTAssertEqual(VideoModel.allCases, expectedCases)

		assertModel(
			Models.video(.lucy2_5),
			name: "lucy-2.5",
			urlPath: "/v1/generate/lucy-2.5",
			jobsUrlPath: "/v1/jobs/lucy-2.5",
			fps: 20,
			width: 1280,
			height: 720
		)

		assertModel(
			Models.video(.lucyVton3_5),
			name: "lucy-vton-3.5",
			urlPath: "/v1/generate/lucy-vton-3.5",
			jobsUrlPath: "/v1/jobs/lucy-vton-3.5",
			fps: 20,
			width: 1280,
			height: 720
		)
	}

	private func assertModel(
		_ model: ModelDefinition,
		name: String,
		urlPath: String,
		jobsUrlPath: String?,
		fps: Int,
		width: Int,
		height: Int,
		hasReferenceImage: Bool = false,
		supportedSpeeds: [Speed] = [],
		file: StaticString = #filePath,
		line: UInt = #line
	) {
		XCTAssertEqual(model.name, name, file: file, line: line)
		XCTAssertEqual(model.urlPath, urlPath, file: file, line: line)
		XCTAssertEqual(model.jobsUrlPath, jobsUrlPath, file: file, line: line)
		XCTAssertEqual(model.fps, fps, file: file, line: line)
		XCTAssertEqual(model.width, width, file: file, line: line)
		XCTAssertEqual(model.height, height, file: file, line: line)
		XCTAssertEqual(model.hasReferenceImage, hasReferenceImage, file: file, line: line)
		XCTAssertEqual(model.supportedSpeeds, supportedSpeeds, file: file, line: line)
	}
}
