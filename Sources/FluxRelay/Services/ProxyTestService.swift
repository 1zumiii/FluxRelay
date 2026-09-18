import Foundation
import SystemConfiguration

struct ProxyTestResult {
  let directAddress: String?
  let proxyAddress: String?
}

enum ProxyTestError: LocalizedError {
  case systemProxyUnavailable
  case invalidManualProxy
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .systemProxyUnavailable:
      return L10n.tr("preferences.proxy.test.error.system_unavailable")
    case .invalidManualProxy:
      return L10n.tr("preferences.proxy.test.error.invalid_manual")
    case .invalidResponse:
      return L10n.tr("preferences.proxy.test.error.invalid_response")
    }
  }
}

enum ProxyTestService {
  private static let endpoint = URL(string: "https://api.ipify.org")!

  static func test(
    mode: ProxyMode,
    scheme: ProxyScheme,
    host: String,
    port: Int
  ) async throws -> ProxyTestResult {
    guard mode != .disabled else {
      let directAddress = try await publicAddress(configuration: directConfiguration())
      return ProxyTestResult(directAddress: directAddress, proxyAddress: nil)
    }

    guard let proxy = ProxyConfiguration.testEndpoint(
      mode: mode,
      scheme: scheme,
      host: host,
      port: port
    ) else {
      throw mode == .system ? ProxyTestError.systemProxyUnavailable : ProxyTestError.invalidManualProxy
    }

    async let directAddress = try? publicAddress(configuration: directConfiguration())
    let proxyAddress = try await publicAddress(configuration: proxyConfiguration(proxy))
    return await ProxyTestResult(directAddress: directAddress, proxyAddress: proxyAddress)
  }

  private static func directConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 12
    configuration.timeoutIntervalForResource = 15
    configuration.connectionProxyDictionary = [
      kCFNetworkProxiesHTTPEnable as String: false,
      kCFNetworkProxiesHTTPSEnable as String: false
    ]
    return configuration
  }

  static func proxyConfiguration(_ proxy: ProxyEndpoint) -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 12
    configuration.timeoutIntervalForResource = 15
    configuration.connectionProxyDictionary = [
      kCFNetworkProxiesHTTPEnable as String: true,
      kCFNetworkProxiesHTTPProxy as String: proxy.host,
      kCFNetworkProxiesHTTPPort as String: proxy.port,
      kCFNetworkProxiesHTTPSEnable as String: true,
      kCFNetworkProxiesHTTPSProxy as String: proxy.host,
      kCFNetworkProxiesHTTPSPort as String: proxy.port
    ]
    return configuration
  }

  private static func publicAddress(configuration: URLSessionConfiguration) async throws -> String {
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let (data, response) = try await session.data(from: endpoint)
    guard
      let httpResponse = response as? HTTPURLResponse,
      (200..<300).contains(httpResponse.statusCode),
      let address = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !address.isEmpty,
      address.count <= 64
    else {
      throw ProxyTestError.invalidResponse
    }
    return address
  }
}
