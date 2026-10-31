import Darwin
public import LinkWatchCore

/// Reads an interface's 64-bit byte counters; the 32-bit `getifaddrs` ones wrap at 4 GB.
public enum InterfaceCounters {
  public static func traffic(on interface: String) -> TrafficCounters? {
    let index = if_nametoindex(interface)
    guard index > 0 else { return nil }
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
    var length = 0
    guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
    var buffer = [UInt8](repeating: 0, count: length)
    guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }
    return counters(in: Array(buffer.prefix(length)), index: UInt16(truncatingIfNeeded: index))
  }

  /// Finds the `RTM_IFINFO2` message for the interface index among the routing messages.
  static func counters(in bytes: [UInt8], index: UInt16) -> TrafficCounters? {
    let headerSize = MemoryLayout<if_msghdr2>.size
    var offset = 0
    while offset + 4 <= bytes.count {
      let length = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
      guard length >= 4, offset + length <= bytes.count else { return nil }
      if Int32(bytes[offset + 3]) == RTM_IFINFO2, length >= headerSize {
        let message = bytes.withUnsafeBytes {
          $0.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
        }
        if message.ifm_index == index {
          return TrafficCounters(
            received: message.ifm_data.ifi_ibytes, sent: message.ifm_data.ifi_obytes)
        }
      }
      offset += length
    }
    return nil
  }
}
