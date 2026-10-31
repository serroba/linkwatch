# Command line

The LinkWatch app executable doubles as a command-line tool, so everything the menu
bar panel shows, and every action it offers, is available to people, scripts and
coding agents. `scripts/linkwatch help` prints the same reference.

Run commands through the wrapper:

```sh
scripts/linkwatch <command> [options]
```

It uses `LINKWATCH_APP` when set, otherwise this checkout's `dist/LinkWatch.app`,
then `/Applications/LinkWatch.app`, then `~/Applications/LinkWatch.app`. It
launches the bundle through LaunchServices, so macOS treats LinkWatch rather than
the terminal as responsible for Location access and reveals the Wi-Fi name. Running
the bare executable from a shell works but sees the network name redacted. Output
streams back and the exit code is preserved; interrupting the wrapper stops the run.

Add `--json` to any command for machine-readable output (JSON Lines for `watch`).
Absent values are `null`, dates are ISO 8601, rates are bits per second and
latencies milliseconds. Output contains local addresses, network names and hardware
addresses; review it before sharing.

## Inspect

| Command | What it shows | Sends traffic |
|---|---|---|
| `diagnose [--hours N]` | The answer first: live verdict, coverage and unmonitored gaps (explained by events), incidents with evidence, the effect of marked activities, hourly history, events and notes on permissions, VPN and missing data. Default 24 h, up to 168. | No |
| `status [--local]` | Everything the panel shows. Reads the running app; `--local` builds a fresh view. | No |
| `watch [--cycles N] [--local]` | `status` every two seconds. Follows the running app; with `--local` or no app running it monitors itself, probing only approved networks. | Only when monitoring itself |
| `summary [--days N]` | The week at a glance (default 7 days): problems per part of the connection, busiest hours of the day, latency under heavy use, restarts and what to change. | No |
| `incidents [--days N]` | Problems of the last N days (default 7): span, likely cause, evidence per link, action. | No |
| `history [--hours N]` | Hourly rollups (minutes recorded, latency, loss, MB down and up, problem minutes); every stored minute with `--json`. Default 24, up to 168. | No |
| `events [--hours N]` | App and system events (launches, sleep, Wi-Fi changes, permission changes, pauses, verdict changes, marks), default 24 h, up to 168. | No |
| `neighbors` | The Mac's cached ARP neighbours on Wi-Fi and which one matches the access point. | No |
| `probe ADDRESS [--interface IF] [--count N]` | Raw ICMP echoes, for example `probe 127.0.0.1 --interface lo0` as a self-test. Only probe hosts you may test. | Yes |

## Act

These do the same as the panel and the Settings window, and take effect in the
running app immediately.

| Command | Equivalent in the app |
|---|---|
| `accept` | **Monitor this network** or **Update profile** |
| `dismiss` | **Not now** |
| `detect` | **Detect again**: rechecks whether this Mac is connected through the access point or the router's own Wi-Fi, then prints the status; sends no traffic |
| `find-ap` | **Find AP**: pings each address of a private Wi-Fi subnet of /22 or smaller once |
| `pause`, `resume` | **Pause monitoring** |
| `test-device NAME` | **Test**: a guided 90-second test in the running app; prints each instruction as its phase starts, then the conclusion and per-phase spikes and loss |
| `restarted [DEVICE] [--wait]` | **I restarted…**: notes a restart (default: the profile's bridge name, the phone on a hotspot, or the router); `--wait` waits about five minutes and prints whether it helped |
| `mark LABEL` | **Mark**: notes what you are doing now, such as `mark desk moved`, in the running app's event log |
| `profile list` | Settings › selected networks |
| `profile set --ssid NAME [options]` | Settings › save a profile (see below) |
| `profile remove NAME` | Settings › Remove |
| `history clear` | Settings › **Clear history…** |
| `export [--days N] [--dir PATH] [--redact]` | **Export report…**: writes `report.txt` (opening with the summary), `report.json`, `summary.json` and `minutes.json` for the last N days (default 7) into a dated folder and prints its path; `--redact` replaces network names, local addresses and hardware addresses with placeholders |
| `authorize` | **Allow Wi-Fi identification**: asks the running app to show the Location prompt |
| `update [--install] [--auto on\|off]` | Checks GitHub for a newer release now; `--install` runs the bundled installer (copies in an Applications folder only); `--auto` is Settings › **Check for updates once a day** |
| `widget [on\|off] [--behind\|--on-top]` | Settings › **Show a desktop widget** and **Widget placement**; without arguments, shows the current state |
| `notifications [on\|off]` | Settings › **Notify me when a problem lasts 3 minutes**; turning it on asks macOS for permission once; without an argument, shows the current state |
| `open-at-login [on\|off]` | Settings › **Open LinkWatch at login**; without an argument, shows the current state |

`profile set` options; omitted values keep their current setting, and a new profile
needs `--router` (the access point is optional):

| Option | Meaning | Default |
|---|---|---|
| `--router ADDRESS` | Router IPv4 address | — |
| `--ap ADDRESS`, `--ap none` | Access point IPv4 address, or none when there is no separate AP | none |
| `--bridge NAME`, `--no-bridge` | What links the access point to the router, used in advice | none |
| `--internet on\|off` | Also ping Cloudflare 1.1.1.1 and Google 8.8.8.8 | on |
| `--hotspot on\|off` | The network is a phone's personal hotspot: advice names the phone, internet pings every 10 s | off, or on when detected |
| `--difference MS`, `--recovery-difference MS` | Router-minus-AP alert and recovery thresholds | 20, 10 |
| `--slow MS`, `--recovery-slow MS` | Both-slow alert and recovery thresholds | 30, 20 |
| `--sustained SECONDS`, `--recovery SECONDS` | How long a change must hold before alerting or clearing | 10, 6 |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | The action failed or found nothing (no replies, no suggestion, unknown profile) |
| 64 | Usage error |
| 69 | Unavailable: no app installed, the app not running for an app action, no Wi-Fi interface |
| 70 | The app ended without reporting a status |
| 77 | Location permission denied or not granted |

## How it reaches the running app

The command line talks to the running app with local distributed notifications that
carry no settings. They can pause, resume, dismiss a suggestion, reload profiles or
history from the user's own storage, request the Location prompt, or ask for a
status reply. Replies are written only to `status.json` in a new directory the
requester created in the user's temporary folder (owner-only, created exclusively,
never following links). Any local process of the same user could pause monitoring
or hide a suggestion this way; none can change settings or read files through it.

## Examples

```sh
scripts/linkwatch diagnose --hours 12                     # what happened today?
scripts/linkwatch incidents --days 7 --json | jq length   # how many problems this week?
scripts/linkwatch watch --cycles 30 --json > session.jsonl
scripts/linkwatch profile set --ssid "Home" --bridge "TP-Link powerline adapters"
scripts/linkwatch history --hours 168 --json | jq '[.[] | .received] | add'
```
