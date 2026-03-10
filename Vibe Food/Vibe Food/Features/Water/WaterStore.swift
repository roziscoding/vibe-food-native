import Foundation
import Observation

@MainActor
@Observable
final class WaterStore {
    private let waterRepository: WaterRepository
    private let settingsRepository: SettingsRepository
    private let deviceId: String
    private var cachedEntriesByDayKey: [String: [WaterEntryRecord]] = [:]
    private var visibleDayKey: String?

    var entries: [WaterEntryRecord] = []
    var totalMl: Double = 0
    var goalMl: Double = 2000
    var quickWaterAmounts: [Double] = WaterQuickAmountsConfig.defaultValues
    var customAmountMlText: String = ""
    var pendingDelete: WaterEntryRecord?
    var errorMessage: String?

    init(
        waterRepository: WaterRepository,
        settingsRepository: SettingsRepository,
        deviceId: String
    ) {
        self.waterRepository = waterRepository
        self.settingsRepository = settingsRepository
        self.deviceId = deviceId
    }

    func load(for dayKey: String) {
        do {
            try refreshGoal()
            visibleDayKey = dayKey

            if let cached = cachedEntriesByDayKey[dayKey] {
                apply(entries: cached)
                errorMessage = nil
                return
            }

            let loaded = try waterRepository.fetchEntries(localDayKey: dayKey)
            cachedEntriesByDayKey[dayKey] = loaded
            apply(entries: loaded)
            errorMessage = nil
        } catch {
            setError("Failed to load water.", operation: "Load water entries", error: error)
        }
    }

    func reload(for dayKey: String) {
        cachedEntriesByDayKey.removeAll()
        load(for: dayKey)
    }

    func preloadAdjacentDays(around date: Date) {
        do {
            for day in adjacentDates(around: date) {
                let dayKey = LocalDayKey.key(for: day, timeZone: .current)
                guard cachedEntriesByDayKey[dayKey] == nil else { continue }
                cachedEntriesByDayKey[dayKey] = try waterRepository.fetchEntries(localDayKey: dayKey)
            }
        } catch {
            // Ignore preload failures; active day load handles errors explicitly.
        }
    }

    func refresh(for dayKey: String, around date: Date) async {
        reload(for: dayKey)
        preloadAdjacentDays(around: date)
    }

    func addQuick(amountMl: Double, selectedDate: Date) {
        _ = add(amountMl: amountMl, selectedDate: selectedDate)
    }

    func addCustom(selectedDate: Date) {
        let normalized = customAmountMlText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(normalized), parsed > 0 else {
            setError("Enter a valid amount in ml.", operation: "Validate custom water amount")
            return
        }

        if add(amountMl: parsed, selectedDate: selectedDate) {
            customAmountMlText = ""
        }
    }

    func confirmDelete(_ entry: WaterEntryRecord) {
        pendingDelete = entry
    }

    func deletePending() {
        guard let entry = pendingDelete else { return }
        pendingDelete = nil
        delete(entry)
    }

    func cancelDelete() {
        pendingDelete = nil
    }

    private func delete(_ entry: WaterEntryRecord) {
        do {
            try waterRepository.softDelete(entry)

            if var cached = cachedEntriesByDayKey[entry.localDayKey] {
                cached.removeAll { $0.id == entry.id }
                cachedEntriesByDayKey[entry.localDayKey] = cached

                if visibleDayKey == entry.localDayKey {
                    apply(entries: cached)
                }
            } else if visibleDayKey == entry.localDayKey {
                let loaded = try waterRepository.fetchEntries(localDayKey: entry.localDayKey)
                cachedEntriesByDayKey[entry.localDayKey] = loaded
                apply(entries: loaded)
            }

            AppDataChangeNotifier.post(.water)
        } catch {
            setError("Failed to delete water entry.", operation: "Delete water entry", error: error)
        }
    }

    private func add(amountMl: Double, selectedDate: Date) -> Bool {
        guard amountMl > 0 else { return false }

        let consumedAt = logDate(for: selectedDate)
        let localDayKey = LocalDayKey.key(for: consumedAt, timeZone: .current)
        let normalizedAmount = amountMl.rounded()

        do {
            let entry = WaterEntryRecord(
                amountMl: normalizedAmount,
                consumedAt: consumedAt,
                timeZoneIdentifier: TimeZone.current.identifier,
                localDayKey: localDayKey,
                lastModifiedByDeviceId: deviceId
            )
            try waterRepository.insert(entry)

            let cached: [WaterEntryRecord]
            if var existing = cachedEntriesByDayKey[localDayKey] {
                existing.insert(entry, at: 0)
                existing.sort { $0.consumedAt > $1.consumedAt }
                cached = existing
            } else {
                cached = try waterRepository.fetchEntries(localDayKey: localDayKey)
            }
            cachedEntriesByDayKey[localDayKey] = cached

            if visibleDayKey == localDayKey {
                apply(entries: cached)
            }

            AppDataChangeNotifier.post(.water)
            return true
        } catch {
            setError("Failed to log water.", operation: "Log water entry", error: error)
            return false
        }
    }

    private func apply(entries: [WaterEntryRecord]) {
        self.entries = entries
        totalMl = entries.reduce(0) { partial, entry in
            partial + entry.amountMl
        }
    }

    private func refreshGoal() throws {
        if let settings = try settingsRepository.fetchSettings() {
            goalMl = settings.waterGoal ?? 2000
            quickWaterAmounts = WaterQuickAmountsConfig.parse(csv: settings.waterQuickAmountsCsv)
        } else {
            goalMl = 2000
            quickWaterAmounts = WaterQuickAmountsConfig.defaultValues
        }
    }

    private func adjacentDates(around date: Date) -> [Date] {
        var dates: [Date] = []
        if let previous = Calendar.current.date(byAdding: .day, value: -1, to: date) {
            dates.append(previous)
        }
        if let next = Calendar.current.date(byAdding: .day, value: 1, to: date), next <= Date() {
            dates.append(next)
        }
        return dates
    }

    private func logDate(for selectedDate: Date) -> Date {
        let now = Date()
        let selectedKey = LocalDayKey.key(for: selectedDate, timeZone: .current)
        let todayKey = LocalDayKey.key(for: now, timeZone: .current)
        guard selectedKey != todayKey else { return now }

        let calendar = Calendar.current
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: now)
        var components = DateComponents()
        components.year = dayComponents.year
        components.month = dayComponents.month
        components.day = dayComponents.day
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second
        return calendar.date(from: components) ?? selectedDate
    }

    private func setError(_ message: String, operation: String, error: Error? = nil) {
        errorMessage = message
        ErrorReportService.capture(
            key: ErrorReportKey.waterAlert,
            feature: "Water",
            operation: operation,
            userMessage: message,
            error: error
        )
    }
}
