import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum MealsPresentation {
    case tab
    case embedded
}

enum MealsQuickAction {
    case addManual
    case logWithAI
}

struct MealsView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(DaySelectionStore.self) private var dayStore
    @State private var store: MealsStore?
    let presentation: MealsPresentation
    let initialAction: MealsQuickAction?

    init(presentation: MealsPresentation = .tab, initialAction: MealsQuickAction? = nil) {
        self.presentation = presentation
        self.initialAction = initialAction
    }

    var body: some View {
        Group {
            if let store {
                MealsContentView(store: store, presentation: presentation, initialAction: initialAction)
            } else {
                ProgressView()
                    .task {
                        let newStore = MealsStore(
                            mealRepository: appContainer.mealRepository,
                            ingredientRepository: appContainer.ingredientRepository,
                            todaySoFarRepository: appContainer.todaySoFarRepository,
                            settingsRepository: appContainer.settingsRepository,
                            aiIntegrationRepository: appContainer.aiIntegrationRepository,
                            context: appContainer.modelContainer.mainContext,
                            deviceId: appContainer.deviceId
                        )
                        newStore.loadPreferences()
                        newStore.load(for: dayStore.localDayKey)
                        newStore.preloadAdjacentDays(around: dayStore.selectedDate)
                        newStore.loadTodaySoFar(for: dayStore.localDayKey)
                        store = newStore
                    }
            }
        }
    }
}

private struct MealsContentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DaySelectionStore.self) private var dayStore
    @Bindable var store: MealsStore
    let presentation: MealsPresentation
    let initialAction: MealsQuickAction?
    @State private var hasAppliedInitialAction = false
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
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            store.loadPreferences()
            store.load(for: dayStore.localDayKey)
            store.preloadAdjacentDays(around: dayStore.selectedDate)
            store.loadTodaySoFar(for: dayStore.localDayKey)
            applyInitialActionIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppDataChangeNotifier.notificationName)) { notification in
            guard let kind = AppDataChangeNotifier.kind(from: notification) else { return }
            guard kind == .meals || kind == .ingredients || kind == .settings else { return }
            store.loadPreferences()
            store.reload(for: dayStore.localDayKey)
            store.preloadAdjacentDays(around: dayStore.selectedDate)
            store.loadTodaySoFar(for: dayStore.localDayKey)
        }
        .onChange(of: dayStore.localDayKey) { _, newValue in
            store.loadPreferences()
            store.load(for: newValue)
            store.preloadAdjacentDays(around: dayStore.selectedDate)
            store.loadTodaySoFar(for: newValue)
        }
        .alert("Error", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { _ in store.errorMessage = nil }
        )) {
            Button("Report") {
                Task {
                    errorReportPayload = try? await ErrorReportService.makePayload(
                        key: ErrorReportKey.mealsAlert,
                        fallbackFeature: "Meals",
                        fallbackOperation: "Present error alert",
                        fallbackMessage: store.errorMessage ?? "Unknown error"
                    )
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
        .alert("Delete Meal", isPresented: Binding(
            get: { store.pendingDelete != nil },
            set: { _ in store.cancelDelete() }
        )) {
            Button("Delete", role: .destructive) {
                store.deletePending()
            }
            Button("Cancel", role: .cancel) {
                store.cancelDelete()
            }
        } message: {
            Text("This will remove the meal from your history.")
        }
        .sheet(isPresented: $store.isPresentingEditor) {
            MealEditorView(store: store)
        }
        .sheet(isPresented: $store.isPresentingAILogInput) {
            AILogInputView(store: store, consumedAt: dayStore.selectedDate, dayKey: dayStore.localDayKey)
        }
        .fullScreenCover(isPresented: $store.isPresentingAILogStatus) {
            AILogStatusView(store: store)
        }
        .sheet(isPresented: $store.isPresentingImportSheet) {
            NavigationStack {
                Form {
                    Section("Paste JSON") {
                        TextEditor(text: $store.importJSONText)
                            .frame(minHeight: 200)
                            .font(.footnote)
                    }
                }
                .navigationTitle("Import Meal")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            store.isPresentingImportSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Review") {
                            store.importFromJSONText()
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $store.isPresentingFileImporter,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    let data = try Data(contentsOf: url)
                    store.importFromData(data)
                } catch {
                    store.errorMessage = "Failed to read JSON file."
                    ErrorReportService.capture(
                        key: ErrorReportKey.mealsAlert,
                        feature: "Meals",
                        operation: "Read meal JSON file",
                        userMessage: store.errorMessage ?? "Failed to read JSON file.",
                        error: error
                    )
                }
            case .failure:
                store.errorMessage = "Failed to import JSON file."
                ErrorReportService.capture(
                    key: ErrorReportKey.mealsAlert,
                    feature: "Meals",
                    operation: "Open meal file importer",
                    userMessage: store.errorMessage ?? "Failed to import JSON file."
                )
            }
        }
        .sheet(item: $errorReportPayload) { payload in
            ShareSheet(items: [payload.url])
        }
    }

    private var content: some View {
        ZStack {
            AppGlassBackground()

            VStack(spacing: AppGlass.cardSpacing) {
                if presentation == .embedded {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.headline.weight(.semibold))
                                .appIconGlow(active: true)
                                .frame(width: 48, height: 48)
                                .glassPanel(cornerRadius: AppGlass.pillCornerRadius, weight: .secondary)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }

                AppScreenHeader(
                    title: "Meals",
                    trailing: AnyView(
                        Menu {
                            Button("Add Meal") {
                                store.beginCreate(consumedAt: dayStore.selectedDate, dayKey: dayStore.localDayKey)
                            }
                            Button("Log with AI") {
                                store.beginAILog()
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.headline.weight(.semibold))
                                .appIconGlow(active: true)
                                .frame(width: 48, height: 48)
                                .glassPanel(cornerRadius: AppGlass.pillCornerRadius, weight: .secondary)
                        }
                    )
                )
                .padding(.horizontal, 20)
                .padding(.top, presentation == .embedded ? 8 : 20)

                DaySelectorView()
                    .padding(.horizontal, 20)

                List {
                    if store.isTodaySoFarEnabled {
                        todaySoFarCard
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    if store.meals.isEmpty {
                        ContentUnavailableView("No meals", systemImage: "fork.knife", description: Text("Add a meal for this day."))
                            .foregroundStyle(AppGlass.textSecondary, AppGlass.textMuted, AppGlass.textSubtle)
                            .frame(maxWidth: .infinity, minHeight: 280)
                            .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
                            .listRowInsets(EdgeInsets(top: 24, leading: 20, bottom: 96, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(store.meals) { meal in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(meal.name)
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppGlass.textPrimary)
                                macroLineView(for: meal)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                store.beginEdit(meal)
                            }
                            .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .secondary)
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    store.confirmDelete(meal)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await store.refresh(for: dayStore.localDayKey, around: dayStore.selectedDate)
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
    }

    private func applyInitialActionIfNeeded() {
        guard !hasAppliedInitialAction, let initialAction else { return }
        hasAppliedInitialAction = true
        switch initialAction {
        case .addManual:
            store.beginCreate(consumedAt: dayStore.selectedDate, dayKey: dayStore.localDayKey)
        case .logWithAI:
            store.beginAILog()
        }
    }

    private var todaySoFarCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(todaySoFarTitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(AppGlass.sectionTracking)
                    .foregroundStyle(AppGlass.textSubtle)

                Spacer()

                if store.isLoadingTodaySoFar {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppGlass.textPrimary)
                } else if store.todaySoFarErrorMessage != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.yellow)
                } else {
                    Image(systemName: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .appIconGlow(active: true)
                        .foregroundStyle(AppGlass.textPrimary)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        store.toggleTodaySoFarCollapsed()
                    }
                } label: {
                    Image(systemName: store.isTodaySoFarCollapsed ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppGlass.textSubtle)
                        .frame(width: 28, height: 28)
                        .background(AppGlass.controlFill, in: Circle())
                }
                .buttonStyle(.plain)
            }

            if !store.isTodaySoFarCollapsed {
                VStack(alignment: .leading, spacing: 10) {
                    Text(todaySoFarBodyText)
                        .foregroundStyle(AppGlass.textSecondary)
                        .appBodyText()

                    if store.todaySoFarErrorMessage != nil {
                        Button("Report") {
                            Task {
                                errorReportPayload = try? await ErrorReportService.makePayload(
                                    key: ErrorReportKey.mealsTodaySoFar,
                                    fallbackFeature: "Meals",
                                    fallbackOperation: "Generate day summary message",
                                    fallbackMessage: store.todaySoFarErrorMessage ?? "Day summary unavailable"
                                )
                            }
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppGlass.accent)
                    }

                    if let providerText = todaySoFarProviderText {
                        Text(providerText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppGlass.textSubtle)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(AppGlass.heroPadding)
        .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
        .animation(.easeInOut(duration: 0.18), value: store.isTodaySoFarCollapsed)
    }

    private var todaySoFarTitle: String {
        Calendar.current.isDateInToday(dayStore.selectedDate) ? "Today so far" : "Day summary"
    }

    private var todaySoFarBodyText: String {
        if let errorMessage = store.todaySoFarErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !errorMessage.isEmpty {
            return errorMessage
        }

        if let message = store.todaySoFarMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return message
        }

        if store.isLoadingTodaySoFar {
            return Calendar.current.isDateInToday(dayStore.selectedDate)
                ? "Reading today’s meals and goals..."
                : "Reading this day’s meals and goals..."
        }

        if store.meals.isEmpty {
            return Calendar.current.isDateInToday(dayStore.selectedDate)
                ? "Log your first meal today and this section will turn it into a short running check-in."
                : "No meals are logged for this day yet."
        }

        return Calendar.current.isDateInToday(dayStore.selectedDate)
            ? "Add or edit a meal to refresh today’s running check-in."
            : "Add or edit a meal to refresh this day’s saved summary."
    }

    private var todaySoFarProviderText: String? {
        guard let providerLabel = store.todaySoFarProviderLabel,
              let todaySoFarMessage = store.todaySoFarMessage,
              !todaySoFarMessage.isEmpty else {
            return nil
        }

        if providerLabel == "Built-in guidance" {
            return "Built from your meals and goals"
        }

        return "Generated with \(providerLabel)"
    }

    private func macroLineView(for meal: MealRecord) -> some View {
        let time = AppFormatters.shortTime.string(from: meal.consumedAt)
        let calories = AppFormatters.calorieText(meal.calories)
        let protein = AppFormatters.macroText(meal.protein)
        let carbs = AppFormatters.macroText(meal.carbs)
        let fat = AppFormatters.macroText(meal.fat)

        return HStack(spacing: 6) {
            Text(time)
                .foregroundStyle(AppGlass.textSubtle)
            Text("·")
                .foregroundStyle(AppGlass.textFaint)
            Text("\(calories) kcal")
                .foregroundStyle(MacroColors.calories)
            Text("·")
                .foregroundStyle(AppGlass.textFaint)
            Text("P \(protein)g")
                .foregroundStyle(MacroColors.protein)
            Text("·")
                .foregroundStyle(AppGlass.textFaint)
            Text("C \(carbs)g")
                .foregroundStyle(MacroColors.carbs)
            Text("·")
                .foregroundStyle(AppGlass.textFaint)
            Text("F \(fat)g")
                .foregroundStyle(MacroColors.fat)
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
    }
}

private struct AILogInputView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: MealsStore
    let consumedAt: Date
    let dayKey: String

    var body: some View {
        NavigationStack {
            ZStack {
                AppGlassBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: AppGlass.cardSpacing) {
                        AppScreenHeader(title: "Log With AI")

                        VStack(alignment: .leading, spacing: 8) {
                            AppSectionTitle(title: "Meal Name (optional)")

                            TextField("e.g. Chicken salad", text: $store.aiLogMealName)
                                .foregroundStyle(AppGlass.textPrimary)
                                .padding(.horizontal, 14)
                                .frame(height: 48)
                                .background(AppGlass.controlFill)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                        .padding(18)
                        .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)

                        VStack(alignment: .leading, spacing: 8) {
                            AppSectionTitle(title: "Meal Description")

                            TextEditor(text: $store.aiLogDescription)
                                .frame(minHeight: 180)
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .scrollContentBackground(.hidden)
                                .padding(10)
                                .background(AppGlass.controlFill)
                                .clipShape(RoundedRectangle(cornerRadius: 18))

                            if let error = store.aiLogInputError {
                                Text(error)
                                    .foregroundStyle(.red)
                                    .font(.footnote)
                            }
                        }
                        .padding(18)
                        .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Analyze") {
                        Task {
                            await store.submitAILog(consumedAt: consumedAt, dayKey: dayKey)
                        }
                    }
                }
            }
        }
    }
}

private struct AILogStatusView: View {
    @Bindable var store: MealsStore
    @State private var errorReportPayload: ExportPayload?

    var body: some View {
        NavigationStack {
            ZStack {
                AppGlassBackground()

                VStack(spacing: AppGlass.itemSpacing) {
                    Text(titleText)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppGlass.textPrimary)
                        .multilineTextAlignment(.center)

                    if store.aiLogPhase == .processing {
                        ProgressView()
                            .controlSize(.large)
                            .tint(AppGlass.textPrimary)
                    }

                    if let error = store.aiLogError, store.aiLogPhase == .failure {
                        Text(error)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    if let output = store.aiLogOutput, !output.isEmpty, store.aiLogPhase == .failure {
                        ScrollView {
                            Text(output)
                                .font(.footnote.monospaced())
                                .foregroundStyle(AppGlass.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .secondary)
                        }
                        .frame(maxHeight: 260)
                    }

                    if store.aiLogPhase == .failure {
                        VStack(spacing: 10) {
                            Button("Report") {
                                Task {
                                    errorReportPayload = try? await ErrorReportService.makePayload(
                                        key: ErrorReportKey.mealsAILog,
                                        fallbackFeature: "Meals",
                                        fallbackOperation: "AI meal logging",
                                        fallbackMessage: store.aiLogError ?? "Meal AI log failed"
                                    )
                                }
                            }
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppGlass.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .glassPanel(cornerRadius: AppGlass.pillCornerRadius, weight: .secondary)

                            Button("Close") {
                                store.dismissAILogStatus()
                            }
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppGlass.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .glassPanel(cornerRadius: AppGlass.pillCornerRadius, weight: .secondary)
                        }
                    }
                }
                .padding(24)
                .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
                .padding(24)
            }
            .onChange(of: store.aiLogPhase) { _, newPhase in
                guard newPhase == .success else { return }
                store.dismissAILogStatus()
            }
            .sheet(item: $errorReportPayload) { payload in
                ShareSheet(items: [payload.url])
            }
        }
    }

    private var titleText: String {
        switch store.aiLogPhase {
        case .processing:
            return "Analyzing meal with \(store.aiLogProviderLabel)"
        case .failure:
            return "Log failed"
        case .success:
            return "Log complete"
        case .idle:
            return "Log meal"
        }
    }
}

#Preview {
    MealsView()
}
