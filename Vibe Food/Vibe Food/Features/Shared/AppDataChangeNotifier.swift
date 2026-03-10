import Foundation

enum AppDataChangeKind: String {
    case meals
    case water
    case ingredients
    case settings
}

enum AppDataChangeNotifier {
    static let notificationName = Notification.Name("VibeFood.DataDidChange")
    private static let kindUserInfoKey = "kind"

    static func post(_ kind: AppDataChangeKind) {
        NotificationCenter.default.post(
            name: notificationName,
            object: nil,
            userInfo: [kindUserInfoKey: kind.rawValue]
        )
    }

    static func kind(from notification: Notification) -> AppDataChangeKind? {
        guard let rawValue = notification.userInfo?[kindUserInfoKey] as? String else {
            return nil
        }
        return AppDataChangeKind(rawValue: rawValue)
    }
}
