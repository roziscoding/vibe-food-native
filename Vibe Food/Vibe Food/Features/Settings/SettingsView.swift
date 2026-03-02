import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @State private var store: SettingsStore?

    var body: some View {
        Group {
            if let store {
                SettingsFormView(store: store)
            } else {
                ProgressView()
                    .task {
                        let newStore = SettingsStore(
                            repository: appContainer.settingsRepository,
                            aiRepository: appContainer.aiIntegrationRepository,
                            deviceId: appContainer.deviceId
                        )
                        newStore.load()
                        store = newStore
                    }
            }
        }
    }
}

private struct SettingsFormView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Bindable var store: SettingsStore
    @State private var isReadyForAutoSave: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppGlassBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: AppGlass.cardSpacing) {
                        AppScreenHeader(title: "Settings")

                        VStack(alignment: .leading, spacing: AppGlass.sectionSpacing) {
                            AppSectionTitle(title: "Goals")

                            VStack(spacing: AppGlass.sectionSpacing) {
                                goalRow(title: "Calories", unit: "kcal", value: $store.calorieGoal)
                                goalRow(title: "Protein", unit: "g", value: $store.proteinGoal)
                                goalRow(title: "Carbs", unit: "g", value: $store.carbsGoal)
                                goalRow(title: "Fat", unit: "g", value: $store.fatGoal)
                            }
                            .padding(18)
                            .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .secondary)

                            VStack(alignment: .leading, spacing: 10) {
                                AppSectionTitle(title: "Profile")
                                Text(profileSummary)
                                    .foregroundStyle(AppGlass.textSecondary)
                                    .appBodyText()

                                Button("Edit Profile") {
                                    store.showProfileEditor = true
                                }
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppGlass.accent)
                            }
                            .padding(18)
                            .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .secondary)

                            Button("Recommendation Helper") {
                                store.showRecommendation = true
                            }
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppGlass.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .glassPanel(cornerRadius: AppGlass.pillCornerRadius, weight: .primary)
                        }

                        VStack(alignment: .leading, spacing: AppGlass.sectionSpacing) {
                            AppSectionTitle(title: "AI Integration")

                            VStack(alignment: .leading, spacing: AppGlass.sectionSpacing) {
                                VStack(alignment: .leading, spacing: 8) {
                                    AppSectionTitle(title: "Provider")

                                    Picker("Provider", selection: $store.aiProvider) {
                                        ForEach(AIProvider.allCases) { provider in
                                            Text(provider.rawValue.capitalized)
                                                .tag(provider)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    AppSectionTitle(title: "API Key")

                                    SecureField("API Key", text: $store.aiApiKey)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .foregroundStyle(AppGlass.textPrimary)
                                        .padding(.horizontal, 14)
                                        .frame(height: 48)
                                        .background(AppGlass.controlFill)
                                        .clipShape(RoundedRectangle(cornerRadius: 18))
                                }

                                Button("Clear Key", role: .destructive) {
                                    store.aiApiKey = ""
                                    store.saveAI()
                                }
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            }
                            .padding(18)
                            .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .secondary)
                        }

                        VStack(alignment: .leading, spacing: AppGlass.sectionSpacing) {
                            AppSectionTitle(title: "Data")

                            Button("Reset All Data", role: .destructive) {
                                store.showResetConfirm = true
                            }
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .keyboardDoneToolbar()
            .onAppear {
                isReadyForAutoSave = true
            }
            .onChange(of: store.calorieGoal) { _, _ in
                if isReadyForAutoSave { store.save() }
            }
            .onChange(of: store.proteinGoal) { _, _ in
                if isReadyForAutoSave { store.save() }
            }
            .onChange(of: store.carbsGoal) { _, _ in
                if isReadyForAutoSave { store.save() }
            }
            .onChange(of: store.fatGoal) { _, _ in
                if isReadyForAutoSave { store.save() }
            }
            .onChange(of: store.aiProvider) { _, _ in
                if isReadyForAutoSave { store.saveAI() }
            }
            .onChange(of: store.aiApiKey) { _, _ in
                if isReadyForAutoSave { store.saveAI() }
            }
            .alert("Error", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { _ in store.errorMessage = nil }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(store.errorMessage ?? "Unknown error")
            }
            .alert("Reset Data", isPresented: $store.showResetConfirm) {
                Button("Continue", role: .destructive) {
                    store.showResetFinal = true
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will delete meals, ingredients, insights, and settings on this device.")
            }
            .alert("Confirm Reset", isPresented: $store.showResetFinal) {
                Button("Reset", role: .destructive) {
                    do {
                        try appContainer.resetAllData()
                        store.load()
                    } catch {
                        store.errorMessage = "Failed to reset data."
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This cannot be undone.")
            }
            .sheet(isPresented: $store.showRecommendation) {
                GoalRecommendationView(
                    initialInput: GoalRecommendationInput(
                        age: store.age,
                        heightCm: store.heightCm,
                        weightKg: store.weightKg,
                        sex: store.sex,
                        activityLevel: store.activityLevel,
                        objective: store.objective
                    ),
                    onApply: { input in
                        store.applyRecommendation(input: input)
                        store.showRecommendation = false
                    },
                    onCancel: {
                        store.showRecommendation = false
                    }
                )
            }
            .sheet(isPresented: $store.showProfileEditor) {
                GoalRecommendationView(
                    title: "Edit Profile",
                    applyButtonTitle: "Save",
                    initialInput: GoalRecommendationInput(
                        age: store.age,
                        heightCm: store.heightCm,
                        weightKg: store.weightKg,
                        sex: store.sex,
                        activityLevel: store.activityLevel,
                        objective: store.objective
                    ),
                    onApply: { input in
                        store.applyProfile(input: input)
                        store.save()
                        store.showProfileEditor = false
                    },
                    onCancel: {
                        store.showProfileEditor = false
                    }
                )
            }
        }
    }

    private func goalRow(title: String, unit: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppGlass.textPrimary)
            Spacer()
            TextField("", value: value, format: .number)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(maxWidth: 120)
                .foregroundStyle(AppGlass.textPrimary)
            Text(unit)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppGlass.textSubtle)
        }
    }

    private var profileSummary: String {
        "\(store.age)y, \(Int(store.heightCm))cm, \(Int(store.weightKg))kg, \(store.sex.rawValue.capitalized)"
    }
}

#Preview {
    SettingsView()
}
