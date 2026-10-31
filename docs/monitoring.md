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

1. AP lost, or AP median above the both-slow threshold → **access point** (weak
   Wi-Fi signal or an overloaded access point), or **busy** when slow under load.
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

## Usage

Each cycle reads the Wi-Fi interface's 64-bit byte counters from the kernel
(`NET_RT_IFLIST2`; the 32-bit counters from `getifaddrs` wrap at 4 GB). The
difference from the previous cycle gives the live download and upload rate, and
minute summaries store bytes received and sent. Counters that go backwards, or a
new session after a pause or network change, start a new baseline instead of
reporting a spike. Only totals are read: no traffic is sent, and nothing about
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
