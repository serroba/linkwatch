public import Foundation

public struct NetworkProfile: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var ssid: String
  public var accessPoint: String
  public var router: String
  public var thresholds: Thresholds
  /// Whether to also probe `InternetReference.all`, which sends traffic beyond the router.
  public var internetReferences: Bool

  public init(
    id: UUID = UUID(), ssid: String, accessPoint: String, router: String,
    thresholds: Thresholds = Thresholds(), internetReferences: Bool = true
  ) {
    self.id = id
    self.ssid = ssid
    self.accessPoint = accessPoint
    self.router = router
    self.thresholds = thresholds
    self.internetReferences = internetReferences
  }

  public var isValid: Bool {
    !ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && ssid.utf8.count <= 32 && Self.validAddress(accessPoint)
      && Self.validAddress(router) && accessPoint != router && thresholds.isValid
  }

  public static func validAddress(_ address: String) -> Bool {
    guard let bytes = octets(address) else { return false }
    return bytes[0] > 0 && bytes[0] < 224 && bytes[0] != 127
  }

  /// Parses dotted-decimal IPv4 without leading zeros, which some parsers treat as octal.
  public static func octets(_ address: String) -> [UInt8]? {
    let components = address.split(separator: ".", omittingEmptySubsequences: false)
    guard components.count == 4 else { return nil }
    let bytes = components.compactMap { component -> UInt8? in
      guard component.allSatisfy({ $0.isASCII && $0.isNumber }),
        component.count == 1 || component.first != "0"
      else { return nil }
      return UInt8(component)
    }
    return bytes.count == 4 ? bytes : nil
  }
}

public struct NetworkIdentity: Codable, Equatable, Sendable {
  public let ssid: String
  public let bssid: String
  public let interface: String

  public init(ssid: String, bssid: String, interface: String) {
    self.ssid = ssid
    self.bssid = bssid
    self.interface = interface
  }
}

public struct MonitoringSession: Sendable {
  public private(set) var generation = UUID()
  public private(set) var profile: NetworkProfile?
  public private(set) var network: NetworkIdentity?
  public private(set) var window = MonitoringWindow()

  public init() {}

  @discardableResult
  public mutating func select(
    network: NetworkIdentity?, profiles: [NetworkProfile], permitted: Bool, paused: Bool
  ) -> Bool {
    let matches = profiles.filter { $0.isValid && $0.ssid == network?.ssid }
    let selected = permitted && !paused && matches.count == 1 ? matches.first : nil
    let identity = selected == nil ? nil : network
    guard selected != profile || identity != self.network else { return false }
    generation = UUID()
    profile = selected
    self.network = identity
    window = MonitoringWindow(thresholds: selected?.thresholds ?? Thresholds())
    return true
  }

  public mutating func reset() {
    generation = UUID()
    window = MonitoringWindow(thresholds: profile?.thresholds ?? Thresholds())
  }

  public mutating func accept(_ pair: ProbePair, generation: UUID) {
    guard profile != nil, generation == self.generation else { return }
    window.append(pair)
  }
}

extension NetworkProfile {
  /// Profiles saved before internet references existed decode with them enabled.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decode(UUID.self, forKey: .id),
      ssid: try container.decode(String.self, forKey: .ssid),
      accessPoint: try container.decode(String.self, forKey: .accessPoint),
      router: try container.decode(String.self, forKey: .router),
      thresholds: try container.decode(Thresholds.self, forKey: .thresholds),
      internetReferences: try container.decodeIfPresent(Bool.self, forKey: .internetReferences)
        ?? true)
  }
}
