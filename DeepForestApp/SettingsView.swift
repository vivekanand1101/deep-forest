import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Bindable var settings: AppSettings
    var sessions: [DeepWorkSession]
    var leadEvents: [LeadMeasureEvent]
    var profiles: [Profile]
    var measures: [LeadMeasure]

    @Query private var blockTypes: [DailyBlockType]
    @Query private var planBlocks: [DailyPlanBlock]
    @Query private var planDayNotes: [DailyPlanDayNote]
    @Query private var planningInbox: [PlanningInboxItem]

    @State private var exporting = false
    @State private var importing = false
    @State private var exportDocument = DeepForestDocument()
    @State private var syncMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    Toggle("Completion sound", isOn: $settings.soundEnabled)
                        .onChange(of: settings.soundEnabled) { _, _ in try? context.save() }
                }

                ForEach(profiles) { profile in
                    ProfileSettingsSection(
                        profile: profile,
                        measures: measures.filter { $0.profileId == profile.id }.sorted { $0.sortOrder < $1.sortOrder },
                        canDelete: profiles.count > 1,
                        onDelete: { delete(profile) }
                    )
                }

                Section {
                    Button {
                        addProfile()
                    } label: {
                        Label("Add Profile", systemImage: "plus")
                    }
                }

                Section("Free Sync") {
                    Text("CloudKit needs a paid Apple Developer account. This free version syncs by exporting/importing one JSON file through iCloud Drive/Files.")
                        .foregroundStyle(.secondary)
                    Button {
                        prepareExport()
                        exporting = true
                    } label: {
                        Label("Export to iCloud Drive", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("Import/Merge from iCloud Drive", systemImage: "square.and.arrow.down")
                    }
                    if let syncMessage {
                        Text(syncMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .fileExporter(
                isPresented: $exporting,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "deepforest-sync.json"
            ) { result in
                switch result {
                case .success: syncMessage = "Exported. Save it in iCloud Drive, then import it on your other device."
                case .failure(let error): syncMessage = "Export failed: \(error.localizedDescription)"
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): importBackup(from: url)
                case .failure(let error): syncMessage = "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func addProfile() {
        let nextOrder = (profiles.map(\.sortOrder).max() ?? -1) + 1
        let profile = Profile(name: "New Profile", colorHex: "8A5A2B", sessionMinutes: 45, weeklyGoalHours: 10, sortOrder: nextOrder)
        context.insert(profile)
        try? context.save()
    }

    private func delete(_ profile: Profile) {
        let pid = profile.id
        for measure in measures where measure.profileId == pid {
            let mid = measure.id
            try? context.delete(model: LeadMeasureEvent.self, where: #Predicate { $0.measureId == mid })
            context.delete(measure)
        }
        context.delete(profile)
        if settings.activeProfileId == pid {
            settings.activeProfileId = profiles.first(where: { $0.id != pid })?.id
        }
        try? context.save()
    }

    private func prepareExport() {
        let backup = DeepForestBackup(
            profiles: profiles.map(ProfileBackup.init),
            measures: measures.map(MeasureBackup.init),
            sessions: sessions.map(SessionBackup.init),
            leadEvents: leadEvents.map(LeadEventBackup.init),
            settings: SettingsBackup(settings),
            blockTypes: blockTypes.map(BlockTypeBackup.init),
            planBlocks: planBlocks.map(PlanBlockBackup.init),
            planDayNotes: planDayNotes.map(PlanDayNoteBackup.init),
            planningInbox: planningInbox.map(PlanningInboxBackup.init)
        )
        do {
            exportDocument = DeepForestDocument(data: try BackupCoding.encoder.encode(backup))
        } catch {
            syncMessage = "Could not prepare export: \(error.localizedDescription)"
        }
    }

    private func importBackup(from url: URL) {
        do {
            let allowed = url.startAccessingSecurityScopedResource()
            defer { if allowed { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            let backup = try BackupCoding.decoder.decode(DeepForestBackup.self, from: data)

            let existingProfileIds = Set(profiles.map(\.id))
            let existingMeasureIds = Set(measures.map(\.id))
            let existingSessionIds = Set(sessions.map(\.id))
            let existingEventIds = Set(leadEvents.map(\.id))
            let existingBlockTypeIds = Set(blockTypes.map(\.id))
            let existingPlanBlockIds = Set(planBlocks.map(\.id))
            let existingPlanDayNoteIds = Set(planDayNotes.map(\.id))
            let existingPlanningInboxIds = Set(planningInbox.map(\.id))
            var added = (profiles: 0, measures: 0, sessions: 0, events: 0, blockTypes: 0, planBlocks: 0, planNotes: 0, inbox: 0)

            for item in backup.profiles where !existingProfileIds.contains(item.id) {
                let profile = Profile(id: item.id, name: item.name, colorHex: item.colorHex, sessionMinutes: item.sessionMinutes, weeklyGoalHours: item.weeklyGoalHours, sortOrder: item.sortOrder)
                profile.createdAt = item.createdAt
                context.insert(profile)
                added.profiles += 1
            }

            for item in backup.measures where !existingMeasureIds.contains(item.id) {
                let measure = LeadMeasure(id: item.id, profileId: item.profileId, name: item.name, sortOrder: item.sortOrder)
                measure.createdAt = item.createdAt
                context.insert(measure)
                added.measures += 1
            }

            for item in backup.sessions where !existingSessionIds.contains(item.id) {
                let session = DeepWorkSession(
                    id: item.id,
                    date: item.date,
                    startedAt: item.startedAt,
                    endedAt: item.endedAt,
                    durationMinutes: item.durationMinutes,
                    profileId: item.profileId,
                    planBlockId: item.planBlockId,
                    distractions: item.distractions,
                    source: item.source
                )
                session.createdAt = item.createdAt
                session.updatedAt = item.updatedAt
                context.insert(session)
                added.sessions += 1
            }

            for item in backup.leadEvents where !existingEventIds.contains(item.id) {
                let event = LeadMeasureEvent(
                    id: item.id,
                    date: item.date,
                    measureId: item.measureId,
                    delta: item.delta,
                    deviceId: item.deviceId,
                    note: item.note
                )
                event.createdAt = item.createdAt
                context.insert(event)
                added.events += 1
            }

            for item in backup.blockTypes ?? [] where !existingBlockTypeIds.contains(item.id) {
                let type = DailyBlockType(
                    id: item.id,
                    name: item.name,
                    profileId: item.profileId,
                    defaultMinutes: item.defaultMinutes,
                    defaultNotes: item.defaultNotes,
                    sortOrder: item.sortOrder
                )
                type.createdAt = item.createdAt
                type.updatedAt = item.updatedAt
                context.insert(type)
                added.blockTypes += 1
            }

            for item in backup.planBlocks ?? [] where !existingPlanBlockIds.contains(item.id) {
                let block = DailyPlanBlock(
                    id: item.id,
                    day: item.day,
                    profileId: item.profileId,
                    blockTypeId: item.blockTypeId,
                    title: item.title,
                    durationMinutes: item.durationMinutes,
                    notes: item.notes,
                    startMinute: item.startMinute,
                    sortOrder: item.sortOrder
                )
                block.completedAt = item.completedAt
                block.completionSource = item.completionSource
                block.linkedSessionId = item.linkedSessionId
                block.createdAt = item.createdAt
                block.updatedAt = item.updatedAt
                context.insert(block)
                added.planBlocks += 1
            }

            for item in backup.planDayNotes ?? [] where !existingPlanDayNoteIds.contains(item.id) {
                let note = DailyPlanDayNote(id: item.id, day: item.day, text: item.text)
                note.updatedAt = item.updatedAt
                context.insert(note)
                added.planNotes += 1
            }

            for item in backup.planningInbox ?? [] where !existingPlanningInboxIds.contains(item.id) {
                let inboxItem = PlanningInboxItem(id: item.id, title: item.title, sortOrder: item.sortOrder)
                inboxItem.createdAt = item.createdAt
                inboxItem.updatedAt = item.updatedAt
                context.insert(inboxItem)
                added.inbox += 1
            }

            settings.soundEnabled = backup.settings.soundEnabled
            try context.save()
            syncMessage = "Merged \(added.sessions) sessions, \(added.planBlocks) plan blocks, \(added.inbox) inbox items, \(added.blockTypes) block types, \(added.events) lead-measure events, \(added.profiles) profiles, and \(added.measures) measures."
        } catch {
            syncMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}

private struct ProfileSettingsSection: View {
    @Environment(\.modelContext) private var context
    @Bindable var profile: Profile
    var measures: [LeadMeasure]
    var canDelete: Bool
    var onDelete: () -> Void

    @State private var newMeasureName = ""

    private var trimmedName: String { newMeasureName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Section("Profile: \(profile.name)") {
            TextField("Name", text: $profile.name)
                .onSubmit { try? context.save() }
            Picker("Session duration", selection: $profile.sessionMinutes) {
                ForEach(SessionLength.allCases) { option in Text(option.label).tag(option.rawValue) }
            }
            Stepper("Weekly goal: \(profile.weeklyGoalHours) hours", value: $profile.weeklyGoalHours, in: 1...80)

            ForEach(measures) { measure in
                HStack {
                    Text(measure.name)
                    Spacer()
                    Button(role: .destructive) {
                        deleteMeasure(measure)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            HStack {
                TextField("New lead measure", text: $newMeasureName)
                    .onSubmit { addMeasure() }
                Button("Add") { addMeasure() }
                    .disabled(trimmedName.isEmpty)
            }

            if canDelete {
                Button("Delete Profile", role: .destructive) { onDelete() }
            }
        }
        .onChange(of: profile.sessionMinutes) { _, _ in try? context.save() }
        .onChange(of: profile.weeklyGoalHours) { _, _ in try? context.save() }
    }

    private func addMeasure() {
        guard !trimmedName.isEmpty else { return }
        let nextOrder = (measures.map(\.sortOrder).max() ?? -1) + 1
        context.insert(LeadMeasure(profileId: profile.id, name: trimmedName, sortOrder: nextOrder))
        newMeasureName = ""
        try? context.save()
    }

    private func deleteMeasure(_ measure: LeadMeasure) {
        let mid = measure.id
        try? context.delete(model: LeadMeasureEvent.self, where: #Predicate { $0.measureId == mid })
        context.delete(measure)
        try? context.save()
    }
}
