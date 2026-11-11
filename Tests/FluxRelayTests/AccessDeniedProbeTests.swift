import Foundation
import XCTest
@testable import FluxRelay

final class AccessDeniedProbeTests: XCTestCase {
  private func task(status: String, message: String, uri: String = "https://example.test/file.zip") -> Aria2Task {
    Aria2Task.from([
      "gid": "denied", "status": status, "errorCode": "22", "errorMessage": message,
      "files": [["index": "1", "path": "/tmp/file.zip", "uris": [["uri": uri]]]]
    ])!
  }

  func testReadsTheHTTPStatusFromTheErrorMessage() {
    XCTAssertEqual(task(status: "error", message: "The response status is not successful. status=403").httpErrorStatus, 403)
    XCTAssertNil(task(status: "error", message: "SSL/TLS handshake failure").httpErrorStatus)
    XCTAssertNil(task(status: "active", message: "status=403").httpErrorStatus)
  }

  func testOnlyWebSourcesCanBeOpenedInABrowser() {
    XCTAssertEqual(task(status: "error", message: "").webSourceURL?.host, "example.test")
    XCTAssertNil(task(status: "error", message: "", uri: "magnet:?xt=urn:btih:abc").webSourceURL)
    XCTAssertNil(task(status: "error", message: "", uri: "ftp://example.test/file").webSourceURL)
  }

  func testRecognizesCloudflareRefusals() throws {
    func response(_ status: Int, _ headers: [String: String]) throws -> HTTPURLResponse {
      try XCTUnwrap(HTTPURLResponse(url: URL(string: "https://example.test")!, statusCode: status, httpVersion: "HTTP/2", headerFields: headers))
    }
    XCTAssertTrue(AccessDeniedProbe.isBrowserVerification(try response(403, ["Server": "cloudflare"])))
    XCTAssertTrue(AccessDeniedProbe.isBrowserVerification(try response(403, ["cf-mitigated": "challenge"])))
    XCTAssertFalse(AccessDeniedProbe.isBrowserVerification(try response(403, ["Server": "AliyunOSS"])))
    XCTAssertFalse(AccessDeniedProbe.isBrowserVerification(try response(200, ["Server": "cloudflare"])))
  }
}
