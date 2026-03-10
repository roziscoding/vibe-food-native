import SwiftUI

enum InsightsPresentation {
    case tab
    case embedded
}

struct InsightsView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(DaySelectionStore.self) private var dayStore
    @State private var store: InsightsStore?
    let presentation: InsightsPresentation

    init(presentation: InsightsPresentation = .tab) {
        self.presentation = presentation
    }

    var body: some View {
        Group {
            if let store {
                InsightsContentView(store: store, presentation: presentation)
            } else {
                ProgressView()
                    .task {
                        let newStore = InsightsStore(
                            mealRepository: appContainer.mealRepository,
                            settingsRepository: appContainer.settingsRepository,
                            aiIntegrationRepository: appContainer.aiIntegrationRepository,
                            insightRepository: appContainer.insightRepository,
                            deviceId: appContainer.deviceId
                        )
                        newStore.showOnboardingIfNeeded()
                        newStore.showCachedInsightIfAvailable(for: dayStore.localDayKey)
                        await newStore.loadOrGenerate(for: dayStore.selectedDate, targetDayKey: dayStore.settledDayKey)
                        store = newStore
                    }
            }
        }
    }
}

private struct InsightsContentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DaySelectionStore.self) private var dayStore
    @Bindable var store: InsightsStore
    let presentation: InsightsPresentation
    @State private var showDatePicker: Bool = false
    @State private var tempDate: Date = Date()
    @State private var errorReportPayload: ExportPayload?

    var body: some View {
        Group {
            if presentation == .tab {
                NavigationStack {
                    content
                }
            } else {
                content
            }
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                VStack {
                    DatePicker(
                        "Date",
                        selection: $tempDate,
                        in: ...Date(),
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                }
                .padding(.bottom, 8)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .navigationTitle("Select Date")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dayStore.setSelectedDate(tempDate)
                            showDatePicker = false
                        }
                    }
                }
            }
        }
        .refreshable {
            guard !store.showsOnboarding else { return }
            await store.loadOrGenerate(
                for: dayStore.selectedDate,
                targetDayKey: dayStore.localDayKey,
                forceRefresh: true
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .onChange(of: dayStore.localDayKey) { _, newValue in
            store.showCachedInsightIfAvailable(for: newValue)
        }
        .task(id: dayStore.settledDayKey) {
            guard !store.showsOnboarding else { return }
            await store.loadOrGenerate(for: dayStore.selectedDate, targetDayKey: dayStore.settledDayKey)
        }
        .sheet(item: $errorReportPayload) { payload in
            ShareSheet(items: [payload.url])
        }
    }

    private var content: some View {
        ZStack {
            AppGlassBackground()

            VStack(alignment: .leading, spacing: AppGlass.cardSpacing) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: AppGlass.cardSpacing) {
                        if store.showsOnboarding {
                            onboardingCard
                        } else if store.isLoading && !store.isRefreshing {
                            statusCard(
                                title: "Analyzing yesterday",
                                message: "Building a fresh set of insights for today from your latest meals, goals, and body data.",
                                showsProgress: true
                            )
                        } else if let errorMessage = store.errorMessage {
                            errorStatusCard(message: errorMessage)
                        } else if let insightText = store.insightText, !insightText.isEmpty {
                            insightCard(insightText: insightText)
                        } else {
                            emptyState
                        }
                    }
                    .padding(.bottom, 120)
                }
                .scrollDisabled(dayStore.isScrollLockedForDaySwipe)
                .onScrollPhaseChange { _, newPhase in
                    dayStore.setVerticalScrollActive(newPhase.isScrolling)
                }
                .offset(x: dayStore.horizontalDragOffset)
                .contentShape(Rectangle())
                .simultaneousGesture(daySwipeGesture)
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
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

    private var header: some View {
        VStack(spacing: 16) {
            if presentation == .embedded {
                HStack {
                    circularGlassButton(systemImage: "chevron.left") {
                        dismiss()
                    }
                    Spacer()
                }
            }

            Text("Insights")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(AppGlass.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 12) {
                circularGlassButton(systemImage: "chevron.left") {
                    dayStore.goToPreviousDay()
                }

                Button {
                    if Calendar.current.isDateInToday(dayStore.selectedDate) {
                        tempDate = dayStore.selectedDate
                        showDatePicker = true
                    } else {
                        dayStore.goToToday()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .font(.subheadline.weight(.semibold))
                            .appIconGlow(active: true)
                        Text(dayStore.displayDate)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppGlass.textSubtle)
                    }
                    .foregroundStyle(AppGlass.textPrimary)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                }
                .buttonStyle(.plain)
                .glassPanel(cornerRadius: AppGlass.pillCornerRadius, weight: .primary)

                circularGlassButton(systemImage: "chevron.right") {
                    dayStore.goToNextDay()
                }
                .disabled(!dayStore.canGoToNextDay)
                .opacity(dayStore.canGoToNextDay ? 1 : 0.45)
            }

            if let generatedLine {
                Text(generatedLine)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppGlass.textSubtle)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func circularGlassButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .appIconGlow(active: true)
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.plain)
        .glassPanel(cornerRadius: AppGlass.pillCornerRadius, weight: .secondary)
    }

    private var generatedLine: String? {
        guard let sourceDayKey = store.sourceDayKey, let providerLabel = store.providerLabel else {
            return nil
        }

        return "Generated on \(sourceDayKey) with \(providerLabel)"
    }

    private func statusCard(title: String, message: String, showsProgress: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if showsProgress {
                    ProgressView()
                        .tint(AppGlass.textPrimary)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }

                Text(title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppGlass.textPrimary)
            }

            Text(message)
                .foregroundStyle(AppGlass.textMuted)
                .appBodyText()
        }
        .padding(AppGlass.heroPadding)
        .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
    }

    private func errorStatusCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)

                Text("Insights unavailable")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppGlass.textPrimary)
            }

            Text(message)
                .foregroundStyle(AppGlass.textMuted)
                .appBodyText()

            Button("Report") {
                Task {
                    errorReportPayload = try? await ErrorReportService.makePayload(
                        key: ErrorReportKey.insightsStatus,
                        fallbackFeature: "Insights",
                        fallbackOperation: "Load insights",
                        fallbackMessage: message
                    )
                }
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(AppGlass.accent)
        }
        .padding(AppGlass.heroPadding)
        .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No insights yet")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(AppGlass.textPrimary)

            Text("Open this tab to generate day-specific guidance from yesterday’s meals, today’s goals, and your saved profile.")
                .foregroundStyle(AppGlass.textMuted)
                .appBodyText()
        }
        .padding(AppGlass.heroPadding)
        .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
    }

    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Insights")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(AppGlass.textPrimary)

            Text("When you’re ready, generate your first insight from yesterday’s meals, today’s goals, and your saved profile.")
                .foregroundStyle(AppGlass.textMuted)
                .appBodyText()

            Button("Generate First Insight") {
                Task {
                    await store.loadOrGenerate(
                        for: dayStore.selectedDate,
                        targetDayKey: dayStore.settledDayKey,
                        allowInitialGeneration: true
                    )
                }
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(AppGlass.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .glassPanel(cornerRadius: AppGlass.pillCornerRadius, weight: .primary)
        }
        .padding(AppGlass.heroPadding)
        .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
    }

    @ViewBuilder
    private func insightCard(insightText: String) -> some View {
        if let data = insightText.data(using: .utf8),
           let structured = try? JSONDecoder().decode(InsightContent.self, from: data) {
            VStack(alignment: .leading, spacing: AppGlass.cardSpacing) {
                summaryCard(summary: structured.summary)

                VStack(alignment: .leading, spacing: AppGlass.sectionSpacing) {
                    AppSectionTitle(title: "Focus Points")

                    ForEach(Array(structured.bullets.enumerated()), id: \.offset) { index, bullet in
                        insightBulletRow(index: index + 1, bullet: bullet)
                    }
                }
            }
        } else {
            Text(insightText)
                .foregroundStyle(AppGlass.textSecondary)
                .appBodyText()
                .padding(AppGlass.heroPadding)
                .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
        }
    }

    private func summaryCard(summary: String) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.28))
                    .frame(width: 170, height: 170)
                    .blur(radius: 56)
                    .offset(x: -80, y: -10)

                Circle()
                    .fill(Color.purple.opacity(0.24))
                    .frame(width: 180, height: 180)
                    .blur(radius: 58)
                    .offset(x: 90, y: 10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

            VStack(alignment: .leading, spacing: 14) {
                Text("Today’s Read")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(AppGlass.sectionTracking)
                    .foregroundStyle(AppGlass.textSubtle)

                Text(summary)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppGlass.textPrimary)
                    .appBodyText()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(AppGlass.heroPadding)

            Image(systemName: "sparkles")
                .font(.headline.weight(.semibold))
                .appIconGlow(active: true)
                .frame(width: 36, height: 36)
                .glassPanel(cornerRadius: 18)
                .padding(16)
        }
        .appHeroCard()
    }

    private func insightBulletRow(index: Int, bullet: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(index)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AppGlass.textPrimary)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(AppGlass.secondaryFill)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            AppGlass.primaryBorderStart,
                                            AppGlass.primaryBorderEnd
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .white.opacity(0.04), radius: 6, y: 0)
                )

            Text(bullet)
                .foregroundStyle(AppGlass.textSecondary)
                .appBodyText()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
        .padding(16)
        .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .secondary)
    }

    private func bulletAccentColor(index: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.19, green: 0.86, blue: 0.95),
            Color(red: 0.48, green: 0.63, blue: 1.00),
            Color(red: 0.63, green: 0.46, blue: 0.97),
            Color(red: 0.18, green: 0.82, blue: 0.73),
            Color(red: 0.42, green: 0.88, blue: 1.00)
        ]
        return colors[(index - 1) % colors.count]
    }
}

#Preview {
    InsightsView()
}
