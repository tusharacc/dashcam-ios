//
//  GoogleCloudAuth.swift
//  dashcam
//
//  Created by Claude on 9/22/25.
//

import Foundation
import Security
import CryptoKit
import CommonCrypto

struct GoogleCloudAuth {
    struct ServiceAccountKey: Codable {
        let type: String
        let project_id: String
        let private_key_id: String
        let private_key: String
        let client_email: String
        let client_id: String
        let auth_uri: String
        let token_uri: String
        let auth_provider_x509_cert_url: String
        let client_x509_cert_url: String
    }

    struct TokenResponse: Codable {
        let access_token: String
        let expires_in: Int
        let token_type: String
    }

    struct JWTHeader: Codable {
        let alg: String
        let typ: String
    }

    struct JWTPayload: Codable {
        let iss: String // issuer (service account email)
        let scope: String // requested scopes
        let aud: String // audience (token URI)
        let exp: Int // expiration time
        let iat: Int // issued at time
    }

    static func generateAccessToken(from serviceAccountJSON: String) async throws -> (token: String, expiresAt: Date) {
        // Parse service account key
        guard let jsonData = serviceAccountJSON.data(using: .utf8) else {
            throw AuthError.invalidServiceAccount
        }

        let serviceAccount: ServiceAccountKey
        do {
            serviceAccount = try JSONDecoder().decode(ServiceAccountKey.self, from: jsonData)
        } catch {
            throw AuthError.invalidServiceAccount
        }

        // Validate key fields
        guard !serviceAccount.private_key.isEmpty,
              !serviceAccount.client_email.isEmpty,
              !serviceAccount.token_uri.isEmpty else {
            throw AuthError.invalidServiceAccount
        }

        // Create JWT and exchange for access token
        let jwt = try createJWT(serviceAccount: serviceAccount)
        let (token, expiresAt) = try await exchangeJWTForAccessToken(jwt: jwt, tokenURI: serviceAccount.token_uri)

        return (token, expiresAt)
    }

    private static func createJWT(serviceAccount: ServiceAccountKey) throws -> String {
        let now = Date()
        let expiry = now.addingTimeInterval(3600) // 1 hour

        // JWT Header
        let header = JWTHeader(alg: "RS256", typ: "JWT")
        let headerData = try JSONEncoder().encode(header)
        let headerBase64 = headerData.base64URLEncodedString()

        // JWT Payload
        let payload = JWTPayload(
            iss: serviceAccount.client_email,
            scope: "https://www.googleapis.com/auth/cloud-platform",
            aud: serviceAccount.token_uri,
            exp: Int(expiry.timeIntervalSince1970),
            iat: Int(now.timeIntervalSince1970)
        )
        let payloadData = try JSONEncoder().encode(payload)
        let payloadBase64 = payloadData.base64URLEncodedString()

        // Create signature
        let message = "\(headerBase64).\(payloadBase64)"
        let signature = try signMessage(message, privateKey: serviceAccount.private_key)

        return "\(message).\(signature)"
    }

    private static func signMessage(_ message: String, privateKey: String) throws -> String {
        // Clean the private key - Google Cloud uses PKCS#8 format
        let cleanKey = privateKey
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\\n", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let keyData = Data(base64Encoded: cleanKey) else {
            throw AuthError.invalidPrivateKey
        }

        // Google Cloud service accounts use PKCS#8 format
        // Try multiple approaches to create the SecKey
        let keyAttributes: [[String: Any]] = [
            // Standard PKCS#8 approach
            [
                kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
                kSecAttrKeySizeInBits as String: 2048
            ],
            // Alternative PKCS#8 approach
            [
                kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
            ],
            // Fallback approach
            [
                kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
                kSecAttrKeySizeInBits as String: 2048,
                kSecAttrIsPermanent as String: false
            ]
        ]

        var secKey: SecKey?
        var lastError: CFError?

        for (index, keyAttrs) in keyAttributes.enumerated() {
            print("🔐 Trying key creation approach \(index + 1)")

            var error: Unmanaged<CFError>?
            if let key = SecKeyCreateWithData(keyData as CFData, keyAttrs as CFDictionary, &error) {
                print("✅ Successfully created SecKey using approach \(index + 1)")
                secKey = key
                break
            } else {
                if let err = error?.takeRetainedValue() {
                    print("⚠️ Failed with approach \(index + 1): \(err)")
                    lastError = err
                } else {
                    print("⚠️ Failed with approach \(index + 1): Unknown error")
                }
            }
        }

        // Try converting PKCS#8 to PKCS#1 format
        if secKey == nil {
            print("🔐 Trying to extract RSA private key from PKCS#8...")
            if let pkcs1Data = extractRSAPrivateKeyFromPKCS8(keyData) {
                print("🔐 Extracted PKCS#1 data, size: \(pkcs1Data.count) bytes")

                let pkcs1Attrs: [String: Any] = [
                    kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                    kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
                    kSecAttrKeySizeInBits as String: 2048
                ]

                var error: Unmanaged<CFError>?
                secKey = SecKeyCreateWithData(pkcs1Data as CFData, pkcs1Attrs as CFDictionary, &error)

                if secKey != nil {
                    print("✅ Successfully created SecKey from extracted PKCS#1 data")
                } else if let err = error?.takeRetainedValue() {
                    print("⚠️ PKCS#1 extraction failed: \(err)")
                }
            }
        }

        // Final fallback: try SecItemImport
        if secKey == nil {
            print("🔐 Trying SecItemImport as final fallback...")
            secKey = try importPrivateKeyUsingSecItemImport(keyData: keyData)
        }

        guard let validSecKey = secKey else {
            print("❌ Could not create SecKey from private key data using any method")
            if let error = lastError {
                print("❌ Last error: \(error)")
            }
            throw AuthError.invalidPrivateKey
        }

        // Sign the message
        guard let messageData = message.data(using: .utf8) else {
            print("❌ Failed to convert message to data")
            throw AuthError.signatureFailed
        }

        print("🔐 Signing message of length: \(messageData.count)")

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            validSecKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            messageData as CFData,
            &error
        ) else {
            if let err = error?.takeRetainedValue() {
                print("❌ Signature creation failed: \(err)")
            }
            throw AuthError.signatureFailed
        }

        print("✅ Successfully signed message, signature length: \((signature as Data).count)")
        return (signature as Data).base64URLEncodedString()
    }

    private static func extractRSAPrivateKeyFromPKCS8(_ pkcs8Data: Data) -> Data? {
        // PKCS#8 RSA private key structure (simplified ASN.1 parsing):
        // SEQUENCE {
        //   version INTEGER,
        //   privateKeyAlgorithm AlgorithmIdentifier,
        //   privateKey OCTET STRING (contains PKCS#1 RSA private key)
        // }

        print("🔐 Parsing PKCS#8 structure...")
        let bytes = [UInt8](pkcs8Data)

        // Look for the RSA algorithm OID: 1.2.840.113549.1.1.1
        let rsaOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]

        // Find OID position
        var oidPosition: Int?
        for i in 0..<(bytes.count - rsaOID.count) {
            if Array(bytes[i..<(i + rsaOID.count)]) == rsaOID {
                oidPosition = i
                break
            }
        }

        guard let oid = oidPosition else {
            print("❌ Could not find RSA OID in PKCS#8 data")
            return nil
        }

        print("🔐 Found RSA OID at position \(oid)")

        // Look for the OCTET STRING that contains the PKCS#1 private key
        // This is a simplified search - in production you'd want proper ASN.1 parsing
        for i in (oid + rsaOID.count)..<(bytes.count - 10) {
            if bytes[i] == 0x04 { // OCTET STRING tag
                // Check if this could be the start of a PKCS#1 key
                let remainingBytes = bytes.count - i
                if remainingBytes > 100 { // Reasonable size check
                    // Get the length of the octet string
                    var length: Int
                    var dataStart: Int

                    if bytes[i + 1] & 0x80 == 0 {
                        // Short form length
                        length = Int(bytes[i + 1])
                        dataStart = i + 2
                    } else {
                        // Long form length
                        let lengthOfLength = Int(bytes[i + 1] & 0x7F)
                        if lengthOfLength == 2 && i + 3 < bytes.count {
                            length = Int(bytes[i + 2]) << 8 + Int(bytes[i + 3])
                            dataStart = i + 4
                        } else if lengthOfLength == 1 && i + 2 < bytes.count {
                            length = Int(bytes[i + 2])
                            dataStart = i + 3
                        } else {
                            continue
                        }
                    }

                    // Verify we have enough data and it looks like PKCS#1
                    if dataStart + length <= bytes.count &&
                       dataStart + 10 < bytes.count &&
                       bytes[dataStart] == 0x30 { // SEQUENCE tag for PKCS#1

                        let pkcs1Data = Data(bytes[dataStart..<(dataStart + length)])
                        print("🔐 Extracted PKCS#1 private key, length: \(length)")
                        return pkcs1Data
                    }
                }
            }
        }

        print("❌ Could not extract PKCS#1 private key from PKCS#8 data")
        return nil
    }

    private static func importPrivateKeyUsingSecItemImport(keyData: Data) throws -> SecKey? {
        print("🔐 SecItemImport fallback not available on iOS")
        // SecItemImport is not available on iOS, only macOS
        // This was just a fallback attempt
        return nil
    }

    private static func exchangeJWTForAccessToken(jwt: String, tokenURI: String) async throws -> (token: String, expiresAt: Date) {
        print("🔐 Exchanging JWT for access token at: \(tokenURI)")

        guard let url = URL(string: tokenURI) else {
            print("❌ Invalid token URI: \(tokenURI)")
            throw AuthError.invalidTokenURI
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(jwt)"
        request.httpBody = body.data(using: .utf8)

        print("🔐 Sending token exchange request...")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid HTTP response")
                throw AuthError.tokenExchangeFailed
            }

            print("🔐 Token exchange response status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 200 {
                do {
                    let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
                    let expiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
                    print("✅ Successfully obtained access token")
                    return (tokenResponse.access_token, expiresAt)
                } catch {
                    print("❌ Failed to decode token response: \(error)")
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("❌ Response body: \(responseString)")
                    }
                    throw AuthError.tokenExchangeFailed
                }
            } else {
                print("❌ Token exchange failed with status: \(httpResponse.statusCode)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("❌ Error response: \(responseString)")
                }
                throw AuthError.tokenExchangeFailed
            }
        } catch let error as AuthError {
            throw error
        } catch {
            print("❌ Network error during token exchange: \(error)")
            throw AuthError.tokenExchangeFailed
        }
    }

    enum AuthError: Error {
        case invalidServiceAccount
        case invalidPrivateKey
        case invalidTokenURI
        case tokenExchangeFailed
        case signatureFailed
        case notImplemented

        var localizedDescription: String {
            switch self {
            case .invalidServiceAccount:
                return "Invalid service account key format"
            case .invalidPrivateKey:
                return "Invalid private key"
            case .invalidTokenURI:
                return "Invalid token URI"
            case .tokenExchangeFailed:
                return "Failed to exchange token"
            case .signatureFailed:
                return "Failed to sign JWT"
            case .notImplemented:
                return "Google Cloud authentication requires additional setup. Files will be stored locally for now."
            }
        }
    }
}

// MARK: - Base64 URL Encoding Extension
extension Data {
    func base64URLEncodedString() -> String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}