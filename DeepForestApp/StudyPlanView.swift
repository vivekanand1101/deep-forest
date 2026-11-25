import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct StudyPlanView: View {
    var sessions: [DeepWorkSession]
    var profiles: [Profile]

    @Environment(\.modelContext) private var context
    @Query private var storedBlocks: [DailyPlanBlock]
    @Query private var blockTypes: [DailyBlockType]
    @Query private var dayNotes: [DailyPlanDayNote]
    @Query private var planningInboxItems: [PlanningInboxItem]

    @AppStorage("deepForest.studyPlans") private var legacyStoredPlans = "{}"
    @AppStorage("deepForest.dailyPlanMigrationVersion") private var migrationVersion = 0

    @State private var date = Date()
    @State private var profileFilter: UUID?
    @State private var presentedSheet: PlanSheet?
    @State private var timerAction: TimerAction?
    @State private var operationError: String?
    @State private var draggedBlockID: UUID?
    @State private var blockPendingDeletionID: UUID?
    @State private var planningInboxDraft = ""
    @State private var showingCalendar = false
    @State private var copiedBlockID: UUID?

    private let timer = TimerController.shared

    private enum PlanSheet: Identifiable {
        case addBlock
        case customBlock
        case newFromType(UUID)
        case editBlock(UUID)
        case manageTypes
        case editInboxItem(UUID)
        case planInboxItem(UUID)
        case doneNotes

        var id: String {
            switch self {
            case .addBlock: "add"
            case .customBlock: "custom"
            case .newFromType(let id): "new-type-\(id)"
            case .editBlock(let id): "edit-\(id)"
            case .manageTypes: "types"
            case .editInboxItem(let id): "edit-inbox-\(id)"
            case .planInboxItem(let id): "inbox-\(id)"
            case .doneNotes: "notes"
            }
        }
    }

    private enum TimerAction: String, Identifiable {
        case restart = "Restart Block"
        case cancel = "Cancel Block"
        var id: Self { self }
    }

    private var selectedDay: Date { Calendar.current.startOfDay(for: date) }

    private var dayBlocks: [DailyPlanBlock] {
        storedBlocks
            .filter { Calendar.current.isDate($0.day, inSameDayAs: selectedDay) }
            .sorted { lhs, rhs in
                lhs.sortOrder == rhs.sortOrder ? lhs.createdAt < rhs.createdAt : lhs.sortOrder < rhs.sortOrder
            }
    }

    private var displayedBlocks: [DailyPlanBlock] {
        guard let profileFilter else { return dayBlocks }
        return dayBlocks.filter { $0.profileId == profileFilter }
    }

    private var selectedDayNote: DailyPlanDayNote? {
        dayNotes.first { Calendar.current.isDate($0.day, inSameDayAs: selectedDay) }
    }

    private var sortedPlanningInboxItems: [PlanningInboxItem] {
        planningInboxItems.sorted { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.createdAt < rhs.createdAt : lhs.sortOrder < rhs.sortOrder
        }
    }

    var body: some View {
        let completedMinutes = dayBlocks.filter { $0.completedAt != nil }.reduce(0) { $0 + $1.durationMinutes }
        let plannedMinutes = dayBlocks.reduce(0) { $0 + $1.durationMinutes }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    overview(completedMinutes: completedMinutes, plannedMinutes: plannedMinutes)

                    if profiles.count > 1 {
                        Picker("Profile filter", selection: $profileFilter) {
                            Text("All").tag(nil as UUID?)
                            ForEach(profiles) { profile in
                                Text(profile.name).tag(Optional(profile.id))
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    planningInboxCard

                    HStack {
                        Text("Blocks").font(.headline)
                        Spacer()
                        Button {
                            presentedSheet = .addBlock
                        } label: {
                            Label("Add Block", systemImage: "plus")
                        }
                        .buttonStyle(StudyButtonStyle(.primary, compact: true))
                        .disabled(profiles.isEmpty)
                    }

                    if displayedBlocks.isEmpty {
                        ContentUnavailableView(
                            profileFilter == nil ? "No blocks planned" : "No blocks for this profile",
                            systemImage: "calendar.badge.plus",
                            description: Text("Add a reusable block type or create a custom block.")
                        )
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(displayedBlocks.enumerated()), id: \.element.id) { index, block in
                                blockCard(block, displayIndex: index)
                                    .onDrop(
                                        of: [UTType.text],
                                        delegate: PlanBlockDropDelegate(
                                            destinationID: block.id,
                                            draggedID: $draggedBlockID,
                                            move: moveBlock
                                        )
                                    )
                            }
                        }
                    }

                    doneCard
                }
                .frame(maxWidth: 760)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background(Color.green.opacity(0.045))
            .safeAreaInset(edge: .top, spacing: 0) {
                if let activeID = timer.planBlockID {
                    activeBlock(activeID)
                }
            }
            .navigationTitle("Daily Plan")
        }
        .onAppear { migrateLegacyPlansIfNeeded() }
        .sheet(item: $presentedSheet) { sheet in
            sheetContent(sheet)
        }
        .alert("Couldn’t update the plan", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(operationError ?? "Please try again.")
        }
        .alert("Delete Block?", isPresented: Binding(
            get: { blockPendingDeletionID != nil },
            set: { if !$0 { blockPendingDeletionID = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let id = blockPendingDeletionID,
                   let block = storedBlocks.first(where: { $0.id == id }) {
                    delete(block)
                }
                blockPendingDeletionID = nil
            }
            Button("Cancel", role: .cancel) { blockPendingDeletionID = nil }
        } message: {
            Text("This removes the block from the Daily Plan. Any work already logged in the forest will remain.")
        }
        .alert(timerAction?.rawValue ?? "", isPresented: Binding(
            get: { timerAction != nil },
            set: { if !$0 { timerAction = nil } }
        ), presenting: timerAction) { action in
            Button(action == .restart ? "Restart" : "Discard and Cancel", role: .destructive) {
                guard timer.planBlockID != nil else { return }
                if action == .restart { timer.restart() } else { timer.cancel() }
                timerAction = nil
            }
            Button("Keep Block", role: .cancel) { timerAction = nil }
        } message: { action in
            Text(action == .restart
                 ? "Start this block again from the full duration?"
                 : "Discard the time spent on this attempt? The block will stay in your plan.")
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: PlanSheet) -> some View {
        switch sheet {
        case .addBlock:
            BlockPickerSheet(
                blockTypes: blockTypes.sorted { $0.sortOrder < $1.sortOrder },
                profiles: profiles,
                addType: { type in presentedSheet = .newFromType(type.id) },
                createCustom: { presentedSheet = .customBlock },
                manageTypes: { presentedSheet = .manageTypes }
            )
        case .customBlock:
            BlockEditorSheet(
                title: "Custom Block",
                profiles: profiles,
                otherBlocks: dayBlocks,
                initial: BlockDraft(profileId: profileFilter ?? profiles.first?.id)
            ) { draft in
                createBlock(from: draft)
            }
        case .newFromType(let id):
            if let type = blockTypes.first(where: { $0.id == id }) {
                BlockEditorSheet(
                    title: "Customize Block",
                    profiles: profiles,
                    otherBlocks: dayBlocks,
                    initial: BlockDraft(type)
                ) { draft in
                    createBlock(from: draft, blockTypeId: type.id)
                }
            } else {
                ContentUnavailableView("Block type not found", systemImage: "exclamationmark.triangle")
            }
        case .editBlock(let id):
            if let block = storedBlocks.first(where: { $0.id == id }) {
                BlockEditorSheet(
                    title: "Edit Block",
                    profiles: profiles,
                    otherBlocks: dayBlocks.filter { $0.id != id },
                    initial: BlockDraft(block)
                ) { draft in
                    update(block, from: draft)
                }
            } else {
                ContentUnavailableView("Block not found", systemImage: "exclamationmark.triangle")
            }
        case .manageTypes:
            BlockTypeManagerSheet(profiles: profiles)
        case .editInboxItem(let id):
            if let item = planningInboxItems.first(where: { $0.id == id }) {
                PlanningInboxEditorSheet(content: item.title) { content in
                    updatePlanningInboxItem(item, content: content)
                }
            } else {
                ContentUnavailableView("Inbox item not found", systemImage: "exclamationmark.triangle")
            }
        case .planInboxItem(let id):
            if let item = planningInboxItems.first(where: { $0.id == id }) {
                BlockEditorSheet(
                    title: "Plan Inbox Item",
                    profiles: profiles,
                    otherBlocks: dayBlocks,
                    initial: BlockDraft(inboxContent: item.title, profileId: profileFilter ?? profiles.first?.id)
                ) { draft in
                    createBlock(from: draft, removing: item)
                }
            } else {
                ContentUnavailableView("Inbox item not found", systemImage: "exclamationmark.triangle")
            }
        case .doneNotes:
            DayNotesSheet(text: selectedDayNote?.text ?? "") { text in
                saveDayNotes(text)
            }
        }
    }

    private func overview(completedMinutes: Int, plannedMinutes: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    dateControls
                    Spacer(minLength: 18)
                    Label("DAILY PLAN", systemImage: "leaf.fill")
                        .font(.caption.bold()).tracking(1.2)
                }
                dateControls
            }
            Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(.largeTitle, design: .rounded).bold())
            HStack(alignment: .firstTextBaseline) {
                Text(PeriodStats.format(plannedMinutes)).font(.title2.bold())
                Text("planned · \(dayBlocks.count) blocks")
            }
            if plannedMinutes > 0 {
                ProgressView(value: Double(completedMinutes), total: Double(plannedMinutes))
                    .tint(Color(red: 0.67, green: 0.90, blue: 0.70))
                    .accessibilityLabel("Plan progress")
                Text("\(PeriodStats.format(completedMinutes)) of \(PeriodStats.format(plannedMinutes)) completed")
                    .font(.subheadline)
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.24, blue: 0.19), Color(red: 0.16, green: 0.34, blue: 0.32)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    private var dateControls: some View {
        HStack(spacing: 8) {
            Button {
                moveSelectedDate(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 18)
            }
            .accessibilityLabel("Previous day")
            .keyboardShortcut(.leftArrow, modifiers: [.command])

            Button {
                showingCalendar = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                    Text(date.formatted(.dateTime.day().month(.abbreviated).year()))
                        .monospacedDigit()
                }
            }
            .sheet(isPresented: $showingCalendar) {
                PlanCalendarPicker(date: $date) {
                    showingCalendar = false
                }
            }
            .accessibilityLabel("Choose plan date")

            Button {
                moveSelectedDate(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 18)
            }
            .accessibilityLabel("Next day")
            .keyboardShortcut(.rightArrow, modifiers: [.command])

            Button("Today") {
                withAnimation { date = .now }
            }
            .disabled(Calendar.current.isDateInToday(date))
        }
        .buttonStyle(StudyButtonStyle(.onHero, compact: true))
    }

    private func moveSelectedDate(by days: Int) {
        guard let moved = Calendar.current.date(byAdding: .day, value: days, to: date) else { return }
        withAnimation { date = moved }
    }

    private var planningInboxCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "tray.full.fill")
                    .font(.headline)
                    .foregroundStyle(Color(red: 0.16, green: 0.48, blue: 0.36))
                    .frame(width: 40, height: 40)
                    .background(Color.green.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text("Planning Inbox").font(.headline)
                        if !sortedPlanningInboxItems.isEmpty {
                            Text("\(sortedPlanningInboxItems.count)")
                                .font(.caption2.bold())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.13), in: Capsule())
                        }
                    }
                    Text("Dump it here now. Decide when and how to do it later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(alignment: .bottom, spacing: 10) {
                planningInboxInput
            }

            if sortedPlanningInboxItems.isEmpty {
                Text("Nothing waiting to be planned.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(sortedPlanningInboxItems) { item in
                        planningInboxRow(item)
                    }
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Color.green.opacity(0.16)) }
    }

    @ViewBuilder
    private var planningInboxInput: some View {
        ZStack(alignment: .topLeading) {
            if planningInboxDraft.isEmpty {
                Text("Capture a thought, link, list, or Markdown note…")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 13)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $planningInboxDraft)
                .font(.body)
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(7)
                .accessibilityLabel("Planning inbox content")
        }
        .frame(minHeight: 74, maxHeight: 130)
        .background(.background.opacity(0.82), in: RoundedRectangle(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(Color.primary.opacity(0.1)) }

        Button {
            addPlanningInboxItem()
        } label: {
            Label("Capture", systemImage: "arrow.down.to.line")
        }
        .buttonStyle(StudyButtonStyle(.primary, compact: true))
        .disabled(planningInboxDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func planningInboxRow(_ item: PlanningInboxItem) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                planningInboxItemLabel(item)
                Spacer()
                planningInboxActions(item)
            }
            VStack(alignment: .leading, spacing: 10) {
                planningInboxItemLabel(item)
                HStack { Spacer(); planningInboxActions(item) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.032), in: RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button("Edit", systemImage: "pencil") { presentedSheet = .editInboxItem(item.id) }
            Button("Plan", systemImage: "calendar.badge.plus") { presentedSheet = .planInboxItem(item.id) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { deletePlanningInboxItem(item) }
        }
    }

    private func planningInboxItemLabel(_ item: PlanningInboxItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.dashed")
                .font(.subheadline)
                .foregroundStyle(.green)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                renderedNotes(item.title)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Captured \(item.createdAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func planningInboxActions(_ item: PlanningInboxItem) -> some View {
        HStack(spacing: 7) {
            Button {
                presentedSheet = .editInboxItem(item.id)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(StudyButtonStyle(.secondary, compact: true))

            Button {
                presentedSheet = .planInboxItem(item.id)
            } label: {
                Label("Plan", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(StudyButtonStyle(.secondary, compact: true))

            Button(role: .destructive) {
                deletePlanningInboxItem(item)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .padding(7)
            .accessibilityLabel("Delete \(item.title)")
        }
    }

    private func activeBlock(_ id: UUID) -> some View {
        let block = storedBlocks.first { $0.id == id }
        let title = block?.title ?? "Focus Block"
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label(timer.isPaused ? "PAUSED" : "IN FOCUS", systemImage: timer.isPaused ? "pause.fill" : "leaf.fill")
                        .font(.caption.bold()).tracking(1.2)
                        .foregroundStyle(timer.isPaused ? Color.orange : Color.green)
                    Text(title).font(.headline)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let remaining = timer.remainingSeconds(at: timeline.date)
                    VStack(alignment: .trailing) {
                        Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))
                            .font(.system(size: 38, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        ProgressView(value: Double(remaining), total: Double(max(timer.plannedMinutes * 60, 1)))
                            .tint(timer.isPaused ? .orange : .green)
                            .frame(width: 96)
                    }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack { timerControls }
                VStack(alignment: .leading) { timerControls }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Color.green.opacity(0.25)) }
        .frame(maxWidth: 760)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder
    private var timerControls: some View {
        Button {
            if timer.isPaused { timer.resume() } else { timer.pause() }
        } label: {
            Label(timer.isPaused ? "Resume" : "Pause", systemImage: timer.isPaused ? "play.fill" : "pause.fill")
        }
        .buttonStyle(StudyButtonStyle(timer.isPaused ? .primary : .pause))

        Button { timerAction = .restart } label: {
            Label("Restart", systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(StudyButtonStyle(.secondary))

        Button(role: .destructive) { timerAction = .cancel } label: {
            Label("Cancel Block", systemImage: "xmark")
        }
        .buttonStyle(StudyButtonStyle(.danger))
    }

    private func blockCard(_ block: DailyPlanBlock, displayIndex: Int) -> some View {
        let profile = profiles.first { $0.id == block.profileId }
        let active = timer.planBlockID == block.id
        let completed = block.completedAt != nil

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 40)
                .contentShape(Rectangle())
                .onDrag {
                    draggedBlockID = block.id
                    return NSItemProvider(object: block.id.uuidString as NSString)
                }
                .accessibilityLabel("Drag \(block.title)")

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text(block.title)
                        .font(.headline)
                        .textSelection(.enabled)
                    Text("\(block.durationMinutes) min")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                    if let start = block.startMinute {
                        Text(planClockTime(start).formatted(.dateTime.hour().minute()))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        blockPendingDeletionID = block.id
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(active ? Color.secondary : Color.red)
                    .disabled(active)
                    .help(active ? "Cancel the running timer before deleting this block" : "Delete block")
                    .accessibilityLabel("Delete \(block.title)")
                }

                if let profile {
                    Label(profile.name, systemImage: "circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(profile.color)
                } else {
                    Label("Missing profile", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }

                if !block.notes.isEmpty {
                    renderedNotes(block.notes)
                }

                HStack(spacing: 7) {
                    Button {
                        presentedSheet = .editBlock(block.id)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(StudyButtonStyle(.secondary, compact: true))

                    Button {
                        copyContents(of: block)
                    } label: {
                        Label(
                            copiedBlockID == block.id ? "Copied" : "Copy",
                            systemImage: copiedBlockID == block.id ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .buttonStyle(StudyButtonStyle(.secondary, compact: true))
                    .disabled(block.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Copy the block details")

                    if completed {
                        Label("Completed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Undo") { reopen(block) }
                            .buttonStyle(StudyButtonStyle(.secondary, compact: true))
                    } else if active {
                        Label(timer.isPaused ? "Paused" : "In focus", systemImage: timer.isPaused ? "pause.circle" : "timer")
                            .foregroundStyle(timer.isPaused ? Color.orange : Color.green)
                    } else {
                        Button {
                            guard let profile, !timer.isRunning else { return }
                            timer.start(profile: profile, planBlock: block)
                        } label: {
                            Label("Start", systemImage: "play.fill")
                        }
                        .buttonStyle(StudyButtonStyle(.primary, compact: true))
                        .disabled(timer.isRunning || profile == nil || !Calendar.current.isDateInToday(selectedDay))

                        if selectedDay <= Calendar.current.startOfDay(for: .now) {
                            Button {
                                markDone(block)
                            } label: {
                                Label("Mark Done", systemImage: "checkmark")
                            }
                            .buttonStyle(StudyButtonStyle(.secondary, compact: true))
                            .disabled(profile == nil)
                            .help("Log this block’s full \(block.durationMinutes) minutes as completed")
                        }
                    }
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.green.opacity(active ? 0.6 : completed ? 0.28 : 0.12))
        }
        .opacity(completed ? 0.78 : 1)
        .onTapGesture(count: 2) {
            presentedSheet = .editBlock(block.id)
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { presentedSheet = .editBlock(block.id) }
            Button("Copy Contents", systemImage: "doc.on.doc") { copyContents(of: block) }
                .disabled(block.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(block) }
            Divider()
            Button("Move Up", systemImage: "arrow.up") { moveOne(block, delta: -1) }
                .disabled(displayIndex == 0)
            Button("Move Down", systemImage: "arrow.down") { moveOne(block, delta: 1) }
                .disabled(displayIndex == displayedBlocks.count - 1)
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                blockPendingDeletionID = block.id
            }
            .disabled(active)
        }
        .accessibilityAction(named: "Move up") { moveOne(block, delta: -1) }
        .accessibilityAction(named: "Move down") { moveOne(block, delta: 1) }
    }

    private var doneCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Done Notes", systemImage: "checklist").font(.headline)
            if let text = selectedDayNote?.text, !text.isEmpty {
                renderedNotes(text)
            } else {
                Text("Save completed tasks, nested lists, and links.")
                    .foregroundStyle(.secondary)
            }
            Button(selectedDayNote?.text.isEmpty == false ? "Edit Done Notes" : "Add Done Notes") {
                presentedSheet = .doneNotes
            }
            .buttonStyle(StudyButtonStyle(.secondary, compact: true))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func addPlanningInboxItem() {
        let title = planningInboxDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        context.insert(PlanningInboxItem(
            title: title,
            sortOrder: (planningInboxItems.map(\.sortOrder).max() ?? -1) + 1
        ))
        planningInboxDraft = ""
        saveContext()
    }

    private func updatePlanningInboxItem(_ item: PlanningInboxItem, content: String) {
        let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        item.title = content
        item.updatedAt = .now
        saveContext()
    }

    private func deletePlanningInboxItem(_ item: PlanningInboxItem) {
        context.delete(item)
        for (index, remaining) in sortedPlanningInboxItems.filter({ $0.id != item.id }).enumerated() {
            remaining.sortOrder = index
            remaining.updatedAt = .now
        }
        saveContext()
    }

    private func createBlock(
        from draft: BlockDraft,
        blockTypeId: UUID? = nil,
        removing inboxItem: PlanningInboxItem? = nil
    ) {
        guard let profileId = draft.profileId else { return }
        let block = DailyPlanBlock(
            day: selectedDay,
            profileId: profileId,
            blockTypeId: blockTypeId,
            title: draft.trimmedTitle,
            durationMinutes: draft.durationMinutes,
            notes: draft.notes,
            startMinute: draft.startMinute,
            sortOrder: (dayBlocks.map(\.sortOrder).max() ?? -1) + 1
        )
        context.insert(block)
        if let inboxItem {
            context.delete(inboxItem)
            for (index, remaining) in sortedPlanningInboxItems.filter({ $0.id != inboxItem.id }).enumerated() {
                remaining.sortOrder = index
                remaining.updatedAt = .now
            }
        }
        saveContext()
    }

    private func update(_ block: DailyPlanBlock, from draft: BlockDraft) {
        guard let profileId = draft.profileId else { return }
        block.profileId = profileId
        block.title = draft.trimmedTitle
        block.durationMinutes = draft.durationMinutes
        block.notes = draft.notes
        block.startMinute = draft.startMinute
        block.updatedAt = .now
        saveContext()
    }

    private func markDone(_ block: DailyPlanBlock) {
        guard block.completedAt == nil, timer.planBlockID != block.id else { return }

        if let timedSession = sessions
            .filter({ $0.planBlockId == block.id && $0.source.hasPrefix("timer") })
            .max(by: { $0.createdAt < $1.createdAt }) {
            block.completedAt = timedSession.endedAt ?? .now
            block.completionSource = "timer"
            block.linkedSessionId = timedSession.id
        } else {
            let session = DeepWorkSession(
                date: block.day,
                durationMinutes: block.durationMinutes,
                profileId: block.profileId,
                planBlockId: block.id,
                source: "plan-manual"
            )
            context.insert(session)
            block.completedAt = .now
            block.completionSource = "manual"
            block.linkedSessionId = session.id
        }
        block.updatedAt = .now
        saveContext()
    }

    private func reopen(_ block: DailyPlanBlock) {
        if block.completionSource == "manual",
           let linkedID = block.linkedSessionId,
           let session = sessions.first(where: { $0.id == linkedID }),
           session.source == "plan-manual" || session.source == "manual" {
            context.delete(session)
        }
        block.completedAt = nil
        block.completionSource = nil
        block.linkedSessionId = nil
        block.updatedAt = .now
        saveContext()
    }

    private func copyContents(of block: DailyPlanBlock) {
        let contents = block.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !contents.isEmpty else { return }

        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(contents, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = contents
        #endif

        copiedBlockID = block.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedBlockID == block.id {
                copiedBlockID = nil
            }
        }
    }

    private func duplicate(_ block: DailyPlanBlock) {
        for existing in dayBlocks where existing.sortOrder > block.sortOrder {
            existing.sortOrder += 1
        }
        let copy = DailyPlanBlock(
            day: block.day,
            profileId: block.profileId,
            blockTypeId: block.blockTypeId,
            title: block.title,
            durationMinutes: block.durationMinutes,
            notes: block.notes,
            startMinute: block.startMinute,
            sortOrder: block.sortOrder + 1
        )
        context.insert(copy)
        saveContext()
    }

    private func delete(_ block: DailyPlanBlock) {
        guard timer.planBlockID != block.id else { return }
        context.delete(block)
        normalizeSortOrder(dayBlocks.filter { $0.id != block.id })
        saveContext()
    }

    private func moveOne(_ block: DailyPlanBlock, delta: Int) {
        guard let index = displayedBlocks.firstIndex(where: { $0.id == block.id }) else { return }
        let target = index + delta
        guard displayedBlocks.indices.contains(target) else { return }
        moveBlock(block.id, displayedBlocks[target].id)
    }

    private func moveBlock(_ sourceID: UUID, _ destinationID: UUID) {
        var visible = displayedBlocks
        guard let sourceIndex = visible.firstIndex(where: { $0.id == sourceID }),
              let destinationIndex = visible.firstIndex(where: { $0.id == destinationID }),
              sourceIndex != destinationIndex else { return }

        visible.move(
            fromOffsets: IndexSet(integer: sourceIndex),
            toOffset: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
        )

        let visibleIDs = Set(visible.map(\.id))
        var visibleIterator = visible.makeIterator()
        let merged = dayBlocks.map { block in
            visibleIDs.contains(block.id) ? (visibleIterator.next() ?? block) : block
        }
        normalizeSortOrder(merged)
        saveContext()
    }

    private func normalizeSortOrder(_ blocks: [DailyPlanBlock]) {
        for (index, block) in blocks.enumerated() {
            block.sortOrder = index
            block.updatedAt = .now
        }
    }

    private func saveDayNotes(_ text: String) {
        if let note = selectedDayNote {
            note.text = text
            note.updatedAt = .now
        } else {
            context.insert(DailyPlanDayNote(day: selectedDay, text: text))
        }
        saveContext()
    }

    private func saveContext() {
        do {
            try context.save()
        } catch {
            context.rollback()
            operationError = error.localizedDescription
        }
    }

    private func migrateLegacyPlansIfNeeded() {
        guard migrationVersion < 1 else { return }
        guard let data = legacyStoredPlans.data(using: .utf8),
              let legacyPlans = try? JSONDecoder().decode([String: LegacyStudyDay].self, from: data) else {
            migrationVersion = 1
            return
        }

        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        do {
            var migratedDoneNotes: [Date: [String]] = [:]
            for (key, legacyDay) in legacyPlans {
                let isWork = key.hasPrefix("work/")
                let dateText = isWork ? String(key.dropFirst("work/".count)) : key
                guard let planDate = formatter.date(from: dateText),
                      let profile = profiles.first(where: { $0.name.caseInsensitiveCompare(isWork ? "Work" : "Study") == .orderedSame }) ?? profiles.first else {
                    continue
                }

                for (index, legacyBlock) in legacyDay.slots.enumerated() where !storedBlocks.contains(where: { $0.id == legacyBlock.id }) {
                    let session = sessions.first { $0.id == legacyBlock.id }
                    let block = DailyPlanBlock(
                        id: legacyBlock.id,
                        day: planDate,
                        profileId: profile.id,
                        title: legacyBlock.title(fallback: "\(profile.name) Block \(index + 1)"),
                        durationMinutes: legacyBlock.minutes,
                        notes: legacyBlock.notes,
                        startMinute: legacyBlock.startMinute,
                        sortOrder: index
                    )
                    if let session {
                        session.planBlockId = block.id
                        block.completedAt = session.endedAt ?? session.date
                        block.completionSource = session.source.hasPrefix("timer") ? "timer" : "manual"
                        block.linkedSessionId = session.id
                    }
                    context.insert(block)
                }

                if !legacyDay.done.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let day = Calendar.current.startOfDay(for: planDate)
                    migratedDoneNotes[day, default: []].append("\(profile.name)\n\(legacyDay.done)")
                }
            }

            for (day, sections) in migratedDoneNotes {
                let migratedText = sections.joined(separator: "\n\n")
                if let note = dayNotes.first(where: { Calendar.current.isDate($0.day, inSameDayAs: day) }) {
                    let prefix = note.text.isEmpty ? "" : "\n\n"
                    note.text += prefix + migratedText
                } else {
                    context.insert(DailyPlanDayNote(day: day, text: migratedText))
                }
            }
            try context.save()
            migrationVersion = 1
        } catch {
            context.rollback()
            operationError = "Your existing Daily Plan could not be migrated: \(error.localizedDescription)"
        }
    }
}

private struct BlockDraft {
    var title = ""
    var profileId: UUID?
    var durationMinutes = 25
    var notes = ""
    var startMinute: Int?

    init(profileId: UUID?) {
        self.profileId = profileId
    }

    init(title: String, profileId: UUID?) {
        self.title = title
        self.profileId = profileId
    }

    init(inboxContent: String, profileId: UUID?) {
        let firstLine = inboxContent
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? "Inbox Item"
        let cleanedTitle = firstLine
            .replacingOccurrences(of: #"^[#>*+\-\d.\s]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        title = String((cleanedTitle.isEmpty ? "Inbox Item" : cleanedTitle).prefix(100))
        self.profileId = profileId
        notes = inboxContent
    }

    init(_ type: DailyBlockType) {
        title = type.name
        profileId = type.profileId
        durationMinutes = type.defaultMinutes
        notes = type.defaultNotes
    }

    init(_ block: DailyPlanBlock) {
        title = block.title
        profileId = block.profileId
        durationMinutes = block.durationMinutes
        notes = block.notes
        startMinute = block.startMinute
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
}

private struct PlanningInboxEditorSheet: View {
    let save: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var content: String
    @FocusState private var editorFocused: Bool

    init(content: String, save: @escaping (String) -> Void) {
        _content = State(initialValue: content)
        self.save = save
    }

    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            ModernSheetHeader(
                icon: "tray.full.fill",
                eyebrow: "PLANNING INBOX",
                title: "Edit Inbox Item",
                subtitle: "Markdown, lists, and links are supported.",
                close: { dismiss() }
            )

            Divider().opacity(0.55)

            ScrollView {
                #if os(macOS)
                HStack(alignment: .top, spacing: 18) {
                    editorPanel.frame(minWidth: 380)
                    previewPanel.frame(minWidth: 300)
                }
                .padding(24)
                #else
                VStack(spacing: 18) {
                    editorPanel
                    previewPanel
                }
                .padding(20)
                #endif
            }

            Divider().opacity(0.55)

            HStack(spacing: 12) {
                Label("Use Markdown for headings, emphasis, lists, and links", systemImage: "text.alignleft")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(StudyButtonStyle(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button {
                    save(trimmedContent)
                    dismiss()
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(StudyButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedContent.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.bar)
        }
        .background(Color.green.opacity(0.035))
        #if os(macOS)
        .frame(minWidth: 720, idealWidth: 820, maxWidth: 900, minHeight: 540, idealHeight: 620, maxHeight: 720)
        #endif
        .onAppear { editorFocused = true }
    }

    private var editorPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorSectionTitle(
                icon: "square.and.pencil",
                title: "Content",
                caption: "Edit the source text directly. Plain URLs become clickable automatically."
            )
            ZStack(alignment: .topLeading) {
                if content.isEmpty {
                    Text("Add notes, links, lists, or Markdown…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $content)
                    .font(.body)
                    .lineSpacing(5)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .focused($editorFocused)
                    .accessibilityLabel("Inbox item content")
            }
            .frame(minHeight: 330)
            .background(.background.opacity(0.86), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(editorFocused ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: editorFocused ? 2 : 1)
            }
        }
        .editorPanel()
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorSectionTitle(
                icon: "eye",
                title: "Preview",
                caption: "Links are live here and in the Planning Inbox."
            )
            Group {
                if trimmedContent.isEmpty {
                    Text("Your formatted preview will appear here.")
                        .foregroundStyle(.tertiary)
                } else {
                    renderedNotes(trimmedContent)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 330, alignment: .topLeading)
            .padding(16)
            .background(.background.opacity(0.86), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.primary.opacity(0.12))
            }
        }
        .editorPanel()
    }
}

private struct BlockEditorSheet: View {
    let title: String
    let profiles: [Profile]
    let otherBlocks: [DailyPlanBlock]
    let save: (BlockDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: BlockDraft
    @State private var hasStart: Bool
    @State private var start: Date
    @FocusState private var focusedField: Field?

    private enum Field {
        case title, details
    }

    init(
        title: String,
        profiles: [Profile],
        otherBlocks: [DailyPlanBlock],
        initial: BlockDraft,
        save: @escaping (BlockDraft) -> Void
    ) {
        self.title = title
        self.profiles = profiles
        self.otherBlocks = otherBlocks
        self.save = save
        _draft = State(initialValue: initial)
        _hasStart = State(initialValue: initial.startMinute != nil)
        _start = State(initialValue: planClockTime(initial.startMinute ?? 9 * 60))
    }

    private var selectedStartMinute: Int? {
        guard hasStart else { return nil }
        let components = Calendar.current.dateComponents([.hour, .minute], from: start)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private var scheduleError: String? {
        guard let startMinute = selectedStartMinute else { return nil }
        let end = startMinute + draft.durationMinutes
        if end > 24 * 60 { return "This block would run past midnight." }
        for other in otherBlocks {
            if let otherStart = other.startMinute,
               startMinute < otherStart + other.durationMinutes,
               otherStart < end {
                return "This time overlaps “\(other.title)”."
            }
        }
        return nil
    }

    private var canSave: Bool {
        !draft.trimmedTitle.isEmpty && draft.profileId != nil && scheduleError == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ModernSheetHeader(
                icon: "leaf.fill",
                eyebrow: "FOCUS BLOCK",
                title: title,
                subtitle: "Shape the work, then protect the time.",
                close: { dismiss() }
            )

            Divider().opacity(0.55)

            GeometryReader { proxy in
                let wide = proxy.size.width >= 650
                ScrollView {
                    Group {
                        if wide {
                            HStack(alignment: .top, spacing: 20) {
                                primaryColumn(detailsHeight: max(300, proxy.size.height - 250))
                                    .frame(maxWidth: .infinity)
                                settingsColumn
                                    .frame(width: 300)
                            }
                        } else {
                            VStack(spacing: 16) {
                                primaryColumn(detailsHeight: 260)
                                settingsColumn
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 980)
                    .frame(maxWidth: .infinity)
                }
            }

            Divider().opacity(0.55)

            HStack(spacing: 12) {
                if let scheduleError {
                    Label(scheduleError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                } else {
                    Label("Markdown, links, and nested lists are supported", systemImage: "text.alignleft")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(StudyButtonStyle(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button {
                    draft.startMinute = selectedStartMinute
                    save(draft)
                    dismiss()
                } label: {
                    Label("Save Block", systemImage: "checkmark")
                }
                .buttonStyle(StudyButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.bar)
        }
        .background(Color.green.opacity(0.035))
        #if os(macOS)
        .frame(minWidth: 700, idealWidth: 860, maxWidth: 940, minHeight: 600, idealHeight: 700, maxHeight: 780)
        #endif
        .onAppear {
            focusedField = draft.trimmedTitle.isEmpty ? .title : .details
        }
    }

    private func primaryColumn(detailsHeight: CGFloat) -> some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                EditorSectionTitle(icon: "textformat", title: "What are you working on?", caption: "A short, concrete outcome works best.")
                TextField("Example: Review chapter 4 and capture notes", text: $draft.title)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(focusedField == .title ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: focusedField == .title ? 2 : 1)
                    }
                    .focused($focusedField, equals: .title)
            }
            .editorPanel()

            VStack(alignment: .leading, spacing: 10) {
                EditorSectionTitle(icon: "checklist", title: "Details", caption: "Tasks, links, prompts, and the definition of done.")
                ZStack(alignment: .topLeading) {
                    if draft.notes.isEmpty {
                        Text("Add the details that will keep you moving once the timer starts…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $draft.notes)
                        .font(.body)
                        .lineSpacing(5)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .focused($focusedField, equals: .details)
                        .accessibilityLabel("Block details")
                }
                .frame(minHeight: detailsHeight)
                .background(.background.opacity(0.86), in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(focusedField == .details ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: focusedField == .details ? 2 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 14))
                .onTapGesture { focusedField = .details }
            }
            .editorPanel()
        }
    }

    private var settingsColumn: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                EditorSectionTitle(icon: "person.crop.circle", title: "Profile", caption: "Where this work should count.")
                ProfileChoiceGrid(profiles: profiles, selection: $draft.profileId)
            }
            .editorPanel()

            VStack(alignment: .leading, spacing: 12) {
                EditorSectionTitle(icon: "timer", title: "Duration", caption: "Pick a preset or tune it in five-minute steps.")
                DurationPicker(minutes: $draft.durationMinutes)
            }
            .editorPanel()

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    EditorSectionTitle(icon: "calendar.badge.clock", title: "Schedule", caption: "Optional—order and time stay independent.")
                    Spacer(minLength: 8)
                    Toggle("", isOn: $hasStart)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                if hasStart {
                    DatePicker("Start time", selection: $start, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                    if let scheduleError {
                        Label(scheduleError, systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .editorPanel()
        }
    }
}

private struct BlockPickerSheet: View {
    let blockTypes: [DailyBlockType]
    let profiles: [Profile]
    let addType: (DailyBlockType) -> Void
    let createCustom: () -> Void
    let manageTypes: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ModernSheetHeader(
                icon: "plus",
                eyebrow: "BUILD TODAY",
                title: "Add a block",
                subtitle: "Start from a reusable type or make something one-off.",
                close: { dismiss() }
            )

            Divider().opacity(0.55)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if blockTypes.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "square.stack.3d.up")
                                .font(.system(size: 34, weight: .medium))
                                .foregroundStyle(.green)
                            Text("Build your block library")
                                .font(.title3.bold())
                            Text("Reusable types remember the profile, duration, and default details for work you repeat.")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: 430)
                            Button {
                                manageTypes()
                            } label: {
                                Label("Create First Block Type", systemImage: "plus")
                            }
                            .buttonStyle(StudyButtonStyle(.primary))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                        .editorPanel()
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("YOUR BLOCK TYPES")
                                .font(.caption.weight(.bold))
                                .tracking(1.2)
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                                ForEach(blockTypes) { type in
                                    blockTypeCard(type)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("OTHER OPTIONS")
                            .font(.caption.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                            actionCard(
                                icon: "square.and.pencil",
                                title: "Custom block",
                                subtitle: "Create a one-off block without saving a type.",
                                action: createCustom
                            )
                            actionCard(
                                icon: "slider.horizontal.3",
                                title: "Manage block types",
                                subtitle: "Create, edit, or remove reusable defaults.",
                                action: manageTypes
                            )
                        }
                    }
                }
                .padding(24)
            }
        }
        .background(Color.green.opacity(0.035))
        #if os(macOS)
        .frame(minWidth: 620, idealWidth: 760, maxWidth: 860, minHeight: 520, idealHeight: 620, maxHeight: 720)
        #endif
    }

    private func blockTypeCard(_ type: DailyBlockType) -> some View {
        let profile = profiles.first { $0.id == type.profileId }
        return Button {
            addType(type)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "leaf.fill")
                        .font(.headline)
                        .foregroundStyle(profile?.color ?? .green)
                        .frame(width: 38, height: 38)
                        .background((profile?.color ?? .green).opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(type.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text("\(profile?.name ?? "Missing profile") · \(type.defaultMinutes) min")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !type.defaultNotes.isEmpty {
                    Text(type.defaultNotes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding(16)
            .background(.background.opacity(0.82), in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.1)) }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func actionCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.green)
                    .frame(width: 42, height: 42)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(14)
            .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 15))
            .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(Color.primary.opacity(0.09)) }
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }
}

private struct BlockTypeManagerSheet: View {
    let profiles: [Profile]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var types: [DailyBlockType]
    @Query private var blocks: [DailyPlanBlock]
    @State private var editing: TypeEditorTarget?
    @State private var pendingDeletionID: UUID?

    private struct TypeEditorTarget: Identifiable {
        let id = UUID()
        let typeID: UUID?
    }

    var body: some View {
        VStack(spacing: 0) {
            ModernSheetHeader(
                icon: "square.stack.3d.up.fill",
                eyebrow: "BLOCK LIBRARY",
                title: "Reusable block types",
                subtitle: "Set defaults once, then add them to any day in one click.",
                trailing: AnyView(
                    Button {
                        editing = TypeEditorTarget(typeID: nil)
                    } label: {
                        Label("New Type", systemImage: "plus")
                    }
                    .buttonStyle(StudyButtonStyle(.primary, compact: true))
                    .disabled(profiles.isEmpty)
                ),
                close: { dismiss() }
            )

            Divider().opacity(0.55)

            ScrollView {
                if types.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(.green)
                        Text("No block types yet")
                            .font(.title2.bold())
                        Text("Create a reusable starting point for work you schedule often.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            editing = TypeEditorTarget(typeID: nil)
                        } label: {
                            Label("Create Block Type", systemImage: "plus")
                        }
                        .buttonStyle(StudyButtonStyle(.primary))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 70)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(types.sorted { $0.sortOrder < $1.sortOrder }) { type in
                            typeRow(type)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color.green.opacity(0.035))
        .sheet(item: $editing) { target in
            BlockTypeEditorSheet(
                profiles: profiles,
                existing: target.typeID.flatMap { id in types.first { $0.id == id } }
            ) { draft in
                save(draft, typeID: target.typeID)
            }
        }
        .alert("Delete Block Type?", isPresented: Binding(
            get: { pendingDeletionID != nil },
            set: { if !$0 { pendingDeletionID = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeletionID, let type = types.first(where: { $0.id == id }) {
                    delete(type)
                }
                pendingDeletionID = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletionID = nil }
        } message: {
            Text("Existing plan blocks keep their current title, duration, and details.")
        }
        #if os(macOS)
        .frame(minWidth: 640, idealWidth: 760, maxWidth: 860, minHeight: 520, idealHeight: 620, maxHeight: 720)
        #endif
    }

    private func typeRow(_ type: DailyBlockType) -> some View {
        let profile = profiles.first { $0.id == type.profileId }
        return HStack(spacing: 16) {
            Image(systemName: "leaf.fill")
                .font(.title3)
                .foregroundStyle(profile?.color ?? .green)
                .frame(width: 46, height: 46)
                .background((profile?.color ?? .green).opacity(0.12), in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 5) {
                Text(type.name).font(.headline)
                Text("\(profile?.name ?? "Missing profile") · \(type.defaultMinutes) minutes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !type.defaultNotes.isEmpty {
                    Text(type.defaultNotes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                editing = TypeEditorTarget(typeID: type.id)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(StudyButtonStyle(.secondary, compact: true))
            Button(role: .destructive) {
                pendingDeletionID = type.id
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .padding(8)
            .accessibilityLabel("Delete \(type.name)")
        }
        .padding(16)
        .background(.background.opacity(0.78), in: RoundedRectangle(cornerRadius: 17))
        .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(Color.primary.opacity(0.09)) }
    }

    private func save(_ draft: BlockTypeDraft, typeID: UUID?) {
        if let typeID, let type = types.first(where: { $0.id == typeID }) {
            type.name = draft.trimmedName
            type.profileId = draft.profileId
            type.defaultMinutes = draft.defaultMinutes
            type.defaultNotes = draft.defaultNotes
            type.updatedAt = .now
        } else {
            context.insert(DailyBlockType(
                name: draft.trimmedName,
                profileId: draft.profileId,
                defaultMinutes: draft.defaultMinutes,
                defaultNotes: draft.defaultNotes,
                sortOrder: (types.map(\.sortOrder).max() ?? -1) + 1
            ))
        }
        try? context.save()
    }

    private func delete(_ type: DailyBlockType) {
        for block in blocks where block.blockTypeId == type.id {
            block.blockTypeId = nil
        }
        context.delete(type)
        try? context.save()
    }
}

private struct BlockTypeDraft {
    var name = ""
    var profileId: UUID
    var defaultMinutes = 25
    var defaultNotes = ""

    init(profileId: UUID) {
        self.profileId = profileId
    }

    init(_ type: DailyBlockType) {
        name = type.name
        profileId = type.profileId
        defaultMinutes = type.defaultMinutes
        defaultNotes = type.defaultNotes
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
}

private struct BlockTypeEditorSheet: View {
    let profiles: [Profile]
    let save: (BlockTypeDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: BlockTypeDraft
    @FocusState private var detailsFocused: Bool

    init(profiles: [Profile], existing: DailyBlockType?, save: @escaping (BlockTypeDraft) -> Void) {
        self.profiles = profiles
        self.save = save
        let initial = existing.map(BlockTypeDraft.init) ?? BlockTypeDraft(profileId: profiles.first?.id ?? UUID())
        _draft = State(initialValue: initial)
    }

    private var canSave: Bool {
        !draft.trimmedName.isEmpty && profiles.contains { $0.id == draft.profileId }
    }

    var body: some View {
        VStack(spacing: 0) {
            ModernSheetHeader(
                icon: "square.stack.3d.up.fill",
                eyebrow: "REUSABLE DEFAULTS",
                title: "Block type",
                subtitle: "Future blocks start here; existing plans stay unchanged.",
                close: { dismiss() }
            )

            Divider().opacity(0.55)

            GeometryReader { proxy in
                let wide = proxy.size.width >= 620
                ScrollView {
                    Group {
                        if wide {
                            HStack(alignment: .top, spacing: 20) {
                                typeIdentityColumn
                                    .frame(width: 290)
                                typeDetailsColumn(height: max(260, proxy.size.height - 150))
                                    .frame(maxWidth: .infinity)
                            }
                        } else {
                            VStack(spacing: 16) {
                                typeIdentityColumn
                                typeDetailsColumn(height: 240)
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 860)
                    .frame(maxWidth: .infinity)
                }
            }

            Divider().opacity(0.55)

            HStack(spacing: 12) {
                Label("Changes apply when this type is added again", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(StudyButtonStyle(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button {
                    save(draft)
                    dismiss()
                } label: {
                    Label("Save Type", systemImage: "checkmark")
                }
                .buttonStyle(StudyButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.bar)
        }
        .background(Color.green.opacity(0.035))
        #if os(macOS)
        .frame(minWidth: 660, idealWidth: 780, maxWidth: 880, minHeight: 560, idealHeight: 650, maxHeight: 740)
        #endif
    }

    private var typeIdentityColumn: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                EditorSectionTitle(icon: "textformat", title: "Name", caption: "Make it recognizable in the add-block palette.")
                TextField("Example: DSA practice", text: $draft.name)
                    .textFieldStyle(.plain)
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(.background.opacity(0.82), in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)) }
            }
            .editorPanel()

            VStack(alignment: .leading, spacing: 12) {
                EditorSectionTitle(icon: "person.crop.circle", title: "Profile", caption: "Where completed time should count.")
                ProfileChoiceGrid(
                    profiles: profiles,
                    selection: Binding(
                        get: { Optional(draft.profileId) },
                        set: { if let id = $0 { draft.profileId = id } }
                    )
                )
            }
            .editorPanel()

            VStack(alignment: .leading, spacing: 12) {
                EditorSectionTitle(icon: "timer", title: "Default duration", caption: "Individual blocks can still override this.")
                DurationPicker(minutes: $draft.defaultMinutes)
            }
            .editorPanel()
        }
    }

    private func typeDetailsColumn(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorSectionTitle(icon: "checklist", title: "Default details", caption: "Seed every new block with useful prompts or a checklist.")
            ZStack(alignment: .topLeading) {
                if draft.defaultNotes.isEmpty {
                    Text("Add an optional checklist, links, or starting prompt…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft.defaultNotes)
                    .font(.body)
                    .lineSpacing(5)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .focused($detailsFocused)
            }
            .frame(minHeight: height)
            .background(.background.opacity(0.86), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(detailsFocused ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: detailsFocused ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture { detailsFocused = true }
        }
        .editorPanel()
    }
}

private struct DayNotesSheet: View {
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var focused: Bool

    init(text: String, save: @escaping (String) -> Void) {
        self.save = save
        _text = State(initialValue: text)
    }

    var body: some View {
        VStack(spacing: 0) {
            ModernSheetHeader(
                icon: "checklist",
                eyebrow: "DAILY LOG",
                title: "Done notes",
                subtitle: "Capture outcomes, loose ends, and useful links.",
                close: { dismiss() }
            )
            Divider().opacity(0.55)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("What did you finish today?")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.body)
                    .lineSpacing(6)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .focused($focused)
            }
            .background(.background.opacity(0.82), in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(focused ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: focused ? 2 : 1)
            }
            .padding(24)

            Divider().opacity(0.55)
            HStack {
                Text("Markdown and links are supported")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(StudyButtonStyle(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button {
                    save(text)
                    dismiss()
                } label: {
                    Label("Save Notes", systemImage: "checkmark")
                }
                .buttonStyle(StudyButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.bar)
        }
        .background(Color.green.opacity(0.035))
        #if os(macOS)
        .frame(minWidth: 600, idealWidth: 700, maxWidth: 820, minHeight: 520, idealHeight: 600, maxHeight: 700)
        #endif
        .onAppear { focused = true }
    }
}

private struct PlanCalendarPicker: View {
    @Binding var date: Date
    let done: () -> Void

    @State private var visibleMonth: Date

    private let calendar = Calendar.current
    private let forest = Color(red: 0.10, green: 0.34, blue: 0.26)
    private let mint = Color(red: 0.82, green: 0.92, blue: 0.84)

    init(date: Binding<Date>, done: @escaping () -> Void) {
        _date = date
        self.done = done
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date.wrappedValue)
        _visibleMonth = State(initialValue: calendar.date(from: components) ?? date.wrappedValue)
    }

    private var monthTitle: String {
        visibleMonth.formatted(.dateTime.month(.wide).year())
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[($0 + calendar.firstWeekday - 1) % 7] }
    }

    private var displayedDates: [Date] {
        guard
            let dayRange = calendar.range(of: .day, in: .month, for: visibleMonth),
            let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: visibleMonth))
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingDays = (firstWeekday - calendar.firstWeekday + 7) % 7
        let occupiedCells = leadingDays + dayRange.count
        let cellCount = ((occupiedCells + 6) / 7) * 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: firstDay) else { return [] }

        return (0..<cellCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: gridStart)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            calendarHeader
            Divider().opacity(0.5)
            calendarBody
        }
        .foregroundStyle(Color.primary)
        .background(Color(red: 0.965, green: 0.978, blue: 0.955))
        #if os(macOS)
        .frame(width: 470)
        #endif
    }

    private var calendarHeader: some View {
        HStack(spacing: 13) {
            Image(systemName: "calendar")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(forest)
                .frame(width: 44, height: 44)
                .background(mint, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Choose plan date")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Today") {
                date = .now
                done()
            }
            .buttonStyle(.bordered)
            .disabled(calendar.isDateInToday(date))

            Button(action: done) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close calendar")
        }
        .padding(22)
    }

    private var calendarBody: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Button {
                    moveMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Previous month")

                Text(monthTitle)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity)

                Button {
                    moveMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("Next month")
            }
            .buttonStyle(CalendarArrowButtonStyle())

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 9) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(displayedDates, id: \.self) { day in
                    calendarDay(day)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }

    private func calendarDay(_ day: Date) -> some View {
        let selected = calendar.isDate(day, inSameDayAs: date)
        let today = calendar.isDateInToday(day)
        let inVisibleMonth = calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month)

        return Button {
            date = day
            done()
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(.body, design: .rounded, weight: selected ? .bold : .medium))
                .foregroundStyle(selected ? Color.white : inVisibleMonth ? Color.primary : Color.secondary.opacity(0.55))
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Rectangle())
                .background(selected ? forest : Color.clear, in: Circle())
                .overlay {
                    if today && !selected {
                        Circle().stroke(forest.opacity(0.7), lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func moveMonth(by value: Int) {
        guard let month = calendar.date(byAdding: .month, value: value, to: visibleMonth) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            visibleMonth = startOfMonth(month)
        }
    }

    private func startOfMonth(_ value: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: value)) ?? value
    }
}

private struct CalendarArrowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color(red: 0.10, green: 0.34, blue: 0.26))
            .frame(width: 38, height: 38)
            .background(Color.primary.opacity(configuration.isPressed ? 0.11 : 0.06), in: Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

private struct ModernSheetHeader: View {
    let icon: String
    let eyebrow: String
    let title: String
    let subtitle: String
    var trailing: AnyView? = nil
    let close: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(red: 0.14, green: 0.46, blue: 0.34))
                .frame(width: 46, height: 46)
                .background(Color.green.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow)
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            if let trailing { trailing }

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 34, height: 34)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.bar)
    }
}

private struct EditorSectionTitle: View {
    let icon: String
    let title: String
    let caption: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ProfileChoiceGrid: View {
    let profiles: [Profile]
    @Binding var selection: UUID?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], spacing: 8) {
            ForEach(profiles) { profile in
                let selected = selection == profile.id
                Button {
                    selection = profile.id
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(profile.color)
                            .frame(width: 9, height: 9)
                        Text(profile.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                        }
                    }
                    .foregroundStyle(selected ? profile.color : Color.primary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(selected ? profile.color.opacity(0.14) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .strokeBorder(selected ? profile.color.opacity(0.55) : Color.primary.opacity(0.08))
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct DurationPicker: View {
    @Binding var minutes: Int
    private let presets = [25, 45, 60, 90]

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 7)], spacing: 7) {
                ForEach(presets, id: \.self) { preset in
                    Button {
                        minutes = preset
                    } label: {
                        Text(preset == 90 ? "90m" : "\(preset)m")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(minutes == preset ? Color.white : Color.primary)
                            .background(minutes == preset ? Color(red: 0.13, green: 0.40, blue: 0.31) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Button {
                    minutes = max(5, minutes - 5)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(minutes <= 5)

                VStack(spacing: 1) {
                    Text("\(minutes)")
                        .font(.title2.bold())
                        .monospacedDigit()
                    Text("minutes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Button {
                    minutes = min(240, minutes + 5)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(minutes >= 240)
            }
            .padding(.horizontal, 4)
        }
    }
}

private struct EditorPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.primary.opacity(0.08))
            }
    }
}

private extension View {
    func editorPanel() -> some View {
        modifier(EditorPanelModifier())
    }
}

private struct PlanBlockDropDelegate: DropDelegate {
    let destinationID: UUID
    @Binding var draggedID: UUID?
    let move: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedID, draggedID != destinationID else { return }
        move(draggedID, destinationID)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct LegacyStudySlot: Codable {
    var id: UUID
    var minutes: Int
    var notes: String
    var startMinute: Int?

    func title(fallback: String) -> String {
        guard let firstLine = notes.split(whereSeparator: \.isNewline).first else { return fallback }
        let cleaned = firstLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[-*+0-9.\s]+"#, with: "", options: .regularExpression)
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(80))
    }
}

private struct LegacyStudyDay: Codable {
    var slots: [LegacyStudySlot]
    var done: String
}

private func renderedNotes(_ text: String) -> some View {
    MarkdownContentView(text: text)
}

private struct MarkdownContentView: View {
    let text: String

    private var lines: [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "&#x9;", with: "\t")
            .replacingOccurrences(of: "\t", with: "    ")
            .components(separatedBy: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                lineView(line)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func lineView(_ rawLine: String) -> some View {
        let leadingSpaces = rawLine.prefix(while: { $0 == " " }).count
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        let indentation = CGFloat(min(leadingSpaces / 2, 4)) * 14

        if line.isEmpty {
            Color.clear.frame(height: 5)
        } else if line.hasPrefix("### ") {
            inlineText(String(line.dropFirst(4)))
                .font(.subheadline.weight(.bold))
                .padding(.leading, indentation)
        } else if line.hasPrefix("## ") {
            inlineText(String(line.dropFirst(3)))
                .font(.headline)
                .padding(.leading, indentation)
        } else if line.hasPrefix("# ") {
            inlineText(String(line.dropFirst(2)))
                .font(.title3.weight(.bold))
                .padding(.leading, indentation)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                inlineText(String(line.dropFirst(2)))
            }
            .padding(.leading, indentation)
        } else if let ordered = orderedListParts(line) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ordered.number)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                inlineText(ordered.content)
            }
            .padding(.leading, indentation)
        } else if line.hasPrefix("> ") {
            HStack(alignment: .top, spacing: 9) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.green.opacity(0.45))
                    .frame(width: 3)
                inlineText(String(line.dropFirst(2)))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, indentation)
        } else {
            inlineText(line)
                .padding(.leading, indentation)
        }
    }

    private func inlineText(_ content: String) -> Text {
        let linked = content.replacingOccurrences(
            of: #"(?<![\[\(<])(https?://[^\s<>\[\]()]+)"#,
            with: "[$1]($1)",
            options: .regularExpression
        )
        let rendered = try? AttributedString(
            markdown: linked,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        return Text(rendered ?? AttributedString(content))
    }

    private func orderedListParts(_ line: String) -> (number: String, content: String)? {
        guard let dot = line.firstIndex(of: "."), dot < line.index(before: line.endIndex) else { return nil }
        let number = String(line[...dot])
        guard Int(line[..<dot]) != nil else { return nil }
        let contentStart = line.index(after: dot)
        guard line[contentStart] == " " else { return nil }
        return (number, String(line[line.index(after: contentStart)...]))
    }
}

private func planClockTime(_ minute: Int) -> Date {
    Calendar.current.date(
        from: DateComponents(year: 2026, month: 1, day: 1, hour: minute / 60, minute: minute % 60)
    ) ?? .now
}

private struct StudyButtonStyle: ButtonStyle {
    enum Role {
        case primary, secondary, pause, danger, onHero
    }

    let role: Role
    var compact: Bool

    init(_ role: Role, compact: Bool = false) {
        self.role = role
        self.compact = compact
    }

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, role: role, compact: compact)
    }

    private struct Face: View {
        let configuration: Configuration
        let role: Role
        let compact: Bool

        @Environment(\.isEnabled) private var enabled
        @Environment(\.colorScheme) private var scheme
        @State private var hovered = false

        private var ink: Color {
            switch role {
            case .primary, .onHero: .white
            case .secondary: .primary
            case .pause: scheme == .dark ? Color(red: 1, green: 0.81, blue: 0.52) : Color(red: 0.46, green: 0.26, blue: 0.05)
            case .danger: scheme == .dark ? Color(red: 1, green: 0.66, blue: 0.65) : Color(red: 0.66, green: 0.15, blue: 0.19)
            }
        }

        private var fill: Color {
            switch role {
            case .primary: Color(red: 0.13, green: 0.40, blue: 0.31)
            case .secondary: Color.primary.opacity(0.045)
            case .pause: Color.orange.opacity(0.16)
            case .danger: Color.red.opacity(0.09)
            case .onHero: Color.white.opacity(0.10)
            }
        }

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: compact ? 9 : 12)
            configuration.label
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .padding(.horizontal, compact ? 10 : 14)
                .padding(.vertical, compact ? 7 : 10)
                .foregroundStyle(ink.opacity(enabled ? 1 : 0.45))
                .background(fill.opacity(configuration.isPressed ? 0.7 : hovered ? 1.25 : 1), in: shape)
                .overlay { shape.strokeBorder(ink.opacity(role == .onHero ? 0.16 : 0.08)) }
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .onHover { hovered = $0 }
        }
    }
}
