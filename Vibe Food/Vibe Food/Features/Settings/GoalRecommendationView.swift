import SwiftUI

struct GoalRecommendationView: View {
    let title: String
    let applyButtonTitle: String
    let initialInput: GoalRecommendationInput
    @State private var age: Int = 18
    @State private var showAgePicker: Bool = false
    @State private var heightCm: Double = 170
    @State private var showHeightPicker: Bool = false
    @State private var weightKg: Double = 70
    @State private var showWeightPicker: Bool = false
    @State private var sex: Sex = .female
    @State private var activityLevel: ActivityLevel = .active
    @State private var objective: GoalObjective = .maintainWeight

    var onApply: (GoalRecommendationInput) -> Void
    var onCancel: () -> Void

    init(
        title: String = "Goal Helper",
        applyButtonTitle: String = "Apply",
        initialInput: GoalRecommendationInput,
        onApply: @escaping (GoalRecommendationInput) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.applyButtonTitle = applyButtonTitle
        self.initialInput = initialInput
        self.onApply = onApply
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Body") {
                    Button {
                        showAgePicker = true
                    } label: {
                        HStack {
                            Text("Age")
                            Spacer()
                            Text("\(age)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        showHeightPicker = true
                    } label: {
                        HStack {
                            Text("Height (cm)")
                            Spacer()
                            Text("\(Int(heightCm))")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        showWeightPicker = true
                    } label: {
                        HStack {
                            Text("Weight (kg)")
                            Spacer()
                            Text("\(Int(weightKg))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Profile") {
                    Picker("Sex", selection: $sex) {
                        ForEach(Sex.allCases) { option in
                            Text(option.rawValue.capitalized)
                                .tag(option)
                        }
                    }

                    Picker("Activity", selection: $activityLevel) {
                        ForEach(ActivityLevel.allCases) { level in
                            Text(label(for: level))
                                .tag(level)
                        }
                    }

                    Picker("Objective", selection: $objective) {
                        ForEach(GoalObjective.allCases) { goal in
                            Text(label(for: goal))
                                .tag(goal)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .onAppear {
                age = initialInput.age
                heightCm = initialInput.heightCm
                weightKg = initialInput.weightKg
                sex = initialInput.sex
                activityLevel = initialInput.activityLevel
                objective = initialInput.objective
            }
            .keyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(applyButtonTitle) {
                        let input = GoalRecommendationInput(
                            age: age,
                            heightCm: heightCm,
                            weightKg: weightKg,
                            sex: sex,
                            activityLevel: activityLevel,
                            objective: objective
                        )
                        onApply(input)
                    }
                }
            }
            .sheet(isPresented: $showAgePicker) {
                pickerSheet(title: "Age") {
                    Picker("Age", selection: $age) {
                        ForEach(18...90, id: \.self) { value in
                            Text("\(value)")
                                .tag(value)
                        }
                    }
                } onDone: {
                    showAgePicker = false
                }
            }
            .sheet(isPresented: $showHeightPicker) {
                pickerSheet(title: "Height (cm)") {
                    Picker("Height", selection: $heightCm) {
                        ForEach(120...230, id: \.self) { value in
                            Text("\(value)")
                                .tag(Double(value))
                        }
                    }
                } onDone: {
                    showHeightPicker = false
                }
            }
            .sheet(isPresented: $showWeightPicker) {
                pickerSheet(title: "Weight (kg)") {
                    Picker("Weight", selection: $weightKg) {
                        ForEach(40...250, id: \.self) { value in
                            Text("\(value)")
                                .tag(Double(value))
                        }
                    }
                } onDone: {
                    showWeightPicker = false
                }
            }
        }
    }

    private func pickerSheet<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content,
        onDone: @escaping () -> Void
    ) -> some View {
        NavigationStack {
            VStack {
                content()
                    .pickerStyle(.wheel)
                    .labelsHidden()
            }
            .presentationDetents([.height(260)])
            .presentationDragIndicator(.visible)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone()
                    }
                }
            }
        }
    }

    private func label(for level: ActivityLevel) -> String {
        switch level {
        case .sedentary:
            return "Sedentary"
        case .lowActive:
            return "Low Active"
        case .active:
            return "Active"
        case .veryActive:
            return "Very Active"
        }
    }

    private func label(for objective: GoalObjective) -> String {
        switch objective {
        case .loseWeight:
            return "Lose Weight"
        case .maintainWeight:
            return "Maintain"
        case .gainWeight:
            return "Gain Weight"
        case .muscle:
            return "Muscle"
        }
    }
}
