import Foundation

public enum DecartError: Error {
	case invalidAPIKey
	case invalidBaseURL(String?)
	case webRTCError(Error)
	case processingError(String)
	case invalidInput(String)
	case invalidOptions(String)
	case modelNotFound(String)
	case connectionTimeout
	case websocketError(String)

	public var errorDescription: String? {
		switch self {
		case .invalidAPIKey:
			return "API key is required and must be a non-empty string"
		case .invalidBaseURL(let url):
			if let url = url {
				return "Invalid base URL: \(url)"
			}
			return "Invalid base URL"
		case .webRTCError(let error):
			return "WebRTC error: \(error.localizedDescription)"
		case .processingError(let message):
			return "Processing error: \(message)"
		case .invalidInput(let message):
			return "Invalid input: \(message)"
		case .invalidOptions(let message):
			return "Invalid options: \(message)"
		case .modelNotFound(let model):
			return "Model \(model) not found"
		case .connectionTimeout:
			return "Connection timeout"
		case .websocketError(let message):
			return "WebSocket error: \(message)"
		}
	}

	public var errorCode: String {
		switch self {
		case .invalidAPIKey:
			return "INVALID_API_KEY"
		case .invalidBaseURL:
			return "INVALID_BASE_URL"
		case .webRTCError:
			return "WEB_RTC_ERROR"
		case .processingError:
			return "PROCESSING_ERROR"
		case .invalidInput:
			return "INVALID_INPUT"
		case .invalidOptions:
			return "INVALID_OPTIONS"
		case .modelNotFound:
			return "MODEL_NOT_FOUND"
		case .connectionTimeout:
			return "CONNECTION_TIMEOUT"
		case .websocketError:
			return "WEBSOCKET_ERROR"
		}
	}
}
