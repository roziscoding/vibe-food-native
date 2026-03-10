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
                            waterRepository: appContainer.waterRepository,
                            settingsRepository: appContainer.settingsRepository,
                            insightRepository: appContainer.insightRepository,
                            deviceId: appContainer.deviceId
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
    private static let bottomContentPadding: CGFloat = 120

    @Environment(DaySelectionStore.self) private var dayStore
    @Bindable var store: DashboardStore
    @State private var errorReportPayload: ExportPayload?

    var body: some View {
        NavigationStack {
            ZStack {
                AppGlassBackground()

                VStack(spacing: AppGlass.cardSpacing) {
                    AppScreenHeader(title: "Overview")
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    DaySelectorView()
                        .padding(.horizontal, 20)

                    ScrollView {
                        VStack(alignment: .leading, spacing: AppGlass.cardSpacing) {
                            summarySection

                            if Self.showsMealsSection {
                                mealsSection
                            }

                            insightsSection
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, Self.bottomContentPadding)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Color.clear)
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollDisabled(dayStore.isScrollLockedForDaySwipe)
                    .onScrollPhaseChange { _, newPhase in
                        dayStore.setVerticalScrollActive(newPhase.isScrolling)
                    }
                    .offset(x: dayStore.horizontalDragOffset)
                    .contentShape(Rectangle())
                    .simultaneousGesture(daySwipeGesture)
                    .scrollIndicators(.hidden)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                store.load(for: dayStore.localDayKey)
                store.preloadAdjacentDays(around: dayStore.selectedDate)
            }
            .onReceive(NotificationCenter.default.publisher(for: AppDataChangeNotifier.notificationName)) { notification in
                guard let kind = AppDataChangeNotifier.kind(from: notification) else { return }
                guard kind == .meals || kind == .settings || kind == .water else { return }
                store.reload(for: dayStore.localDayKey)
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
                Button("Report") {
                    Task {
                        errorReportPayload = try? await ErrorReportService.makePayload(
                            key: ErrorReportKey.dashboardAlert,
                            fallbackFeature: "Dashboard",
                            fallbackOperation: "Present error alert",
                            fallbackMessage: store.errorMessage ?? "Unknown error"
                        )
                    }
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text(store.errorMessage ?? "Unknown error")
            }
            .sheet(item: $errorReportPayload) { payload in
                ShareSheet(items: [payload.url])
            }
        }
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
                summaryCard(title: "Water", value: store.waterTotalMl, goal: store.waterGoalMl, unit: "ml", color: .cyan)
            }

            macroDistributionCard(totals: totals)
            remainingTodayCard(totals: totals)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: AppGlass.sectionSpacing) {
            AppSectionTitle(title: "Insights")

            if store.showsInsights {
                VStack(alignment: .leading, spacing: 14) {
                    if let insightPreview = store.insightPreview {
                        Text(insightPreview.summary)
                            .foregroundStyle(AppGlass.textSecondary)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .lineLimit(4)

                        Text("Generated with \(insightPreview.providerLabel)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppGlass.textSubtle)
                    } else {
                        Text("No insight generated for this day yet. Open full insights to generate one.")
                            .foregroundStyle(AppGlass.textSecondary)
                            .appBodyText()
                    }

                    NavigationLink {
                        InsightsView(presentation: .embedded)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .semibold))
                            Text("See Full Insights")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(AppGlass.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                    }
                    .buttonStyle(.plain)
                    .glassPanel(cornerRadius: AppGlass.pillCornerRadius, weight: .secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Insights are disabled")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppGlass.textPrimary)
                    Text("Enable Insights in Settings to see AI guidance directly on your overview.")
                        .foregroundStyle(AppGlass.textMuted)
                        .appBodyText()
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
            }
        }
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
        return VStack(alignment: .leading, spacing: 10) {
            AppSectionTitle(title: "Macros")

            HStack(alignment: .top, spacing: 14) {
                macroGoalChip(
                    title: "Protein",
                    value: totals.protein,
                    goal: store.goals.protein,
                    color: MacroColors.protein
                )
                macroGoalChip(
                    title: "Carbs",
                    value: totals.carbs,
                    goal: store.goals.carbs,
                    color: MacroColors.carbs
                )
                macroGoalChip(
                    title: "Fat",
                    value: totals.fat,
                    goal: store.goals.fat,
                    color: MacroColors.fat
                )
            }

            Text("Macro Split")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(AppGlass.textSubtle)
                .textCase(.uppercase)

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

            HStack(spacing: 12) {
                splitShareLabel(title: "Protein", share: proteinShare, color: MacroColors.protein)
                splitShareLabel(title: "Carbs", share: carbsShare, color: MacroColors.carbs)
                splitShareLabel(title: "Fat", share: fatShare, color: MacroColors.fat)
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

    private func splitShareLabel(title: String, share: Double, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(title) \(share, format: .percent.precision(.fractionLength(0)))")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppGlass.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func macroGoalChip(title: String, value: Double, goal: Double, color: Color) -> some View {
        let progress = goal > 0 ? value / goal : 0

        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .textCase(.uppercase)
            Text("\(value, format: .number)g / \(goal, format: .number)g")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppGlass.textPrimary)
            Text(goal > 0 ? "\(progress, format: .percent.precision(.fractionLength(0))) of goal" : "No goal set")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppGlass.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func remainingTodayCard(totals: MacroBreakdown) -> some View {
        let remainingCalories = max(0.0, store.goals.calories - totals.calories)
        let remainingWater = max(0.0, store.waterGoalMl - store.waterTotalMl)
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
                    title: "Water",
                    valueText: "\(remainingWater.formatted(.number)) ml",
                    color: .cyan
                )
            }

            HStack(spacing: 12) {
                remainingMetricChip(
                    title: "Protein",
                    valueText: "\(remainingProtein.formatted(.number)) g",
                    color: MacroColors.protein
                )
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

#Preview {
    DashboardView()
}
