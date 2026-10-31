import Darwin
public import LinkWatchCore

/// Reads interface addresses from the system without sending traffic.
public enum InterfaceAddresses {
  /// The first IPv4 address and netmask configured on the named interface.
  public static func ipv4(on interface: String) -> InterfaceAddress? {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0, let first = list else { return nil }
    defer { freeifaddrs(list) }
    for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let item = entry.pointee
      guard String(cString: item.ifa_name) == interface,
        let address = item.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
        let netmask = item.ifa_netmask,
        let addressText = text(address), let netmaskText = text(netmask)
      else { continue }
      return InterfaceAddress(address: addressText, netmask: netmaskText)
    }
    return nil
  }

  /// Reads the IPv4 bytes at offsets 4–7, honouring `sa_len`: netmasks may be stored
  /// truncated, with omitted trailing bytes meaning zero.
  private static func text(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
    let length = Int(address.pointee.sa_len)
    let bytes = UnsafeRawPointer(address)
    let octets = (4..<8).map { $0 < length ? bytes.load(fromByteOffset: $0, as: UInt8.self) : 0 }
    return octets.map(String.init).joined(separator: ".")
  }
}
