import Darwin
import Foundation
public import LinkWatchCore

/// Reads the kernel's existing IPv4 ARP cache without sending any traffic.
public enum NeighborTable {
  public static func entries() -> [NeighborEntry] {
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
    var length = 0
    guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return [] }
    var buffer = [UInt8](repeating: 0, count: length)
    guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else { return [] }
    return parse(Array(buffer.prefix(length)))
  }

  /// Parses routing messages, each a header followed by `sockaddr_in` and `sockaddr_dl`.
  static func parse(_ bytes: [UInt8]) -> [NeighborEntry] {
    var entries: [NeighborEntry] = []
    var offset = 0
    let headerSize = MemoryLayout<rt_msghdr>.size
    while offset + headerSize <= bytes.count {
      let length = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
      guard length >= headerSize, offset + length <= bytes.count else { break }
      if let entry = entry(in: Array(bytes[offset + headerSize..<offset + length])) {
        entries.append(entry)
      }
      offset += length
    }
    return entries
  }

  private static func entry(in addresses: [UInt8]) -> NeighborEntry? {
    let inetSize = MemoryLayout<sockaddr_in>.size
    guard addresses.count >= inetSize, Int32(addresses[1]) == AF_INET else { return nil }
    let link = Array(addresses.dropFirst(rounded(Int(addresses[0]))))
    guard link.count >= 8, Int32(link[1]) == AF_LINK else { return nil }
    let index = UInt32(link[2]) | UInt32(link[3]) << 8
    let nameLength = Int(link[5])
    let addressLength = Int(link[6])
    guard addressLength == 6, link.count >= 8 + nameLength + addressLength,
      let interface = interfaceName(index)
    else { return nil }
    let hardware = link[(8 + nameLength)..<(8 + nameLength + addressLength)]
    let octets = addresses[4..<8].map(String.init)
    return NeighborEntry(
      address: octets.joined(separator: "."),
      hardwareAddress: hardware.map { hex($0) }.joined(separator: ":"),
      interface: interface)
  }

  /// Socket addresses in routing messages are padded to 32-bit boundaries.
  private static func rounded(_ length: Int) -> Int {
    length > 0 ? 1 + ((length - 1) | 3) : 4
  }

  private static func hex(_ byte: UInt8) -> String {
    let digits = Array("0123456789abcdef")
    return String([digits[Int(byte >> 4)], digits[Int(byte & 15)]])
  }

  private static func interfaceName(_ index: UInt32) -> String? {
    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
    guard if_indextoname(index, &name) != nil else { return nil }
    return String(bytes: name.prefix { $0 != 0 }.map(UInt8.init), encoding: .utf8)
  }
}
