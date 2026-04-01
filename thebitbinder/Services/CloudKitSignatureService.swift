//
//  CloudKitSignatureService.swift
//  thebitbinder
//
//  Service for verifying CloudKit schema signatures using ECDSA P-256
//

import Foundation
import Security
import CryptoKit

/// Service for verifying CloudKit schema signatures
final class CloudKitSignatureService {
    
    static let shared = CloudKitSignatureService()
    
    private var cachedPublicKey: P256.Signing.PublicKey?
    
    private init() {
        loadPublicKey()
    }
    
    // MARK: - Key Management
    
    /// Loads the public key from configuration
    private func loadPublicKey() {
        guard let keyData = CloudKitPublicKey.keyData else {
            print(" [Signature] Failed to decode public key data")
            return
        }
        
        do {
            // Parse the SPKI format to get the raw EC key
            cachedPublicKey = try parseECPublicKey(from: keyData)
            print(" [Signature] Public key loaded successfully")
        } catch {
            print(" [Signature] Failed to parse public key: \(error)")
        }
    }
    
    /// Parses an EC public key from SPKI (SubjectPublicKeyInfo) format
    private func parseECPublicKey(from spkiData: Data) throws -> P256.Signing.PublicKey {
        // SPKI header for P-256 is 26 bytes, raw key is 65 bytes (04 || x || y)
        // Total SPKI is 91 bytes for uncompressed P-256
        let spkiHeaderLength = 26
        
        guard spkiData.count >= spkiHeaderLength + 65 else {
            throw SignatureError.invalidKeyFormat
        }
        
        // Extract the raw EC point (skip SPKI header)
        let rawKeyData = spkiData.suffix(from: spkiHeaderLength)
        
        // CryptoKit expects x963 format (which includes the 04 prefix)
        return try P256.Signing.PublicKey(x963Representation: rawKeyData)
    }
    
    /// Stores the public key in the Keychain for additional security
    func storeKeyInKeychain() -> Bool {
        guard let keyData = CloudKitPublicKey.keyData else { return false }
        
        // Delete any existing key
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: CloudKitPublicKey.keyIdentifier.data(using: .utf8)!
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add the new key
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: CloudKitPublicKey.keyIdentifier.data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        
        if status == errSecSuccess {
            print(" [Signature] Public key stored in Keychain")
            return true
        } else {
            print(" [Signature] Failed to store key in Keychain: \(status)")
            return false
        }
    }
    
    // MARK: - Signature Verification
    
    /// Verifies a signature against data using the stored public key
    /// - Parameters:
    ///   - signature: The signature to verify (DER or raw format)
    ///   - data: The original data that was signed
    /// - Returns: True if signature is valid
    func verifySignature(_ signature: Data, for data: Data) -> Bool {
        guard let publicKey = cachedPublicKey else {
            print(" [Signature] No public key available")
            return false
        }
        
        do {
            let ecdsaSignature = try P256.Signing.ECDSASignature(derRepresentation: signature)
            return publicKey.isValidSignature(ecdsaSignature, for: SHA256.hash(data: data))
        } catch {
            // Try raw signature format (r || s, 64 bytes)
            do {
                let ecdsaSignature = try P256.Signing.ECDSASignature(rawRepresentation: signature)
                return publicKey.isValidSignature(ecdsaSignature, for: SHA256.hash(data: data))
            } catch {
                print(" [Signature] Invalid signature format: \(error)")
                return false
            }
        }
    }
    
    /// Verifies a base64-encoded signature against a string
    func verifySignature(base64Signature: String, for message: String) -> Bool {
        guard let signatureData = Data(base64Encoded: base64Signature),
              let messageData = message.data(using: .utf8) else {
            return false
        }
        return verifySignature(signatureData, for: messageData)
    }
    
    /// Verifies schema integrity using a signed hash
    func verifySchemaIntegrity(schemaHash: String, signature: Data) -> SchemaVerificationResult {
        guard let hashData = schemaHash.data(using: .utf8) else {
            return .failed(reason: "Invalid schema hash encoding")
        }
        
        if verifySignature(signature, for: hashData) {
            return .valid(schemaVersion: CloudKitPublicKey.associatedSchemaVersion)
        } else {
            return .invalid(reason: "Signature verification failed")
        }
    }
    
    // MARK: - Schema Hash Generation
    
    /// Generates a hash of the current schema for verification
    func generateSchemaHash(recordTypes: [String]) -> String {
        let sortedTypes = recordTypes.sorted()
        let schemaString = sortedTypes.joined(separator: "|")
        
        guard let data = schemaString.data(using: .utf8) else {
            return ""
        }
        
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Key Info
    
    /// Returns information about the loaded public key
    func getKeyInfo() -> KeyInfo {
        return KeyInfo(
            identifier: CloudKitPublicKey.keyIdentifier,
            algorithm: CloudKitPublicKey.keyAlgorithm,
            schemaVersion: CloudKitPublicKey.associatedSchemaVersion,
            isLoaded: cachedPublicKey != nil
        )
    }
}

// MARK: - Supporting Types

extension CloudKitSignatureService {
    
    enum SignatureError: Error, LocalizedError {
        case invalidKeyFormat
        case invalidSignatureFormat
        case verificationFailed
        case keyNotLoaded
        
        var errorDescription: String? {
            switch self {
            case .invalidKeyFormat:
                return "Invalid public key format"
            case .invalidSignatureFormat:
                return "Invalid signature format"
            case .verificationFailed:
                return "Signature verification failed"
            case .keyNotLoaded:
                return "Public key not loaded"
            }
        }
    }
    
    enum SchemaVerificationResult {
        case valid(schemaVersion: String)
        case invalid(reason: String)
        case failed(reason: String)
        
        var isValid: Bool {
            if case .valid = self { return true }
            return false
        }
        
        var description: String {
            switch self {
            case .valid(let version):
                return " Schema verified (v\(version))"
            case .invalid(let reason):
                return " Schema invalid: \(reason)"
            case .failed(let reason):
                return " Verification failed: \(reason)"
            }
        }
    }
    
    struct KeyInfo {
        let identifier: String
        let algorithm: String
        let schemaVersion: String
        let isLoaded: Bool
        
        var description: String {
            """
            Key Info:
              Identifier: \(identifier)
              Algorithm: \(algorithm)
              Schema Version: \(schemaVersion)
              Status: \(isLoaded ? " Loaded" : " Not Loaded")
            """
        }
    }
}
