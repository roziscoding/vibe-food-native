import SwiftUI

struct WaterView: View {
    @EnvironmentObject private var appContainer: AppContainer
    @Environment(DaySelectionStore.self) private var dayStore
    @State private var store: WaterStore?

    var body: some View {
        Group {
            if let store {
                WaterContentView(store: store)
            } else {
                ProgressView()
                    .task {
                        let newStore = WaterStore(
                            waterRepository: appContainer.waterRepository,
                            settingsRepository: appContainer.settingsRepository,
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

private struct WaterContentView: View {
    @Environment(DaySelectionStore.self) private var dayStore
    @Bindable var store: WaterStore
    @State private var errorReportPayload: ExportPayload?

    var body: some View {
        NavigationStack {
            ZStack {
                AppGlassBackground()

                VStack(spacing: AppGlass.cardSpacing) {
                    AppScreenHeader(title: "Water")
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    DaySelectorView()
                        .padding(.horizontal, 20)

                    List {
                        overviewCard
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)

                        if store.entries.isEmpty {
                            ContentUnavailableView(
                                "No water entries",
                                systemImage: "drop",
                                description: Text("Log your first glass for this day.")
                            )
                            .foregroundStyle(AppGlass.textSecondary, AppGlass.textMuted, AppGlass.textSubtle)
                            .frame(maxWidth: .infinity, minHeight: 260)
                            .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 96, trailing: 20))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        } else {
                            ForEach(store.entries) { entry in
                                waterEntryRow(entry)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            store.confirmDelete(entry)
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
            .keyboardDoneToolbar()
            .onAppear {
                store.load(for: dayStore.localDayKey)
                store.preloadAdjacentDays(around: dayStore.selectedDate)
            }
            .onReceive(NotificationCenter.default.publisher(for: AppDataChangeNotifier.notificationName)) { notification in
                guard let kind = AppDataChangeNotifier.kind(from: notification) else { return }
                guard kind == .water || kind == .settings else { return }
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
                            key: ErrorReportKey.waterAlert,
                            fallbackFeature: "Water",
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
            .alert("Delete Entry", isPresented: Binding(
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
                Text("This water entry will be removed from your history.")
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

    private var overviewCard: some View {
        let goal = max(1, store.goalMl)
        let progress = min(1, store.totalMl / goal)
        let remaining = max(0, goal - store.totalMl)

        return VStack(alignment: .leading, spacing: 14) {
            Text("Today")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .textCase(.uppercase)
                .tracking(AppGlass.sectionTracking)
                .foregroundStyle(AppGlass.textSubtle)

            HStack(spacing: 12) {
                summaryMetric(
                    title: "Consumed",
                    value: "\(store.totalMl.formatted(.number)) ml",
                    color: Color.cyan
                )
                summaryMetric(
                    title: "Goal",
                    value: "\(store.goalMl.formatted(.number)) ml",
                    color: AppGlass.textSecondary
                )
                summaryMetric(
                    title: "Remaining",
                    value: "\(remaining.formatted(.number)) ml",
                    color: AppGlass.textSecondary
                )
            }

            ProgressView(value: progress)
                .tint(Color.cyan)
                .scaleEffect(x: 1, y: 0.72, anchor: .center)

            HStack(spacing: 10) {
                ForEach(Array(store.quickWaterAmounts.enumerated()), id: \.offset) { _, amountMl in
                    quickAddButton(amountMl)
                }
            }
            .buttonStyle(.borderless)

            HStack(spacing: 10) {
                TextField("Custom ml", text: $store.customAmountMlText)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(AppGlass.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(AppGlass.controlFill)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Button("Add") {
                    store.addCustom(selectedDate: dayStore.selectedDate)
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AppGlass.textPrimary)
                .frame(minWidth: 70)
                .frame(height: 44)
                .glassPanel(cornerRadius: 18, weight: .secondary)
            }
        }
        .padding(16)
        .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .primary)
    }

    private func quickAddButton(_ amountMl: Double) -> some View {
        Button {
            store.addQuick(amountMl: amountMl, selectedDate: dayStore.selectedDate)
        } label: {
            Text("+\(Int(amountMl)) ml")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AppGlass.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
        .buttonStyle(.plain)
        .glassPanel(cornerRadius: 16, weight: .secondary)
    }

    private func summaryMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AppGlass.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func waterEntryRow(_ entry: WaterEntryRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(entry.amountMl.formatted(.number)) ml")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppGlass.textPrimary)
                Text(AppFormatters.shortTime.string(from: entry.consumedAt))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppGlass.textSubtle)
            }
            Spacer()
            Image(systemName: "drop.fill")
                .foregroundStyle(Color.cyan)
        }
        .padding(16)
        .glassPanel(cornerRadius: AppGlass.cardCornerRadius, weight: .secondary)
    }
}

#Preview {
    WaterView()
}
