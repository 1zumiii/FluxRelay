import XCTest
@testable import MotrixNative

final class ProxyConfigurationTests: XCTestCase {
  func testNormalizingLegacyProxyDoesNotRewriteCredentials() {
    var engineConfig: [String: Any] = [
      "all-proxy": "https://proxy.example:8443",
      "all-proxy-passwd": "https://secret.example",
      "all-proxy-user": "https://user.example"
    ]
    ProxyConfiguration.apply(to: &engineConfig, userConfig: [:])
    XCTAssertEqual(engineConfig["all-proxy"] as? String, "http://proxy.example:8443")
    XCTAssertEqual(engineConfig["all-proxy-passwd"] as? String, "https://secret.example")
    XCTAssertEqual(engineConfig["all-proxy-user"] as? String, "https://user.example")
  }

  func testLegacyHTTPSProxyIsLoadedAsHTTP() {
    let endpoint = ProxyConfiguration.legacyEndpoint(in: [
      "all-proxy": "https://legacy.proxy.example:8443"
    ])

    XCTAssertEqual(endpoint?.scheme, .http)
    XCTAssertEqual(endpoint?.host, "legacy.proxy.example")
    XCTAssertEqual(endpoint?.port, 8443)
  }

  func testLegacyHTTPSProxyWithoutPortUsesHTTPDefault() {
    let endpoint = ProxyConfiguration.legacyEndpoint(in: [
      "all-proxy": "https://legacy.proxy.example"
    ])

    XCTAssertEqual(endpoint?.scheme, .http)
    XCTAssertEqual(endpoint?.port, 80)
  }

  func testLegacyHTTPSEngineOptionIsNormalizedWhenProxyModeIsMissing() {
    var engineConfig: [String: Any] = [
      "all-proxy": "https://legacy.proxy.example:8443"
    ]

    ProxyConfiguration.apply(to: &engineConfig, userConfig: [:])

    XCTAssertEqual(engineConfig["all-proxy"] as? String, "http://legacy.proxy.example:8443")
  }

  func testManualHTTPSSettingProducesHTTPEngineEndpoint() {
    let userConfig: [String: Any] = [
      "proxy-mode": ProxyMode.manual.rawValue,
      "proxy-scheme": "https",
      "proxy-host": "  manual.proxy.example ",
      "proxy-port": "3128"
    ]
    var engineConfig: [String: Any] = ["dir": "/tmp"]

    ProxyConfiguration.apply(to: &engineConfig, userConfig: userConfig)

    XCTAssertEqual(engineConfig["all-proxy"] as? String, "http://manual.proxy.example:3128")
    XCTAssertEqual(
      ProxyConfiguration.testEndpoint(
        mode: .manual,
        scheme: ProxyScheme(rawValue: "https")!,
        host: "  manual.proxy.example ",
        port: 3128
      ),
      ProxyEndpoint(scheme: .http, host: "manual.proxy.example", port: 3128)
    )
  }

  func testManualValidationAndOptionsRejectBlankHostAndClampPortTheSameWay() {
    let invalidEndpoint = ProxyConfiguration.testEndpoint(
      mode: .manual,
      scheme: .http,
      host: "   ",
      port: 0
    )
    XCTAssertNil(invalidEndpoint)
    XCTAssertTrue(ProxyConfiguration.manualOptions(userConfig: [
      "proxy-host": "   ",
      "proxy-port": 0
    ]).isEmpty)

    let endpoint = ProxyConfiguration.testEndpoint(
      mode: .manual,
      scheme: .http,
      host: "proxy.example",
      port: 99_999
    )
    XCTAssertEqual(endpoint, ProxyEndpoint(scheme: .http, host: "proxy.example", port: 65_535))
    XCTAssertEqual(
      ProxyConfiguration.manualOptions(userConfig: [
        "proxy-host": "proxy.example",
        "proxy-port": 99_999
      ])["all-proxy"],
      "http://proxy.example:65535"
    )
  }

  func testProxyTestUsesHTTPProxyForHTTPAndHTTPSDestinations() {
    let configuration = ProxyTestService.proxyConfiguration(
      ProxyEndpoint(scheme: .http, host: "proxy.example", port: 8080)
    )
    let dictionary = configuration.connectionProxyDictionary

    XCTAssertEqual(dictionary?[kCFNetworkProxiesHTTPProxy as String] as? String, "proxy.example")
    XCTAssertEqual(dictionary?[kCFNetworkProxiesHTTPPort as String] as? Int, 8080)
    XCTAssertEqual(dictionary?[kCFNetworkProxiesHTTPSProxy as String] as? String, "proxy.example")
    XCTAssertEqual(dictionary?[kCFNetworkProxiesHTTPSPort as String] as? Int, 8080)
  }
}
