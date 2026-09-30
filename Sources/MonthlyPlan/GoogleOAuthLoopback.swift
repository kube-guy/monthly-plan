import Foundation
import MonthlyPlanCore
import Network

/// A short-lived HTTP callback listener bound only to this Mac's loopback interface.
@MainActor
final class GoogleOAuthLoopback {
  private let listener: NWListener
  private let queue = DispatchQueue(label: "monthly-plan.google-oauth-callback")
  private var startWaiter: CheckedContinuation<UInt16, Error>?
  private var callbackWaiter: CheckedContinuation<URL, Error>?
  private var callbackResult: Result<URL, Error>?
  private var timeoutTask: Task<Void, Never>?
  private var finished = false

  init() throws {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
    listener = try NWListener(using: parameters)
  }

  func start() async throws -> UInt16 {
    try await withCheckedThrowingContinuation { continuation in
      startWaiter = continuation
      listener.stateUpdateHandler = { [weak self] state in
        Task { @MainActor in
          guard let self else { return }
          switch state {
          case .ready:
            if let port = self.listener.port?.rawValue {
              self.startWaiter?.resume(returning: port)
              self.startWaiter = nil
            }
          case .failed(let error): self.fail(error)
          case .cancelled: self.fail(PlanError.invalid("Google 연결이 취소됐습니다."))
          default: break
          }
        }
      }
      let queue = self.queue
      listener.newConnectionHandler = { [weak self] connection in
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
          let page = "<html><meta charset=\"utf-8\"><body>Google Calendar 연결 응답을 받았습니다. monthly-plan으로 돌아가세요.</body></html>"
          let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(page.utf8.count)\r\nConnection: close\r\n\r\n\(page)"
          connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
          })
          Task { @MainActor in self?.receive(data) }
        }
      }
      listener.start(queue: queue)
      timeoutTask = Task { [weak self] in
        do {
          try await Task.sleep(for: .seconds(300))
          self?.fail(PlanError.invalid("Google 연결 시간이 만료되었습니다. 다시 시도해 주세요."))
        } catch {}
      }
    }
  }

  func waitForCallback() async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      if let callbackResult {
        self.callbackResult = nil
        continuation.resume(with: callbackResult)
      } else {
        callbackWaiter = continuation
      }
    }
  }

  func stop() {
    timeoutTask?.cancel()
    timeoutTask = nil
    listener.cancel()
  }

  private func receive(_ data: Data?) {
    guard let data, let request = String(data: data, encoding: .utf8),
      let first = request.components(separatedBy: "\r\n").first,
      first.hasPrefix("GET /oauth/callback?"),
      let target = first.split(separator: " ").dropFirst().first,
      let port = listener.port?.rawValue,
      let url = URL(string: "http://127.0.0.1:\(port)\(target)")
    else { return }
    complete(.success(url))
  }

  private func fail(_ error: Error) { complete(.failure(error)) }

  private func complete(_ result: Result<URL, Error>) {
    guard !finished else { return }
    finished = true
    if let startWaiter {
      switch result {
      case .success: startWaiter.resume(throwing: PlanError.invalid("Google 연결을 시작하지 못했습니다."))
      case .failure(let error): startWaiter.resume(throwing: error)
      }
    }
    startWaiter = nil
    if let callbackWaiter {
      self.callbackWaiter = nil
      callbackWaiter.resume(with: result)
    } else {
      callbackResult = result
    }
    stop()
  }
}
