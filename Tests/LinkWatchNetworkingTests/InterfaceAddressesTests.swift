import LinkWatchCore
import Testing

@testable import LinkWatchNetworking

/// Every Mac has the loopback interface, so this reads real system data without traffic.
@Test func loopbackAddressAndNetmaskAreRead() {
  let loopback = InterfaceAddresses.ipv4(on: "lo0")
  #expect(loopback?.address == "127.0.0.1")
  #expect(loopback?.netmask == "255.0.0.0")
  #expect(InterfaceAddresses.ipv4(on: "linkwatch-missing0") == nil)
}
