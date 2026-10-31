# Monitoring semantics

Each cycle records a pair of outcomes against monotonic elapsed time. Cancelled
pairs and non-increasing timestamps are discarded. Statistics use the last 60
pairs; each display median uses successful outcomes within the last five pairs.
A separate display history keeps 450 pairs, about 15 minutes, in memory only. A failed
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

## Network discovery

Discovery runs when the Wi-Fi identity or the network path changes, not on every
refresh. The router comes from the global IPv4 state only when its primary
interface is the Wi-Fi interface. Neighbours come from the kernel ARP cache via
`sysctl` and are limited to the Wi-Fi interface. A neighbour matches the BSSID when
its hardware address is identical, or differs only in the locally administered bit
and by at most seven in the last byte, which is how vendors usually derive radio
addresses. Zero or several matches leave the AP unknown; a match on the router
means there is no separate AP. Suggestions are dismissed per discovered address set.

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
