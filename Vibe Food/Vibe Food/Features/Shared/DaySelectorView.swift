import SwiftUI

struct DaySelectorView: View {
    @Environment(DaySelectionStore.self) private var dayStore
    @State private var showDatePicker: Bool = false
    @State private var tempDate: Date = Date()

    var body: some View {
        HStack(spacing: 12) {
            Button {
                dayStore.goToPreviousDay()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .appIconGlow(active: true)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)
            .glassPanel(cornerRadius: AppGlass.pillCornerRadius, weight: .secondary)

            VStack(spacing: 4) {
                Button {
                    if Calendar.current.isDateInToday(dayStore.selectedDate) {
                        tempDate = dayStore.selectedDate
                        showDatePicker = true
                    } else {
                        dayStore.goToToday()
                    }
                } label: {
                    Text(dayStore.displayDate)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppGlass.textPrimary)
                }

                Button("Today") {
                    dayStore.goToToday()
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppGlass.textSubtle)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .glassPanel(cornerRadius: AppGlass.pillCornerRadius, weight: .primary)

            Button {
                dayStore.goToNextDay()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .appIconGlow(active: true)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)
            .glassPanel(cornerRadius: AppGlass.pillCornerRadius, weight: .secondary)
            .disabled(!dayStore.canGoToNextDay)
            .opacity(dayStore.canGoToNextDay ? 1 : 0.45)
        }
        .padding(.vertical, 4)
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
    }
}
