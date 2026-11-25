import Foundation
import SwiftUI
import UniformTypeIdentifiers

public struct DeepForestBackup: Codable {
    public var version: Int
    public var exportedAt: Date
    public var profiles: [ProfileBackup]
    public var measures: [MeasureBackup]
    public var sessions: [SessionBackup]
    public var leadEvents: [LeadEventBackup]
    public var settings: SettingsBackup
    public var blockTypes: [BlockTypeBackup]?
    public var planBlocks: [PlanBlockBackup]?
    public var planDayNotes: [PlanDayNoteBackup]?
    public var planningInbox: [PlanningInboxBackup]?

    public init(
        exportedAt: Date = .now,
        profiles: [ProfileBackup],
        measures: [MeasureBackup],
        sessions: [SessionBackup],
        leadEvents: [LeadEventBackup],
        settings: SettingsBackup,
        blockTypes: [BlockTypeBackup] = [],
        planBlocks: [PlanBlockBackup] = [],
        planDayNotes: [PlanDayNoteBackup] = [],
        planningInbox: [PlanningInboxBackup] = []
    ) {
        self.version = 4
        self.exportedAt = exportedAt
        self.profiles = profiles
        self.measures = measures
        self.sessions = sessions
        self.leadEvents = leadEvents
        self.settings = settings
        self.blockTypes = blockTypes
        self.planBlocks = planBlocks
        self.planDayNotes = planDayNotes
        self.planningInbox = planningInbox
    }
}

public struct ProfileBackup: Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public var sessionMinutes: Int
    public var weeklyGoalHours: Int
    public var sortOrder: Int
    public var createdAt: Date

    public init(_ profile: Profile) {
        self.id = profile.id
        self.name = profile.name
        self.colorHex = profile.colorHex
        self.sessionMinutes = profile.sessionMinutes
        self.weeklyGoalHours = profile.weeklyGoalHours
        self.sortOrder = profile.sortOrder
        self.createdAt = profile.createdAt
    }
}

public struct MeasureBackup: Codable, Identifiable {
    public var id: UUID
    public var profileId: UUID
    public var name: String
    public var sortOrder: Int
    public var createdAt: Date

    public init(_ measure: LeadMeasure) {
        self.id = measure.id
        self.profileId = measure.profileId
        self.name = measure.name
        self.sortOrder = measure.sortOrder
        self.createdAt = measure.createdAt
    }
}

public struct SessionBackup: Codable, Identifiable {
    public var id: UUID
    public var date: Date
    public var startedAt: Date?
    public var endedAt: Date?
    public var durationMinutes: Int
    public var profileId: UUID?
    public var planBlockId: UUID?
    public var distractions: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var source: String

    public init(_ session: DeepWorkSession) {
        self.id = session.id
        self.date = session.date
        self.startedAt = session.startedAt
        self.endedAt = session.endedAt
        self.durationMinutes = session.durationMinutes
        self.profileId = session.profileId
        self.planBlockId = session.planBlockId
        self.distractions = session.distractions
        self.createdAt = session.createdAt
        self.updatedAt = session.updatedAt
        self.source = session.source
    }
}

public struct LeadEventBackup: Codable, Identifiable {
    public var id: UUID
    public var date: Date
    public var measureId: UUID
    public var delta: Int
    public var createdAt: Date
    public var deviceId: String
    public var note: String

    public init(_ event: LeadMeasureEvent) {
        self.id = event.id
        self.date = event.date
        self.measureId = event.measureId
        self.delta = event.delta
        self.createdAt = event.createdAt
        self.deviceId = event.deviceId
        self.note = event.note
    }
}

public struct BlockTypeBackup: Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var profileId: UUID
    public var defaultMinutes: Int
    public var defaultNotes: String
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(_ type: DailyBlockType) {
        id = type.id
        name = type.name
        profileId = type.profileId
        defaultMinutes = type.defaultMinutes
        defaultNotes = type.defaultNotes
        sortOrder = type.sortOrder
        createdAt = type.createdAt
        updatedAt = type.updatedAt
    }
}

public struct PlanBlockBackup: Codable, Identifiable {
    public var id: UUID
    public var day: Date
    public var profileId: UUID
    public var blockTypeId: UUID?
    public var title: String
    public var durationMinutes: Int
    public var notes: String
    public var startMinute: Int?
    public var sortOrder: Int
    public var completedAt: Date?
    public var completionSource: String?
    public var linkedSessionId: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(_ block: DailyPlanBlock) {
        id = block.id
        day = block.day
        profileId = block.profileId
        blockTypeId = block.blockTypeId
        title = block.title
        durationMinutes = block.durationMinutes
        notes = block.notes
        startMinute = block.startMinute
        sortOrder = block.sortOrder
        completedAt = block.completedAt
        completionSource = block.completionSource
        linkedSessionId = block.linkedSessionId
        createdAt = block.createdAt
        updatedAt = block.updatedAt
    }
}

public struct PlanDayNoteBackup: Codable, Identifiable {
    public var id: UUID
    public var day: Date
    public var text: String
    public var updatedAt: Date

    public init(_ note: DailyPlanDayNote) {
        id = note.id
        day = note.day
        text = note.text
        updatedAt = note.updatedAt
    }
}

public struct PlanningInboxBackup: Codable, Identifiable {
    public var id: UUID
    public var title: String
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(_ item: PlanningInboxItem) {
        id = item.id
        title = item.title
        sortOrder = item.sortOrder
        createdAt = item.createdAt
        updatedAt = item.updatedAt
    }
}

public struct SettingsBackup: Codable {
    public var soundEnabled: Bool
    public var activeProfileId: UUID?
    public var lastShutdownAt: Date?

    public init(_ settings: AppSettings) {
        self.soundEnabled = settings.soundEnabled
        self.activeProfileId = settings.activeProfileId
        self.lastShutdownAt = settings.lastShutdownAt
    }
}

public struct DeepForestDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.json] }
    public var data: Data

    public init(data: Data = Data()) { self.data = data }

    public init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

public enum BackupCoding {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
