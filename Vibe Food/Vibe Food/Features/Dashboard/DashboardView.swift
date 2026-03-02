import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(DaySelectionStore.self) private var dayStore
    @State private var store: DashboardStore?

    var body: some View {
        Group {
            if let store {
                DashboardContentView(store: store)
            } else {
                ProgressView()
                    .task {
                        let newStore = DashboardStore(
                            mealRepository: appContainer.mealRepository,
                            settingsRepository: appContainer.settingsRepository
                        )
                        newStore.load(for: dayStore.localDayKey)
                        newStore.preloadAdjacentDays(around: dayStore.selectedDate)
                        store = newStore
                    }
            }
        }
    }
}

private struct DashboardContentView: View {
    private static let showsMealsSection = false

    @Environment(DaySelectionStore.self) private var dayStore
    @Bindable var store: DashboardStore
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var scrollContentHeight: CGFloat = 0

    var body: some View {
        NavigationStack {
            ZStack {
                AppGlassBackground()

                VStack(spacing: AppGlass.cardSpacing) {
                    AppScreenHeader(title: "Dashboard")
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    DaySelectorView()
                        .padding(.horizontal, 20)

                    GeometryReader { geometry in
                        ScrollView {
                            VStack(alignment: .leading, spacing: AppGlass.cardSpacing) {
                                summarySection

                                if Self.showsMealsSection {
                                    mealsSection
                                }

                                Spacer(minLength: 0)
                            }
                            .background {
                                GeometryReader { contentGeometry in
                                    Color.clear
                                        .preference(
                                            key: DashboardScrollContentHeightKey.self,
                                            value: contentGeometry.size.height
                                        )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 120)
                        }
                        .background(Color.clear)
                        .onAppear {
                            scrollViewportHeight = geometry.size.height
                        }
                        .onChange(of: geometry.size.height) { _, newValue in
                            scrollViewportHeight = newValue
                        }
                        .onPreferenceChange(DashboardScrollContentHeightKey.self) { newValue in
                            scrollContentHeight = newValue
                        }
                        .scrollDisabled(!isDashboardScrollable || dayStore.isScrollLockedForDaySwipe)
                        .onScrollPhaseChange { _, newPhase in
                            dayStore.setVerticalScrollActive(isDashboardScrollable && newPhase.isScrolling)
                        }
                        .offset(x: dayStore.horizontalDragOffset)
                        .contentShape(Rectangle())
                        .simultaneousGesture(daySwipeGesture)
                        .scrollIndicators(.hidden)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                store.load(for: dayStore.localDayKey)
                store.preloadAdjacentDays(around: dayStore.selectedDate)
            }
            .onChange(of: dayStore.localDayKey) { _, newValue in
                store.load(for: newValue)
                store.preloadAdjacentDays(around: dayStore.selectedDate)
            }
            .alert("Error", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { _ in store.errorMessage = nil }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(store.errorMessage ?? "Unknown error")
            }
        }
    }

    private var isDashboardScrollable: Bool {
        scrollContentHeight > scrollViewportHeight + 1
    }

    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard shouldHandleDaySwipe(value) else { return }
                dayStore.updateHorizontalSwipe(translationWidth: value.translation.width)
            }
            .onEnded { value in
                guard shouldHandleDaySwipe(value) else {
                    dayStore.cancelHorizontalSwipe()
                    return
                }
                dayStore.finishHorizontalSwipe(translationWidth: value.translation.width)
            }
    }

    private func shouldHandleDaySwipe(_ value: DragGesture.Value) -> Bool {
        let horizontal = abs(value.translation.width)
        let vertical = abs(value.translation.height)
        return !dayStore.isVerticalScrollActive && horizontal > 18 && horizontal > vertical * 1.35
    }

    private var summarySection: some View {
        let totals = store.summary?.totals ?? MacroBreakdown(calories: 0, protein: 0, carbs: 0, fat: 0)
        return VStack(alignment: .leading, spacing: AppGlass.sectionSpacing) {
            AppSectionTitle(title: "Today")

            HStack(spacing: 12) {
                summaryCard(title: "Calories", value: totals.calories, goal: store.goals.calories, unit: "kcal", color: MacroColors.calories)
                summaryCard(title: "Protein", value: totals.protein, goal: store.goals.protein, unit: "g", color: MacroColors.protein)
            }
            HStack(spacing: 12) {
                summaryCard(title: "Carbs", value: totals.carbs, goal: store.goals.carbs, unit: "g", color: MacroColors.carbs)
                summaryCard(title: "Fat", value: totals.fat, goal: store.goals.fat, unit: "g", color: MacroColors.fat)
            }

            macroDistributionCard(totals: totals)
            remainingTodayCard(totals: totals)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: AppGlass.sectionSpacing) {
            AppSectionTitle(title: "Meals")

            if store.meals.isEmpty {
                ContentUnavailableView("No meals", systemImage: "fork.knife", description: Text("Add a meal for this day."))
                    .foregroundStyle(AppGlass.textSecondary, AppGlass.textMuted, AppGlass.textSubtle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
            } else {
                ForEach(store.meals) { meal in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(meal.name)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppGlass.textPrimary)
                            Text(AppFormatters.shortTime.string(from: meal.consumedAt))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AppGlass.textSubtle)
                        }
                        Spacer()
                        Text("\(meal.calories, format: .number) kcal")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(MacroColors.calories)
                    }
                    .padding(16)
                    .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .secondary)
                }
            }
        }
    }

    private func summaryCard(title: String, value: Double, goal: Double, unit: String, color: Color) -> some View {
        let progress = goal > 0 ? min(1, value / goal) : 0
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppGlass.textSubtle)
                .textCase(.uppercase)
            Text("\(value, format: .number) \(unit)")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(AppGlass.textPrimary)
            HStack {
                Text("Goal \(goal, format: .number) \(unit)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppGlass.textMuted)
                Text("\(progress, format: .percent.precision(.fractionLength(0)))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Spacer()
            }
            ProgressView(value: progress)
                .tint(color)
                .scaleEffect(x: 1, y: 0.72, anchor: .center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .secondary)
    }

    private func macroDistributionCard(totals: MacroBreakdown) -> some View {
        let proteinCalories = max(0, totals.protein * 4)
        let carbsCalories = max(0, totals.carbs * 4)
        let fatCalories = max(0, totals.fat * 9)
        let totalMacroCalories = proteinCalories + carbsCalories + fatCalories

        let proteinShare = totalMacroCalories > 0 ? proteinCalories / totalMacroCalories : 0
        let carbsShare = totalMacroCalories > 0 ? carbsCalories / totalMacroCalories : 0
        let fatShare = totalMacroCalories > 0 ? fatCalories / totalMacroCalories : 0
        let segments = [
            MacroSplitSegment(title: "Protein", value: totals.protein, share: proteinShare, color: MacroColors.protein),
            MacroSplitSegment(title: "Carbs", value: totals.carbs, share: carbsShare, color: MacroColors.carbs),
            MacroSplitSegment(title: "Fat", value: totals.fat, share: fatShare, color: MacroColors.fat)
        ]
        let segmentStarts = [
            0.0,
            proteinShare,
            proteinShare + carbsShare
        ]

        return VStack(alignment: .leading, spacing: 10) {
            AppSectionTitle(title: "Macro Split")

            GeometryReader { geometry in
                let width = geometry.size.width

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(MacroColors.protein)
                        .frame(width: width * proteinShare)

                    Rectangle()
                        .fill(MacroColors.carbs)
                        .frame(width: width * carbsShare)

                    Rectangle()
                        .fill(MacroColors.fat)
                        .frame(width: width * fatShare)
                }
                .frame(height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 999))
                .overlay {
                    if totalMacroCalories == 0 {
                        RoundedRectangle(cornerRadius: 999)
                            .fill(Color(.tertiarySystemFill))
                    }
                }
            }
            .frame(height: 14)

            if totalMacroCalories > 0 {
                GeometryReader { geometry in
                    let width = geometry.size.width

                    ZStack(alignment: .topLeading) {
                        ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                            macroSplitLabel(
                                title: segment.title,
                                value: segment.value,
                                share: segment.share,
                                color: segment.color
                            )
                            .frame(width: max(88, width * segment.share), alignment: .leading)
                            .offset(x: width * segmentStarts[index])
                        }
                    }
                }
                .frame(height: 44)
            } else {
                HStack(spacing: 12) {
                    ForEach(segments) { segment in
                        macroSplitLabel(title: segment.title, value: segment.value, share: segment.share, color: segment.color)
                    }
                }
            }

            if totalMacroCalories == 0 {
                Text("Log meals to see your macro distribution.")
                    .foregroundStyle(AppGlass.textSubtle)
                    .appBodyText()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
    }

    private func remainingTodayCard(totals: MacroBreakdown) -> some View {
        let remainingCalories = max(0.0, store.goals.calories - totals.calories)
        let remainingProtein = max(0.0, store.goals.protein - totals.protein)
        let remainingCarbs = max(0.0, store.goals.carbs - totals.carbs)
        let remainingFat = max(0.0, store.goals.fat - totals.fat)

        return VStack(alignment: .leading, spacing: 10) {
            AppSectionTitle(title: "Remaining Today")

            HStack(spacing: 12) {
                remainingMetricChip(
                    title: "Calories",
                    valueText: "\(remainingCalories.formatted(.number)) kcal",
                    color: MacroColors.calories
                )
                remainingMetricChip(
                    title: "Protein",
                    valueText: "\(remainingProtein.formatted(.number)) g",
                    color: MacroColors.protein
                )
            }

            HStack(spacing: 12) {
                remainingMetricChip(
                    title: "Carbs",
                    valueText: "\(remainingCarbs.formatted(.number)) g",
                    color: MacroColors.carbs
                )
                remainingMetricChip(
                    title: "Fat",
                    valueText: "\(remainingFat.formatted(.number)) g",
                    color: MacroColors.fat
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
    }

    private func macroSplitLabel(title: String, value: Double, share: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text("\(value, format: .number)g")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppGlass.textSecondary)
            Text("\(share, format: .percent.precision(.fractionLength(0)))")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AppGlass.textSubtle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func remainingMetricChip(title: String, valueText: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(valueText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AppGlass.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 16, weight: .secondary)
    }
}

private struct DashboardScrollContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct MacroSplitSegment: Identifiable {
    let id = UUID()
    let title: String
    let value: Double
    let share: Double
    let color: Color
}

#Preview {
    DashboardView()
}
