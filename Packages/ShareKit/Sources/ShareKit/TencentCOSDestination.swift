import Foundation

public actor TencentCOSDestination: ShareDestination {
    private let config: ShareConfig
    private let secretID: String
    private let secretKey: String

    public init(config: ShareConfig, secretID: String, secretKey: String) {
        self.config = config
        self.secretID = secretID
        self.secretKey = secretKey
    }

    public nonisolated func publicURL(for key: String) -> URL {
        config.publicURL(forObjectKey: config.objectKey(for: key))
    }

    public func upload(file: URL, key: String, contentType: String) async throws -> URL {
        let objectKey = config.objectKey(for: key)
        let request = try signedRequest(method: "PUT", objectKey: objectKey, contentType: contentType)
        try await ShareHTTP.upload(request: request, file: file)
        return config.publicURL(forObjectKey: objectKey)
    }

    public func delete(key: String) async throws {
        let objectKey = config.objectKey(for: key)
        let request = try signedRequest(method: "DELETE", objectKey: objectKey, contentType: nil)
        try await ShareHTTP.data(request: request)
    }

    private func signedRequest(method: String, objectKey: String, contentType: String?) throws -> URLRequest {
        let host = "\(config.bucket).cos.\(config.region).myqcloud.com"
        let encodedKey = ShareConfig.encodeObjectKey(objectKey)
        guard let url = URL(string: "https://\(host)/\(encodedKey)") else {
            throw ShareError.notConfigured
        }

        var signedHeaders = ["host": host]
        if let contentType { signedHeaders["content-type"] = contentType }
        let authorization = Self.authorization(
            method: method,
            encodedKey: encodedKey,
            headers: signedHeaders,
            secretID: secretID,
            secretKey: secretKey,
            now: Int(Date().timeIntervalSince1970)
        )

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// Lifetime of a request signature. Short, because it only has to cover
    /// the request about to be sent (audit Q4, 21.11.; was 1 h).
    static let signatureLifetime = 900

    /// COS request signature (sign version 5). Host and Content-Type are part
    /// of the signature, so a leaked Authorization header cannot be replayed
    /// against another host or with another content type (audit Q4, 21.11.).
    static func authorization(
        method: String,
        encodedKey: String,
        headers: [String: String],
        secretID: String,
        secretKey: String,
        now: Int
    ) -> String {
        let keyTime = "\(now);\(now + signatureLifetime)"
        let signKey = ShareSigning.hex(ShareSigning.hmacSHA1(key: secretKey, message: keyTime))
        let sorted = headers
            .map { (cosEncode($0.key.lowercased()), cosEncode($0.value)) }
            .sorted { $0.0 < $1.0 }
        let headerList = sorted.map(\.0).joined(separator: ";")
        let httpHeaders = sorted.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        let httpString = "\(method.lowercased())\n/\(encodedKey)\n\n\(httpHeaders)\n"
        let stringToSign = "sha1\n\(keyTime)\n\(ShareSigning.sha1Hex(httpString))\n"
        let signature = ShareSigning.hex(ShareSigning.hmacSHA1(key: signKey, message: stringToSign))
        return "q-sign-algorithm=sha1"
            + "&q-ak=\(secretID)"
            + "&q-sign-time=\(keyTime)"
            + "&q-key-time=\(keyTime)"
            + "&q-header-list=\(headerList)"
            + "&q-url-param-list="
            + "&q-signature=\(signature)"
    }

    /// URL encoding as COS expects it: everything except RFC 3986 unreserved
    /// characters, with upper-case hex.
    static func cosEncode(_ text: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-_.~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
