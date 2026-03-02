import CoreGraphics
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class DaySelectionStore {
    var selectedDate: Date {
        didSet {
            if selectedDate > today {
                selectedDate = today
                return
            }
            localDayKey = LocalDayKey.key(for: selectedDate, timeZone: timeZone)
        }
    }
    private(set) var localDayKey: String
    private(set) var settledDayKey: String
    private(set) var horizontalDragOffset: CGFloat = 0
    private(set) var isHorizontalSwipeActive: Bool = false
    private(set) var isSwipeTransitioning: Bool = false
    private(set) var isVerticalScrollActive: Bool = false
    private let timeZone: TimeZone

    init(date: Date = Date(), timeZone: TimeZone = .current) {
        self.timeZone = timeZone
        self.selectedDate = date
        self.localDayKey = LocalDayKey.key(for: date, timeZone: timeZone)
        self.settledDayKey = LocalDayKey.key(for: date, timeZone: timeZone)
    }

    func goToToday() {
        selectedDate = Date()
        settleSelection()
    }

    func goToPreviousDay() {
        selectedDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        settleSelection()
    }

    func goToNextDay() {
        guard canGoToNextDay else { return }
        let nextDay = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        selectedDate = min(nextDay, today)
        settleSelection()
    }

    func setSelectedDate(_ date: Date) {
        selectedDate = min(date, today)
        settleSelection()
    }

    var displayDate: String {
        AppFormatters.shortDate.string(from: selectedDate)
    }

    var canGoToNextDay: Bool {
        !calendar.isDate(selectedDate, inSameDayAs: today)
    }

    var isScrollLockedForDaySwipe: Bool {
        isHorizontalSwipeActive || isSwipeTransitioning
    }

    func updateHorizontalSwipe(translationWidth: CGFloat) {
        guard !isSwipeTransitioning, !isVerticalScrollActive else { return }
        isHorizontalSwipeActive = true
        horizontalDragOffset = adjustedDragOffset(for: translationWidth)
    }

    func finishHorizontalSwipe(translationWidth: CGFloat, minimumDistance: CGFloat = 60) {
        guard !isSwipeTransitioning else { return }

        let finalOffset = adjustedDragOffset(for: translationWidth)
        guard abs(finalOffset) >= minimumDistance else {
            snapBack()
            return
        }

        let direction: SwipeDirection = finalOffset < 0 ? .next : .previous
        guard direction != .next || canGoToNextDay else {
            snapBack()
            return
        }

        isSwipeTransitioning = true

        let travelDistance = transitionTravelDistance(for: finalOffset)
        let outgoingOffset = direction == .next ? -travelDistance : travelDistance
        let incomingOffset = -outgoingOffset
        let animation = Animation.interactiveSpring(response: 0.26, dampingFraction: 0.88)

        withAnimation(animation) {
            horizontalDragOffset = outgoingOffset
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            apply(direction)
            horizontalDragOffset = incomingOffset
            withAnimation(animation) {
                horizontalDragOffset = 0
            }
            try? await Task.sleep(nanoseconds: 260_000_000)
            settleSelection()
            isHorizontalSwipeActive = false
            isSwipeTransitioning = false
        }
    }

    func cancelHorizontalSwipe() {
        guard !isSwipeTransitioning else { return }
        snapBack()
    }

    func setVerticalScrollActive(_ isActive: Bool) {
        guard !isHorizontalSwipeActive, !isSwipeTransitioning else { return }
        isVerticalScrollActive = isActive
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private var today: Date {
        Date()
    }

    private func apply(_ direction: SwipeDirection) {
        switch direction {
        case .previous:
            selectedDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        case .next:
            let nextDay = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
            selectedDate = min(nextDay, today)
        }
    }

    private func settleSelection() {
        settledDayKey = localDayKey
    }

    private func adjustedDragOffset(for translationWidth: CGFloat) -> CGFloat {
        if translationWidth < 0 && !canGoToNextDay {
            return translationWidth * 0.18
        }
        return translationWidth
    }

    private func snapBack() {
        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.9)) {
            horizontalDragOffset = 0
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            isHorizontalSwipeActive = false
        }
    }

    private func transitionTravelDistance(for translationWidth: CGFloat) -> CGFloat {
        max(220, min(360, abs(translationWidth) + 140))
    }
}

private extension DaySelectionStore {
    enum SwipeDirection {
        case previous
        case next
    }
}
