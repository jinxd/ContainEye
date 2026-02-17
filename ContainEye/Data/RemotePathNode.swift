import Foundation
import Blackbird

struct RemotePathNode: BlackbirdModel {
    @BlackbirdColumn var id: String
    @BlackbirdColumn var credentialKey: String
    @BlackbirdColumn var path: String
    @BlackbirdColumn var isDirectory: Bool
    @BlackbirdColumn var lastSeen: Date

    static let primaryKey: [BlackbirdColumnKeyPath] = [\.$id]

    static let indexes: [[BlackbirdColumnKeyPath]] = [
        [\.$credentialKey, \.$path],
        [\.$credentialKey, \.$lastSeen],
    ]

    init(credentialKey: String, path: String, isDirectory: Bool, lastSeen: Date = .now) {
        self.id = "\(credentialKey)|\(path)"
        self.credentialKey = credentialKey
        self.path = path
        self.isDirectory = isDirectory
        self.lastSeen = lastSeen
    }
}
