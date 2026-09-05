import Foundation
import SystemConfiguration

enum ProxyMode: String, CaseIterable, Identifiable {
  case disabled
  case system
  case manual

  var id: String { rawValue }

  var title: String {
    switch self {
    case .disabled: return L10n.tr("preferences.proxy.mode.disabled")
    case .system: return L10n.tr("preferences.proxy.mode.system")
    case .manual: return L10n.tr("preferences.proxy.mode.manual")
    }
  }
}

enum ProxyScheme: String, CaseIterable, Identifiable {
  case http

  // aria2's proxy options use an HTTP proxy endpoint, including CONNECT for
  // HTTPS destinations. Keep accepting the old persisted value so upgrades
  // do not leave an unsupported scheme in settings.
  init?(rawValue: String) {
    switch rawValue.lowercased() {
    case "http", "https":
      self = .http
    default:
      return nil
    }
  }

  var id: String { rawValue }
  var title: String { rawValue.uppercased() }
}

struct ProxyEndpoint: Equatable {
  let scheme: ProxyScheme
  let host: String
  let port: Int

  var urlString: String? {
    var components = URLComponents()
    components.scheme = scheme.rawValue
    components.host = host
    components.port = port
    return components.string
  }
}

enum ProxyConfiguration {
  static let defaultHost = "127.0.0.1"
  static let defaultPort = 42613

  private static let aria2ProxyKeys: Set<String> = [
    "all-proxy",
    "all-proxy-user",
    "all-proxy-passwd",
    "http-proxy",
    "http-proxy-user",
    "http-proxy-passwd",
    "https-proxy",
    "https-proxy-user",
    "https-proxy-passwd",
    "no-proxy"
  ]

  static func apply(to engineConfig: inout [String: Any], userConfig: [String: Any]) {
    let legacyOptions = engineConfig.filter { aria2ProxyKeys.contains($0.key) }
    aria2ProxyKeys.forEach { engineConfig.removeValue(forKey: $0) }

    guard let rawMode = userConfig["proxy-mode"] as? String else {
      engineConfig.merge(normalizedLegacyOptions(legacyOptions)) { _, new in new }
      return
    }

    let mode = ProxyMode(rawValue: rawMode) ?? .disabled
    let options: [String: String]
    switch mode {
    case .disabled:
      options = [:]
    case .system:
      options = SystemProxyResolver.aria2Options()
    case .manual:
      options = manualOptions(userConfig: userConfig)
    }

    engineConfig.merge(options) { _, new in new }
  }

  static func hasLegacyProxy(in systemConfig: [String: Any]) -> Bool {
    systemConfig.keys.contains { aria2ProxyKeys.contains($0) }
  }

  static func legacyEndpoint(in systemConfig: [String: Any]) -> (scheme: ProxyScheme, host: String, port: Int)? {
    for key in ["all-proxy", "https-proxy", "http-proxy"] {
      guard
        let value = systemConfig[key] as? String,
        let components = URLComponents(string: value.contains("://") ? value : "http://\(value)"),
        let host = components.host,
        !host.isEmpty
      else {
        continue
      }

      let scheme = ProxyScheme(rawValue: components.scheme?.lowercased() ?? "http") ?? .http
      let port = components.port ?? 80
      return (scheme, host, port)
    }
    return nil
  }

  static func testEndpoint(
    mode: ProxyMode,
    scheme: ProxyScheme,
    host: String,
    port: Int
  ) -> ProxyEndpoint? {
    switch mode {
    case .disabled:
      return nil
    case .system:
      return SystemProxyResolver.preferredEndpoint()
    case .manual:
      return manualEndpoint(scheme: scheme, host: host, port: port)
    }
  }

  static func manualOptions(userConfig: [String: Any]) -> [String: String] {
    let scheme = ProxyScheme(rawValue: userConfig["proxy-scheme"] as? String ?? "") ?? .http
    let host = userConfig["proxy-host"] as? String ?? defaultHost
    let port = intValue(userConfig["proxy-port"]) ?? defaultPort

    guard let endpoint = manualEndpoint(scheme: scheme, host: host, port: port) else {
      return [:]
    }
    guard let endpointURL = endpoint.urlString else {
      return [:]
    }

    return [
      "all-proxy": endpointURL,
      "no-proxy": "localhost,127.0.0.1,::1"
    ]
  }

  static func manualEndpoint(scheme: ProxyScheme, host: String, port: Int) -> ProxyEndpoint? {
    let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !host.isEmpty else { return nil }
    return ProxyEndpoint(scheme: scheme, host: host, port: min(65535, max(1, port)))
  }

  private static func normalizedLegacyOptions(_ options: [String: Any]) -> [String: Any] {
    let endpointKeys: Set<String> = ["all-proxy", "http-proxy", "https-proxy"]
    return options.reduce(into: options) { result, entry in
      guard endpointKeys.contains(entry.key), let value = entry.value as? String,
        let components = URLComponents(string: value),
        components.scheme?.lowercased() == "https"
      else {
        return
      }
      var normalized = components
      normalized.scheme = ProxyScheme.http.rawValue
      result[entry.key] = normalized.string ?? value
    }
  }

  private static func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? NSNumber { return value.intValue }
    if let value = value as? String { return Int(value) }
    return nil
  }
}

private enum SystemProxyResolver {
  static func aria2Options() -> [String: String] {
    guard let settings = SCDynamicStoreCopyProxies(nil) as? [String: Any] else {
      return [:]
    }

    var options: [String: String] = [:]
    if let endpoint = endpoint(prefix: "HTTP", settings: settings)?.urlString {
      options["http-proxy"] = endpoint
    }
    if let endpoint = endpoint(prefix: "HTTPS", settings: settings)?.urlString {
      options["https-proxy"] = endpoint
    }
    if !options.isEmpty {
      options["no-proxy"] = "localhost,127.0.0.1,::1"
    }
    return options
  }

  static func preferredEndpoint() -> ProxyEndpoint? {
    guard let settings = SCDynamicStoreCopyProxies(nil) as? [String: Any] else {
      return nil
    }
    return endpoint(prefix: "HTTPS", settings: settings)
      ?? endpoint(prefix: "HTTP", settings: settings)
  }

  private static func endpoint(prefix: String, settings: [String: Any]) -> ProxyEndpoint? {
    guard
      boolValue(settings["\(prefix)Enable"]),
      let host = settings["\(prefix)Proxy"] as? String,
      !host.isEmpty,
      let port = intValue(settings["\(prefix)Port"]),
      (1...65535).contains(port)
    else {
      return nil
    }

    return ProxyEndpoint(scheme: .http, host: host, port: port)
  }

  private static func boolValue(_ value: Any?) -> Bool {
    if let value = value as? Bool { return value }
    if let value = value as? NSNumber { return value.boolValue }
    if let value = value as? String { return value == "1" || value == "true" }
    return false
  }

  private static func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? NSNumber { return value.intValue }
    if let value = value as? String { return Int(value) }
    return nil
  }
}
