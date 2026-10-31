# Privacy

LinkWatch is a local tool. It has no account, no server and no telemetry. This page
lists everything it measures, sends and stores.

## Permissions

| Permission | Why | What LinkWatch does not do |
|---|---|---|
| Location | macOS reveals the Wi-Fi name (SSID) and access point (BSSID) only to apps with Location permission. | It never requests or reads coordinates. |
| Local Network | Needed to ping the router and access point on your network. | It does not browse or advertise services, and only sweeps the subnet when you click Find AP. |

## Traffic it sends

Only on Wi-Fi networks you approved, while monitoring is not paused, bound to the
Wi-Fi interface:

- **One ICMP echo (ping) every two seconds** to the access point and to the router
  you configured.
- **One ping every two seconds to Cloudflare (`1.1.1.1`) and Google (`8.8.8.8`)**,
  unless internet reference points are turned off for that network. These leave
  your network, so both providers can see your public IP address and that it pings
  them. Turn them off per network in Settings or with
  `profile set --ssid NAME --internet off`.
- **Find AP**, only when you click it: one ping to each address of your Wi-Fi subnet,
  so macOS learns the access point's hardware address. It refuses public networks
  and subnets larger than /22.
- **`probe`**, only when run from the command line, to the address given.

In total that is about one megabyte an hour. Unapproved networks receive nothing.
Discovering the router and access point reads information macOS already has (the
network service's router and the existing ARP cache) and sends nothing.

## What it reads on the Mac

- Wi-Fi name, access point hardware address and interface state, through CoreWLAN.
- The router assigned to the Wi-Fi network service, through SystemConfiguration.
- The existing ARP cache, to recognise the access point.
- The Wi-Fi interface's total bytes received and sent, to show download and upload
  rates. Only totals: nothing about which applications, sites or content.

## What it stores

| What | Where | Kept |
|---|---|---|
| Approved networks: name, access point and router addresses, thresholds, bridge name | `defaults read io.github.serroba.LinkWatch` | Until removed |
| One summary per minute: latency, loss, bytes moved and the worst state | `~/Library/Application Support/io.github.serroba.LinkWatch/history.jsonl` (owner-only) | Seven days |
| The last hour of raw measurements | Memory only | Until quit |
| Whether to open at login | `defaults read io.github.serroba.LinkWatch` and macOS Login Items | Until changed |

History never contains coordinates, browsing activity or anything about other devices
beyond the addresses you configured. **Clear history…** in Settings, or
`scripts/linkwatch history clear`, deletes it; [uninstalling](install.md#uninstall)
removes everything.

## Sharing

LinkWatch sends nothing anywhere. **Export report…** and `scripts/linkwatch export`
write a folder (owner-only) in `~/Library/Application Support/io.github.serroba.LinkWatch/Reports`
containing the diagnosis, the network name, local addresses and every stored minute
for the period; it only leaves the Mac if you send it. `export --redact` replaces
network names, local addresses and hardware addresses with placeholders, keeping
the public reference hosts, for sharing more widely. Command-line output contains
the same details; redact it before posting publicly.
