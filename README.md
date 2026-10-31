# LinkWatch

**LinkWatch helps you notice and investigate local network latency by comparing
responses from your Wi-Fi access point and router, directly in the macOS menu bar.**

The objective is a lightweight native app that answers: **“Is the delay already
visible at the access point, or is the router responding noticeably later?”**
It keeps paired measurements visible while you work, highlights sustained changes,
and provides enough recent history to investigate intermittent problems.

The direction is to answer the question people actually ask, **“which link is
struggling, and what should I do about it?”**, in one plain sentence that anyone in
the household can act on, while keeping the numbers available for whoever wants them.
See the [roadmap](#roadmap).

## Intended experience

The menu bar shows a health indicator and live numbers, for example
`● AP 1 · R 62 ms`. Clicking it opens latency, packet loss, history for the last hour,
day or week, the
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
reads the router assigned to the Wi-Fi service (even when a VPN owns the default
route) and the Mac's
existing ARP cache, and proposes an AP only when exactly one cached neighbour on
the Wi-Fi interface matches the associated BSSID. Discovery itself sends no traffic.
Bridged and mesh APs are often absent from the cache; you can then enter the AP
manually or click **Find AP**, which pings each address of a private Wi-Fi subnet of
/22 or smaller once so macOS learns the AP's hardware address. The search runs only
when you ask, never automatically, and refuses public or larger networks. Nothing is probed until you accept, and changed addresses on a
known network are offered as an update rather than applied silently.

The starting cadence is one paired measurement every two seconds, with latency
displayed as the median of the last five samples. A router-minus-AP difference
above 20 ms must persist for ten seconds before alerting. Recovery uses lower
thresholds and sustained healthy samples to avoid flickering. Thresholds are
configurable; [monitoring semantics](docs/monitoring.md) define the exact rules.

Settings and history stay on the Mac, and there is no telemetry. The last hour is
kept in memory as raw 2-second pairs; per-minute summaries (median, 95th percentile
and loss for each target, and the worst state) are stored privately for seven days
and can be cleared in Settings. The only subnet-wide traffic is the explicit,
one-time **Find AP** search and, when enabled for a profile, the internet reference
pings to Cloudflare and Google. macOS Location permission is used to identify the
current Wi-Fi network; the app does not need location coordinates.
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

## Roadmap

A connection is a chain of links, and the common problems each live on a different one:

```
Home:     Mac ─Wi-Fi─ AP ─bridge (e.g. powerline adapters)─ Router ─ISP─ Internet
Tether:   Mac ─Wi-Fi/USB─ Phone ─cellular─ Internet
```

Two everyday examples drive the plan: a Wi-Fi access point connected to the router
through powerline adapters that degrade until they are restarted, and a laptop
tethered to a phone, where the fix is either moving the phone for better reception or
fixing the link between laptop and phone. Comparing neighbouring links locates the
fault; reference points on the internet separate home problems from provider ones.

History matters as much as live state: when someone says "the internet wasn't
working last night", the stored week should show **when** it happened and **which
link** failed, on the Mac where it happened.

Planned work, in order:

1. **Internet reference points.** Probe Cloudflare (`1.1.1.1`) and Google
   (`8.8.8.8`) alongside the AP and router. The internet is blamed only when both are
   slow, so one provider's hiccup does not trigger advice. These probes leave the
   local network and reveal the public address to those providers, so they are a
   per-profile setting, documented, and slowed down on metered connections.
2. **Plain-language verdict, live and in history.** Each profile can name what sits
   between the AP and the router (for example "Powerline adapters (TP-Link)"), and
   LinkWatch turns measurements into one sentence and at most one action. The same
   rules classify every stored minute, so past problems get the same explanation:

   | First hop | Router | Internet | Verdict |
   |---|---|---|---|
   | OK | OK | OK | Everything is working normally. |
   | OK | slow or lost | any | Restart the bridge between the AP and the router (e.g. the powerline adapters). |
   | slow, weak signal | slow | slow | The Wi-Fi signal is weak here; move closer. Restarting the bridge will not help. |
   | slow, good signal | slow | slow | The access point itself is slow; try restarting it. |
   | OK | OK | both slow | The internet provider is having trouble; nothing to fix at home. |
   | Phone slow or lossy | — | any | The link to the phone is weak; bring the laptop closer, use a cable, or restart the hotspot. |
   | Phone OK | — | both slow | Phone reception is poor; move the phone, for example near a window. |

   Verdicts follow the existing sustained-alert rules and say "most likely": latency
   differences are evidence, not proof of a faulty device.
3. **Incident timeline.** Consecutive problem minutes grouped into incidents with
   start, end, the failing link and the verdict, for example "yesterday 19:40–20:05:
   the link between the AP and the router failed (router 100% loss, AP and internet
   fine)". Shown in the app and by `scripts/linkwatch incidents --days 7`.
4. **Shareable report.** An **Export report** button that writes a short text and
   JSON summary of recent incidents and minute data, to send by AirDrop or message to
   whoever looks after the network. It contains local addresses, so it is only
   created on request and never sent automatically.
5. **Releases.** Versioned builds from CI attached to GitHub Releases on each tag,
   then an easy update path (a Homebrew tap or an in-app update notice), so new
   versions install on another Mac without building. A clean install needs an Apple
   Developer ID and notarisation; without it, Gatekeeper requires right-click › Open
   for each release. The signing key would live in CI secrets, so its handling must
   be decided deliberately.
6. **Wi-Fi signal readings.** Signal strength, noise and link rate from macOS, with
   no extra traffic, to separate "move closer" from "the access point is struggling".
7. **Simple mode.** Only the coloured icon and the sentence, with details one click
   away, plus an optional notification once a problem has lasted a few minutes.
8. **Automatic phone-tether mode.** A personal hotspot is detected because macOS
   marks the path as expensive and the first hop is also the router; the verdicts
   switch to phone wording without setup.
9. **"I restarted it."** Record a restart in the history and show its effect a few
   minutes later, for example "router latency 85 → 4 ms".
10. **Weekly summary.** From the stored week: incidents per link, typical duration
    and time-of-day patterns, to decide whether to move or replace equipment.

Later: optionally power-cycling a bridge through a smart plug once verdicts have
proven reliable.

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
allow monitoring. The router suggested is the one assigned to the Wi-Fi service,
so it stays correct while a VPN owns the default route. No profile or network
addresses are preconfigured.

macOS may also request Local Network access when the first probe is sent. If
access is denied, measurements fail visibly; review Location and Local Network
permissions in System Settings. The app never requests location coordinates.
macOS ties the Location grant to the code signature. An ad-hoc signature changes
with every build, so `build_app.sh` signs with a local "LinkWatch Local Development"
code-signing identity when one exists; see [CONTRIBUTING.md](CONTRIBUTING.md).

The bundle is for local development, not notarised public distribution. See the
[verification checklist](docs/verification.md) for remaining manual checks.

## Headless diagnosis and control

The app executable also runs as a command-line tool. Everything the menu bar panel
shows, and every action it offers, is available as text or JSON for scripts and
coding agents (`scripts/linkwatch help` lists all options):

```sh
scripts/linkwatch status [--json]   # live state of the running app: latency, loss, alert,
                                    # Wi-Fi facts, discovery, suggestion, profiles
scripts/linkwatch watch --cycles 5  # follow the running app every 2 s (JSON Lines with --json)
scripts/linkwatch accept            # "Monitor this network" / "Update profile"
scripts/linkwatch dismiss           # "Not now"
scripts/linkwatch find-ap           # opt-in one-time subnet ping to locate the AP
scripts/linkwatch pause | resume    # the panel's pause toggle
scripts/linkwatch profile list | set --ssid NAME [--ap A] [--router R] [--difference MS ...]
scripts/linkwatch profile remove NAME
scripts/linkwatch history --hours 6 # hourly rollups of the stored week (--json: every minute)
scripts/linkwatch history clear     # delete the stored week, as in Settings
scripts/linkwatch neighbors         # cached ARP neighbours and the BSSID match
scripts/linkwatch probe 127.0.0.1 --interface lo0  # raw ICMP self-test
scripts/linkwatch authorize         # ask the running app to request Location permission
```

`status` and `watch` read the running app's live state; with `--local`, or when the
app is not running, they build a fresh view and `watch` monitors headlessly. Profile
changes made from the command line take effect in the running app immediately.

Commands launch the app bundle through LaunchServices, so macOS treats LinkWatch,
not the terminal, as responsible for Location access and reveals the Wi-Fi name;
output streams back and the exit code is preserved. The command line reaches the
running app through local distributed notifications that carry no settings: they
can pause, resume, dismiss a suggestion, reload profiles from the user's defaults
or request a status reply, which is written only into a new private directory the
requester created. Output contains local network addresses; review it before sharing.

See [CONTRIBUTING.md](CONTRIBUTING.md) for build checks and the required PR workflow.
LinkWatch is open source under the [MIT licence](LICENSE).
