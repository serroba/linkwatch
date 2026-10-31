# Architecture

LinkWatch is a Swift package with three modules. The rules live in a pure core so
they can be tested without a network, a Mac's permissions or a user interface.

```
LinkWatchApp ──────────► LinkWatchCore ◄────────── LinkWatchNetworking
SwiftUI menu bar,        rules, state machine,     ICMP sockets, ARP cache,
CLI, macOS adapters      reports (pure Swift)      interface counters
```

## LinkWatchCore

Pure logic with injected dependencies; everything here is unit tested.

| File | Responsibility |
|---|---|
| `Monitoring.swift` | Probe outcomes, paired measurements, internet references, the rolling window (medians, loss, evidence) and the sustained alert state machine. |
| `Profiles.swift` | Network profiles, address validation, Wi-Fi identity and the monitoring session (which profile applies, stale-result rejection by generation). |
| `MonitorController.swift` | The `@Observable` coordinator: selects the session, runs one probe cycle at a time, handles pause, sleep and network changes. Depends on `LatencyProbe`, `NetworkEnvironment`, `ProfileStore`, `HistoryStore` and two clocks. |
| `MonitorController+*.swift` | Extensions for history recording, the sustained verdict, usage rates, probing and the Find AP search. |
| `Verdict.swift` | Link evidence, the load heuristic and the verdict rules with their sentence and action. |
| `Discovery.swift`, `SubnetSweep.swift` | Passive router and access point discovery, and the bounded Find AP address list. |
| `WeekHistory.swift`, `FileHistoryStore.swift` | Minute aggregation, retention and JSON Lines storage. |
| `Incident.swift`, `HourSummary.swift` | Incident grouping and hourly rollups computed from stored minutes. |
| `StatusReport.swift`, `DiagnoseReport.swift` | Everything the panel shows, and the diagnosis bundle, as text and JSON. |
| `HeadlessCommand.swift` | Command-line parsing and profile updates. |

## LinkWatchNetworking

Thin, defensive wrappers over Darwin system interfaces; no shell commands.

| File | Responsibility |
|---|---|
| `ICMPProbe.swift` | Unprivileged ICMP datagram sockets bound to an interface with `IP_BOUND_IF`, strict reply matching and cancellation. |
| `NeighborTable.swift` | The ARP cache through `sysctl(NET_RT_FLAGS, RTF_LLINFO)`. |
| `InterfaceCounters.swift` | 64-bit byte counters through `sysctl(NET_RT_IFLIST2)`. |
| `InterfaceAddresses.swift` | An interface's IPv4 address and netmask through `getifaddrs`. |

## LinkWatchApp

| File | Responsibility |
|---|---|
| `Monitor.swift` | Wires the controller to macOS: CoreWLAN and CoreLocation (`SystemEnvironment`), SystemConfiguration routes, sleep and wake, path changes, profile storage in `UserDefaults` and the timer loops. |
| `LinkWatchApp.swift`, `HistoryCharts.swift` | The menu bar label, panel and Settings window, observing the controller directly. |
| `Headless.swift`, `HeadlessActions.swift` | The entry point: commands run headlessly, otherwise the menu bar app starts. |
| `AppControl.swift` | Distributed notifications between command-line runs and the running app, and the private status reply. |

## One probe cycle

1. Every two seconds `MonitorController.cycle()` refreshes the Wi-Fi identity and
   selects the profile. No profile, no permission, paused or asleep means no probes.
2. It pings the access point, router and internet references concurrently, bound to
   the Wi-Fi interface, and stamps the result with monotonic uptime.
3. Results from an older session (a network change, roam, pause or sleep in between)
   are discarded by generation.
4. The accepted pair updates the rolling window and alert state, the usage rate, the
   current minute of history and the sustained verdict.
5. The panel observes the controller; the command line reads the same state through
   `StatusReport`.

## Design rules

- Keep rules in `LinkWatchCore`, behind protocols, and test them with fakes and
  injected clocks; see `Tests/LinkWatchCoreTests/ControllerHarness.swift`.
- Never probe without an approved profile; never send traffic during discovery.
- Use monotonic time for measurements and wall-clock time only for stored history.
- Compute verdicts, incidents and rollups when read, so rule changes apply to the
  whole stored week.
- Prefer explicit nulls and stated gaps over guesses in anything a person or agent
  reads.
