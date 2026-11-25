import SwiftUI
import SwiftData

/// Newport's end-of-day shutdown ritual: review the day, plan tomorrow's
/// depth, close the loops, then declare the day done — and mean it.
struct ShutdownView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var settings: AppSettings
    var todayStats: PeriodStats

    @State private var reviewedDay = false
    @State private var plannedTomorrow = false
    @State private var closedLoops = false

    private var allChecked: Bool { reviewedDay && plannedTomorrow && closedLoops }

    var body: some View {
        NavigationStack {
            Form {
                Section("Today") {
                    Text("\(todayStats.hoursText) deep · \(todayStats.sessions) sessions · \(todayStats.distractions) urges resisted")
                }
                Section("Ritual") {
                    Toggle("Reviewed today's sessions and open loops", isOn: $reviewedDay)
                    Toggle("Sketched tomorrow's deep blocks", isOn: $plannedTomorrow)
                    Toggle("Closed every work app, tab, and notification", isOn: $closedLoops)
                }
                Section {
                    Button("Shutdown Complete") {
                        settings.lastShutdownAt = .now
                        try? context.save()
                        if settings.soundEnabled { playCompletionFeedback() }
                        dismiss()
                    }
                    .disabled(!allChecked)
                    Text("Say it and mean it: no more work thoughts until tomorrow.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Shutdown Ritual")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not Yet") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 380)
        #endif
    }
}
