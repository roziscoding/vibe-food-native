import SwiftUI
import Observation
import Foundation

struct FoodView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @State private var store: FoodStore?

    var body: some View {
        Group {
            if let store {
                FoodContentView(store: store)
            } else {
                ProgressView()
                    .task {
                        let newStore = FoodStore(
                            mealRepository: appContainer.mealRepository,
                            ingredientRepository: appContainer.ingredientRepository
                        )
                        newStore.load()
                        store = newStore
                    }
            }
        }
    }
}

private struct FoodContentView: View {
    @Bindable var store: FoodStore
    @State private var errorReportPayload: ExportPayload?

    var body: some View {
        NavigationStack {
            ZStack {
                AppGlassBackground()

                VStack(spacing: AppGlass.cardSpacing) {
                    AppScreenHeader(title: "Food")
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    ScrollView {
                        VStack(alignment: .leading, spacing: AppGlass.cardSpacing) {
                            mealsCard
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
            .onAppear {
                store.load()
            }
            .onReceive(NotificationCenter.default.publisher(for: AppDataChangeNotifier.notificationName)) { notification in
                guard let kind = AppDataChangeNotifier.kind(from: notification) else { return }
                guard kind == .meals || kind == .ingredients else { return }
                store.load()
            }
            .alert("Error", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { _ in store.errorMessage = nil }
            )) {
                Button("Report") {
                    Task {
                        errorReportPayload = try? await ErrorReportService.makePayload(
                            key: ErrorReportKey.foodAlert,
                            fallbackFeature: "Food",
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

    private var mealsCard: some View {
        NavigationLink {
            MealsView(presentation: .embedded)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    AppSectionTitle(title: "Meals")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppGlass.textSubtle)
                }

                HStack(spacing: 12) {
                    metricPill(
                        title: "Today",
                        value: "\(store.todayMealsCount)",
                        subtitle: store.todayMealsCount == 1 ? "meal logged" : "meals logged",
                        color: MacroColors.calories
                    )

                    metricPill(
                        title: "Calories",
                        value: "\(store.todayCalories.formatted(.number)) kcal",
                        subtitle: store.lastMealTimeText,
                        color: MacroColors.protein
                    )
                }

                Text("Open full meals history, add meals, and use Today so far guidance.")
                    .foregroundStyle(AppGlass.textSubtle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
        }
        .buttonStyle(.plain)
    }

    private var ingredientsCard: some View {
        NavigationLink {
            IngredientsView(presentation: .embedded)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    AppSectionTitle(title: "Ingredients")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppGlass.textSubtle)
                }

                metricPill(
                    title: "Library",
                    value: "\(store.ingredientCount)",
                    subtitle: store.ingredientCount == 1 ? "ingredient saved" : "ingredients saved",
                    color: MacroColors.carbs
                )

                Text("Open your ingredients library to add, edit, or scan labels.")
                    .foregroundStyle(AppGlass.textSubtle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
        }
        .buttonStyle(.plain)
    }

    private func metricPill(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(AppGlass.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(subtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppGlass.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 16, weight: .secondary)
    }
}

@MainActor
@Observable
final class FoodStore {
    private let mealRepository: MealRepository
    private let ingredientRepository: IngredientRepository

    var todayMealsCount: Int = 0
    var todayCalories: Double = 0
    var lastMealAt: Date?
    var ingredientCount: Int = 0
    var errorMessage: String?

    init(mealRepository: MealRepository, ingredientRepository: IngredientRepository) {
        self.mealRepository = mealRepository
        self.ingredientRepository = ingredientRepository
    }

    var lastMealTimeText: String {
        guard let lastMealAt else { return "No meals logged yet" }
        return "Last: \(AppFormatters.shortTime.string(from: lastMealAt))"
    }

    func load() {
        do {
            let todayKey = LocalDayKey.key(for: Date(), timeZone: .current)
            let meals = try mealRepository.fetchMeals(localDayKey: todayKey)
            let ingredients = try ingredientRepository.fetchActiveIngredients()

            todayMealsCount = meals.count
            todayCalories = meals.reduce(0) { partial, meal in
                partial + meal.calories
            }
            lastMealAt = meals.max(by: { $0.consumedAt < $1.consumedAt })?.consumedAt
            ingredientCount = ingredients.count
            errorMessage = nil
        } catch {
            setError("Failed to load food summary.", operation: "Load food summary", error: error)
        }
    }

    private func setError(_ message: String, operation: String, error: Error? = nil) {
        errorMessage = message
        ErrorReportService.capture(
            key: ErrorReportKey.foodAlert,
            feature: "Food",
            operation: operation,
            userMessage: message,
            error: error
        )
    }
}

#Preview {
    FoodView()
}
