import SwiftUI

struct ArchiveView: View {
    var sessions: [DeepWorkSession]
    var leadEvents: [LeadMeasureEvent]
    var profiles: [Profile]
    var measures: [LeadMeasure]

    private var combinedGoalMinutes: Int {
        max(60, profiles.reduce(0) { $0 + $1.weeklyGoalHours } * 60)
    }

    var weeks: [DateInterval] {
        let calendar = Calendar.current
        let sessionStarts = sessions.map { StatsEngine.weekInterval(containing: $0.date).start }
        let eventStarts = leadEvents.map { StatsEngine.weekInterval(containing: $0.date).start }
        let starts = Set(sessionStarts + eventStarts)
        let current = StatsEngine.weekInterval().start
        let allStarts = (starts.union([current])).sorted(by: >)
        return allStarts.map { DateInterval(start: $0, end: calendar.date(byAdding: .day, value: 7, to: $0)!) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(weeks, id: \.start) { week in
                        let stats = StatsEngine.stats(sessions: sessions, leadEvents: leadEvents, measures: measures, interval: week, goalMinutes: combinedGoalMinutes)
                        VStack(alignment: .leading, spacing: 12) {
                            ForestCanvasView(progress: stats.progress, activeDays: stats.activeDays, seed: Int(week.start.timeIntervalSince1970 / 86400))
                                .frame(height: 170)
                            Text(weekTitle(week)).font(.headline)
                            Text("\(stats.hoursText) / \(combinedGoalMinutes / 60)h · \(stats.sessions) sessions · \(stats.activeDays) active days")
                                .foregroundStyle(.secondary)
                            if profiles.count > 1 {
                                Text(profileSplit(for: week))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Forest Archive")
        }
    }

    private func profileSplit(for week: DateInterval) -> String {
        profiles.map { profile in
            let stats = StatsEngine.stats(sessions: sessions, leadEvents: leadEvents, measures: measures, interval: week, goalMinutes: profile.weeklyGoalHours * 60, profileId: profile.id)
            return "\(profile.name) \(stats.hoursText)"
        }
        .joined(separator: " · ")
    }

    private func weekTitle(_ interval: DateInterval) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "\(f.string(from: interval.start)) – \(f.string(from: interval.end.addingTimeInterval(-1)))"
    }
}
