import Foundation

/// Manages WebSocket signaling connection with AsyncStream-based message delivery
class SignalingManager {

    // MARK: - Public Properties

    /// Stream of all incoming WebSocket messages
    public let messages: AsyncStream<IncomingWebSocketMessage>

    // MARK: - Private Properties

    /// WebSocket task for signaling
    private var webSocket: URLSessionWebSocketTask?

    /// URL session for WebSocket
    private var urlSession: URLSession?

    /// Continuation for incoming messages
    private var messageContinuation: AsyncStream<IncomingWebSocketMessage>.Continuation?

    /// Optional error callback
    private let onError: ((Error) -> Void)?
    private let decoder: JSONDecoder = JSONDecoder()
    private let encoder: JSONEncoder = JSONEncoder()
    // MARK: - Initialization

    /// Creates a new signaling manager
    /// - Parameter onError: Optional callback for signaling errors
    init(onError: ((Error) -> Void)? = nil) {
        self.onError = onError

        // Create single AsyncStream for all messages
        let (stream, continuation) = AsyncStream.makeStream(
            of: IncomingWebSocketMessage.self,
            bufferingPolicy: .bufferingNewest(10)
        )
        self.messages = stream
        self.messageContinuation = continuation
    }

    // MARK: - Public Methods

    /// Establishes WebSocket connection to signaling server
    /// - Parameters:
    ///   - url: WebSocket URL for signaling
    ///   - timeout: Connection timeout in seconds (default: 30)
    /// - Throws: DecartError.websocketError if connection fails
    func connect(url: URL, timeout: TimeInterval = 30) async throws {
        // Convert HTTP(S) to WS(S)
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if urlComponents?.scheme == "https" {
            urlComponents?.scheme = "wss"
        } else if urlComponents?.scheme == "http" {
            urlComponents?.scheme = "ws"
        }

        guard let wsURL = urlComponents?.url else {
            print("[SignalingManager] Failed to create WebSocket URL from: \(url.absoluteString)")
            throw DecartError.websocketError("Failed to create WebSocket URL")
        }

        // Create WebSocket
        urlSession = URLSession(configuration: .default)
        webSocket = urlSession?.webSocketTask(with: wsURL)
        webSocket?.resume()

        // Start receiving messages
        receiveMessage()

        // Wait for first message to confirm connection (with timeout)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            // Check if we've received any message by attempting to read from the stream
            // If the continuation yields a message, the connection is working
            let checkTask = Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            }
            await checkTask.value

            // If WebSocket has an error state, it will be caught by receiveMessage
            // For now, just wait a bit and assume connection is established
            // The actual verification happens when first message arrives
            if webSocket?.state == .running {
                return
            }
        }

        print("[SignalingManager] WebSocket connection timeout after \(timeout)s")
        throw DecartError.websocketError("WebSocket timeout")
    }

    /// Sends a signaling message over WebSocket
    /// - Parameter message: The outgoing message to send
    func send(_ message: OutgoingWebSocketMessage) async {
        guard webSocket != nil else {
            return
        }

        do {
            let data = try encoder.encode(message)

            if let jsonString = String(data: data, encoding: .utf8) {
                webSocket?.send(.string(jsonString)) { _ in }
            }
        } catch {
            // Ignore encoding errors
        }
    }

    /// Disconnects WebSocket and cleans up resources
    func disconnect() async {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil

        urlSession?.invalidateAndCancel()
        urlSession = nil

        // Finish message stream
        messageContinuation?.finish()
    }

    // MARK: - Private Methods

    /// Continuously receives messages from WebSocket
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            Task { [weak self] in
                guard let self = self else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        if let data = text.data(using: .utf8) {
                            await self.parseAndRouteMessage(data)
                        }
                    case .data(let data):
                        await self.parseAndRouteMessage(data)
                    @unknown default:
                        break
                    }

                    // Continue receiving
                    self.receiveMessage()

                case .failure(let error):
                    print("[SignalingManager] WebSocket error: \(error.localizedDescription)")
                    self.onError?(error)
                }
            }
        }
    }

    /// Parses incoming data and yields to message stream
    /// - Parameter data: Raw JSON data from WebSocket
    private func parseAndRouteMessage(_ data: Data) async {
        do {
            let message = try decoder.decode(IncomingWebSocketMessage.self, from: data)
            // Yield message to stream
            messageContinuation?.yield(message)
        } catch {
            // Ignore unknown message types (e.g., ping/pong)
        }
    }
}
