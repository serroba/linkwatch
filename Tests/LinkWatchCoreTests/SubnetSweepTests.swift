import Testing

@testable import LinkWatchCore

@Test func sweepCoversPrivateSubnetsExceptOwnNetworkAndBroadcast() throws {
  let hosts = try SubnetSweep.hosts(address: "192.168.7.20", netmask: "255.255.255.0")
  #expect(hosts.count == 253)
  #expect(hosts.first == "192.168.7.1")
  #expect(hosts.last == "192.168.7.254")
  #expect(!hosts.contains("192.168.7.20"))
  #expect(try SubnetSweep.hosts(address: "10.1.2.3", netmask: "255.255.252.0").count == 1021)
  #expect(
    try SubnetSweep.hosts(address: "172.16.0.1", netmask: "255.255.255.252") == ["172.16.0.2"])
  #expect(try SubnetSweep.hosts(address: "169.254.3.4", netmask: "255.255.255.255").isEmpty)
}

private struct Refused {
  let address: String
  let netmask: String
  let refusal: SubnetSweep.Refusal
}

@Test func sweepRefusesPublicLargeAndMalformedSubnets() {
  let cases = [
    Refused(address: "203.0.113.5", netmask: "255.255.255.0", refusal: .notPrivate),
    Refused(address: "172.32.0.1", netmask: "255.255.255.0", refusal: .notPrivate),
    Refused(address: "10.0.0.5", netmask: "255.255.248.0", refusal: .tooLarge(prefixLength: 21)),
    Refused(address: "10.0.0.5", netmask: "255.0.255.0", refusal: .invalidAddress),
    Refused(address: "10.0.0.5", netmask: "0.0.0.0", refusal: .invalidAddress),
    Refused(address: "10.0.0", netmask: "255.255.255.0", refusal: .invalidAddress),
  ]
  for test in cases {
    #expect(throws: test.refusal) {
      try SubnetSweep.hosts(address: test.address, netmask: test.netmask)
    }
  }
}
