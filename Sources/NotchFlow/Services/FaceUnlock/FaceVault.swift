import CryptoKit
import Foundation
import OpenDirectory
import Security

/// Un visage enregistré (plusieurs prises de vue : lunettes, éclairage, expressions…).
struct FaceIdentity: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var enabled = true
    var samples: [[Float]]
    var created = Date()

    var centroid: [Float] { FaceMath.centroid(samples) }

    /// Similarité au centre du profil et au meilleur échantillon.
    func score(_ embedding: [Float]) -> (centroid: Float, best: Float) {
        let c = FaceMath.cosine(centroid, embedding)
        let best = samples.map { FaceMath.cosine($0, embedding) }.max() ?? 0
        return (c, best)
    }

    /// Seuil conseillé d'après la cohérence des prises de vue (validation « un contre tous »).
    var suggestedThreshold: Double {
        guard samples.count >= 4 else { return 0.9 }
        var sims: [Float] = []
        for i in samples.indices {
            var others = samples
            others.remove(at: i)
            sims.append(FaceMath.cosine(FaceMath.centroid(others), samples[i]))
        }
        sims.sort()
        let p10 = sims[max(0, Int(Double(sims.count) * 0.1) - 1)]
        return min(0.97, max(0.85, Double(p10) - 0.01))
    }
}

/// Trousseau macOS (session de l'utilisateur).
enum FaceKeychain {
    private static let service = "app.notchflow.faceunlock"

    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    @discardableResult
    static func set(_ data: Data, account: String) -> Bool {
        SecItemDelete(base(account) as CFDictionary)
        var query = base(account)
        query[kSecValueData as String] = data
        query[kSecAttrLabel as String] = "NotchFlow — déverrouillage facial"
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// `allowUI` : false = n'affiche jamais de fenêtre du trousseau (écran verrouillé).
    static func get(account: String, allowUI: Bool) -> Data? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if !allowUI {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(account: String) {
        SecItemDelete(base(account) as CFDictionary)
    }

    static func exists(account: String) -> Bool {
        var query = base(account)
        query[kSecReturnAttributes as String] = true
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }
}

/// Stockage chiffré : empreintes des visages (AES-GCM, clé dans le trousseau)
/// et mot de passe de session (dans le trousseau).
enum FaceVault {
    private static let keyAccount = "storeKey"
    private static let passwordAccount = "password"

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NotchFlow/FaceUnlock", isDirectory: true)
    }

    private static var identitiesURL: URL { folder.appendingPathComponent("identities.bin") }

    private static func key(create: Bool) -> SymmetricKey? {
        if let data = FaceKeychain.get(account: keyAccount, allowUI: true), data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard create else { return nil }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        return FaceKeychain.set(data, account: keyAccount) ? key : nil
    }

    // MARK: Visages

    static func loadIdentities() -> [FaceIdentity] {
        guard let sealed = try? Data(contentsOf: identitiesURL),
              let key = key(create: false),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let plain = try? AES.GCM.open(box, using: key) else { return [] }
        return (try? JSONDecoder().decode([FaceIdentity].self, from: plain)) ?? []
    }

    @discardableResult
    static func save(_ identities: [FaceIdentity]) -> Bool {
        if identities.isEmpty {
            try? FileManager.default.removeItem(at: identitiesURL)
            return true
        }
        guard let key = key(create: true),
              let plain = try? JSONEncoder().encode(identities),
              let sealed = try? AES.GCM.seal(plain, using: key).combined else { return false }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try sealed.write(to: identitiesURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: identitiesURL.path)
            return true
        } catch {
            return false
        }
    }

    // MARK: Mot de passe

    static var hasPassword: Bool { FaceKeychain.exists(account: passwordAccount) }

    static func storePassword(_ password: String) -> Bool {
        FaceKeychain.set(Data(password.utf8), account: passwordAccount)
    }

    static func readPassword() -> Data? {
        FaceKeychain.get(account: passwordAccount, allowUI: true)
    }

    static func deletePassword() {
        FaceKeychain.delete(account: passwordAccount)
    }

    /// Supprime tout : visages, clé et mot de passe.
    static func eraseAll() {
        try? FileManager.default.removeItem(at: identitiesURL)
        FaceKeychain.delete(account: keyAccount)
        FaceKeychain.delete(account: passwordAccount)
    }

    /// Vérifie le mot de passe du compte macOS courant (Open Directory, local).
    static func verifyAccountPassword(_ password: String) -> Bool {
        do {
            let node = try ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeAuthentication))
            let record = try node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
            try record.verifyPassword(password)
            return true
        } catch {
            return false
        }
    }
}
