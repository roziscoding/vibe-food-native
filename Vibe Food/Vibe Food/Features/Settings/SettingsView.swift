import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit
import os

private let settingsViewLogger = Logger(subsystem: "ninja.roz.vibefood", category: "SettingsView")

struct SettingsView: View {
    @EnvironmentObject private var appContainer: AppContainer

    var body: some View {
        SettingsFormView(store: appContainer.settingsStore)
        .onAppear {
            settingsViewLogger.info("onAppear. loading settings store if needed.")
            appContainer.settingsStore.loadIfNeeded()
        }
        .onDisappear {
            settingsViewLogger.debug("onDisappear")
        }
    }
}

private struct SettingsFormView: View {
    private enum FocusField: Hashable {
        case calorieGoal
        case proteinGoal
        case carbsGoal
        case fatGoal
        case waterGoal
        case quickWater1
        case quickWater2
        case quickWater3
        case aiApiKey
    }

    @EnvironmentObject private var appContainer: AppContainer
    @Bindable var store: SettingsStore
    @State private var isReadyForAutoSave: Bool = false
    @State private var errorReportPayload: ExportPayload?
    @State private var isKeyboardPresented: Bool = false
    @FocusState private var focusedField: FocusField?

    var body: some View {
        settingsModalFlows
    }

    private var settingsRoot: some View {
        NavigationStack {
            mainContent
        }
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardPresented = false
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isKeyboardPresented {
                keyboardDismissBar
            }
        }
    }

    private var settingsAutoSaveFlows: some View {
        settingsRoot
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
        .onChange(of: store.waterGoal) { _, _ in
            if isReadyForAutoSave { store.save() }
        }
        .onChange(of: store.quickWaterAmount1) { _, _ in
            if isReadyForAutoSave { store.save() }
        }
        .onChange(of: store.quickWaterAmount2) { _, _ in
            if isReadyForAutoSave { store.save() }
        }
        .onChange(of: store.quickWaterAmount3) { _, _ in
            if isReadyForAutoSave { store.save() }
        }
        .onChange(of: store.showsInsights) { _, _ in
            if isReadyForAutoSave { store.save() }
        }
        .onChange(of: store.showsTodaySoFarBanner) { _, _ in
            if isReadyForAutoSave { store.save() }
        }
        .onChange(of: store.aiProvider) { _, _ in
            if isReadyForAutoSave { store.aiProviderChanged() }
        }
    }

    private var settingsErrorAndResetFlows: some View {
        settingsAutoSaveFlows
        .alert("Error", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { _ in store.errorMessage = nil }
        )) {
            Button("Report") {
                Task {
                    errorReportPayload = try? await ErrorReportService.makePayload(
                        key: ErrorReportKey.settingsAlert,
                        fallbackFeature: "Settings",
                        fallbackOperation: "Present error alert",
                        fallbackMessage: store.errorMessage ?? "Unknown error"
                    )
                }
            }
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
    }

    private var settingsImportExportFlows: some View {
        settingsErrorAndResetFlows
        .fileImporter(
            isPresented: $store.isPresentingBackupImporter,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                do {
                    let didStartAccess = url.startAccessingSecurityScopedResource()
                    defer {
                        if didStartAccess {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    let data = try Data(contentsOf: url)
                    store.importAllData(from: data)
                } catch {
                    store.errorMessage = "Failed to read backup file: \(error.localizedDescription)"
                    ErrorReportService.capture(
                        key: ErrorReportKey.settingsAlert,
                        feature: "Settings",
                        operation: "Read backup file",
                        userMessage: store.errorMessage ?? "Failed to read backup file.",
                        error: error
                    )
                }
            case .failure:
                store.errorMessage = "Failed to import backup file."
                ErrorReportService.capture(
                    key: ErrorReportKey.settingsAlert,
                    feature: "Settings",
                    operation: "Open backup file importer",
                    userMessage: store.errorMessage ?? "Failed to import backup file."
                )
            }
        }
        .sheet(item: $store.backupExportPayload) { payload in
            ShareSheet(items: [payload.url])
        }
        .sheet(item: $errorReportPayload) { payload in
            ShareSheet(items: [payload.url])
        }
    }

    private var settingsModalFlows: some View {
        settingsImportExportFlows
        .alert("Confirm Reset", isPresented: $store.showResetFinal) {
            Button("Reset", role: .destructive) {
                do {
                    try appContainer.resetAllData()
                    store.load()
                } catch {
                    store.errorMessage = "Failed to reset data."
                    ErrorReportService.capture(
                        key: ErrorReportKey.settingsAlert,
                        feature: "Settings",
                        operation: "Reset all data",
                        userMessage: store.errorMessage ?? "Failed to reset data.",
                        error: error
                    )
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }
        .sheet(isPresented: $store.showRecommendation) {
            recommendationSheet
        }
        .sheet(isPresented: $store.showProfileEditor) {
            profileEditorSheet
        }
    }

    private var mainContent: some View {
        ZStack {
            AppGlassBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: AppGlass.cardSpacing) {
                    AppScreenHeader(title: "Settings")
                    profileSection
                    goalsSection
                    hydrationSection
                    aiAndInsightsSection
                    dataSection
                    appVersionFooter
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: AppGlass.sectionSpacing) {
            AppSectionTitle(title: "Goals")

            VStack(spacing: AppGlass.sectionSpacing) {
                goalRow(title: "Calories", unit: "kcal", value: $store.calorieGoal, focusField: .calorieGoal)
                goalRow(title: "Protein", unit: "g", value: $store.proteinGoal, focusField: .proteinGoal)
                goalRow(title: "Carbs", unit: "g", value: $store.carbsGoal, focusField: .carbsGoal)
                goalRow(title: "Fat", unit: "g", value: $store.fatGoal, focusField: .fatGoal)
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
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: AppGlass.sectionSpacing) {
            AppSectionTitle(title: "Profile")

            VStack(alignment: .leading, spacing: 10) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .secondary)
        }
    }

    private var hydrationSection: some View {
        VStack(alignment: .leading, spacing: AppGlass.sectionSpacing) {
            AppSectionTitle(title: "Hydration")

            VStack(spacing: AppGlass.sectionSpacing) {
                goalRow(title: "Water Goal", unit: "ml", value: $store.waterGoal, focusField: .waterGoal)
            }
            .padding(18)
            .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .secondary)

            VStack(alignment: .leading, spacing: 10) {
                AppSectionTitle(title: "Water quick buttons")
                Text("Used by Input and Water tabs.")
                    .foregroundStyle(AppGlass.textSecondary)
                    .font(.system(size: 13, weight: .medium, design: .rounded))

                HStack(spacing: 10) {
                    quickWaterAmountField(title: "1", value: $store.quickWaterAmount1, focusField: .quickWater1)
                    quickWaterAmountField(title: "2", value: $store.quickWaterAmount2, focusField: .quickWater2)
                    quickWaterAmountField(title: "3", value: $store.quickWaterAmount3, focusField: .quickWater3)
                }
            }
            .padding(18)
            .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .secondary)
        }
    }

    private var aiAndInsightsSection: some View {
        VStack(alignment: .leading, spacing: AppGlass.sectionSpacing) {
            AppSectionTitle(title: "AI & Insights")

            VStack(spacing: AppGlass.sectionSpacing) {
                Toggle(isOn: $store.showsInsights) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Enable Insights")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppGlass.textPrimary)
                        Text("Show or hide insights guidance in the app without affecting your meals, ingredients, or goals.")
                            .foregroundStyle(AppGlass.textSecondary)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                    }
                }
                .toggleStyle(.switch)
                .tint(AppGlass.accent)

                Divider()
                    .overlay(AppGlass.secondaryBorder)

                Toggle(isOn: $store.showsTodaySoFarBanner) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Show day summary banner")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppGlass.textPrimary)
                        Text("Show or hide the collapsible Today so far card on the Meals tab.")
                            .foregroundStyle(AppGlass.textSecondary)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                    }
                }
                .toggleStyle(.switch)
                .tint(AppGlass.accent)

                Divider()
                    .overlay(AppGlass.secondaryBorder)

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

                    if store.isEditingAIKey {
                        SecureField("API Key", text: $store.aiApiKeyDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($focusedField, equals: .aiApiKey)
                            .onSubmit {
                                dismissKeyboard()
                            }
                            .foregroundStyle(AppGlass.textPrimary)
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(AppGlass.controlFill)
                            .clipShape(RoundedRectangle(cornerRadius: 18))

                        Button {
                            Task {
                                await store.confirmAIKey()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if store.isConfirmingAIKey {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(store.isConfirmingAIKey ? "Checking..." : "Confirm")
                            }
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                        }
                        .disabled(store.isConfirmingAIKey || store.aiApiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .buttonStyle(.borderedProminent)
                        .tint(AppGlass.accent)

                        if let creditError = store.aiCreditErrorMessage {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(creditError)
                                    .foregroundStyle(Color.red.opacity(0.92))
                                    .font(.system(size: 12, weight: .medium, design: .rounded))

                                Button("Report") {
                                    Task {
                                        errorReportPayload = try? await ErrorReportService.makePayload(
                                            key: ErrorReportKey.settingsAICredit,
                                            fallbackFeature: "Settings",
                                            fallbackOperation: "Verify AI API key",
                                            fallbackMessage: creditError
                                        )
                                    }
                                }
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppGlass.accent)
                            }
                        }
                    } else {
                        if store.isConfirmingAIKey && store.aiCreditDisplayText == nil {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Validating key...")
                            }
                            .foregroundStyle(AppGlass.textSecondary)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        } else if let creditText = store.aiCreditDisplayText {
                            Text(creditText)
                                .foregroundStyle(AppGlass.textSecondary)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                        }

                        if let keyPreview = maskedKeyPreview(from: store.aiApiKey) {
                            Text("Key: \(keyPreview)")
                                .foregroundStyle(AppGlass.textSecondary)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        HStack(spacing: 12) {
                            Button("Change Key") {
                                store.beginChangingAIKey()
                            }
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppGlass.accent)

                            Button("Clear Key", role: .destructive) {
                                store.clearAIKey()
                            }
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }

                        if let creditError = store.aiCreditErrorMessage {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(creditError)
                                    .foregroundStyle(Color.red.opacity(0.92))
                                    .font(.system(size: 12, weight: .medium, design: .rounded))

                                Button("Report") {
                                    Task {
                                        errorReportPayload = try? await ErrorReportService.makePayload(
                                            key: ErrorReportKey.settingsAICredit,
                                            fallbackFeature: "Settings",
                                            fallbackOperation: "Verify AI API key",
                                            fallbackMessage: creditError
                                        )
                                    }
                                }
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppGlass.accent)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .secondary)
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: AppGlass.sectionSpacing) {
            AppSectionTitle(title: "Data")

            Button("Export Data (No Insights)") {
                store.exportAllData()
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .secondary)

            Button("Import Data (No Insights)") {
                store.isPresentingBackupImporter = true
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .secondary)

            Button("Reset All Data", role: .destructive) {
                store.showResetConfirm = true
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .secondary)
        }
    }

    private var appVersionFooter: some View {
        Text(appVersionLabel)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(AppGlass.textSubtle)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 6)
    }

    private var recommendationSheet: some View {
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

    private var profileEditorSheet: some View {
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

    private func goalRow(title: String, unit: String, value: Binding<Double>, focusField: FocusField) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppGlass.textPrimary)
            Spacer()
            TextField("", value: value, format: .number)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .submitLabel(.done)
                .focused($focusedField, equals: focusField)
                .frame(maxWidth: 120)
                .foregroundStyle(AppGlass.textPrimary)
            Text(unit)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppGlass.textSubtle)
        }
    }

    private func quickWaterAmountField(title: String, value: Binding<Double>, focusField: FocusField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Button \(title)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(AppGlass.textSubtle)
                .textCase(.uppercase)

            HStack(spacing: 6) {
                TextField("", value: value, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .submitLabel(.done)
                    .focused($focusedField, equals: focusField)
                    .foregroundStyle(AppGlass.textPrimary)
                    .frame(maxWidth: .infinity)
                Text("ml")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppGlass.textSubtle)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(AppGlass.controlFill)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var keyboardDismissBar: some View {
        HStack {
            Spacer()
            Button("Done") {
                dismissKeyboard()
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(AppGlass.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppGlass.secondaryBorder)
                .frame(height: 1)
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func maskedKeyPreview(from key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let totalCount = trimmed.count
        let prefixCount = min(4, totalCount)
        let suffixCount = min(4, max(totalCount - prefixCount, 0))

        let prefix = String(trimmed.prefix(prefixCount))
        let suffix = String(trimmed.suffix(suffixCount))
        let mask = String(repeating: "*", count: 10)

        if suffix.isEmpty {
            return "\(prefix)\(mask)"
        }
        return "\(prefix)\(mask)\(suffix)"
    }

    private var profileSummary: String {
        "\(store.age)y, \(Int(store.heightCm))cm, \(Int(store.weightKg))kg, \(store.sex.rawValue.capitalized)"
    }

    private var appVersionLabel: String {
        let marketingVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (marketingVersion, buildNumber) {
        case let (version?, build?):
            return "Version \(version) • Build \(build)"
        case let (version?, nil):
            return "Version \(version)"
        case let (nil, build?):
            return "Build \(build)"
        default:
            return "Version unavailable"
        }
    }
}

#Preview {
    SettingsView()
}
