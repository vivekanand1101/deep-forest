import SwiftUI
import SwiftData

struct ManualEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var profiles: [Profile]
    var defaultProfileId: UUID?

    @State private var date = Date()
    @State private var duration = SessionLength.fortyFive
    @State private var profileSelection: UUID?

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Duration", selection: $duration) {
                    ForEach(SessionLength.allCases) { option in Text(option.label).tag(option) }
                }
                Picker("Profile", selection: $profileSelection) {
                    ForEach(profiles) { profile in Text(profile.name).tag(Optional(profile.id)) }
                }
                Section("Rule") {
                    Text("Manual entries are saved as completed deep work sessions. Short uncompleted sessions are intentionally not tracked.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Session")
            .onAppear {
                if profileSelection == nil { profileSelection = defaultProfileId ?? profiles.first?.id }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        context.insert(DeepWorkSession(date: date, durationMinutes: duration.rawValue, profileId: profileSelection, source: "manual"))
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
