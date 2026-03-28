import Foundation

public enum JobStatus: String, Codable, Sendable {
	case pending
	case processing
	case completed
	case failed
}

public struct JobSubmitResponse: Codable, Sendable {
	public let jobId: String
	public let status: JobStatus

	private enum CodingKeys: String, CodingKey {
		case jobId = "job_id"
		case status
	}
}

public struct JobStatusResponse: Codable, Sendable {
	public let jobId: String
	public let status: JobStatus

	private enum CodingKeys: String, CodingKey {
		case jobId = "job_id"
		case status
	}
}

public enum QueueJobResult: Sendable {
	case completed(jobId: String, data: Data)
	case failed(jobId: String, error: String)
}
