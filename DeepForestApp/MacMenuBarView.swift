#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

struct MacMenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \DeepWorkSession.date, order: .reverse) private var sessions: [DeepWorkSession]
    @Query(sort: \LeadMeasureEvent.createdAt, order: .reverse) private var leadEvents: [LeadMeasureEvent]
    @Query(sort: \Profile.sortOrder) private var profiles: [Profile]
    @Query(sort: \LeadMeasure.sortOrder) private var measures: [LeadMeasure]
    @Query private var settingsRows: [AppSettings]

    private var timer: TimerController { .shared }
    private var settings: AppSettings { settingsRows.first ?? AppSettings() }
    private var activeProfile: Profile? {
        profiles.first { $0.id == settings.activeProfileId } ?? profiles.first
    }
    private var combinedGoalMinutes: Int { profiles.reduce(0) { $0 + $1.weeklyGoalHours } * 60 }
    private var today: PeriodStats {
        StatsEngine.stats(sessions: sessions, leadEvents: leadEvents, measures: measures, interval: StatsEngine.dayInterval(), goalMinutes: DepthCap.dailyMinutes)
    }
    private var week: PeriodStats {
        StatsEngine.stats(sessions: sessions, leadEvents: leadEvents, measures: measures, interval: StatsEngine.weekInterval(), goalMinutes: combinedGoalMinutes)
    }

    var body: some View {
        Text("Today: \(today.hoursText) · \(today.sessions) sessions")
        Text("Week: \(week.hoursText) / \(combinedGoalMinutes / 60)h")
        Divider()
        if timer.isRunning {
            Text("\(runningProfileName): \(remainingMinutesText) left\(timer.isPaused ? " · Paused" : "")")
            Button(timer.isPaused ? "Resume" : "Pause") {
                if timer.isPaused { timer.resume() } else { timer.pause() }
            }
            Button("Distracted +1 (\(timer.distractions))") { timer.tallyDistraction() }
                .disabled(timer.isPaused)
            Button("End Session Early") { endEarly() }
        } else if let profile = activeProfile {
            Button("Start \(profile.name) Session (\(profile.sessionMinutes) min)") {
                timer.start(profile: profile)
            }
        }
        Divider()
        Button("Open Deep Forest") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit") { NSApp.terminate(nil) }
    }

    private var runningProfileName: String {
        profiles.first { $0.id == timer.profileId }?.name ?? "Deep Work"
    }

    private var remainingMinutesText: String {
        let minutes = max(0, Int(ceil(Double(timer.remainingSeconds()) / 60)))
        return "\(minutes)m"
    }

    /// No dialogs in a menu, so default to never losing depth hours:
    /// five or more elapsed minutes get logged as a partial session.
    private func endEarly() {
        guard let info = timer.cancel() else { return }
        if info.elapsedMinutes >= 5 { timer.logPartial(info) }
    }
}
#endif
