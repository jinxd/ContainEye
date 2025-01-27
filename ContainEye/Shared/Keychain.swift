//
//  Keychain.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/27/25.
//

import Foundation
import KeychainAccess


func keychain() -> Keychain {
    Keychain()
        .synchronizable(true)
        .accessibility(.afterFirstUnlock)
        .label("ContainEye")
}


extension Keychain {
    func getCredential(for key: String) -> Credential? {
        if let data = try? self.getData(key),
           let credential = try? JSONDecoder().decode(Credential.self, from: data) {
            return credential
        } else {
            return nil
        }
    }
}
