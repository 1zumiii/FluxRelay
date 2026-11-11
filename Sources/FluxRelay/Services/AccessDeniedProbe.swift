import Foundation

/// Explains a 403 from aria2. aria2 reports only the status code, so the source
/// is requested once more to see whether Cloudflare's bot protection answered.
enum AccessDeniedProbe {
  enum Reason: Equatable {
    case browserVerification
    case unknown
  }

  static func reason(for url: URL, session: URLSession = .shared) async -> Reason {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
    request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
    guard
      let (_, response) = try? await session.data(for: request),
      let response = response as? HTTPURLResponse
    else {
      return .unknown
    }
    return isBrowserVerification(response) ? .browserVerification : .unknown
  }

  static func isBrowserVerification(_ response: HTTPURLResponse) -> Bool {
    guard response.statusCode == 403 || response.statusCode == 503 else { return false }
    let server = (response.value(forHTTPHeaderField: "Server") ?? "").lowercased()
    return server.contains("cloudflare") || response.value(forHTTPHeaderField: "cf-mitigated") != nil
  }
}

extension Aria2Task {
  /// The HTTP status aria2 put in the error message, e.g. "status=403".
  var httpErrorStatus: Int? {
    guard
      status == "error",
      let range = errorMessage.range(of: #"status=(\d{3})"#, options: .regularExpression)
    else {
      return nil
    }
    return Int(errorMessage[range].dropFirst("status=".count))
  }

  /// The source as a web page link the user can open in a browser.
  var webSourceURL: URL? {
    guard
      let sourceURI,
      let url = URL(string: sourceURI),
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    else {
      return nil
    }
    return url
  }
}
