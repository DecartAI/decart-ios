import XCTest
@testable import DecartSDK

final class ModelConfigTests: XCTestCase {
	func testRealtimeVideoDefaultsDisableSimulcast() {
		let videoConfig = RealtimeConfiguration.VideoConfig()

		XCTAssertFalse(videoConfig.simulcast)
		XCTAssertFalse(videoConfig.publishOptions.simulcast)
	}

	func testRealtimeModelsMatchJSSDKRegistry() {
		let expectedCases: [RealtimeModel] = [
			.lucy2_1,
			.lucy2_1_vton,
			.lucyVton2,
			.lucyRestyle2,
			.lucyLatest,
			.lucyVtonLatest,
			.lucyRestyleLatest,
		]
		XCTAssertEqual(RealtimeModel.allCases, expectedCases)

		assertModel(
			Models.realtime(.lucyVton2),
			name: "lucy-vton-2",
			urlPath: "/v1/stream",
			jobsUrlPath: nil,
			fps: 30,
			width: 1088,
			height: 624,
			hasReferenceImage: true
		)

		for model in RealtimeModel.allCases {
			XCTAssertEqual(Models.realtime(model).fps, 30, "\(model.rawValue) realtime fps should match JS SDK")
		}
	}

	func testVideoModelsMatchJSSDKRegistry() {
		let expectedCases: [VideoModel] = [
			.lucyClip,
			.lucy2_1,
			.lucy2_1_vton,
			.lucyVton2,
			.lucyRestyle2,
			.lucyLatest,
			.lucyVtonLatest,
			.lucyRestyleLatest,
			.lucyClipLatest,
		]
		XCTAssertEqual(VideoModel.allCases, expectedCases)

		assertModel(
			Models.video(.lucyVton2),
			name: "lucy-vton-2",
			urlPath: "/v1/generate/lucy-vton-2",
			jobsUrlPath: "/v1/jobs/lucy-vton-2",
			fps: 20,
			width: 1088,
			height: 624
		)
	}

	func testDeprecatedAliasesMatchJSSDKDefinitions() {
		assertModel(
			Models.realtime(realtimeModel("lucy-vton")),
			name: "lucy-vton",
			urlPath: "/v1/stream",
			jobsUrlPath: nil,
			fps: 30,
			width: 1088,
			height: 624,
			hasReferenceImage: true
		)
		assertModel(
			Models.realtime(realtimeModel("lucy-2.1-vton-2")),
			name: "lucy-2.1-vton-2",
			urlPath: "/v1/stream",
			jobsUrlPath: nil,
			fps: 30,
			width: 1088,
			height: 624,
			hasReferenceImage: true
		)
		assertModel(
			Models.video(videoModel("lucy-vton")),
			name: "lucy-vton",
			urlPath: "/v1/generate/lucy-vton",
			jobsUrlPath: "/v1/jobs/lucy-vton",
			fps: 20,
			width: 1088,
			height: 624
		)
		assertModel(
			Models.video(videoModel("lucy-2.1-vton-2")),
			name: "lucy-2.1-vton-2",
			urlPath: "/v1/generate/lucy-2.1-vton-2",
			jobsUrlPath: "/v1/jobs/lucy-2.1-vton-2",
			fps: 20,
			width: 1088,
			height: 624
		)
	}

	private func realtimeModel(_ rawValue: String, file: StaticString = #filePath, line: UInt = #line) -> RealtimeModel {
		guard let model = RealtimeModel(rawValue: rawValue) else {
			XCTFail("Missing realtime model \(rawValue)", file: file, line: line)
			return .lucy2_1
		}
		return model
	}

	private func videoModel(_ rawValue: String, file: StaticString = #filePath, line: UInt = #line) -> VideoModel {
		guard let model = VideoModel(rawValue: rawValue) else {
			XCTFail("Missing video model \(rawValue)", file: file, line: line)
			return .lucyClip
		}
		return model
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
	}
}
