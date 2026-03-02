import Foundation

enum LocalDayKey {
    static func key(for date: Date, timeZone: TimeZone = .current) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: timeZone, from: date)
        guard
            let year = components.year,
            let month = components.month,
            let day = components.day
        else {
            return ""
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
