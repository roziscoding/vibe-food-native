import SwiftUI

struct InputView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(DaySelectionStore.self) private var dayStore
    @State private var route: InputRoute?
    @State private var errorMessage: String?
    @State private var quickWaterAmounts: [Double] = WaterQuickAmountsConfig.defaultValues
    @State private var waterAddedMessage: String?
    @State private var waterAddedMessageToken = UUID()
    @State private var errorReportPayload: ExportPayload?

    var body: some View {
        NavigationStack {
            ZStack {
                AppGlassBackground()

                VStack(spacing: AppGlass.cardSpacing) {
                    AppScreenHeader(title: "Input")
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    DaySelectorView()
                        .padding(.horizontal, 20)

                    ScrollView {
                        VStack(alignment: .leading, spacing: AppGlass.cardSpacing) {
                            waterCard
                            foodCard
                            ingredientsCard
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 120)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.hidden)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $route) { destination in
                destinationView(for: destination)
            }
            .onAppear {
                loadWaterQuickAmounts()
            }
            .onReceive(NotificationCenter.default.publisher(for: AppDataChangeNotifier.notificationName)) { notification in
                guard let kind = AppDataChangeNotifier.kind(from: notification) else { return }
                guard kind == .settings else { return }
                loadWaterQuickAmounts()
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { _ in errorMessage = nil }
            )) {
                Button("Report") {
                    Task {
                        errorReportPayload = try? await ErrorReportService.makePayload(
                            key: ErrorReportKey.inputAlert,
                            fallbackFeature: "Input",
                            fallbackOperation: "Present error alert",
                            fallbackMessage: errorMessage ?? "Unknown error"
                        )
                    }
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .sheet(item: $errorReportPayload) { payload in
                ShareSheet(items: [payload.url])
            }
        }
    }

    private var waterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionTitle(title: "Water")

            Text("Quick add water for the selected day.")
                .foregroundStyle(AppGlass.textSubtle)
                .font(.system(size: 13, weight: .medium, design: .rounded))

            HStack(spacing: 10) {
                ForEach(Array(quickWaterAmounts.enumerated()), id: \.offset) { _, amountMl in
                    waterQuickAddButton(amountMl: amountMl)
                }
            }

            if let waterAddedMessage {
                Text(waterAddedMessage)
                    .foregroundStyle(Color.green.opacity(0.92))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
    }

    private var foodCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionTitle(title: "Food")

            Text("Log meals quickly, with AI or manually.")
                .foregroundStyle(AppGlass.textSubtle)
                .font(.system(size: 13, weight: .medium, design: .rounded))

            HStack(spacing: 10) {
                shortcutButton(
                    title: "Log with AI",
                    systemImage: "sparkles",
                    color: MacroColors.protein
                ) {
                    route = .foodAI
                }

                shortcutButton(
                    title: "Log manually",
                    systemImage: "square.and.pencil",
                    color: MacroColors.calories
                ) {
                    route = .foodManual
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
    }

    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionTitle(title: "Ingredients")

            Text("Scan a label or add ingredient details manually.")
                .foregroundStyle(AppGlass.textSubtle)
                .font(.system(size: 13, weight: .medium, design: .rounded))

            HStack(spacing: 10) {
                shortcutButton(
                    title: "Scan label",
                    systemImage: "camera.viewfinder",
                    color: MacroColors.carbs
                ) {
                    route = .ingredientScan
                }

                shortcutButton(
                    title: "Add manually",
                    systemImage: "plus.square.on.square",
                    color: MacroColors.fat
                ) {
                    route = .ingredientManual
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
    }

    private func waterQuickAddButton(amountMl: Double) -> some View {
        Button {
            logWater(amountMl: amountMl)
        } label: {
            Text("+\(Int(amountMl)) ml")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AppGlass.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
        }
        .glassPanel(cornerRadius: 18, weight: .secondary)
    }

    private func shortcutButton(
        title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)

                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppGlass.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
        }
        .glassPanel(cornerRadius: 18, weight: .secondary)
    }

    @ViewBuilder
    private func destinationView(for destination: InputRoute) -> some View {
        switch destination {
        case .foodAI:
            MealsView(presentation: .embedded, initialAction: .logWithAI)
        case .foodManual:
            MealsView(presentation: .embedded, initialAction: .addManual)
        case .ingredientScan:
            IngredientsView(presentation: .embedded, quickAction: .scanLabel)
        case .ingredientManual:
            IngredientsView(presentation: .embedded, quickAction: .addManual)
        }
    }

    private func logWater(amountMl: Double) {
        let consumedAt = logDate(for: dayStore.selectedDate)
        let localDayKey = LocalDayKey.key(for: consumedAt, timeZone: .current)
        let normalizedAmount = amountMl.rounded()

        do {
            let entry = WaterEntryRecord(
                amountMl: normalizedAmount,
                consumedAt: consumedAt,
                timeZoneIdentifier: TimeZone.current.identifier,
                localDayKey: localDayKey,
                lastModifiedByDeviceId: appContainer.deviceId
            )
            try appContainer.waterRepository.insert(entry)
            AppDataChangeNotifier.post(.water)
            errorMessage = nil
            showWaterAddedFeedback(amountMl: normalizedAmount)
        } catch {
            errorMessage = "Failed to log water."
            ErrorReportService.capture(
                key: ErrorReportKey.inputAlert,
                feature: "Input",
                operation: "Quick add water",
                userMessage: errorMessage ?? "Failed to log water.",
                error: error
            )
            waterAddedMessage = nil
        }
    }

    private func showWaterAddedFeedback(amountMl: Double) {
        let token = UUID()
        waterAddedMessageToken = token

        withAnimation(.easeInOut(duration: 0.15)) {
            waterAddedMessage = "Added \(amountMl.formatted(.number)) ml"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            guard waterAddedMessageToken == token else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                waterAddedMessage = nil
            }
        }
    }

    private func loadWaterQuickAmounts() {
        do {
            let settings = try appContainer.settingsRepository.fetchSettings()
            quickWaterAmounts = WaterQuickAmountsConfig.parse(csv: settings?.waterQuickAmountsCsv)
        } catch {
            quickWaterAmounts = WaterQuickAmountsConfig.defaultValues
        }
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
}

private enum InputRoute: String, Hashable, Identifiable {
    case foodAI
    case foodManual
    case ingredientScan
    case ingredientManual

    var id: String { rawValue }
}

#Preview {
    InputView()
}
