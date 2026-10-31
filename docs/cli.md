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
| `diagnose [--hours N]` | The answer first: live verdict, coverage and unmonitored gaps, incidents with evidence, hourly history and notes on permissions, VPN and missing data. Default 24 h, up to 168. | No |
| `status [--local]` | Everything the panel shows. Reads the running app; `--local` builds a fresh view. | No |
| `watch [--cycles N] [--local]` | `status` every two seconds. Follows the running app; with `--local` or no app running it monitors itself, probing only approved networks. | Only when monitoring itself |
| `incidents [--days N]` | Problems of the last N days (default 7): span, likely cause, evidence per link, action. | No |
| `history [--hours N]` | Hourly rollups (minutes recorded, latency, loss, MB down and up, problem minutes); every stored minute with `--json`. Default 24, up to 168. | No |
| `neighbors` | The Mac's cached ARP neighbours on Wi-Fi and which one matches the access point. | No |
| `probe ADDRESS [--interface IF] [--count N]` | Raw ICMP echoes, for example `probe 127.0.0.1 --interface lo0` as a self-test. Only probe hosts you may test. | Yes |

## Act

These do the same as the panel and the Settings window, and take effect in the
running app immediately.

| Command | Equivalent in the app |
|---|---|
| `accept` | **Monitor this network** or **Update profile** |
| `dismiss` | **Not now** |
| `find-ap` | **Find AP**: pings each address of a private Wi-Fi subnet of /22 or smaller once |
| `pause`, `resume` | **Pause monitoring** |
| `profile list` | Settings › selected networks |
| `profile set --ssid NAME [options]` | Settings › save a profile (see below) |
| `profile remove NAME` | Settings › Remove |
| `history clear` | Settings › **Clear history…** |
| `authorize` | **Allow Wi-Fi identification**: asks the running app to show the Location prompt |

`profile set` options; omitted values keep their current setting, and a new profile
needs `--ap` and `--router`:

| Option | Meaning | Default |
|---|---|---|
| `--ap ADDRESS`, `--router ADDRESS` | Access point and router IPv4 addresses | — |
| `--bridge NAME`, `--no-bridge` | What links the access point to the router, used in advice | none |
| `--internet on\|off` | Also ping Cloudflare 1.1.1.1 and Google 8.8.8.8 | on |
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
