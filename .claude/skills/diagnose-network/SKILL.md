---
name: diagnose-network
description: Diagnose this Mac's network with LinkWatch's recorded evidence. Use when the user asks what is going on with their network, Wi-Fi or internet, why it was slow or down at some time ("last night", "this morning"), whether to restart the powerline adapters, router or access point, or whether the problem is their internet provider.
---

# Diagnose the network with LinkWatch

Answer from LinkWatch's measurements, not from general advice. LinkWatch pings the
Wi-Fi access point (AP), the router and two internet references (Cloudflare 1.1.1.1,
Google 8.8.8.8) every two seconds, records download/upload totals, stores one summary
per minute for seven days, and classifies each period with a plain-language verdict.

## 1. Gather the evidence

Run from the repository root:

```sh
scripts/linkwatch diagnose --hours 24 --json
```

- Widen `--hours` (up to 168) when the user mentions an earlier time ("on Tuesday").
- If `dist/LinkWatch.app` is missing, build it first with `bash scripts/build_app.sh`.
- The text form (`scripts/linkwatch diagnose --hours 24`) is useful to show the user.
- For a specific moment, `scripts/linkwatch history --hours N --json` gives every
  stored minute; `scripts/linkwatch incidents --days 7` lists problems with evidence.
- Always use `scripts/linkwatch`, never the bare executable: run directly from a shell,
  macOS hides the Wi-Fi name and the report looks broken.

## 2. Check the data can answer the question

Before concluding anything, read `appRunning`, `status.permitted`, `coverage`, `gaps`
and `notes`.

- **Gaps** mean the Mac was asleep, paused, away from a monitored network, or
  LinkWatch was not running. Say plainly that nothing can be concluded for those
  times; never treat missing data as "everything was fine".
- **`appRunning: false`**: nothing is being recorded; suggest opening LinkWatch.
- **`status.permitted: false`**: Location permission is missing (grant it from the
  app's Settings window; macOS only prompts for the app).
- **Verdict `routerSilent`** with a working internet usually means the Local Network
  permission is missing (System Settings › Privacy & Security › Local Network).

## 3. Explain what happened

Lead with one plain sentence, then the evidence. Use the incidents first; they
already group problem minutes and name the most likely cause.

| Verdict | Meaning | Evidence pattern |
|---|---|---|
| `allClear` | Working normally | All links fast, no loss |
| `accessPoint` | Weak Wi-Fi signal or overloaded AP | AP slow or lossy |
| `bridge` | The link between AP and router (e.g. powerline adapters) | AP fine, router slow or lost while the internet is also affected |
| `routerSilent` | Router ignores pings, traffic still flows | Router lost, internet fine |
| `routerUnreachable` | Router silent, no internet evidence | Router lost, internet not probed |
| `internet` | Provider trouble, nothing to fix at home | Home links fine, internet slow or lost |
| `busy` | The Mac's own large transfer slowed things | Slow (not lost) while moving a lot of data |

- Quote times in the user's local time and give durations ("19:40–20:05, 25 min").
- Cite the numbers that justify the cause, for example "the AP stayed at 3 ms while
  the router reached 400 ms and the internet lost 80%".
- Say "most likely": latency differences are evidence, not proof of a faulty device.
- Give at most one action per incident, matching the verdict's `action` text and the
  profile's bridge name (for example "Restart the TP-Link powerline adapters").
- Mention patterns across incidents (same time of day, recurring after heavy usage).

## 4. Respect privacy and safety

- Reports contain local addresses, network names and hardware addresses. Do not paste
  them into public places (issues, pull requests, chats with others) without redacting.
- Do not run `find-ap` (it pings the whole subnet) or `probe` against other hosts
  without asking. `diagnose`, `status`, `history`, `incidents` and `neighbors` send no
  traffic and are always safe.
- Do not change profiles, pause monitoring or clear history unless the user asks.
