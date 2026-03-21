//
//  CloudKitPublicKey.swift
//  thebitbinder
//
//  Secure storage for CloudKit schema public key
//

import Foundation

/// Secure storage for CloudKit public key used for schema verification
enum CloudKitPublicKey {
    
    /// The ECDSA P-256 public key for CloudKit schema verification
    /// Format: Base64-encoded SubjectPublicKeyInfo (SPKI)
    static let publicKeyPEM = """
    -----BEGIN PUBLIC KEY-----
    MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEqv8O9S6dxIMEdFV0o4otTB+E2F5L
    zvSgSMT9YsnNikRpP2uQigEiF1lh8BvSiEadSo1suFMNiMjo2w71il63Jg==
    -----END PUBLIC KEY-----
    """
    
    /// Raw base64-encoded key data (without PEM headers)
    static let publicKeyBase64 = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEqv8O9S6dxIMEdFV0o4otTB+E2F5LzvSgSMT9YsnNikRpP2uQigEiF1lh8BvSiEadSo1suFMNiMjo2w71il63Jg=="
    
    /// Key identifier for Keychain storage
    static let keyIdentifier = "com.bitbinder.cloudkit.schema.publickey"
    
    /// Key algorithm type
    static let keyAlgorithm = "ECDSA P-256"
    
    /// Schema version this key is associated with
    static let associatedSchemaVersion = "2.1.0"
    
    /// Returns the raw key data
    static var keyData: Data? {
        // Remove PEM headers and decode base64
        let base64Key = publicKeyPEM
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return Data(base64Encoded: base64Key)
    }
}
