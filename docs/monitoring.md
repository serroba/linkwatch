# Monitoring semantics

Each cycle records a pair of outcomes against monotonic elapsed time. Cancelled
pairs and non-increasing timestamps are discarded. Statistics use the last 60
pairs; each display median uses successful outcomes within the last five pairs.
A separate display history keeps 1,800 pairs, about one hour, in memory only. A failed
latest probe must be displayed as unavailable even if older successes exist.
Loss is the proportion of failed outcomes in the 60-pair statistics window.

Degradation starts when the median difference strictly exceeds 20 ms, or both
medians strictly exceed 30 ms. The condition must remain present at each sample
for at least 10 elapsed seconds. A gap longer than five seconds resets the pending
timer. Both-slow takes precedence over a difference alert. Failures immediately
produce an explicit unreachable state. When both targets reply again, the
unreachable state clears at once and the previous assessment resumes, so a single
lost reply neither hides nor restarts an active alert.

Recovery requires a difference below 10 ms and both medians below 20 ms for six
seconds. Values on recovery boundaries retain the current alert. These defaults
are configurable observations, not proof of a particular faulty component.

## Internet reference points

When a profile enables them (the default, including for profiles saved before the
setting existed), each cycle also sends one ICMP echo to Cloudflare `1.1.1.1` and
Google `8.8.8.8`, bound to the Wi-Fi interface and concurrent with the AP and router
probes, so the cycle does not lengthen. A pair's internet outcome is the fastest
reference reply; it is lost only when every reference is, so one provider's hiccup is
not attributed to the connection. Medians use the last five pairs that probed
references, and each reference's own median is reported too. These probes leave the
local network and disclose the public address to both providers. They do not affect
the AP and router alert rules; the planned verdict uses them.

## Verdict

A verdict names the most likely failing link and at most one action. It is computed
from evidence: the median and loss of each target over the last five pairs (live) or
over one stored minute (history). A target is lost when half or more of its probes
failed. Using the profile's thresholds, the first matching rule wins:

1. AP lost, or AP median above the both-slow threshold → **weak signal** when the
   Mac's Wi-Fi signal is below −70 dBm or within 20 dB of the noise, otherwise
   **access point** (an overloaded or failing access point), or **busy** when slow
   under load. Access point spikes with a weak signal are also **weak signal**.
2. Router lost: with internet references working → **router silent** (traffic still
   flows, so the router only ignores pings, or Local Network access is missing); with
   references also lost → **bridge**; with no references probed → **router
   unreachable**, worded conditionally because the cause cannot be told apart.
3. Router minus AP above the difference threshold → **bridge**, the link between the
   AP and the router, named by the profile (for example powerline adapters), or
   **busy** when the Mac is moving a lot of data.
4. Internet references lost → **internet** provider; slower than the router by more
   than 100 ms → **internet**, or **busy** under load.
5. Typical latency fine, but the 95th percentile over about a minute is more than
   100 ms above the previous link's → **lag spikes** on that link: **access point
   spikes** (its own 95th percentile above 100 ms), **bridge spikes** (router minus
   access point) or **internet spikes** (internet minus router), or **busy** under
   load. At least one probe in twenty that slow is felt as stutter in calls and games,
   even when the median looks healthy.
6. Otherwise **all clear**.

**Busy** means the faster direction of the Mac's traffic is at least 1 Mbit/s and at
least half the busiest rate seen on that network in the stored week (or this
session). It adapts to each connection's capacity without a speed test, and only
explains slowness: losses still point at a link, because load alone rarely stops a
device answering. Live, the busiest of the last five cycles is used; stored minutes
use their average rate against the week's busiest minute.

The live verdict changes only after the new verdict has held for the alert time
(or the recovery time when clearing), and resets on any network change. Stored
minutes are classified when read, so improved rules apply to the whole week.

## Incidents

Stored minutes are classified with the verdict rules (with each network's thresholds
and busiest minute) and problem minutes are grouped per network and per failing link
into incidents: slow and spiky minutes on the same link belong together, while a
change of link (for example from a silent router to bridge spikes) starts a new
incident. Up to two clear or missing minutes inside a run still count as one
incident, so a flapping link reads as one problem; runs of fewer than two problem
minutes are treated as blips, and a blip about another link does not split an
incident. An incident's verdict is its most common problem verdict, with
ties resolved towards the one needing action (bridge, access point, internet,
router, busy). Evidence per link is the slowest minute median and the
sample-weighted loss, plus bytes moved. Incidents are computed when read, so rule
changes apply to the whole week.

## Events

The menu bar app records app and system events as JSON Lines in `events.jsonl`, next
to the history (owner-only, seven days): launches with the version, quits, sleep and
wake, Wi-Fi joined, left or roamed, Location permission granted or missing,
monitoring started or stopped with the reason, pauses, verdict changes, profile and
history changes, and **marks**, short labels a person adds ("desk moved") to match
with the measurements. Only changes are recorded, never repeated state. `diagnose`
lists recent events and explains each unmonitored gap with the last event before it
and the first after it, allowing a minute either side.

## Marked activities

`diagnose` compares the minutes touched by each mark label (case-insensitive) with
all other monitored minutes in the period. A mark touches the minute it falls in and
the next one, since a motor run or a restart can straddle a minute boundary. For
each side it reports the median of the minutes' 95th percentiles per link, the
router loss and the share of problem minutes. With at least three marks, the first
link whose typical spikes grow by 50 ms or more and at least double (or, for the
router, whose loss grows by ten points) is named as most likely affected; otherwise
it says there is no clear effect. Correlation is evidence, not proof: repeat the
activity at different times to rule out coincidence.

## Restarts

**I restarted…** (or `restarted [DEVICE]`) records a `restarted` event naming the
device. Its effect compares the stored minutes wholly within the ten minutes before
the restart with the ten minutes starting two minutes after it, skipping the time
the device needs to boot. Each side reports the median of the minutes' medians per
link and the mean router and internet loss. Until three minutes have followed, the
effect is *measuring*. A link improves when its typical latency drops by at least
10 ms and at least halves, or its loss drops by ten points; it worsens in the
opposite case. Any improvement with nothing worse reads as *helped*, anything worse
as *worse*, and otherwise *no clear difference*. The panel and `status` show the
latest restart for an hour; `diagnose` lists every restart in the period.

## Weekly summary

`summary` (and the top of exported reports) groups the period's incidents by the part
of the connection they point to: Wi-Fi (`accessPoint`, `weakSignal`,
`accessPointSpikes`), the bridge (`bridge`, `bridgeSpikes`, `routerUnreachable`), the
internet (`internet`, `internetSpikes`), the Mac being busy, and the router not
answering. Each area lists incidents, problem minutes and the longest incident. The
busiest hours are the three hours of the day with the most incident minutes across
all days. Latency under load compares the median of minute medians (internet when
probed, otherwise the router) in minutes moving at least 30 MB, about 4 Mbit/s, with
all other minutes. A router that ignores pings while the internet works is listed but
does not count towards the busiest hours or the main cause, since it is usually a
missing Local Network permission rather than a connection problem. Advice names an
area when it holds at least half of the remaining problem minutes over three or more
incidents; reports bufferbloat when at least ten heavy
minutes add 50 ms or more; reports a time-of-day cluster when one hour holds at least
30% of 20 or more problem minutes; and counts how often judged restarts helped.

## Device tests

A guided test has three 30-second phases: as usual, device on, device off. Each
phase's raw two-second pairs (fifteen per link, at least ten required) give a
nearest-rank 95th percentile and loss per link. The on phase is compared with the
calmer of the other two using the same rule as marked activities (spikes up by
50 ms and at least doubled, or router loss up by ten points), and the off phase with
the first to say whether the link recovered. Pausing, sleep or any network change
cancels a running test. Each step and the conclusion are recorded as events.

## Wi-Fi signal

Each cycle reads the Mac's own radio through CoreWLAN, without sending traffic:
signal strength (RSSI) and noise in dBm, their difference (SNR), the negotiated
transmit rate, channel and band. Quality is *excellent* from −55 dBm and SNR 35 dB,
*good* from −65 dBm and 25 dB, *weak* below −70 dBm or 20 dB, and *fair* otherwise.
Minute summaries store the median RSSI, noise and transmit rate, hourly rollups the
median RSSI, and the verdict uses a weak signal to explain a slow access point.

## Usage

Each cycle reads the Wi-Fi interface's 64-bit byte counters from the kernel
(`NET_RT_IFLIST2`; the 32-bit counters from `getifaddrs` wrap at 4 GB). The
difference from the previous cycle gives the live download and upload rate, and
minute summaries store bytes received and sent. Counters that go backwards, or a
new session after a pause or network change, start a new baseline instead of
reporting a spike. Cumulative totals for the last hour, today (from local midnight)
and the stored week add up the stored minutes and the minute in progress, so they
survive restarts; time when LinkWatch was not running is not counted. Only totals are read: no traffic is sent, and nothing about
applications or destinations is recorded. This measures what the Mac used, not
the connection's capacity, so it is not a speed test.

## Week history

Each accepted pair is also aggregated into a wall-clock minute summary per network:
sample count, nearest-rank median and 95th percentile and loss for the AP and the
router, and the most severe state seen (`healthy`, `bothSlow`, `routerSlower`,
`unreachable`). Wall-clock time is used because monotonic uptime restarts at boot.
A minute is completed when the next minute or network begins, and is flushed on
pause, sleep, network change and quit, so partial minutes are kept.

Completed minutes are written immediately, so quitting or a crash loses at most the
current partial minute, and a normal quit or shutdown flushes that too. After a
restart the hour chart shows stored minute medians for the time before launch.

Only the menu bar app writes history. Command-line runs read it through a read-only
store, so they can never rewrite the file while the app appends to it. A restart
can store two partial summaries for the same minute (one flushed by the quitting
copy, one from the new copy); rollups count the minute once.

Summaries are appended as JSON Lines to
`~/Library/Application Support/io.github.serroba.LinkWatch/history.jsonl` (directory
0700, file 0600); unreadable lines are skipped rather than discarding the week.
Minutes older than seven days are pruned at launch and at most hourly afterwards.
**Clear history** in Settings, or `scripts/linkwatch history clear`, deletes them.
A storage failure is reported and never stops monitoring.

## Network discovery

Discovery runs when the Wi-Fi identity or the network path changes, not on every
refresh. The router comes from the IPv4 state of the network service bound to the
Wi-Fi interface, so a VPN owning the default route does not hide it; services that
disagree leave it unknown. Neighbours come from the kernel ARP cache via
`sysctl` and are limited to the Wi-Fi interface. A neighbour matches the BSSID when
its hardware address is identical, or differs only in the locally administered bit
and by at most seven in the last byte, which is how vendors usually derive radio
addresses. Zero or several matches leave the AP unknown; a match on the router
means there is no separate AP. Suggestions are dismissed per discovered address set.

The access point is optional. Each probe cycle follows the radio the Mac is associated
with: when discovery matches the BSSID to the router, only the router is probed (the
Mac is on the router's own Wi-Fi, for example in a room the AP does not reach); when it
matches a separate device, that device is probed as the AP; otherwise the profile's AP
is used, or the router alone when the profile has none. A roam changes the network
identity, so the monitoring window restarts and the two paths are never mixed. With
only the router probed, its outcome is recorded for both targets, so the bridge
verdicts never apply. A network first joined on the router's radio is saved without
an AP; joining its AP later offers to add it, and returning to the router's radio
keeps it without suggesting anything. A profile whose AP is empty or equals the router
is a single device, such as a phone hotspot or an all-in-one router. A network counts as a phone hotspot when
macOS marks the path as expensive or the router is in the iPhone hotspot range
172.20.10.0/28; then an unknown AP is taken to be the router, and the saved profile
is flagged `hotspot`. Hotspot profiles, and any network on an expensive path, ping
the internet references on every fifth cycle (10 s) instead of every cycle. Their
advice names the phone: a poor or spiky AP link or weak signal becomes "the
connection between the Mac and the phone", and internet trouble becomes the phone's
mobile reception.

**Find AP** is the only feature that sends traffic to discover devices. It runs only
on request, takes the Wi-Fi interface's IPv4 address and netmask, refuses addresses
outside 10/8, 172.16/12, 192.168/16 and 169.254/16 and subnets larger than /22, and
sends one ICMP echo to every other host address, at most 32 at a time, bound to the
Wi-Fi interface. Replies are ignored; the point is that macOS resolves each address
with ARP. Discovery then reruns against the refreshed cache. A /24 takes roughly
half a minute because absent hosts time out after one second.

## Native probes

The IPv4 adapter uses an unprivileged datagram ICMP socket, bound with
`IP_BOUND_IF` to the selected interface. It sends one request, waits at most one
second, and checks cancellation every 50 ms. There is no shell command, privileged
helper, name lookup, subnet scan or fallback to a different interface. Replies
must match the target address, identifier, sequence, random payload and checksum.
The native ICMP approach follows the platform behavior documented by Apple's
[SimplePing sample](https://developer.apple.com/library/archive/samplecode/SimplePing/Introduction/Intro.html).

Run the optional real socket test with `LINKWATCH_TEST_LOOPBACK=1 swift test`.
It sends only to loopback, and is enabled in CI. If local Swift 6.4 Command Line
Tools fail to load the Swift Testing macro plugin, append
`-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`
to the test command. This workaround was verified locally; CI uses Xcode 16.4.
