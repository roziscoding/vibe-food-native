import Foundation

protocol DeviceIdentityStore {
    var deviceId: String { get }
}

final class UserDefaultsDeviceIdentityStore: DeviceIdentityStore {
    private let storage: UserDefaults
    private let key = "vibe_food_device_id"

    init(storage: UserDefaults = .standard) {
        self.storage = storage
    }

    var deviceId: String {
        if let existing = storage.string(forKey: key), !existing.isEmpty {
            return existing
        }

        let newId = UUID().uuidString
        storage.set(newId, forKey: key)
        return newId
    }
}
