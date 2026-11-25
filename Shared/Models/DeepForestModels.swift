import Foundation
import SwiftUI
import SwiftData

public enum SessionLength: Int, CaseIterable, Identifiable, Codable {
    case twentyFive = 25
    case fortyFive = 45
    case sixty = 60
    case ninety = 90
    case oneTwenty = 120

    public var id: Int { rawValue }
    public var label: String { rawValue == 120 ? "2 hours" : "\(rawValue) min" }
}

/// A Newport-style ritual: each profile carries its own session length,
/// weekly goal, and lead measures.
@Model
public final class Profile {
    public var id: UUID = UUID()
    public var name: String = ""
    public var colorHex: String = "2F6B4F"
    public var sessionMinutes: Int = 45
    public var weeklyGoalHours: Int = 15
    public var sortOrder: Int = 0
    public var createdAt: Date = Date()

    public init(id: UUID = UUID(), name: String, colorHex: String, sessionMinutes: Int = 45, weeklyGoalHours: Int = 15, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sessionMinutes = sessionMinutes
        self.weeklyGoalHours = weeklyGoalHours
        self.sortOrder = sortOrder
        self.createdAt = .now
    }

    public var color: Color { Color(hex: colorHex) }
}

/// A per-profile lead measure ("DSA Done" for Study, "Deep Tasks Done" for Work).
/// Counts still come from append-only LeadMeasureEvent rows so devices merge safely.
@Model
public final class LeadMeasure {
    public var id: UUID = UUID()
    public var profileId: UUID = UUID()
    public var name: String = ""
    public var sortOrder: Int = 0
    public var createdAt: Date = Date()

    public init(id: UUID = UUID(), profileId: UUID, name: String, sortOrder: Int = 0) {
        self.id = id
        self.profileId = profileId
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = .now
    }
}

@Model
public final class DailyBlockType {
    public var id: UUID = UUID()
    public var name: String = ""
    public var profileId: UUID = UUID()
    public var defaultMinutes: Int = 25
    public var defaultNotes: String = ""
    public var sortOrder: Int = 0
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        name: String,
        profileId: UUID,
        defaultMinutes: Int = 25,
        defaultNotes: String = "",
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.profileId = profileId
        self.defaultMinutes = defaultMinutes
        self.defaultNotes = defaultNotes
        self.sortOrder = sortOrder
        self.createdAt = .now
        self.updatedAt = .now
    }
}

@Model
public final class DailyPlanBlock {
    public var id: UUID = UUID()
    public var day: Date = Date()
    public var profileId: UUID = UUID()
    public var blockTypeId: UUID?
    public var title: String = ""
    public var durationMinutes: Int = 25
    public var notes: String = ""
    public var startMinute: Int?
    public var sortOrder: Int = 0
    public var completedAt: Date?
    public var completionSource: String?
    public var linkedSessionId: UUID?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        day: Date,
        profileId: UUID,
        blockTypeId: UUID? = nil,
        title: String,
        durationMinutes: Int,
        notes: String = "",
        startMinute: Int? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.day = Calendar.current.startOfDay(for: day)
        self.profileId = profileId
        self.blockTypeId = blockTypeId
        self.title = title
        self.durationMinutes = durationMinutes
        self.notes = notes
        self.startMinute = startMinute
        self.sortOrder = sortOrder
        self.createdAt = .now
        self.updatedAt = .now
    }
}

@Model
public final class DailyPlanDayNote {
    public var id: UUID = UUID()
    public var day: Date = Date()
    public var text: String = ""
    public var updatedAt: Date = Date()

    public init(id: UUID = UUID(), day: Date, text: String = "") {
        self.id = id
        self.day = Calendar.current.startOfDay(for: day)
        self.text = text
        self.updatedAt = .now
    }
}

@Model
public final class PlanningInboxItem {
    public var id: UUID = UUID()
    public var title: String = ""
    public var sortOrder: Int = 0
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(id: UUID = UUID(), title: String, sortOrder: Int = 0) {
        self.id = id
        self.title = title
        self.sortOrder = sortOrder
        self.createdAt = .now
        self.updatedAt = .now
    }
}

@Model
public final class DeepWorkSession {
    public var id: UUID = UUID()
    public var date: Date = Date()
    public var startedAt: Date?
    public var endedAt: Date?
    public var durationMinutes: Int = 0
    public var profileId: UUID?
    public var planBlockId: UUID?
    public var distractions: Int = 0
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var source: String = "timer"

    public init(
        id: UUID = UUID(),
        date: Date = .now,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        durationMinutes: Int,
        profileId: UUID? = nil,
        planBlockId: UUID? = nil,
        distractions: Int = 0,
        source: String
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMinutes = durationMinutes
        self.profileId = profileId
        self.planBlockId = planBlockId
        self.distractions = distractions
        self.createdAt = .now
        self.updatedAt = .now
        self.source = source
    }
}

@Model
public final class LeadMeasureEvent {
    public var id: UUID = UUID()
    public var date: Date = Date()
    public var measureId: UUID = UUID()
    public var delta: Int = 1
    public var createdAt: Date = Date()
    public var deviceId: String = "unknown"
    public var note: String = ""

    public init(id: UUID = UUID(), date: Date = .now, measureId: UUID, delta: Int, deviceId: String = HostDevice.id, note: String = "") {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.measureId = measureId
        self.delta = delta
        self.createdAt = .now
        self.deviceId = deviceId
        self.note = note
    }
}

public enum HostDevice {
    public static var id: String {
        let key = "deepForest.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }
}

@Model
public final class AppSettings {
    public var id: String = "main"
    public var soundEnabled: Bool = true
    public var activeProfileId: UUID?
    public var lastShutdownAt: Date?

    public init(id: String = "main", soundEnabled: Bool = true, activeProfileId: UUID? = nil, lastShutdownAt: Date? = nil) {
        self.id = id
        self.soundEnabled = soundEnabled
        self.activeProfileId = activeProfileId
        self.lastShutdownAt = lastShutdownAt
    }

    public var shutdownCompletedToday: Bool {
        guard let lastShutdownAt else { return false }
        return Calendar.current.isDateInToday(lastShutdownAt)
    }
}

/// Newport's observed ceiling for trained deep workers: ~4 hours of depth per day.
public enum DepthCap {
    public static let dailyMinutes = 240
}

public struct MeasureCount: Codable, Equatable {
    public var name: String
    public var count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

public struct PeriodStats: Codable, Equatable {
    public var minutes: Int
    public var sessions: Int
    public var activeDays: Int
    public var goalMinutes: Int
    public var distractions: Int
    public var measures: [MeasureCount]

    public init(minutes: Int = 0, sessions: Int = 0, activeDays: Int = 0, goalMinutes: Int = 900, distractions: Int = 0, measures: [MeasureCount] = []) {
        self.minutes = minutes
        self.sessions = sessions
        self.activeDays = activeDays
        self.goalMinutes = goalMinutes
        self.distractions = distractions
        self.measures = measures
    }

    public var progress: Double { goalMinutes == 0 ? 0 : min(Double(minutes) / Double(goalMinutes), 1.0) }
    public var hoursText: String { Self.format(minutes) }

    public static func format(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }
}

public enum DefaultData {
    /// Idempotent first-launch seeding: settings row plus Work/Study profiles
    /// with their starter lead measures.
    public static func ensureSeeded(context: ModelContext) {
        let settings = (try? context.fetch(FetchDescriptor<AppSettings>()))?.first ?? {
            let created = AppSettings()
            context.insert(created)
            return created
        }()

        let profiles = (try? context.fetch(FetchDescriptor<Profile>())) ?? []
        if profiles.isEmpty {
            let work = Profile(name: "Work", colorHex: "2F6B4F", sessionMinutes: 90, weeklyGoalHours: 15, sortOrder: 0)
            let study = Profile(name: "Study", colorHex: "3A6EA5", sessionMinutes: 45, weeklyGoalHours: 10, sortOrder: 1)
            context.insert(work)
            context.insert(study)
            context.insert(LeadMeasure(profileId: work.id, name: "Deep Tasks Done", sortOrder: 0))
            context.insert(LeadMeasure(profileId: study.id, name: "DSA Done", sortOrder: 0))
            context.insert(LeadMeasure(profileId: study.id, name: "DSA Revised", sortOrder: 1))
            settings.activeProfileId = work.id
        } else if settings.activeProfileId == nil {
            settings.activeProfileId = profiles.sorted(by: { $0.sortOrder < $1.sortOrder }).first?.id
        }

        try? context.save()
    }
}

public extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
