// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
// Applies only to FrameMatter contributions; upstream notices are retained. See COPYRIGHT.txt.

//  UpdateCheck.swift — the one request that says whether a newer release exists.
//
//  RFC-021. This is deliberately not an updater: the app is ad-hoc signed and
//  not notarised, so a downloaded build would still need the quarantine step
//  the release zip needs today. The useful, smaller promise is to tell the
//  user that a newer build exists and open its release page.
//
//  The request is made only when the Settings button is pressed. It is an
//  unauthenticated read of the public FrameMatter release endpoint; no
//  identifier, version or local state is sent.

import Foundation

/// One HTTP result, shaped for tests without requiring a URL loading system.
struct UpdateHTTPResponse: Sendable {
    let status: Int
    /// Header keys are lowercased by the live transport so lookups are
    /// case-insensitive, as HTTP requires.
    let headers: [String: String]
    let body: Data

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

protocol UpdateTransport: Sendable {
    func latestRelease(from url: URL) async throws -> UpdateHTTPResponse
}

/// The shipping transport. Ephemeral, five seconds, no cache and no cookies.
struct URLSessionUpdateTransport: UpdateTransport {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    func latestRelease(from url: URL) async throws -> UpdateHTTPResponse {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 5)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub asks API clients to identify themselves. This is the product
        // name, not a machine identifier and not the app version.
        request.setValue("FrameMatter", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            result[String(describing: pair.key).lowercased()] = String(describing: pair.value)
        }
        return UpdateHTTPResponse(status: http.statusCode, headers: headers, body: data)
    }
}

enum UpdateCheck {
    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/LittleSixNine/FrameMatter/releases/latest")!

    enum Status: Equatable, Sendable {
        case idle
        case checking
        case updateAvailable(version: String, release: URL)
        case upToDate(version: String)
        case failed(reason: String)
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    private struct Version: Comparable {
        let build: Int
        var display: String { "Build \(build)" }
        static func < (lhs: Version, rhs: Version) -> Bool { lhs.build < rhs.build }
    }

    /// Production entry point. The version comes from the bundle, never a
    /// literal in this file.
    static func check(currentVersion: String = Diagnostics.bundleInfo.build) async -> Status {
        await check(currentVersion: currentVersion, transport: URLSessionUpdateTransport())
    }

    /// Testable entry point. Every transport failure maps to `.failed`, never
    /// `.upToDate`: a check that learned nothing must not look successful.
    static func check(currentVersion: String, transport: any UpdateTransport) async -> Status {
        do {
            let response = try await transport.latestRelease(from: latestReleaseURL)
            guard (200..<300).contains(response.status) else {
                if response.status == 403, response.header("X-RateLimit-Remaining") == "0" {
                    return .failed(reason: "GitHub's unauthenticated rate limit was reached. Try again later.")
                }
                if response.status == 404 {
                    return .failed(reason: "No published FrameMatter release was found.")
                }
                return .failed(reason: "GitHub returned HTTP \(response.status).")
            }

            let release: GitHubRelease
            do {
                release = try JSONDecoder().decode(GitHubRelease.self, from: response.body)
            } catch {
                return .failed(reason: "GitHub's release reply could not be read.")
            }

            guard let latest = version(fromTag: release.tagName) else {
                return .failed(reason: "The latest release tag '\(release.tagName)' is not in the expected build-N form.")
            }
            guard let installed = installedVersion(currentVersion) else {
                return .failed(reason: "This build's version '\(currentVersion)' could not be read.")
            }

            return latest > installed
                ? .updateAvailable(version: latest.display, release: release.htmlURL)
                : .upToDate(version: latest.display)
        } catch is CancellationError {
            return .failed(reason: "The check was cancelled.")
        } catch {
            return .failed(reason: failureReason(error))
        }
    }

    private static func version(fromTag tag: String) -> Version? {
        let prefix = "build-"
        guard tag.hasPrefix(prefix) else { return nil }
        return version(fromString: String(tag.dropFirst(prefix.count)))
    }

    private static func installedVersion(_ text: String) -> Version? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), parts.allSatisfy({ part in
            !part.isEmpty && part.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) && Int(part) != nil
        }) else { return nil }
        // Local revisions stay on their parent integer release train.
        return version(fromString: String(parts[0]))
    }

    private static func version(fromString text: String) -> Version? {
        guard !text.isEmpty, text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let build = Int(text), build > 0 else { return nil }
        return Version(build: build)
    }

    private static func failureReason(_ error: Error) -> String {
        guard let urlError = error as? URLError else { return error.localizedDescription }
        switch urlError.code {
        case .timedOut:
            return "GitHub did not answer within five seconds."
        case .notConnectedToInternet:
            return "This Mac appears to be offline."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "GitHub could not be reached."
        default:
            return urlError.localizedDescription
        }
    }
}
