# LinkWatch user guide

LinkWatch watches your connection quietly in the menu bar and tells you, in one
sentence, whether something is wrong and what to do about it.

## The icon

Look at the icon at the top of the screen. You do not need to open anything to know
how things are:

| Icon | What it means | What to do |
|---|---|---|
| Green check | Everything is working normally. | Nothing. |
| Yellow arrows | Something on this Mac is downloading or uploading a lot, which slows everything else. Nothing is broken. | Wait for it to finish, or pause it. |
| Orange globe | Your internet provider is having trouble. | Nothing to fix at home. Wait, or contact the provider if it lasts. |
| Red warning | A device at home needs attention. | Open the panel: it says which device to restart. |
| Purple stop | LinkWatch cannot reach the router, usually because of a permission. | See "The router is not answering" below. |
| Grey pause | LinkWatch is not watching: paused, not set up for this network, or missing a permission. | Open the panel to see why. |

The numbers next to it are how long, in milliseconds, the access point (`AP`) and
the router (`R`) take to answer. Lower is better; single digits are typical at home.

## The panel

Click the icon to open the panel. From the top:

- **The advice**: one sentence about what is happening and, when there is
  something to do, one action, for example *"Restart the TP-Link powerline
  adapters."* LinkWatch waits ten seconds before changing its advice, so a single
  slow moment never triggers it.
- **Latency** for the access point, the router and the internet, and the
  difference between the router and the access point.
- **Usage**: how fast this Mac is downloading and uploading right now.
- **The chart**: choose **1 h**, **24 h** or **7 d**. Red marks are minutes with a
  problem.
- **Problems in the last 24 hours**: when each one happened, how long it lasted and
  the most likely cause. Hover over one to see the measurements behind it.
- **Pause monitoring**, **Settings…** and **Quit**.

## Setting up a network

LinkWatch only watches networks you approve.

1. The first time, open **Settings…** and click **Allow Wi-Fi identification**,
   then allow the macOS prompt. macOS uses Location permission to reveal the Wi-Fi
   name; LinkWatch never reads where you are.
2. When you join a new Wi-Fi network, the panel shows **New Wi-Fi network** with the
   router and, if found, the access point. Click **Monitor this network**.
3. If the access point is not found, click **Find AP**. It asks each address on your
   home network once, so the Mac learns which one is the access point; it only runs
   when you click it. Or enter the access point's address in Settings.
4. Optionally, in Settings, name what connects the access point to the router, for
   example *"TP-Link powerline adapters"*. The advice then uses that name.

If a network's router or access point changes later, LinkWatch offers to **Update
profile**; it never changes settings by itself.

## After a restart

LinkWatch opens at login, so it keeps watching after the Mac restarts; macOS lists it
in **System Settings › General › Login Items**. Saved networks and the week of
history are kept on disk, so nothing is lost when LinkWatch or the Mac restarts. To
stop it opening at login, switch off **Open LinkWatch at login** in Settings.

## Common questions

**The router is not answering, but the internet works.** macOS is probably blocking
LinkWatch from your local network. Open **System Settings › Privacy & Security ›
Local Network** and switch on **LinkWatch**. The icon turns green within about ten
seconds.

**It says to restart the powerline adapters.** Unplug both adapters (or the ones
between your access point and router), wait ten seconds and plug them back in. The
icon should turn green a minute or two after they reconnect.

**Should I restart the router?** Only if the advice says the internet is down *and*
the problem is at home. If the icon is orange, the provider is having trouble and
restarting your equipment will not help.

**It was not working last night. Can I see what happened?** Yes. The panel lists the
last day's problems, and the chart's **7 d** view shows the week. Whoever looks after
your network can also run `scripts/linkwatch incidents --days 7` or ask a coding
agent "what's going on with my network?".

**Why is it grey?** LinkWatch is paused, this network is not set up, Wi-Fi is off,
or Location permission is missing. The panel says which.

**Does it slow my connection?** No. It sends four tiny messages every two seconds,
about one megabyte an hour.

**Is my data shared?** No. Settings and history stay on this Mac. See
[privacy](privacy.md).
