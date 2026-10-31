import Charts
import Foundation
import LinkWatchCore
import SwiftUI

/// Minute medians for one or seven days; red marks minutes with an alert or a lost reply.
struct WeekChart: View {
  let minutes: [MinuteSummary]

  var body: some View {
    let alerts = minutes.filter { $0.worstHealth != "healthy" }
    VStack(alignment: .leading, spacing: 4) {
      Text("\(minutes.count) minutes recorded, \(alerts.count) with an alert or lost reply")
        .font(.caption).foregroundStyle(.secondary)
      Chart {
        ForEach(minutes, id: \.start) { minute in
          if let median = minute.accessPoint.median {
            LineMark(x: .value("Time", minute.start), y: .value("ms", median))
              .foregroundStyle(by: .value("Target", "AP"))
          }
          if let median = minute.router.median {
            LineMark(x: .value("Time", minute.start), y: .value("ms", median))
              .foregroundStyle(by: .value("Target", "Router"))
          }
        }
        ForEach(alerts, id: \.start) { minute in
          RuleMark(x: .value("Time", minute.start)).foregroundStyle(.red.opacity(0.25))
        }
      }
      .chartYAxisLabel("ms")
      .frame(height: 120)
      .accessibilityLabel(
        "Median latency per minute for \(minutes.count) minutes, \(alerts.count) with an alert or lost reply"
      )
    }
  }
}

struct HistoryChart: View {
  let history: [ProbePair]

  var body: some View {
    let latest = history.last?.elapsed ?? 0
    let failures = history.filter { $0.accessPoint.latency == nil || $0.router.latency == nil }
    VStack(alignment: .leading, spacing: 4) {
      Text("Last \(max(1, Int(((history.first.map { latest - $0.elapsed }) ?? 0) / 60))) min")
        .font(.caption).foregroundStyle(.secondary)
      Chart {
        ForEach(Array(history.enumerated()), id: \.offset) { _, pair in
          let minutesAgo = (pair.elapsed - latest) / 60
          if let latency = pair.accessPoint.latency {
            LineMark(x: .value("Minutes", minutesAgo), y: .value("ms", latency))
              .foregroundStyle(by: .value("Target", "AP"))
          }
          if let latency = pair.router.latency {
            LineMark(x: .value("Minutes", minutesAgo), y: .value("ms", latency))
              .foregroundStyle(by: .value("Target", "Router"))
          }
        }
        ForEach(Array(failures.enumerated()), id: \.offset) { _, pair in
          RuleMark(x: .value("Minutes", (pair.elapsed - latest) / 60))
            .foregroundStyle(.purple.opacity(0.4))
        }
      }
      .chartXAxis {
        AxisMarks { value in
          AxisGridLine()
          AxisValueLabel {
            if let minutes = value.as(Double.self) { Text("\(Int(minutes.rounded())) min") }
          }
        }
      }
      .chartYAxisLabel("ms")
      .frame(height: 120)
      .accessibilityLabel(
        "Latency history for the last \(history.count) measurements in milliseconds, with \(failures.count) failed measurements marked"
      )
    }
  }
}

/// The last day's incidents, so "it wasn't working earlier" has an answer.
struct RecentProblems: View {
  let monitor: MonitorController

  var body: some View {
    let incidents = monitor.recentIncidents
    if !incidents.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        Text("Problems in the last 24 hours").font(.caption).foregroundStyle(.secondary)
        ForEach(incidents.prefix(3), id: \.start) { incident in
          let bridge = monitor.profiles.first { $0.ssid == incident.ssid }?.bridgeName
          Text(incident.summary(bridge: bridge)).font(.caption)
            .help(incident.evidence)
        }
        if incidents.count > 3 {
          Text("\(incidents.count - 3) more: scripts/linkwatch incidents")
            .font(.caption2).foregroundStyle(.secondary)
        }
      }
    }
  }
}
