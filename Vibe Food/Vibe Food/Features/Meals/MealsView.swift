import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MealsView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(DaySelectionStore.self) private var dayStore
    @State private var store: MealsStore?

    var body: some View {
        Group {
            if let store {
                MealsContentView(store: store)
            } else {
                ProgressView()
                    .task {
                        let newStore = MealsStore(
                            mealRepository: appContainer.mealRepository,
                            ingredientRepository: appContainer.ingredientRepository,
                            aiIntegrationRepository: appContainer.aiIntegrationRepository,
                            context: appContainer.modelContainer.mainContext,
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

private struct MealsContentView: View {
    @Environment(DaySelectionStore.self) private var dayStore
    @Bindable var store: MealsStore

    var body: some View {
        NavigationStack {
            ZStack {
                AppGlassBackground()

                VStack(spacing: AppGlass.cardSpacing) {
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
                    .padding(.top, 20)

                    DaySelectorView()
                        .padding(.horizontal, 20)

                    List {
                        if store.meals.isEmpty {
                            ContentUnavailableView("No meals", systemImage: "fork.knife", description: Text("Add a meal for this day."))
                                .foregroundStyle(AppGlass.textSecondary, AppGlass.textMuted, AppGlass.textSubtle)
                                .frame(maxWidth: .infinity, minHeight: 280)
                                .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
                                .listRowInsets(EdgeInsets(top: 24, leading: 20, bottom: 96, trailing: 20))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(store.meals.enumerated()), id: \.element.id) { index, meal in
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

                                    if index < store.meals.count - 1 {
                                        Divider()
                                            .overlay(AppGlass.secondaryBorder)
                                            .padding(.horizontal, 16)
                                    }
                                }
                            }
                            .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .secondary)
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollDisabled(dayStore.isScrollLockedForDaySwipe)
                    .onScrollPhaseChange { _, newPhase in
                        dayStore.setVerticalScrollActive(newPhase.isScrolling)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .offset(x: dayStore.horizontalDragOffset)
                    .contentShape(Rectangle())
                    .simultaneousGesture(daySwipeGesture)
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
                    }
                case .failure:
                    store.errorMessage = "Failed to import JSON file."
                }
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

    private func macroLineView(for meal: MealRecord) -> some View {
        let time = AppFormatters.shortTime.string(from: meal.consumedAt)
        let calories = AppFormatters.number.string(from: NSNumber(value: meal.calories)) ?? "0"
        let protein = AppFormatters.number.string(from: NSNumber(value: meal.protein)) ?? "0"
        let carbs = AppFormatters.number.string(from: NSNumber(value: meal.carbs)) ?? "0"
        let fat = AppFormatters.number.string(from: NSNumber(value: meal.fat)) ?? "0"

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
            .toolbar(.hidden, for: .navigationBar)
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

                    if let output = store.aiLogOutput, !output.isEmpty {
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
                }
                .padding(24)
                .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
                .padding(24)
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                if store.aiLogPhase != .processing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(store.aiLogPhase == .failure ? "Close" : "Continue") {
                            store.dismissAILogStatus()
                        }
                    }
                }
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
