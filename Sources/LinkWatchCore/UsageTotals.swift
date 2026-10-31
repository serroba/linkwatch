public import Foundation

/// Bytes the Mac moved on monitored networks over a period.
public struct UsageTotal: Codable, Equatable, Sendable {
  public var received: UInt64
  public var sent: UInt64

  /// For example "↓ 1.2 GB · ↑ 340 MB".
  public var summary: String {
    "↓ \(Self.bytes(received)) · ↑ \(Self.bytes(sent))"
  }

  /// Decimal units, as macOS shows file sizes and providers bill data.
  public static func bytes(_ count: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .decimal
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: Int64(clamping: count))
  }
}

/// Cumulative usage for the last hour, today and the stored week.
public struct UsageTotals: Codable, Equatable, Sendable {
  public var lastHour: UsageTotal
  public var today: UsageTotal
  public var week: UsageTotal

  /// Sums stored minutes plus the minute in progress; only this Mac's traffic on monitored
  /// networks while LinkWatch ran is counted.
  public init(
    minutes: [MinuteSummary], current: TrafficCounters?, now: Date, calendar: Calendar = .current
  ) {
    let midnight = calendar.startOfDay(for: now)
    let hourAgo = now.addingTimeInterval(-3600)
    func total(since date: Date) -> UsageTotal {
      var received = current?.received ?? 0
      var sent = current?.sent ?? 0
      for minute in minutes where minute.start >= date {
        received &+= minute.received ?? 0
        sent &+= minute.sent ?? 0
      }
      return UsageTotal(received: received, sent: sent)
    }
    lastHour = total(since: hourAgo)
    today = total(since: midnight)
    week = total(since: .distantPast)
  }
}
