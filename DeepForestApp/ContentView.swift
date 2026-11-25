import SwiftUI
import SwiftData
#if canImport(WidgetKit)
import WidgetKit
#endif
#if os(iOS)
import UIKit
import AudioToolbox
#elseif os(macOS)
import AppKit
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \DeepWorkSession.date, order: .reverse) private var sessions: [DeepWorkSession]
    @Query(sort: \LeadMeasureEvent.createdAt, order: .reverse) private var leadEvents: [LeadMeasureEvent]
    @Query(sort: \Profile.sortOrder) private var profiles: [Profile]
    @Query(sort: \LeadMeasure.sortOrder) private var measures: [LeadMeasure]
    @Query private var settingsRows: [AppSettings]

    @State private var selectedTab = 0

    var settings: AppSettings { settingsRows.first ?? AppSettings() }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(sessions: sessions, leadEvents: leadEvents, profiles: profiles, measures: measures, settings: settings)
                .tabItem { Label("Home", systemImage: "tree.fill") }.tag(0)
            StudyPlanView(sessions: sessions, profiles: profiles)
                .tabItem { Label("Daily Plan", systemImage: "calendar") }.tag(3)
            ArchiveView(sessions: sessions, leadEvents: leadEvents, profiles: profiles, measures: measures)
                .tabItem { Label("Forest", systemImage: "leaf.fill") }.tag(1)
            SettingsView(settings: settings, sessions: sessions, leadEvents: leadEvents, profiles: profiles, measures: measures)
                .tabItem { Label("Settings", systemImage: "gear") }.tag(2)
        }
        .onAppear {
            DefaultData.ensureSeeded(context: context)
            refreshWidgetSnapshot()
        }
        .onChange(of: sessions.count) { _, _ in refreshWidgetSnapshot() }
        .onChange(of: leadEvents.count) { _, _ in refreshWidgetSnapshot() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { try? context.save() }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            try? context.save()
        }
        #endif
    }

    private func refreshWidgetSnapshot() {
        let combinedWeeklyGoal = profiles.reduce(0) { $0 + $1.weeklyGoalHours } * 60
        let today = StatsEngine.stats(sessions: sessions, leadEvents: leadEvents, measures: measures, interval: StatsEngine.dayInterval(), goalMinutes: DepthCap.dailyMinutes)
        let week = StatsEngine.stats(sessions: sessions, leadEvents: leadEvents, measures: measures, interval: StatsEngine.weekInterval(), goalMinutes: combinedWeeklyGoal)
        WidgetSnapshot(today: today, week: week).save()
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var context
    var sessions: [DeepWorkSession]
    var leadEvents: [LeadMeasureEvent]
    var profiles: [Profile]
    var measures: [LeadMeasure]
    @Bindable var settings: AppSettings

    @State private var now = Date()
    @State private var showingManual = false
    @State private var showingShutdown = false
    @State private var pendingPartial: EndedSessionInfo?
    let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var timer: TimerController { .shared }

    var activeProfile: Profile? {
        profiles.first { $0.id == settings.activeProfileId } ?? profiles.first
    }
    var activeMeasures: [LeadMeasure] {
        guard let activeProfile else { return [] }
        return measures.filter { $0.profileId == activeProfile.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    ForestCanvasView(progress: weekStats.progress, activeDays: weekStats.activeDays, seed: weekSeed)
                        .frame(height: 260)
                        .padding(.horizontal)

                    timerCard
                    todayCard
                    leadMeasuresCard
                    weekCard
                }
                .padding(.vertical)
            }
            .navigationTitle("Deep Forest")
            .toolbar {
                Button {
                    showingShutdown = true
                } label: {
                    Label("Shutdown Ritual", systemImage: settings.shutdownCompletedToday ? "moon.fill" : "moon")
                }
                Button("Manual Entry") { showingManual = true }
            }
            .sheet(isPresented: $showingManual) {
                ManualEntryView(profiles: profiles, defaultProfileId: activeProfile?.id)
            }
            .sheet(isPresented: $showingShutdown) {
                ShutdownView(settings: settings, todayStats: todayStats)
            }
            .alert("Session ended early", isPresented: partialAlertShown, presenting: pendingPartial) { info in
                Button("Log \(info.elapsedMinutes) minutes") {
                    timer.logPartial(info)
                    pendingPartial = nil
                }
                Button("Discard", role: .destructive) { pendingPartial = nil }
            } message: { info in
                Text("You did \(info.elapsedMinutes) minutes of deep work. The hours count — log them?")
            }
            .onReceive(ticker) { date in
                now = date
                timer.completeIfDue(now: date)
            }
        }
    }

    private var partialAlertShown: Binding<Bool> {
        Binding(get: { pendingPartial != nil }, set: { if !$0 { pendingPartial = nil } })
    }

    private var profileSelection: Binding<UUID> {
        Binding(
            get: { activeProfile?.id ?? UUID() },
            set: { newValue in
                settings.activeProfileId = newValue
                try? context.save()
            }
        )
    }

    private var todayStats: PeriodStats {
        StatsEngine.stats(sessions: sessions, leadEvents: leadEvents, measures: measures, interval: StatsEngine.dayInterval(), goalMinutes: DepthCap.dailyMinutes)
    }
    private var weekStats: PeriodStats {
        StatsEngine.stats(
            sessions: sessions,
            leadEvents: leadEvents,
            measures: measures,
            interval: StatsEngine.weekInterval(),
            goalMinutes: (activeProfile?.weeklyGoalHours ?? 15) * 60,
            profileId: activeProfile?.id
        )
    }
    private var weekSeed: Int { Int(StatsEngine.weekInterval().start.timeIntervalSince1970 / 86400) }

    private var displayedSeconds: Int {
        timer.isRunning ? timer.remainingSeconds(at: max(now, timer.startedAt ?? now)) : (activeProfile?.sessionMinutes ?? 45) * 60
    }

    private var timerCard: some View {
        VStack(spacing: 16) {
            if profiles.count > 1 {
                Picker("Profile", selection: profileSelection) {
                    ForEach(profiles) { profile in Text(profile.name).tag(profile.id) }
                }
                .pickerStyle(.segmented)
                .disabled(timer.isRunning)
            }

            Text(timeText(displayedSeconds))
                .font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(timer.isRunning ? (activeProfile?.color ?? .primary) : .primary)
            Text(timer.isPaused ? "Session paused" : timer.isRunning
                 ? (timer.planBlockID == nil ? "Growing today's \(activeProfile?.name.lowercased() ?? "") forest" : "Planned block in progress")
                 : "Ready for a \(activeProfile?.sessionMinutes ?? 45)-minute \(activeProfile?.name ?? "") session")
                .foregroundStyle(.secondary)

            if timer.isRunning {
                HStack(spacing: 12) {
                    Button {
                        timer.tallyDistraction()
                    } label: {
                        Label("Distracted (\(timer.distractions))", systemImage: "hand.raised.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(timer.isPaused)

                    Button(role: .destructive) {
                        endEarly()
                    } label: {
                        Label("End Early", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Button {
                    if timer.isPaused { timer.resume() } else { timer.pause() }
                } label: {
                    Label(timer.isPaused ? "Resume" : "Pause", systemImage: timer.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.bordered)
                Text("Feel the urge to switch? Tally it and stay.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button {
                    if let activeProfile { timer.start(profile: activeProfile) }
                } label: {
                    Label("Start Deep Work", systemImage: "play.fill")
                        .font(.title3.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(activeProfile?.color)
                .disabled(activeProfile == nil)
            }
        }
        .padding(22)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal)
    }

    private var todayCard: some View {
        StatCard(
            title: "Today",
            subtitle: "Depth cap: 4h",
            prominent: true,
            stats: todayStats,
            footnote: todayStats.minutes >= DepthCap.dailyMinutes
                ? "Depth cap reached — you've done the day's deep work. Rest."
                : nil
        )
    }

    private var weekCard: some View {
        StatCard(
            title: "This Week · \(activeProfile?.name ?? "")",
            subtitle: "Goal: \(activeProfile?.weeklyGoalHours ?? 0)h",
            prominent: false,
            stats: weekStats
        )
    }

    private var leadMeasuresCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Lead Measures · \(activeProfile?.name ?? "")").font(.headline)
            if activeMeasures.isEmpty {
                Text("No lead measures yet. Add some in Settings — they're the daily actions that drive your goal.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(activeMeasures) { measure in
                LeadCounterRow(title: measure.name, value: todayCount(for: measure), tint: activeProfile?.color ?? .green) { delta in
                    context.insert(LeadMeasureEvent(measureId: measure.id, delta: delta))
                    try? context.save()
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal)
    }

    private func todayCount(for measure: LeadMeasure) -> Int {
        let interval = StatsEngine.dayInterval()
        return max(0, leadEvents.filter { $0.measureId == measure.id && interval.contains($0.date) }.reduce(0) { $0 + $1.delta })
    }

    private func endEarly() {
        guard let info = timer.cancel() else { return }
        if info.elapsedMinutes >= 5 { pendingPartial = info }
    }

    private func timeText(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
}

struct LeadCounterRow: View {
    var title: String
    var value: Int
    var tint: Color = .green
    var onDelta: (Int) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text("\(value)").font(.title2.bold()).monospacedDigit()
            }
            Spacer()
            Button { if value > 0 { onDelta(-1) } } label: {
                Image(systemName: "minus.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(value > 0 ? .secondary : .tertiary)
            .disabled(value == 0)

            Button { onDelta(1) } label: {
                Image(systemName: "plus.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(tint)
        }
    }
}

struct StatCard: View {
    var title: String
    var subtitle: String? = nil
    var prominent: Bool
    var stats: PeriodStats
    var footnote: String? = nil

    private var detailLine: String {
        var parts = stats.measures.map { "\($0.name) \($0.count)" }
        parts.append("\(stats.activeDays) active days")
        if stats.distractions > 0 { parts.append("\(stats.distractions) urges resisted") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(title).font(prominent ? .title2.bold() : .headline); Spacer(); if let subtitle { Text(subtitle).foregroundStyle(.secondary) } }
            HStack(alignment: .firstTextBaseline) {
                Text(stats.hoursText).font(prominent ? .largeTitle.bold() : .title.bold())
                Text("· \(stats.sessions) sessions").foregroundStyle(.secondary)
            }
            ProgressView(value: stats.progress)
            Text(detailLine)
                .font(.subheadline).foregroundStyle(.secondary)
            if let footnote {
                Text(footnote)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal)
    }
}

func playCompletionFeedback() {
    #if os(iOS)
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    AudioServicesPlaySystemSound(1025)
    #elseif os(macOS)
    NSSound(named: "Glass")?.play()
    #endif
}
