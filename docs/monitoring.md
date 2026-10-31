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

## Week history

Each accepted pair is also aggregated into a wall-clock minute summary per network:
sample count, nearest-rank median and 95th percentile and loss for the AP and the
router, and the most severe state seen (`healthy`, `bothSlow`, `routerSlower`,
`unreachable`). Wall-clock time is used because monotonic uptime restarts at boot.
A minute is completed when the next minute or network begins, and is flushed on
pause, sleep, network change and quit, so partial minutes are kept.

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
