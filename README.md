# LinkWatch

**LinkWatch helps you notice and investigate local network latency by comparing
responses from your Wi-Fi access point and router, directly in the macOS menu bar.**

The objective is a lightweight native app that answers: **“Is the delay already
visible at the access point, or is the router responding noticeably later?”**
It keeps paired measurements visible while you work, highlights sustained changes,
and provides enough recent history to investigate intermittent problems.

## Intended experience

The menu bar shows a health indicator and live numbers, for example
`● AP 1 · R 62 ms`. Clicking it opens latency, packet loss, about 15 minutes of history, the
router-minus-AP difference, the active network and the duration of an alert.
Pause controls and local network-profile settings make monitoring explicit.

- **Green check:** no sustained degradation detected.
- **Red warning:** the router is persistently slower than the configured AP.
- **Amber warning:** both targets are slow; local Wi-Fi or laptop delay may be involved.
- **Purple stop:** a target is unreachable, identified by name and shown as `—`, never zero.
- **Grey pause:** monitoring is paused, the network is unselected, or Wi-Fi identity is unavailable.

Numbers and explanatory text accompany colour so the state remains understandable
without relying on colour alone. Desktop notifications are off by default.

## Monitoring and privacy

You explicitly choose which Wi-Fi networks to monitor and configure an AP and
router address for each. Other networks generate no probes. Missing permission,
disconnection and manual pause also stop monitoring.

When the Mac joins a Wi-Fi network without a profile, LinkWatch suggests one. It
reads the default router (only when Wi-Fi owns the default route) and the Mac's
existing ARP cache, and proposes an AP only when exactly one cached neighbour on
the Wi-Fi interface matches the associated BSSID. It never scans the subnet or
sends traffic to find the AP; if the AP is not cached, or is the router itself, you
enter it manually. Nothing is probed until you accept, and changed addresses on a
known network are offered as an update rather than applied silently.

The starting cadence is one paired measurement every two seconds, with latency
displayed as the median of the last five samples. A router-minus-AP difference
above 20 ms must persist for ten seconds before alerting. Recovery uses lower
thresholds and sustained healthy samples to avoid flickering. Thresholds are
configurable; [monitoring semantics](docs/monitoring.md) define the exact rules.

Settings stay on the Mac, history is bounded and held in memory, and no telemetry
or subnet scanning is part of the design. macOS Location permission is used to
identify the current Wi-Fi network; the app does not need location coordinates.
Probes bind to the selected Wi-Fi interface. Network changes, roaming and
sleep/wake must cancel pending work and discard stale measurements.

## What the measurements mean

AP and router ICMP replies come from different device response paths. Their
difference is useful evidence, but **does not prove a faulty Ethernet uplink,
access point, router or Internet connection**. Strong Wi-Fi signal and a high
negotiated rate do not rule out latency problems either.

LinkWatch is a local latency observer, not a bandwidth speed test, packet sniffer,
network scanner or automatic fault diagnosis tool. The configured AP address may
also differ from the device currently carrying traffic after roaming; the app
must make that distinction visible.

## Development status

The monitoring core, network-profile validation, stale-result protection and
native interface-bound IPv4 ICMP adapter are implemented and tested. Repository
checks, Swift formatting, macOS builds, deterministic tests and a loopback probe
run in CI. A native menu bar app, local profile settings and an ad-hoc-signed
app bundle are available as a development prototype.

The first usable milestone is a locally runnable macOS app with paired live
measurements, explicit profile selection, safe pause and lifecycle handling, and
configurable sustained alerts. Real-network and UI verification are still needed.
Developer ID signing, notarisation and release packaging remain separate work;
this is not yet a public distribution release.

## Build and run locally

Requires macOS 14 or later and a Swift 6.1-compatible Apple toolchain. CI uses
macOS 15 and Xcode 16.4.

```sh
bash scripts/build_app.sh
open dist/LinkWatch.app
```

Open **Settings** from the menu bar panel, allow Wi-Fi identification, and select
**Use current Wi-Fi** or enter the exact network name. Enter distinct AP and router
IPv4 addresses, adjust thresholds if needed, and explicitly save the profile to
allow monitoring. A router address is suggested only when Wi-Fi owns the default
route. No profile or network addresses are preconfigured.

macOS may also request Local Network access when the first probe is sent. If
access is denied, measurements fail visibly; review Location and Local Network
permissions in System Settings. The app never requests location coordinates.
Rebuilding the ad-hoc-signed prototype may affect remembered permissions.

The bundle is for local development, not notarised public distribution. See the
[verification checklist](docs/verification.md) for remaining manual checks.

## Headless diagnosis

The app executable also runs as a command-line tool, so everything the menu bar
shows is available as text or JSON for scripts and coding agents:

```sh
scripts/linkwatch status            # state, latency, loss, alert, discovery, profiles
scripts/linkwatch status --json     # the same as JSON; absent values are null
scripts/linkwatch watch --cycles 5  # monitor headlessly, one report per 2 s cycle
scripts/linkwatch neighbors         # cached ARP neighbours and the BSSID match
scripts/linkwatch probe 127.0.0.1 --interface lo0  # raw ICMP self-test
scripts/linkwatch authorize         # request Location permission from the terminal
```

Commands run through the app bundle, so they share its Location permission and
saved profiles. `status`, `neighbors` and `authorize` send no traffic, and `watch`
probes only networks with a saved profile, like the app. Output contains local
network addresses; review it before sharing.

See [CONTRIBUTING.md](CONTRIBUTING.md) for build checks and the required PR workflow.
LinkWatch is open source under the [MIT licence](LICENSE).
