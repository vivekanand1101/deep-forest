import Foundation

public enum StatsEngine {
    public static func weekInterval(containing date: Date = .now, calendar: Calendar = .current) -> DateInterval {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
        return DateInterval(start: start, end: cal.date(byAdding: .day, value: 7, to: start)!)
    }

    public static func dayInterval(containing date: Date = .now, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start)!)
    }

    /// Pass `profileId` to scope sessions and lead measures to one profile;
    /// nil aggregates across all profiles.
    public static func stats(
        sessions: [DeepWorkSession],
        leadEvents: [LeadMeasureEvent],
        measures: [LeadMeasure],
        interval: DateInterval,
        goalMinutes: Int,
        profileId: UUID? = nil
    ) -> PeriodStats {
        let relevantMeasures = (profileId == nil ? measures : measures.filter { $0.profileId == profileId })
            .sorted { $0.sortOrder < $1.sortOrder }
        let filteredSessions = sessions.filter {
            interval.contains($0.date) && (profileId == nil || $0.profileId == profileId)
        }
        let eventsInInterval = leadEvents.filter { interval.contains($0.date) }
        let minutes = filteredSessions.reduce(0) { $0 + $1.durationMinutes }
        let days = Set(filteredSessions.map { Calendar.current.startOfDay(for: $0.date) })
        let counts = relevantMeasures.map { measure in
            MeasureCount(
                name: measure.name,
                count: max(0, eventsInInterval.filter { $0.measureId == measure.id }.reduce(0) { $0 + $1.delta })
            )
        }
        return PeriodStats(
            minutes: minutes,
            sessions: filteredSessions.count,
            activeDays: days.count,
            goalMinutes: goalMinutes,
            distractions: filteredSessions.reduce(0) { $0 + $1.distractions },
            measures: counts
        )
    }
}
