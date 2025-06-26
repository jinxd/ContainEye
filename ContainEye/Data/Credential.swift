//
//  Credential.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/13/25.
//

import Foundation

enum AuthenticationMethod: Codable, Equatable, Hashable, CaseIterable {
    case password
    case privateKey
    case privateKeyWithPassphrase
    
    var displayName: String {
        switch self {
        case .password:
            return "Password"
        case .privateKey:
            return "SSH Key"
        case .privateKeyWithPassphrase:
            return "SSH Key + Passphrase"
        }
    }
    
    var icon: String {
        switch self {
        case .password:
            return "key.fill"
        case .privateKey:
            return "key.horizontal.fill"
        case .privateKeyWithPassphrase:
            return "key.horizontal.fill"
        }
    }
}

struct Credential: Codable, Equatable, Hashable {
    var key: String
    var label: String
    var host: String
    var port: Int32
    var username: String
    var password: String
    var authMethod: AuthenticationMethod?
    var privateKey: String?
    var passphrase: String?
    
    init(key: String, label: String, host: String, port: Int32, username: String, password: String, authMethod: AuthenticationMethod = .password, privateKey: String? = nil, passphrase: String? = nil) {
        self.key = key
        self.label = label
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.authMethod = authMethod
        self.privateKey = privateKey
        self.passphrase = passphrase
    }
    
    // Custom decoding to handle legacy credentials
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        key = try container.decode(String.self, forKey: .key)
        label = try container.decode(String.self, forKey: .label)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int32.self, forKey: .port)
        username = try container.decode(String.self, forKey: .username)
        password = try container.decode(String.self, forKey: .password)
        
        // Handle optional new fields for backward compatibility
        authMethod = try container.decodeIfPresent(AuthenticationMethod.self, forKey: .authMethod)
        privateKey = try container.decodeIfPresent(String.self, forKey: .privateKey)
        passphrase = try container.decodeIfPresent(String.self, forKey: .passphrase)
    }
    
    private enum CodingKeys: String, CodingKey {
        case key, label, host, port, username, password, authMethod, privateKey, passphrase
    }
    
    // Legacy support for password-only credentials
    var isPasswordAuth: Bool {
        (authMethod ?? .password) == .password
    }
    
    var requiresPassphrase: Bool {
        (authMethod ?? .password) == .privateKeyWithPassphrase
    }
    
    var hasPrivateKey: Bool {
        let method = authMethod ?? .password
        return method != .password && privateKey != nil && !privateKey!.isEmpty
    }
    
    // Get the effective auth method (defaults to password for legacy credentials)
    var effectiveAuthMethod: AuthenticationMethod {
        authMethod ?? .password
    }
}
