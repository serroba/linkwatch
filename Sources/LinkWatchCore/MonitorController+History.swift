import Foundation

extension MonitorController {
  /// Completes the current minute, for shutdown and before reading history elsewhere.
  public func flushHistory() {
    if let summary = week.flush() { persist(summary) }
  }

  /// Deletes the week of stored minute summaries.
  public func clearHistory() {
    week.clear()
    do {
      try historyStore.clear()
      historyError = nil
      record(.historyCleared)
    } catch {
      historyError = "History could not be cleared."
    }
  }

  /// Rereads stored history, for changes made by another process such as the command line.
  public func reloadHistory() {
    loadHistory()
  }

  func loadHistory() {
    let cutoff = now().addingTimeInterval(-WeekHistory.retention)
    try? events.prune(before: cutoff)
    do {
      week = WeekHistory(minutes: try historyStore.load(since: cutoff))
      try historyStore.prune(before: cutoff)
      historyError = nil
    } catch {
      week = WeekHistory()
      historyError = "Stored history could not be read; new measurements are still recorded."
    }
  }

  func record(_ pair: ProbePair, traffic: TrafficCounters?) {
    guard let ssid = session.profile?.ssid else { return }
    if let summary = week.record(
      pair, health: session.window.health, ssid: ssid, at: now(), traffic: traffic,
      signal: signal, path: connectionPath)
    {
      persist(summary)
    }
  }

  private func persist(_ summary: MinuteSummary) {
    do {
      try historyStore.append(summary)
      // Prune at most hourly: only once the oldest minute is an hour past retention.
      if let oldest = week.minutes.first,
        now().timeIntervalSince(oldest.start) > WeekHistory.retention + 3600
      {
        try historyStore.prune(before: week.prune(now: now()))
      }
    } catch {
      historyError = "History could not be saved; the menu shows only recent measurements."
    }
  }
}

extension MonitorController {
  /// Incidents from the last day, newest first, for the panel.
  public var recentIncidents: [Incident] {
    let since = now().addingTimeInterval(-86_400)
    return IncidentTimeline.incidents(
      from: week.minutes.filter { $0.start >= since }, profiles: profiles
    ).reversed()
  }
}
