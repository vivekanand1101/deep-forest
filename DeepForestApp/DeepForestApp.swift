import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

@main
struct DeepForestApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            DeepWorkSession.self, LeadMeasureEvent.self, Profile.self, LeadMeasure.self, AppSettings.self,
            DailyBlockType.self, DailyPlanBlock.self, DailyPlanDayNote.self, PlanningInboxItem.self
        ])

        // Free Apple accounts cannot use CloudKit entitlement. Keep SwiftData local.
        // Free Mac/iPhone sync will be implemented via iCloud Drive file sync instead.
        // Explicit store URL: the unsandboxed macOS default would be the shared
        // ~/Library/Application Support/default.store, which other apps can collide with.
        let storeDirectory = URL.applicationSupportDirectory.appendingPathComponent("DeepForest", isDirectory: true)
        try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let localConfig = ModelConfiguration(schema: schema, url: storeDirectory.appendingPathComponent("DeepForest.store"))
        do { return try ModelContainer(for: schema, configurations: [localConfig]) }
        catch { fatalError("Could not create SwiftData container: \(error)") }
    }()

    init() {
        TimerController.shared.configure(container: sharedModelContainer)
    }

    var body: some Scene {
        WindowGroup("Deep Forest", id: "main") { ContentView() }
            .modelContainer(sharedModelContainer)

        #if os(macOS)
        MenuBarExtra {
            MacMenuBarView()
                .modelContainer(sharedModelContainer)
        } label: {
            MenuBarCountdownLabel()
        }
        #endif
    }
}

#if os(macOS)
struct MenuBarCountdownLabel: View {
    // A MenuBarExtra label is rebuilt on every status-item update, so a
    // TimelineView here restarts its schedule each rebuild and re-renders
    // forever, pegging the main thread. Plain observed state updated by
    // TimerController's own ticker keeps each update discrete.
    var body: some View {
        if TimerController.shared.isRunning {
            HStack(spacing: 3) {
                Image(systemName: TimerController.shared.isPaused ? "pause.fill" : "tree.fill")
                Text("\(TimerController.shared.menuBarMinutesLeft)m").monospacedDigit()
            }
        } else {
            Image(systemName: "tree.fill")
        }
    }
}
#endif
