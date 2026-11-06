//  UpdateCheckTests.swift — RFC-021's failure paths, and the two success paths.

import XCTest

final class UpdateCheckTests: XCTestCase {
    private struct StubTransport: UpdateTransport {
        let response: UpdateHTTPResponse
        let error: URLError?

        init(status: Int, headers: [String: String] = [:], body: String,
             error: URLError? = nil) {
            response = UpdateHTTPResponse(status: status, headers: headers,
                                          body: Data(body.utf8))
            self.error = error
        }

        init(error: URLError) {
            response = UpdateHTTPResponse(status: 0, headers: [:], body: Data())
            self.error = error
        }

        func latestRelease(from url: URL) async throws -> UpdateHTTPResponse {
            if let error { throw error }
            return response
        }
    }

    private func release(_ tag: String, url: String = "https://github.com/LittleSixNine/FrameMatter/releases/tag/build-4") -> String {
        """
        {"tag_name":"\(tag)","html_url":"\(url)"}
        """
    }

    func testTheCheckUsesTheFrameMatterReleaseEndpoint() {
        XCTAssertEqual(
            UpdateCheck.latestReleaseURL.absoluteString,
            "https://api.github.com/repos/LittleSixNine/FrameMatter/releases/latest")
    }

    func testANewerBuildIsComparedNumerically() async {
        let stub = StubTransport(status: 200, body: release("build-10"))
        let status = await UpdateCheck.check(currentVersion: "9", transport: stub)
        guard case .updateAvailable(let version, let url) = status else {
            return XCTFail("expected an update, got \(status)")
        }
        XCTAssertEqual(version, "Build 10")
        XCTAssertEqual(url.absoluteString,
                       "https://github.com/LittleSixNine/FrameMatter/releases/tag/build-4")
    }

    func testTheLatestReleaseIsReportedAsCurrent() async {
        let stub = StubTransport(status: 200, body: release("build-3"))
        let status = await UpdateCheck.check(currentVersion: "3", transport: stub)
        XCTAssertEqual(status, .upToDate(version: "Build 3"))
    }

    func testAnOlderReleaseDoesNotOfferADowngrade() async {
        let status = await UpdateCheck.check(currentVersion: "10", transport:
            StubTransport(status: 200, body: release("build-9")))
        XCTAssertEqual(status, .upToDate(version: "Build 9"))
    }

    func testOnlyPositiveIntegerReleaseTagsAreAccepted() async {
        for tag in ["build-0", "build--1", "build-1.2", "build-+2", "build-2beta", "build- 2"] {
            let status = await UpdateCheck.check(currentVersion: "1", transport:
                StubTransport(status: 200, body: release(tag)))
            guard case .failed = status else { return XCTFail("accepted invalid tag: \(tag)") }
        }
    }

    func testARateLimitNeverLooksLikeUpToDate() async {
        let stub = StubTransport(status: 403, headers: ["x-ratelimit-remaining": "0"],
                                 body: #"{"message":"API rate limit exceeded"}"#)
        let status = await UpdateCheck.check(currentVersion: "3", transport: stub)
        guard case .failed(let reason) = status else {
            return XCTFail("a rate limit became \(status)")
        }
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("rate limit"), reason)
    }

    func testAnUnparseableTagNeverLooksLikeUpToDate() async {
        let stub = StubTransport(status: 200, body: release("build-next"))
        let status = await UpdateCheck.check(currentVersion: "3", transport: stub)
        guard case .failed(let reason) = status else {
            return XCTFail("an unparseable tag became \(status)")
        }
        XCTAssertTrue(reason.contains("build-next"), reason)
    }

    func testNoReleaseNeverLooksLikeUpToDate() async {
        let stub = StubTransport(status: 404, body: #"{"message":"Not Found"}"#)
        let status = await UpdateCheck.check(currentVersion: "3", transport: stub)
        guard case .failed(let reason) = status else {
            return XCTFail("a missing release became \(status)")
        }
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("no published"), reason)
    }

    func testANetworkFailureNeverLooksLikeUpToDate() async {
        let stub = StubTransport(error: URLError(.notConnectedToInternet))
        let status = await UpdateCheck.check(currentVersion: "3", transport: stub)
        guard case .failed(let reason) = status else {
            return XCTFail("an offline Mac became \(status)")
        }
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("offline"), reason)
    }

    func testATimeoutNeverLooksLikeUpToDate() async {
        let stub = StubTransport(error: URLError(.timedOut))
        let status = await UpdateCheck.check(currentVersion: "3", transport: stub)
        guard case .failed(let reason) = status else {
            return XCTFail("a timeout became \(status)")
        }
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("five seconds"), reason)
    }
}
