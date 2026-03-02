import Foundation

extension IngredientRecord {
    func touch(updatedBy deviceId: String) {
        updatedAt = Date()
        lastModifiedByDeviceId = deviceId
        syncVersion += 1
    }
}

extension MealRecord {
    func touch(updatedBy deviceId: String) {
        updatedAt = Date()
        lastModifiedByDeviceId = deviceId
        syncVersion += 1
    }
}

extension SettingsRecord {
    func touch(updatedBy deviceId: String) {
        updatedAt = Date()
        lastModifiedByDeviceId = deviceId
        syncVersion += 1
    }
}

extension AIIntegrationRecord {
    func touch(updatedBy deviceId: String) {
        updatedAt = Date()
        lastModifiedByDeviceId = deviceId
        syncVersion += 1
    }
}

extension InsightRecord {
    func touch(updatedBy deviceId: String) {
        updatedAt = Date()
        lastModifiedByDeviceId = deviceId
        syncVersion += 1
    }
}
