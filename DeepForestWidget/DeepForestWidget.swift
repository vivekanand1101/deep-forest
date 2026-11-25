import WidgetKit
import SwiftUI

struct DeepForestEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DeepForestEntry { DeepForestEntry(date: .now, snapshot: WidgetSnapshot()) }
    func getSnapshot(in context: Context, completion: @escaping (DeepForestEntry) -> Void) {
        completion(DeepForestEntry(date: .now, snapshot: WidgetSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DeepForestEntry>) -> Void) {
        let entry = DeepForestEntry(date: .now, snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

struct DeepForestWidgetView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ForestCanvasView(progress: entry.snapshot.week.progress, activeDays: entry.snapshot.week.activeDays, seed: 7)
            VStack(alignment: .leading, spacing: 3) {
                Text("Today").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.86))
                Text("\(entry.snapshot.today.hoursText) · \(entry.snapshot.today.sessions) sessions")
                    .font(family == .systemSmall ? .caption : .headline.weight(.bold))
                    .foregroundStyle(.white)
                if family != .systemSmall {
                    Text("Week \(entry.snapshot.week.hoursText) / \(entry.snapshot.week.goalMinutes / 60)h")
                        .font(.caption).foregroundStyle(.white.opacity(0.9))
                    let measuresLine = entry.snapshot.today.measures.prefix(2)
                        .map { "\($0.name) \($0.count)" }
                        .joined(separator: " · ")
                    if !measuresLine.isEmpty {
                        Text(measuresLine)
                            .font(.caption2).foregroundStyle(.white.opacity(0.82))
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.16))
        }
    }
}

@main
struct DeepForestWidget: Widget {
    let kind = "DeepForestWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            DeepForestWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Deep Forest")
        .description("Today first, weekly forest always visible.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
