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
| Orange pulse | Lag spikes on a home link: typical latency is fine, but frequent slow moments make calls stutter. |
| Grey pause | Not monitoring: paused, an unselected network or a missing permission. |

Clicking it opens the advice, latency for each link, packet loss, download and
upload rates, a chart of the last hour, day or week, and the problems of the last
24 hours. The [user guide](docs/user-guide.md) explains each part.

## Install

LinkWatch runs on macOS 14 (Sonoma) or later. Open **Terminal** and run:

```sh
curl -fsSL https://raw.githubusercontent.com/serroba/linkwatch/main/scripts/install.sh | bash
```

This downloads the latest [release](https://github.com/serroba/linkwatch/releases),
checks it against its published checksum, installs `LinkWatch.app` in
`/Applications` and opens it. It needs no administrator password. Run the same
command again at any time to update. To read the script before running it, or to
install by hand, see [installing LinkWatch](docs/install.md).

## Getting started

1. **Find the icon.** LinkWatch lives in the menu bar at the top of the screen, not
   in the Dock. It opens automatically at login from now on.
2. **Allow Wi-Fi identification.** Click the icon → **Settings…** → **Allow Wi-Fi
   identification** → **Allow**. macOS only reveals the Wi-Fi name to apps with
   Location permission; LinkWatch never reads where you are.
3. **Monitor your network.** Back in the panel, LinkWatch suggests your current
   Wi-Fi network with its router and, if found, its access point. Click **Monitor
   this network**. If the access point is missing, click **Find AP**, or enter its
   address in Settings.
4. **Allow Local Network access if asked.** If the icon turns purple and says the
   router is not answering, open **System Settings › Privacy & Security › Local
   Network** and switch on **LinkWatch**.
5. **Optionally name the link** between your access point and router in Settings,
   for example *TP-Link powerline adapters*, so the advice can say "Restart the
   TP-Link powerline adapters".

After an update, if the icon is grey or purple, repeat steps 2 and 4: releases are
not yet signed by Apple, so macOS may ask again.

## Everyday use

- **Glance at the icon.** Its colour and shape say how things are (see the table
  above); you do not need to open anything.
- **Open the panel** for the advice, latency per link, download and upload, the
  chart for the last hour, day or week, and the problems of the last 24 hours.
- **Say you restarted something**: after restarting the powerline adapters, router
  or phone, click **I restarted…**. A few minutes later the panel says whether it
  helped, for example *"router 85 → 4 ms"*.
- **On a phone hotspot**, LinkWatch recognises it, talks about the phone (move it
  near a window, or bring the Mac closer) and pings the internet less often to save
  mobile data.
- **Mark what you are doing** when you suspect something at home affects the
  connection: type it into **What just happened?** (for example *desk moved*) and
  click **Mark**. After three or more marks, the diagnosis says whether the
  connection got worse around them and which link was affected.
- **Test a suspect device** in 90 seconds: type its name (for example *desk*) next to
  **Test** and follow the prompts: 30 seconds as usual, 30 seconds with it on (or
  moving), 30 seconds off. LinkWatch then says which link, if any, it disturbs.
- **Share a report** when someone else looks after the network: click **Export
  report…**. LinkWatch saves a folder with the last week's diagnosis and
  measurements and shows it in Finder, ready to send by AirDrop or Messages. It
  contains your network name and local addresses, so share it only with people you
  trust.
- **Pause** monitoring from the panel when you do not want any measurements.

The [user guide](docs/user-guide.md) explains every part of the panel and answers
common questions.

## Ask "what's going on with my network?"

Everything in the app is also available from the command line, as text or JSON.
From a clone of this repository (or with the app installed in `/Applications`):

```sh
scripts/linkwatch diagnose --hours 24   # the answer first, then the evidence
scripts/linkwatch incidents --days 7    # when it broke, for how long, the likely cause
scripts/linkwatch mark desk moved       # note what you are doing now
scripts/linkwatch restarted --wait      # note a restart, then say whether it helped
scripts/linkwatch test-device desk      # guided 90-second test with prompts
scripts/linkwatch export --redact       # a shareable report without names or addresses
```

In this repository, coding agents such as Claude Code answer that question from the
recorded evidence using the
[`diagnose-network` skill](.claude/skills/diagnose-network/SKILL.md), including from
a report exported on another Mac. The [command-line reference](docs/cli.md) lists
every command.

## Updating and uninstalling

Run the install command again to update; it quits LinkWatch, replaces it and opens
the new version. To uninstall, follow the steps in
[installing LinkWatch](docs/install.md#uninstall).

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
