# Roadmap

LinkWatch aims to answer the question people actually ask, **"which link is
struggling, and what should I do about it?"**, in one plain sentence anyone in the
household can act on, live and after the fact, while keeping the evidence available
for whoever looks after the network.

```
Home:     Mac ─Wi-Fi─ access point ─bridge (e.g. powerline adapters)─ router ─ISP─ internet
Tether:   Mac ─Wi-Fi/USB─ phone ─cellular─ internet
```

Two everyday cases drive the plan: an access point connected to the router through
powerline adapters that degrade until restarted, and a laptop tethered to a phone,
where the fix is either moving the phone or fixing the link to it. History matters
as much as live state: "the internet wasn't working last night" should show when it
happened and which link failed, on the Mac where it happened.

## Done

- **Paired monitoring** of the access point and router with sustained alerts,
  network-profile opt-in, stale-result protection and lifecycle handling.
- **Network discovery**: router from the Wi-Fi service, access point from the ARP
  cache, and an opt-in **Find AP** search.
- **Internet reference points**: Cloudflare and Google, blamed only when both are
  slow or lost.
- **Plain-language verdict**, live and for every stored minute, naming the bridge.
- **Usage**: download and upload rates and bytes per minute, with a **busy** verdict
  so heavy transfers are not mistaken for failing equipment.
- **Seven-day history** of minute summaries, an **incident timeline**, and the menu
  bar icon **coloured by verdict**.
- **Command line** for every panel and Settings action, and **`diagnose`** with a
  project skill so coding agents answer "what's going on with my network?" from the
  evidence.
- **Releases** from version tags with a checksum-verifying installer.
- **Marks and a guided device test** to check whether something at home, such as an
  electric desk, disturbs a link, and an **event log** that explains gaps.
- **Lag-spike detection**, so stutter hidden behind healthy medians is reported.
- **Wi-Fi signal readings** (RSSI, noise, SNR, link rate, channel), separating a
  weak signal from a struggling access point in the verdict and the history.
- **Export report** for sending a week of evidence from another Mac, with optional
  redaction, which the diagnose skill reads directly.
- **Survives restarts**: opens at login, and settings and the week of history are
  kept on disk; the hour chart fills in from stored minutes after a restart.
- **Phone hotspots and single-box routers**: a network whose access point is the
  router is monitored with one ping per cycle. A personal hotspot is recognised
  (macOS marks the path as expensive, or the iPhone hotspot range), advice names the
  phone ("move the phone near a window", "bring the Mac and the phone closer"), and
  internet reference pings run every 10 seconds to save mobile data.
- **"I restarted…"**: records a restart and, a few minutes later, says whether it
  helped, for example "router 85 → 4 ms", in the panel, `status` and `diagnose`.

## Next

1. **Easier updates.** A Homebrew tap (`brew install --cask linkwatch`) or an in-app
   "update available" notice built on the releases.
2. **Simple mode.** Only the coloured icon and the sentence, with details one click
   away, plus an optional notification once a problem has lasted a few minutes
   (asks for Notifications permission).
3. **Weekly summary.** Incidents per link, typical duration, time-of-day patterns and
   latency under load, to decide whether to move or replace equipment.
4. **App icon.**

Later: optionally power-cycling a bridge through a smart plug once verdicts have
proven reliable.

## Distribution

LinkWatch is free and open source, and is meant to stay free.

- **Today:** GitHub Releases with an installer that verifies checksums. Builds are
  signed ad hoc or with a project identity, not by Apple, so installing by hand asks
  for confirmation and ad-hoc updates need permissions granted again.
- **Developer ID and notarisation** (Apple Developer Program, USD 99 per year):
  clean installs from any download, permissions kept across updates, a Homebrew cask
  without warnings, and no feature changes. This is the recommended next step.
- **Mac App Store**, free: the same membership, plus the App Sandbox. Several
  features would need entitlements or redesign: reading the Wi-Fi name (Location),
  ICMP sockets, the ARP cache and interface counters through `sysctl`, the command
  line and its messaging with the app, and the Find AP sweep, which App Review may
  question. It also needs an app icon, screenshots and a privacy policy (simple,
  since nothing leaves the Mac). Worth revisiting once the feature set settles.
