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
| Orange pulse | The connection is mostly fine but has frequent short lag spikes, which make calls and video stutter. | If it bothers you, do what the panel suggests, usually restarting the TP-Link. |
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
- **Wi-Fi signal**: strength in dBm (closer to zero is stronger), how far above the
  background noise it is, the link speed and the channel. *Weak* means moving closer
  to the access point will help more than restarting anything.
- **Usage**: how fast this Mac is downloading and uploading right now, and how much
  it has downloaded and uploaded today and over the last seven days. Totals count
  only this Mac, on networks LinkWatch monitors, while it is running.
- **The chart**: choose **1 h**, **24 h** or **7 d**. Red marks are minutes with a
  problem.
- **Problems in the last 24 hours**: when each one happened, how long it lasted and
  the most likely cause. Hover over one to see the measurements behind it.
- **Pause monitoring**, **Settings…** and **Quit**.

## A simpler panel and notifications

In Settings, **Simple panel** shows only the advice, the **I restarted…** menu and the
buttons; **Show details** opens the measurements and charts. **Notify me when a
problem lasts 3 minutes** (off until you turn it on, when macOS asks once) sends one
notification saying what to do, such as restarting the powerline adapters, and
another when the connection is back to normal. Short blips, lag spikes, large
downloads and a router that only ignores LinkWatch never notify.

## Marking what you were doing

If you suspect something at home affects the connection (an electric desk, a
microwave, a heater), type what you are doing into **What just happened?** in the
panel and click **Mark** each time you use it. The marks are saved with the
measurements, so whoever looks at the data later can see whether problems follow
them. After three or more marks with the same words, the diagnosis says whether the
connection got worse around them and which link was affected. Powerline adapters
are particularly sensitive to electrical noise from motors and power supplies; if
the desk turns out to disturb them, plug the adapters straight into a wall socket,
plug the desk into another circuit or into an adapter's filtered socket, or replace
the powerline link with a cable.

## Saying you restarted something

After restarting the powerline adapters, the router or the phone, click **I
restarted…** in the panel and pick the device. LinkWatch notes the time, skips the
two minutes the device needs to start, and after a few more minutes says whether it
helped, for example *"Restarting the TP-Link powerline adapters helped: router 85 → 4
ms."* If it made no difference, the problem is most likely somewhere else. Restarts
also appear in the diagnosis, so the history shows what was tried and what worked.

## Testing a device

For a quick answer, type the device's name (for example *desk*) next to **Test** in
the panel and click it. Follow the prompts: leave it off for 30 seconds, turn it on
(or keep the desk moving) for 30 seconds, then turn it off for 30 seconds. LinkWatch
compares the three and says, for example, *"The desk most likely disturbs the link
between the access point and the router, such as powerline adapters. It recovered
once it was off."* Run it two or three times to be sure; pausing or a network change
cancels it.

## Setting up a network

LinkWatch only watches networks you approve.

1. The first time, open **Settings…** and click **Allow Wi-Fi identification**,
   then allow the macOS prompt. macOS uses Location permission to reveal the Wi-Fi
   name; LinkWatch never reads where you are.
2. When you join a new Wi-Fi network, the panel shows **New Wi-Fi network** with the
   router and, if found, the access point. Click **Monitor this network**.
3. The access point is optional. If the Mac is connected straight to the router's
   Wi-Fi, LinkWatch monitors the router alone. If there is a separate access point
   that was not found, click **Find AP**. It asks each address on your home network
   once, so the Mac learns which one is the access point, and only runs when you
   click it. Or enter the access point's address in Settings.

   **Moving around the house.** Many homes have the router's own Wi-Fi in one room and
   an access point (for example behind powerline adapters) in another, with the same
   network name. LinkWatch keeps pinging both from anywhere and works out which one the
   Mac is connected through; the panel says so, and **Detect again** rechecks it.
   Behind the access point, advice about the powerline adapters applies to this Mac.
   On the router's Wi-Fi, a slow access point only shows as a note ("only devices
   using the access point are affected"), because this Mac does not use it there. If
   you first set up the network on the router's Wi-Fi, LinkWatch offers to add the
   access point the first time you join it.
4. Optionally, in Settings, name what connects the access point to the router, for
   example *"TP-Link powerline adapters"*. The advice then uses that name.

**Phone hotspots.** When the Mac joins a phone's personal hotspot, the panel says
**Phone hotspot detected** and the phone is monitored as both access point and
router. Advice then talks about the phone, for example *"Move the phone where
reception is better, for example near a window"* or *"Bring the Mac and the phone
closer together"*, and the internet pings run every ten seconds to save mobile data.
This is remembered with the network's name, so you never switch anything when you
tether: a network saved earlier is marked as a hotspot the first time LinkWatch
recognises it. Only if your phone is never recognised, turn on **This network is a
phone's personal hotspot** in Settings once. Home routers with built-in Wi-Fi and no separate access point
work the same way, with ordinary wording.

If a network's router or access point changes later, LinkWatch offers to **Update
profile**; it never changes settings by itself.

## Updates

Once a day LinkWatch asks GitHub whether a newer version exists. If so, the panel shows
**LinkWatch X is available**: click **Install update** and LinkWatch quits, installs
the new version and reopens within a minute. **What's new** opens the release notes.
macOS may then ask again for Location and Local Network access. Turn the daily check
off in Settings under **Check for updates once a day**.

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
icon should turn green a minute or two after they reconnect. Click **I restarted…**
afterwards so LinkWatch can confirm whether it helped.

**Should I restart the router?** Only if the advice says the internet is down *and*
the problem is at home. If the icon is orange, the provider is having trouble and
restarting your equipment will not help.

**It was not working last night. Can I see what happened?** Yes. The panel lists the
last day's problems, and the chart's **7 d** view shows the week. To let someone else
look, click **Export report…** at the bottom of the panel: LinkWatch saves the last
week's summary, diagnosis and measurements in a folder and shows it in Finder. The
summary at the top says which part of the connection caused most trouble, at what
time of day, and what to change, such as replacing powerline adapters with a cable. Send that
folder by AirDrop or Messages. It contains your network name and local addresses, so
send it only to people you trust.

**Why is it grey?** LinkWatch is paused, this network is not set up, Wi-Fi is off,
or Location permission is missing. The panel says which.

**Does it slow my connection?** No. It sends four tiny messages every two seconds,
about one megabyte an hour.

**Is my data shared?** No. Settings and history stay on this Mac. See
[privacy](privacy.md).
