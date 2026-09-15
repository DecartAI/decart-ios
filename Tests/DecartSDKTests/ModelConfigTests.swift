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
			hasReferenceImage: true
		)

		assertModel(
			Models.realtime(.lucyVton3_5),
			name: "lucy-vton-3.5",
			urlPath: "/v1/stream",
			jobsUrlPath: nil,
			fps: 30,
			width: 1280,
			height: 720,
			hasReferenceImage: true
		)

		for model in RealtimeModel.allCases {
			// All realtime models run at 30 fps.
			XCTAssertEqual(Models.realtime(model).fps, 30, "\(model.rawValue) realtime fps should match JS SDK")
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
