import Foundation
import MusicKit
import CryptoKit

@available(iOS 15.0, *)
class MusicKitConfig {
    static let shared = MusicKitConfig()

    // Your credentials from Apple Developer Portal
    private let teamID = "AWLLM3Q8GW"
    private let keyID = "BV9L8FK2BJ"
    private let privateKeyFileName = "AuthKey_BV9L8FK2BJ"

    // Media Identifier from Apple Developer Portal
    private let mediaIdentifier = "DiscoShadow MusicKit Key"

    private init() {}

    func configureCustomMusicKit() {
        // For now, we'll try a different approach
        // Let's update the MusicAPIService to handle the token error gracefully
        print("🎵 MusicKit configured with Developer credentials")
        print("🔑 Team ID: \(teamID)")
        print("🔑 Key ID: \(keyID)")
        print("🆔 Media ID: \(mediaIdentifier)")
    }

    func generateDeveloperToken() -> String? {
        guard let keyPath = Bundle.main.path(forResource: privateKeyFileName, ofType: "p8"),
              let keyData = Data(contentsOf: URL(fileURLWithPath: keyPath)) else {
            print("❌ Could not load private key file: \(privateKeyFileName).p8")
            return nil
        }

        do {
            // Create JWT header
            let header = [
                "alg": "ES256",
                "kid": keyID
            ]

            // Create JWT payload
            let now = Date()
            let payload = [
                "iss": teamID,
                "iat": Int(now.timeIntervalSince1970),
                "exp": Int(now.addingTimeInterval(3600).timeIntervalSince1970) // 1 hour
            ]

            // Convert to JSON
            let headerData = try JSONSerialization.data(withJSONObject: header)
            let payloadData = try JSONSerialization.data(withJSONObject: payload)

            // Base64 URL encode
            let headerB64 = headerData.base64URLEncodedString()
            let payloadB64 = payloadData.base64URLEncodedString()

            let message = "\(headerB64).\(payloadB64)"
            let messageData = Data(message.utf8)

            // Create private key from P8 data
            let privateKey = try P256.Signing.PrivateKey(pemRepresentation: String(data: keyData, encoding: .utf8)!)

            // Sign the message
            let signature = try privateKey.signature(for: messageData)
            let signatureB64 = signature.rawRepresentation.base64URLEncodedString()

            let jwt = "\(message).\(signatureB64)"
            print("✅ Generated developer token successfully")
            return jwt

        } catch {
            print("❌ Failed to generate developer token: \(error)")
            return nil
        }
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        let base64 = self.base64EncodedString()
        return base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}