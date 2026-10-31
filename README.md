# LinkWatch

**LinkWatch tells you which link of your network is struggling, and what to do
about it, from the macOS menu bar.**

A connection is a chain of links, and the common problems each live on a different
one:

```
Mac ─Wi-Fi─ access point ─bridge (e.g. powerline adapters)─ router ─ISP─ internet
```

LinkWatch measures each link every two seconds: your Wi-Fi access point, your
router and two internet reference points (Cloudflare and Google). It compares
neighbouring links to find the one at fault and turns the evidence into one plain
sentence anyone in the household can act on, such as *"Restart the TP-Link powerline
adapters"* or *"Your internet provider is having trouble; nothing to fix at home"*.
It keeps a week of history, so "the internet wasn't working last night" has an
answer too.

## What you see

The menu bar icon is coloured by the current verdict, with live numbers next to it
(`AP 3 · R 7 ms`):

| Icon | Meaning |
|---|---|
| Green check | Everything is working normally. |
| Yellow arrows | Busy: the Mac's own large download or upload is slowing things; nothing is broken. |
| Orange globe | The internet provider is having trouble; nothing to fix at home. |
| Red warning | A home link needs action: the access point, or the bridge between it and the router. |
| Purple stop | The router is not answering LinkWatch, usually a permission rather than a fault. |
| Grey pause | Not monitoring: paused, an unselected network or a missing permission. |

Clicking it opens the advice, latency for each link, packet loss, download and
upload rates, a chart of the last hour, day or week, and the problems of the last
24 hours. The [user guide](docs/user-guide.md) explains each part.

## Install

On macOS 14 or later:

```sh
curl -fsSL https://raw.githubusercontent.com/serroba/linkwatch/main/scripts/install.sh | bash
```

Run it again to update. See [installing LinkWatch](docs/install.md) for reviewing
the script first, manual installation, first-run permissions and uninstalling.

## Ask "what's going on with my network?"

Everything in the app is also available from the command line, as text or JSON:

```sh
scripts/linkwatch diagnose --hours 24   # verdict, coverage, incidents with evidence, hourly history
scripts/linkwatch incidents --days 7    # when it broke, for how long, the likely cause
```

In this repository, coding agents such as Claude Code answer that question from the
recorded evidence using the
[`diagnose-network` skill](.claude/skills/diagnose-network/SKILL.md). The
[command-line reference](docs/cli.md) lists every command.

## Privacy

LinkWatch monitors only the Wi-Fi networks you approve, keeps settings and history
on the Mac, and sends no telemetry. It pings your own devices and, unless you turn
it off per network, Cloudflare and Google. [Privacy](docs/privacy.md) details what is
measured, sent and stored.

## Documentation

| Document | For |
|---|---|
| [User guide](docs/user-guide.md) | Everyday use: colours, advice, setup, common questions |
| [Installing](docs/install.md) | Install, update, permissions, uninstall, releases |
| [Command line](docs/cli.md) | Every command, for people, scripts and agents |
| [Privacy](docs/privacy.md) | What is measured, sent and stored |
| [Monitoring semantics](docs/monitoring.md) | Exact rules: probes, alerts, verdicts, incidents, history |
| [Architecture](docs/architecture.md) | How the code fits together |
| [Roadmap](docs/roadmap.md) | What comes next |
| [Verification](docs/verification.md) | Manual checks before distribution |
| [Contributing](CONTRIBUTING.md) | Building, checks and the pull request workflow |

## Status

LinkWatch is an early, actively developed open-source project. Releases are signed
with a local identity or ad hoc, not yet with an Apple Developer ID, so macOS may
ask for confirmation when installing by hand. Measurements are evidence, not proof:
latency differences point at the most likely link, not at a confirmed faulty device.

LinkWatch is open source under the [MIT licence](LICENSE).
