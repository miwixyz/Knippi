// Packages/ShareKit/Sources/ShareKit/IDGenerator.swift

public enum IDGenerator {
    private static let charset: [Character] = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

    /// 22 Zeichen base62 aus dem System-Zufallsgenerator ≈ 131 Bit.
    /// Öffentliche Links dürfen nicht erratbar sein (Knippi-Spec R3).
    public static func shortID() -> String {
        var rng = SystemRandomNumberGenerator()
        return String((0..<22).map { _ in charset[Int(rng.next(upperBound: UInt32(charset.count)))] })
    }
}
