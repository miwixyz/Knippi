import CryptoKit
import Foundation

enum ShareSigning {
    static func hmacSHA1(key: String, message: String) -> Data {
        let signature = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(message.utf8),
            using: SymmetricKey(data: Data(key.utf8))
        )
        return Data(signature)
    }

    static func sha1Hex(_ text: String) -> String {
        hex(Data(Insecure.SHA1.hash(data: Data(text.utf8))))
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func base64(_ data: Data) -> String {
        data.base64EncodedString()
    }

    static func rfc1123Date(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }
}

/// Signed uploads and deletes never follow a redirect: a 3xx from the store (or a
/// proxy in between) would resend the request, including its signed headers, to a
/// host the user never configured. The 3xx then surfaces as an ordinary HTTP error.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = NoRedirectDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

enum ShareHTTP {
    static func upload(request: URLRequest, file: URL) async throws {
        let (body, response) = try await URLSession.shared.upload(
            for: request, fromFile: file, delegate: NoRedirectDelegate.shared
        )
        try validate(response: response, body: body)
    }

    static func data(request: URLRequest) async throws {
        let (body, response) = try await URLSession.shared.data(for: request, delegate: NoRedirectDelegate.shared)
        try validate(response: response, body: body)
    }

    /// Aliyun OSS and Tencent COS answer with S3-style XML (`<Code>…</Code>`), so the
    /// S3 mapping applies: only real auth codes mean "invalid credentials"; others
    /// (e.g. `RequestTimeTooSkewed`, `NoSuchBucket`) keep their own message.
    private static func validate(response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ShareError.network(underlying: "Missing HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw S3CompatibleHTTP.mapResponseError(statusCode: http.statusCode, body: body)
        }
    }
}
