import Foundation

public actor R2Destination: ShareDestination {
    private let config: ShareConfig
    private let accessKey: String
    private let secretKey: String

    public init(config: ShareConfig, accessKey: String, secretKey: String) {
        self.config = config
        self.accessKey = accessKey
        self.secretKey = secretKey
    }

    public nonisolated func publicURL(for key: String) -> URL {
        config.publicURL(forObjectKey: config.objectKey(for: key))
    }

    public nonisolated var destinationID: String { config.destinationID }

    public func upload(file: URL, key: String, contentType: String) async throws -> URL {
        let objectKey = config.objectKey(for: key)
        let target = S3CompatibleHTTP.r2Target(
            accountID: config.accountID,
            bucket: config.bucket,
            objectKey: objectKey
        )
        // R2 ignores region for routing; SigV4 still requires a region string.
        try await S3CompatibleHTTP.putObject(
            file: file,
            target: target,
            region: "auto",
            accessKeyId: accessKey,
            secretAccessKey: secretKey,
            contentType: contentType
        )
        return config.publicURL(forObjectKey: objectKey)
    }

    public func delete(key: String) async throws {
        let objectKey = config.objectKey(for: key)
        let target = S3CompatibleHTTP.r2Target(
            accountID: config.accountID,
            bucket: config.bucket,
            objectKey: objectKey
        )
        try await S3CompatibleHTTP.deleteObject(
            target: target,
            region: "auto",
            accessKeyId: accessKey,
            secretAccessKey: secretKey
        )
    }

    // validateConfig: shared implementation in ShareDestination (ShareDestinationFactory.swift).
}
