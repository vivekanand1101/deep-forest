import Foundation

public struct WidgetSnapshot: Codable {
    public var today: PeriodStats
    public var week: PeriodStats
    public var generatedAt: Date

    public init(today: PeriodStats = .init(), week: PeriodStats = .init(), generatedAt: Date = .now) {
        self.today = today
        self.week = week
        self.generatedAt = generatedAt
    }

    public static let key = "deepForest.widgetSnapshot"

    public static func load() -> WidgetSnapshot {
        guard let data = UserDefaults.standard.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return WidgetSnapshot()
        }
        return snapshot
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
