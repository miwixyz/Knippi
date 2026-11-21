import CryptoKit
import Foundation
import Testing
@testable import ShareKit

/// Audit Q4, 21.11.: Host and Content-Type are signed, signature lives 15 min.
@Suite("Tencent COS signing")
struct TencentCOSSigningTests {
    @Test("host and content-type are in the header list and the signature")
    func signsHostAndContentType() throws {
        let auth = TencentCOSDestination.authorization(
            method: "PUT",
            encodedKey: "shots/a.png",
            headers: ["host": "b-1250000000.cos.ap-shanghai.myqcloud.com", "content-type": "image/png"],
            secretID: "AKID",
            secretKey: "secret",
            now: 1_000
        )
        let fields = Dictionary(uniqueKeysWithValues: auth.split(separator: "&").map {
            let pair = $0.split(separator: "=", maxSplits: 1)
            return (String(pair[0]), pair.count > 1 ? String(pair[1]) : "")
        })
        #expect(fields["q-header-list"] == "content-type;host")
        #expect(fields["q-key-time"] == "1000;1900")

        // Independent recomputation of the COS v5 signature.
        func hmac(_ key: String, _ msg: String) -> String {
            HMAC<Insecure.SHA1>.authenticationCode(for: Data(msg.utf8), using: SymmetricKey(data: Data(key.utf8)))
                .map { String(format: "%02x", $0) }.joined()
        }
        func sha1(_ s: String) -> String {
            Insecure.SHA1.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        let httpString = "put\n/shots/a.png\n\ncontent-type=image%2Fpng&host=b-1250000000.cos.ap-shanghai.myqcloud.com\n"
        let stringToSign = "sha1\n1000;1900\n\(sha1(httpString))\n"
        let expected = hmac(hmac("secret", "1000;1900"), stringToSign)
        #expect(fields["q-signature"] == expected)
    }

    @Test("COS encoding keeps only unreserved characters")
    func encoding() {
        #expect(TencentCOSDestination.cosEncode("image/png") == "image%2Fpng")
        #expect(TencentCOSDestination.cosEncode("a-b_c.d~e") == "a-b_c.d~e")
        #expect(TencentCOSDestination.cosEncode("a b+c") == "a%20b%2Bc")
    }
}
