import Darwin
import LinkWatchCore
import Testing

@testable import LinkWatchNetworking

private func message(address: [UInt8], hardware: [UInt8], interface: UInt32) -> [UInt8] {
  var inet = [UInt8](repeating: 0, count: 16)
  inet[0] = 16
  inet[1] = UInt8(AF_INET)
  inet.replaceSubrange(4..<8, with: address)
  var link: [UInt8] = [
    20, UInt8(AF_LINK), UInt8(interface & 255), UInt8(interface >> 8), 6, 0,
    UInt8(hardware.count), 0,
  ]
  link += hardware
  link += [UInt8](repeating: 0, count: 20 - link.count)
  let length = MemoryLayout<rt_msghdr>.size + inet.count + link.count
  var header = [UInt8](repeating: 0, count: MemoryLayout<rt_msghdr>.size)
  header[0] = UInt8(length & 255)
  header[1] = UInt8(length >> 8)
  return header + inet + link
}

@Test func parsesRoutingMessagesAndSkipsIncompleteEntries() {
  let loopback = if_nametoindex("lo0")
  let complete = message(
    address: [192, 0, 2, 1], hardware: [0, 0, 0x5e, 0, 0x53, 0x0a], interface: loopback)
  let incomplete = message(address: [192, 0, 2, 2], hardware: [], interface: loopback)
  let entries = NeighborTable.parse(complete + incomplete + Array(complete.prefix(10)))
  #expect(
    entries == [
      NeighborEntry(address: "192.0.2.1", hardwareAddress: "00:00:5e:00:53:0a", interface: "lo0")
    ])
  #expect(NeighborTable.parse([]).isEmpty)
}

@Test func systemNeighborTableEntriesAreWellFormed() {
  for entry in NeighborTable.entries() {
    #expect(entry.address.split(separator: ".").count == 4)
    #expect(entry.hardwareAddress.count == 17)
    #expect(if_nametoindex(entry.interface) > 0)
  }
}

@Test func countersComeFromTheMatchingInterfaceMessage() {
  func message(index: UInt16, received: UInt64, sent: UInt64, type: Int32 = RTM_IFINFO2) -> [UInt8]
  {
    var header = if_msghdr2()
    header.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.size)
    header.ifm_type = UInt8(type)
    header.ifm_index = index
    header.ifm_data.ifi_ibytes = received
    header.ifm_data.ifi_obytes = sent
    return withUnsafeBytes(of: header) { Array($0) }
  }
  let bytes =
    message(index: 4, received: 1, sent: 2, type: RTM_IFINFO)
    + message(index: 9, received: 5_000_000_000, sent: 6)
    + message(index: 4, received: 7_000_000_000, sent: 8)
  #expect(
    InterfaceCounters.counters(in: bytes, index: 4)
      == TrafficCounters(received: 7_000_000_000, sent: 8))
  #expect(InterfaceCounters.counters(in: bytes, index: 3) == nil)
  #expect(InterfaceCounters.counters(in: Array(bytes.prefix(10)), index: 4) == nil)
}

@Test func systemCountersAreReadableForLoopback() {
  #expect(InterfaceCounters.traffic(on: "lo0") != nil)
  #expect(InterfaceCounters.traffic(on: "no-such-interface") == nil)
}
