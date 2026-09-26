import CommonCrypto
import CryptoKit
import Foundation

/// Encrypts vault files with AES-GCM. The key is made once, on this iPhone, and kept in the
/// Keychain (this device only). Pure logic apart from `deviceKey()`, unit tested.
nonisolated enum VaultCrypto {
    private static let keyAccount = "encryption-key"

    enum Failure: LocalizedError {
        case unreadable
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unreadable: "The vault's data couldn't be read."
            case .keychain(let status):
                "The vault's key couldn't be stored in the Keychain (\(SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)")). Make sure your iPhone has a passcode set."
            }
        }
    }

    /// This device's vault key, created the first time it's needed.
    static func deviceKey() throws -> SymmetricKey {
        if let stored = Keychain.read(keyAccount), stored.count == 32 {
            return SymmetricKey(data: stored)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let status = Keychain.write(data, for: keyAccount)
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        return key
    }

    /// Nonce, ciphertext and tag in one blob.
    static func seal(_ data: Data, with key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else { throw Failure.unreadable }
        return combined
    }

    /// Fails if the data was changed or the key is wrong.
    static func open(_ sealed: Data, with key: SymmetricKey) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key)
    }
}

/// The vault's own PIN, the fallback for Face ID. Only a salted, slow hash is kept.
/// Pure logic apart from the Keychain calls, unit tested.
nonisolated enum VaultPIN {
    private static let account = "pin"
    static let rounds: UInt32 = 100_000
    static let validLengths = 4...6

    /// 4 to 6 digits.
    static func isValid(_ pin: String) -> Bool {
        validLengths.contains(pin.count) && pin.allSatisfy(\.isASCII) && pin.allSatisfy(\.isNumber)
    }

    /// PBKDF2-SHA256 of the PIN with the salt.
    static func hash(_ pin: String, salt: Data, rounds: UInt32 = rounds) -> Data {
        var derived = Data(count: 32)
        let pinBytes = Array(pin.utf8).map { Int8(bitPattern: $0) }
        _ = derived.withUnsafeMutableBytes { output in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2), pinBytes, pinBytes.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                    output.bindMemory(to: UInt8.self).baseAddress, 32
                )
            }
        }
        return derived
    }

    /// Salt followed by hash, as stored.
    static func record(for pin: String, salt: Data = randomSalt()) -> Data {
        salt + hash(pin, salt: salt)
    }

    static func matches(_ pin: String, record: Data) -> Bool {
        guard record.count == 48 else { return false }
        let salt = record.prefix(16)
        let expected = record.suffix(32)
        let actual = hash(pin, salt: Data(salt))
        // Compare every byte so timing doesn't reveal how much matched.
        return zip(actual, expected).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    static func randomSalt() -> Data {
        Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
    }

    // MARK: Stored PIN

    static var isSet: Bool { Keychain.read(account) != nil }

    static func save(_ pin: String) -> Bool { Keychain.write(record(for: pin), for: account) == errSecSuccess }

    static func check(_ pin: String) -> Bool {
        guard let record = Keychain.read(account) else { return false }
        return matches(pin, record: record)
    }
}

/// Slows down guessing: after 5 wrong PINs, the next try waits 30 seconds. Pure logic, unit tested.
nonisolated struct PINAttempts: Equatable {
    static let allowedMisses = 5
    static let lockout: TimeInterval = 30

    private(set) var misses = 0
    private(set) var lockedUntil: Date?

    func isLocked(at now: Date) -> Bool { lockedUntil.map { now < $0 } ?? false }

    func secondsLeft(at now: Date) -> Int {
        guard let lockedUntil, now < lockedUntil else { return 0 }
        return Int(lockedUntil.timeIntervalSince(now).rounded(.up))
    }

    mutating func recordMiss(at now: Date) {
        misses += 1
        if misses >= Self.allowedMisses {
            lockedUntil = now.addingTimeInterval(Self.lockout)
            misses = 0
        }
    }

    mutating func recordSuccess() {
        misses = 0
        lockedUntil = nil
    }
}
