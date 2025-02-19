//
//  Error+GenerateDescription.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/30/25.
//

import NIO
import Citadel
import NIOSSH

extension Error {
    func generateDescription() -> String {
        if let error = self as? ServerError {
            switch error {
            case .connectionFailed:
                return "Could not connect to the server."
            case .invalidStatsOutput(let output):
                return "Invalid output from server: \(output)"
            case .notConnected:
                return "Not connected to the server."
            case .invalidServerResponse:
                return "Invalid server response."
            case .otherError(let error):
                return "Other Error: \((error as Error).generateDescription())"
            case .cpuCommandFailed:
                return "Could not execute the CPU command."
            case .noPasswordInKeychain:
                return "No password found in keychain."
            }
        }
        if let error = self as? DataStreamerError {
            switch error {
            case .failedToConnect(to: let key, error: let error):
                let host = keychain().getCredential(for: key)?.host ?? "?"
                return "Failed to connect to \(host): \(error)"
            }
        }
        if let error = self as? ChannelError {
            return switch error {
            case .connectPending:
                "Connection is pending"
            case .connectTimeout(let timeAmount):
                "Connection timed out after \(timeAmount)"
            case .operationUnsupported:
                "Operation is not supported"
            case .ioOnClosedChannel:
                "io was called on a closed channel"
            case .alreadyClosed:
                "Channel is already closed"
            case .outputClosed:
                "Output is closed"
            case .inputClosed:
                "Input is closed"
            case .eof:
                "End of file"
            case .writeMessageTooLarge:
                "Write message too large"
            case .writeHostUnreachable:
                "write host unreachable"
            case .unknownLocalAddress:
                "unknown local address"
            case .badMulticastGroupAddressFamily:
                "bad multicast group address family"
            case .badInterfaceAddressFamily:
                "bad interface address family"
            case .illegalMulticastAddress(let socketAddress):
                "illegal multicast address: \(socketAddress)"
            case .multicastNotSupported(let nIONetworkInterface):
                "multicast not supported on \(nIONetworkInterface)"
            case .inappropriateOperationForState:
                "inappropriate operation for state"
            case .unremovableHandler:
                "unremovable handler"
            }
        }
        if let error = self as? IOError {
            return error.localizedDescription
        }
        if let error = self as? SSHClientError {
            return switch error {
            case .unsupportedPasswordAuthentication:
                "Unsupported password authentication"
            case .unsupportedPrivateKeyAuthentication:
                "Unsupported private key authentication"
            case .unsupportedHostBasedAuthentication:
                "Unsupported host-based authentication"
            case .channelCreationFailed:
                "Channel creation failed"
            case .allAuthenticationOptionsFailed:
                "All authentication options failed"
            }
        }
        if let message = (self as? TTYSTDError)?.message {
            return String(buffer: message)
        }
        if let error = self as? NIOSSHError {
            return switch error.type {
            case .invalidSSHMessage:
                "Received an invalid SSH message"
            case .weakSharedSecret:
                "Weak shared secret in key exchange"
            case .invalidNonceLength:
                "Invalid nonce length for cipher"
            case .excessiveVersionLength:
                "Client sent an excessively long version string"
            case .invalidEncryptedPacketLength:
                "Received an encrypted packet with an invalid length"
            case .invalidDecryptedPlaintextLength:
                "Decrypted plaintext length is not a multiple of block size"
            case .invalidKeySize:
                "Generated key size is invalid for encryption scheme"
            case .insufficientPadding:
                "Packet had insufficient padding"
            case .excessPadding:
                "Packet had excess padding"
            case .invalidMacSelected:
                "Invalid MAC algorithm selected for transport"
            case .unknownPublicKey:
                "Unknown public key type received"
            case .unknownSignature:
                "Unknown signature type received"
            case .invalidDomainParametersForKey:
                "Invalid domain parameters in public key"
            case .invalidExchangeHashSignature:
                "Exchange hash signature validation failed"
            case .invalidPacketFormat:
                "Packet format is invalid"
            case .protocolViolation:
                "SSH protocol violation detected"
            case .keyExchangeNegotiationFailure:
                "Key exchange negotiation failed"
            case .unsupportedVersion:
                "Remote peer offered an unsupported SSH version"
            case .channelSetupRejected:
                "Remote peer rejected channel setup"
            case .flowControlViolation:
                "Flow control violation detected"
            case .creatingChannelAfterClosure:
                "Attempted to create channel after SSH handler closure"
            case .tcpShutdown:
                "TCP connection shut down without closing SSH channel"
            case .invalidUserAuthSignature:
                "User authentication signature was invalid"
            case .unknownPacketType:
                "Received an unknown packet type"
            case .unsupportedGlobalRequest:
                "Received an unsupported global request"
            case .unexpectedGlobalRequestResponse:
                "Unexpected response to a global request"
            case .missingGlobalRequestResponse:
                "Expected but did not receive a response to a global request"
            case .globalRequestRefused:
                "Global request was refused by the peer"
            case .remotePeerDoesNotSupportMessage:
                "Remote peer does not support a sent message"
            case .invalidHostKeyForKeyExchange:
                "Invalid host key provided for key exchange"
            case .invalidOpenSSHPublicKey:
                "Failed to parse OpenSSH public key"
            case .invalidCertificate:
                "Certificate validation failed"
            default:
                "Unknown error: \(String(describing: self))"
            }
        }
        return "Unknown error: \(String(describing: self))"
    }
}
