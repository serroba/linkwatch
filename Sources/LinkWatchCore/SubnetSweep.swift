/// The bounded set of addresses an explicitly requested access point search may ping.
enum SubnetSweep {
  /// The largest subnet searched; bigger networks are refused rather than partially scanned.
  static let minimumPrefixLength = 22

  enum Refusal: Error, Equatable, CustomStringConvertible {
    case invalidAddress
    case notPrivate
    case tooLarge(prefixLength: Int)

    var description: String {
      switch self {
      case .invalidAddress: "The Wi-Fi interface has no usable IPv4 address."
      case .notPrivate:
        "The Wi-Fi network does not use a private address range, so it is not searched."
      case .tooLarge(let prefixLength):
        "The Wi-Fi subnet is a /\(prefixLength); only /\(minimumPrefixLength) or smaller is searched."
      }
    }
  }

  /// Host addresses in the interface's subnet, excluding its own, network and broadcast addresses.
  static func hosts(address: String, netmask: String) throws(Refusal) -> [String] {
    guard let own = NetworkProfile.octets(address).map(value),
      let mask = NetworkProfile.octets(netmask).map(value),
      mask != 0, (~mask &+ 1) & ~mask == 0
    else { throw .invalidAddress }
    let prefixLength = mask.nonzeroBitCount
    guard isPrivate(own) else { throw .notPrivate }
    guard prefixLength >= minimumPrefixLength else { throw .tooLarge(prefixLength: prefixLength) }
    guard prefixLength <= 30 else { return [] }
    let network = own & mask
    let broadcast = network | ~mask
    return ((network + 1)..<broadcast).filter { $0 != own }.map(text)
  }

  private static func isPrivate(_ address: UInt32) -> Bool {
    address >> 24 == 10 || address >> 20 == 0xAC1 || address >> 16 == 0xC0A8
      || address >> 16 == 0xA9FE
  }

  private static func value(_ octets: [UInt8]) -> UInt32 {
    octets.reduce(0) { $0 << 8 | UInt32($1) }
  }

  private static func text(_ address: UInt32) -> String {
    [24, 16, 8, 0].map { String(address >> UInt32($0) & 255) }.joined(separator: ".")
  }
}
