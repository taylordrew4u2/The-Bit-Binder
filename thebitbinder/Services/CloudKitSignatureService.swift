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
    
}

// MARK: - Supporting Types

extension CloudKitSignatureService {
    
    enum SignatureError: Error, LocalizedError {
        case invalidKeyFormat

        var errorDescription: String? {
            switch self {
            case .invalidKeyFormat:
                return "Invalid public key format"
            }
        }
    }
}
