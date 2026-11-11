import Foundation

/// aria2 pushes state changes (start, pause, stop, complete, error) over its
/// WebSocket endpoint, so they do not have to wait for the next poll. Byte
/// progress is not pushed and is still polled while a download is running.
@MainActor
final class Aria2EventStream {
  var onEvent: (@MainActor () -> Void)?

  private let session: URLSession
  private var port: Int?
  private var socket: URLSessionWebSocketTask?
  private var loop: Task<Void, Never>?

  init() {
    let configuration = URLSessionConfiguration.ephemeral
    // An idle queue sends nothing for hours; that is not a failed request.
    configuration.timeoutIntervalForRequest = 7 * 24 * 3600
    session = URLSession(configuration: configuration)
  }

  /// Keeps one connection to the engine on `port`, reconnecting when it drops.
  func connect(port: Int) {
    guard loop == nil || self.port != port else { return }
    disconnect()
    guard let url = URL(string: "ws://127.0.0.1:\(port)/jsonrpc") else { return }
    self.port = port
    loop = Task { [weak self, session] in
      while !Task.isCancelled {
        let socket = session.webSocketTask(with: url)
        self?.socket = socket
        socket.resume()
        do {
          while true {
            let message = try await socket.receive()
            if Self.isNotification(message) { self?.onEvent?() }
          }
        } catch {
          socket.cancel(with: .goingAway, reason: nil)
        }
        try? await Task.sleep(for: .seconds(2))
      }
    }
  }

  func disconnect() {
    loop?.cancel()
    loop = nil
    socket?.cancel(with: .goingAway, reason: nil)
    socket = nil
    port = nil
  }

  nonisolated static func isNotification(_ message: URLSessionWebSocketTask.Message) -> Bool {
    let text: String
    switch message {
    case .string(let string): text = string
    case .data(let data): text = String(decoding: data, as: UTF8.self)
    @unknown default: return false
    }
    return text.contains("\"aria2.on")
  }
}
