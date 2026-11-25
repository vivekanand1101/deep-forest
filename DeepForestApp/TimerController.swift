import Foundation
import Observation
import SwiftData

public struct EndedSessionInfo {
    public let startedAt: Date
    public let elapsedMinutes: Int
    public let profileId: UUID?
    public let distractions: Int
}

/// Owns the running deep work session. State is persisted to UserDefaults the
/// moment a session starts, so a quit, crash, or reboot never loses the work:
/// on relaunch the countdown resumes, or the session is logged retroactively
/// if it finished while the app was closed.
@MainActor
@Observable
public final class TimerController {
    public static let shared = TimerController()

    public private(set) var startedAt: Date?
    public private(set) var pausedAt: Date?
    private var pausedDuration: TimeInterval = 0
    public private(set) var plannedMinutes: Int = 0
    public private(set) var profileId: UUID?
    public private(set) var planBlockID: UUID?
    public private(set) var distractions: Int = 0
    /// Whole minutes left, for the macOS menu bar label.
    public private(set) var menuBarMinutesLeft: Int = 0

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var completionTimer: Timer?
    @ObservationIgnored private var menuBarTicker: Timer?

    private struct PersistedState: Codable {
        var startedAt: Date
        var plannedMinutes: Int
        var profileId: UUID?
        var distractions: Int
        var planBlockID: UUID?
        var pausedAt: Date?
        var pausedDuration: TimeInterval?

        private enum CodingKeys: String, CodingKey {
            case startedAt, plannedMinutes, profileId, distractions, pausedAt, pausedDuration
            case planBlockID = "studySlotID"
        }
    }
    private static let defaultsKey = "deepForest.activeTimer"

    public var isRunning: Bool { startedAt != nil }
    public var isPaused: Bool { pausedAt != nil }
    private var endDate: Date? {
        startedAt?.addingTimeInterval(TimeInterval(plannedMinutes * 60) + pausedDuration)
    }

    public func remainingSeconds(at date: Date = .now) -> Int {
        guard let endDate else { return 0 }
        return max(0, Int(ceil(endDate.timeIntervalSince(pausedAt ?? date))))
    }

    public func configure(container: ModelContainer) {
        self.container = container
        restore()
    }

    func start(profile: Profile, planBlock: DailyPlanBlock? = nil) {
        guard !isRunning else { return }
        startedAt = .now
        plannedMinutes = planBlock?.durationMinutes ?? profile.sessionMinutes
        planBlockID = planBlock?.id
        profileId = profile.id
        distractions = 0
        persist()
        scheduleCompletion()
    }

    func pause(now: Date = .now) {
        guard let endDate, !isPaused else { return }
        guard now < endDate else {
            completeIfDue(now: now)
            return
        }
        pausedAt = now
        stopTickers()
        updateMenuBarMinutes()
        persist()
    }

    func resume(now: Date = .now) {
        guard let pausedAt else { return }
        pausedDuration += max(0, now.timeIntervalSince(pausedAt))
        self.pausedAt = nil
        persist()
        scheduleCompletion()
    }

    func restart(now: Date = .now) {
        guard isRunning else { return }
        startedAt = now
        pausedAt = nil
        pausedDuration = 0
        distractions = 0
        persist()
        scheduleCompletion()
    }

    /// Newport's "embrace boredom" drill: when the urge to switch hits,
    /// tally it and stay in the session.
    public func tallyDistraction() {
        guard isRunning, !isPaused else { return }
        distractions += 1
        persist()
    }

    /// Ends the session early without logging. Returns what happened so the
    /// caller can offer to log the partial minutes.
    @discardableResult
    public func cancel() -> EndedSessionInfo? {
        guard let startedAt else { return nil }
        let focused = (pausedAt ?? .now).timeIntervalSince(startedAt) - pausedDuration
        let elapsed = max(0, min(Int(focused / 60), plannedMinutes))
        let info = EndedSessionInfo(startedAt: startedAt, elapsedMinutes: elapsed, profileId: profileId, distractions: distractions)
        clear()
        return info
    }

    public func logPartial(_ info: EndedSessionInfo) {
        insertSession(
            startedAt: info.startedAt,
            endedAt: info.startedAt.addingTimeInterval(TimeInterval(info.elapsedMinutes * 60)),
            minutes: info.elapsedMinutes,
            profileId: info.profileId,
            distractions: info.distractions,
            source: "timer-partial"
        )
    }

    /// Fired by the internal timer at the planned end; also safe to call
    /// defensively from any ticking view (covers sleep/wake drift).
    public func completeIfDue(now: Date = .now) {
        guard !isPaused, let startedAt, let endDate, now >= endDate else { return }
        if let planBlockID {
            guard savePlanBlock(id: planBlockID, startedAt: startedAt, endedAt: endDate) else {
                scheduleCompletion(fireAt: .now.addingTimeInterval(5))
                return
            }
        } else {
            insertSession(startedAt: startedAt, endedAt: endDate, minutes: plannedMinutes, profileId: profileId, distractions: distractions, source: "timer")
        }
        let soundOn = container.flatMap { try? $0.mainContext.fetch(FetchDescriptor<AppSettings>()).first?.soundEnabled } ?? true
        clear()
        if soundOn { playCompletionFeedback() }
    }

    private func insertSession(startedAt: Date, endedAt: Date, minutes: Int, profileId: UUID?, distractions: Int, source: String) {
        guard let context = container?.mainContext, minutes > 0 else { return }
        context.insert(DeepWorkSession(
            date: startedAt,
            startedAt: startedAt,
            endedAt: endedAt,
            durationMinutes: minutes,
            profileId: profileId,
            distractions: distractions,
            source: source
        ))
        try? context.save()
    }

    private func savePlanBlock(id: UUID, startedAt: Date, endedAt: Date) -> Bool {
        guard let container else { return false }
        let mainContext = container.mainContext
        let descriptor = FetchDescriptor<DailyPlanBlock>(predicate: #Predicate { $0.id == id })

        do {
            let block = try mainContext.fetch(descriptor).first
            if block?.completedAt != nil { return true }

            let session = DeepWorkSession(
                date: startedAt,
                startedAt: startedAt,
                endedAt: endedAt,
                durationMinutes: plannedMinutes,
                profileId: profileId,
                planBlockId: id,
                distractions: distractions,
                source: "timer"
            )
            mainContext.insert(session)
            block?.completedAt = endedAt
            block?.completionSource = "timer"
            block?.linkedSessionId = session.id
            block?.updatedAt = .now
            try mainContext.save()
            return true
        } catch {
            mainContext.rollback()
            return false
        }
    }

    private func scheduleCompletion(fireAt: Date? = nil) {
        completionTimer?.invalidate()
        guard let endDate else { return }
        let timer = Timer(fire: fireAt ?? endDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.completeIfDue() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        completionTimer = timer
        startMenuBarTicker()
    }

    private func startMenuBarTicker() {
        updateMenuBarMinutes()
        menuBarTicker?.invalidate()
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateMenuBarMinutes() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        menuBarTicker = timer
    }

    private func updateMenuBarMinutes() {
        menuBarMinutesLeft = Int(ceil(Double(remainingSeconds()) / 60))
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        startedAt = state.startedAt
        plannedMinutes = state.plannedMinutes
        profileId = state.profileId
        distractions = state.distractions
        planBlockID = state.planBlockID
        pausedAt = state.pausedAt
        pausedDuration = state.pausedDuration ?? 0
        if isPaused {
            updateMenuBarMinutes()
            return
        }
        completeIfDue() // finished while the app was closed → log it retroactively
        if isRunning && completionTimer == nil { scheduleCompletion() }
    }

    private func persist() {
        guard let startedAt else { return }
        let state = PersistedState(startedAt: startedAt, plannedMinutes: plannedMinutes, profileId: profileId, distractions: distractions, planBlockID: planBlockID, pausedAt: pausedAt, pausedDuration: pausedDuration)
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func clear() {
        startedAt = nil
        pausedAt = nil
        pausedDuration = 0
        plannedMinutes = 0
        profileId = nil
        planBlockID = nil
        distractions = 0
        stopTickers()
        menuBarMinutesLeft = 0
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }

    private func stopTickers() {
        completionTimer?.invalidate()
        completionTimer = nil
        menuBarTicker?.invalidate()
        menuBarTicker = nil
    }
}
