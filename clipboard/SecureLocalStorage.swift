import CryptoKit
import Foundation
import LocalAuthentication
import Security

enum LocalDataCipherError: Error, Equatable {
    case invalidKey
    case invalidEnvelope
    case keychain(OSStatus)
    case randomGeneration(OSStatus)
}

struct OpenedLocalData {
    let plaintext: Data
    let wasEncrypted: Bool
}

struct LocalDataCipher {
    private static let envelopePrefix = Data("clipboard-encrypted-v1\n".utf8)
    private let keyDataProvider: () throws -> Data

    init(keyDataProvider: @escaping () throws -> Data) {
        self.keyDataProvider = keyDataProvider
    }

    static var keychainBacked: LocalDataCipher {
        LocalDataCipher { try LocalDataKeychain.shared.keyData() }
    }

    func seal(_ plaintext: Data, purpose: String) throws -> Data {
        let key = try symmetricKey()
        let sealedBox = try AES.GCM.seal(
            plaintext,
            using: key,
            authenticating: Data(purpose.utf8)
        )
        guard let combined = sealedBox.combined else {
            throw LocalDataCipherError.invalidEnvelope
        }
        return Self.envelopePrefix + combined
    }

    func open(_ data: Data, purpose: String) throws -> OpenedLocalData {
        guard data.starts(with: Self.envelopePrefix) else {
            return OpenedLocalData(plaintext: data, wasEncrypted: false)
        }

        let combined = Data(data.dropFirst(Self.envelopePrefix.count))
        guard !combined.isEmpty else {
            throw LocalDataCipherError.invalidEnvelope
        }
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        let plaintext = try AES.GCM.open(
            sealedBox,
            using: try symmetricKey(),
            authenticating: Data(purpose.utf8)
        )
        return OpenedLocalData(plaintext: plaintext, wasEncrypted: true)
    }

    func isEncrypted(_ data: Data) -> Bool {
        data.starts(with: Self.envelopePrefix)
    }

    private func symmetricKey() throws -> SymmetricKey {
        let keyData = try keyDataProvider()
        guard keyData.count == 32 else { throw LocalDataCipherError.invalidKey }
        return SymmetricKey(data: keyData)
    }
}

private final class LocalDataKeychain {
    private enum KeyReadResult {
        case key(Data)
        case status(OSStatus)
    }

    static let shared = LocalDataKeychain()

    private let service = "com.kelsiito.clipboard.local-storage"
    private let account = "aes-gcm-key-v1"
    private var cachedKey: Data?

    func keyData() throws -> Data {
        if let cachedKey { return cachedKey }

        switch readKey() {
        case .key(let key):
            cachedKey = key
            return key
        case .status(let status) where status == errSecItemNotFound:
            let key = try generateKey()
            let addStatus = SecItemAdd([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                kSecUseDataProtectionKeychain as String: true,
                kSecValueData as String: key
            ] as CFDictionary, nil)

            if addStatus == errSecSuccess {
                cachedKey = key
                return key
            }
            if addStatus == errSecDuplicateItem,
               case .key(let existingKey) = readKey() {
                cachedKey = existingKey
                return existingKey
            }
            throw LocalDataCipherError.keychain(addStatus)
        case .status(let status):
            throw LocalDataCipherError.keychain(status)
        }
    }

    private func readKey() -> KeyReadResult {
        let query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ] as CFDictionary
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query, &result)
        guard status == errSecSuccess else { return .status(status) }
        guard let data = result as? Data, data.count == 32 else {
            return .status(errSecDecode)
        }
        return .key(data)
    }

    private func generateKey() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, baseAddress)
        }
        guard status == errSecSuccess else {
            throw LocalDataCipherError.randomGeneration(status)
        }
        return Data(bytes)
    }
}

@MainActor
final class DeviceAuthenticationService {
    var isAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(false)
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
}
