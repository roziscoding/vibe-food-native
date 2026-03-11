import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import os

private let ingredientsViewLogger = Logger(subsystem: "ninja.roz.vibefood", category: "IngredientsView")

enum IngredientsPresentation {
    case tab
    case embedded
}

enum IngredientsQuickAction {
    case addManual
    case scanLabel
}

struct IngredientsView: View {
    @EnvironmentObject private var appContainer: AppContainer
    let presentation: IngredientsPresentation
    let quickAction: IngredientsQuickAction?

    init(presentation: IngredientsPresentation = .tab, quickAction: IngredientsQuickAction? = nil) {
        self.presentation = presentation
        self.quickAction = quickAction
    }

    var body: some View {
        IngredientsListView(store: appContainer.ingredientsStore, presentation: presentation, quickAction: quickAction)
        .onAppear {
            ingredientsViewLogger.info("onAppear. loading ingredients store if needed.")
            appContainer.ingredientsStore.loadIfNeeded()
        }
        .onDisappear {
            ingredientsViewLogger.debug("onDisappear")
        }
    }
}

private struct IngredientsListView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: IngredientsStore
    let presentation: IngredientsPresentation
    let quickAction: IngredientsQuickAction?
    @State private var photoItem: PhotosPickerItem?
    @State private var cameraImage: UIImage?
    @State private var hasAppliedQuickAction = false
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
            applyQuickActionIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppDataChangeNotifier.notificationName)) { notification in
            guard let kind = AppDataChangeNotifier.kind(from: notification) else { return }
            guard kind == .ingredients else { return }
            store.load()
        }
        .alert("Error", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { _ in store.errorMessage = nil }
        )) {
            Button("Report") {
                Task {
                    errorReportPayload = try? await ErrorReportService.makePayload(
                        key: ErrorReportKey.ingredientsAlert,
                        fallbackFeature: "Ingredients",
                        fallbackOperation: "Present error alert",
                        fallbackMessage: store.errorMessage ?? "Unknown error"
                    )
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
        .alert("Delete Ingredient", isPresented: Binding(
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
            Text("This will remove the ingredient from lists and pickers, but existing meals keep their snapshots.")
        }
        .sheet(isPresented: $store.isPresentingEditor) {
            if let draft = store.draft {
                IngredientEditorView(
                    draft: Binding(
                        get: { draft },
                        set: { store.draft = $0 }
                    ),
                    errorMessage: store.draftError,
                    fieldErrors: store.fieldErrors,
                    onSave: { store.saveDraft() },
                    onCancel: { store.cancelEdit() }
                )
            }
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
                .navigationTitle("Import Ingredient")
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
                        key: ErrorReportKey.ingredientsAlert,
                        feature: "Ingredients",
                        operation: "Read ingredient JSON file",
                        userMessage: store.errorMessage ?? "Failed to read JSON file.",
                        error: error
                    )
                }
            case .failure:
                store.errorMessage = "Failed to import JSON file."
                ErrorReportService.capture(
                    key: ErrorReportKey.ingredientsAlert,
                    feature: "Ingredients",
                    operation: "Open ingredient file importer",
                    userMessage: store.errorMessage ?? "Failed to import JSON file."
                )
            }
        }
        .sheet(item: $store.exportPayload) { payload in
            ShareSheet(items: [payload.url])
        }
        .sheet(item: $errorReportPayload) { payload in
            ShareSheet(items: [payload.url])
        }
        .modifier(ScanPresentationModifier(
            store: store,
            photoItem: $photoItem,
            cameraImage: $cameraImage
        ))
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
                    title: "Ingredients",
                    trailing: AnyView(
                        Menu {
                            Button("Add Ingredient") {
                                store.beginCreate()
                            }
                            Button("Scan Label") {
                                store.beginScan()
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

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .appIconGlow(active: false)

                    TextField("Search ingredients", text: $store.searchText)
                        .foregroundStyle(AppGlass.textPrimary)
                        .tint(AppGlass.accent)
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .glassPanel(cornerRadius: AppGlass.pillCornerRadius, weight: .secondary)
                .padding(.horizontal, 20)

                List {
                    if store.filteredIngredients.isEmpty {
                        ContentUnavailableView("No Ingredients", systemImage: "leaf", description: Text("Add your first ingredient or scan a label."))
                            .foregroundStyle(AppGlass.textSecondary, AppGlass.textMuted, AppGlass.textSubtle)
                            .frame(maxWidth: .infinity, minHeight: 280)
                            .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
                            .listRowInsets(EdgeInsets(top: 24, leading: 20, bottom: 96, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(store.filteredIngredients.enumerated()), id: \.element.id) { index, ingredient in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(ingredient.name)
                                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                                        .foregroundStyle(AppGlass.textPrimary)
                                    macroLineView(for: ingredient)
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    store.beginEdit(ingredient)
                                }

                                if index < store.filteredIngredients.count - 1 {
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
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
    }

    private func macroLineView(for ingredient: IngredientRecord) -> some View {
        let calories = AppFormatters.calorieText(ingredient.caloriesPerPortion)
        let protein = AppFormatters.macroText(ingredient.proteinPerPortion)
        let carbs = AppFormatters.macroText(ingredient.carbsPerPortion)
        let fat = AppFormatters.macroText(ingredient.fatPerPortion)

        return HStack(spacing: 6) {
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

    private func applyQuickActionIfNeeded() {
        guard !hasAppliedQuickAction, let quickAction else { return }
        hasAppliedQuickAction = true
        switch quickAction {
        case .addManual:
            store.beginCreate()
        case .scanLabel:
            store.beginScan()
        }
    }
}

private struct ScanPresentationModifier: ViewModifier {
    @Bindable var store: IngredientsStore
    @Binding var photoItem: PhotosPickerItem?
    @Binding var cameraImage: UIImage?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $store.isPresentingCamera) {
                CameraPicker(image: $cameraImage)
                    .onDisappear {
                        if let cameraImage {
                            Task { await store.handleScanImage(cameraImage) }
                            self.cameraImage = nil
                        }
                    }
            }
            .photosPicker(isPresented: $store.isPresentingPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await store.handleScanImage(image)
                    } else {
                        store.scanError = "Failed to load photo."
                        ErrorReportService.capture(
                            key: ErrorReportKey.ingredientsScan,
                            feature: "Ingredients",
                            operation: "Load selected scan photo",
                            userMessage: store.scanError ?? "Failed to load photo."
                        )
                    }
                    photoItem = nil
                }
            }
            .fullScreenCover(isPresented: $store.isPresentingScanStatus) {
                ScanStatusView(store: store)
            }
    }
}

private struct ScanStatusView: View {
    @Bindable var store: IngredientsStore
    @State private var errorReportPayload: ExportPayload?

    var body: some View {
        NavigationStack {
            ZStack {
                AppGlassBackground()

                VStack(spacing: AppGlass.cardSpacing) {
                    Text(titleText)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppGlass.textPrimary)
                        .multilineTextAlignment(.center)

                    if store.scanPhase == .processing {
                        ProgressView()
                            .controlSize(.large)
                            .tint(AppGlass.textPrimary)
                    }

                    if let scanError = store.scanError, store.scanPhase == .failure {
                        Text(scanError)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    if let output = store.scanOutput, !output.isEmpty, store.scanPhase == .failure {
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

                    if store.scanPhase == .failure {
                        VStack(spacing: 10) {
                            Button("Report") {
                                Task {
                                    errorReportPayload = try? await ErrorReportService.makePayload(
                                        key: ErrorReportKey.ingredientsScan,
                                        fallbackFeature: "Ingredients",
                                        fallbackOperation: "Scan nutrition label",
                                        fallbackMessage: store.scanError ?? "Scan failed"
                                    )
                                }
                            }
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppGlass.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .glassPanel(cornerRadius: AppGlass.pillCornerRadius, weight: .secondary)

                            Button("Close") {
                                store.dismissScanStatus()
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
            .onChange(of: store.scanPhase) { _, newPhase in
                guard newPhase == .success else { return }
                store.dismissScanStatus()
            }
            .sheet(item: $errorReportPayload) { payload in
                ShareSheet(items: [payload.url])
            }
        }
    }

    private var titleText: String {
        switch store.scanPhase {
        case .processing:
            return "Analyzing label with \(store.scanProviderLabel)"
        case .failure:
            return "Scan failed"
        case .success:
            return "Scan complete"
        case .idle:
            return "Scan"
        }
    }
}

#Preview {
    IngredientsView()
}
