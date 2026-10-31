/// The Mac's own Wi-Fi radio readings, available without sending traffic.
public struct WiFiSignal: Codable, Equatable, Sendable {
  /// Received signal strength in dBm; closer to zero is stronger.
  public var rssi: Int
  /// Background noise in dBm.
  public var noise: Int
  /// The negotiated transmit rate in Mbit/s.
  public var transmitRate: Double
  public var channel: Int?
  /// `2.4 GHz`, `5 GHz` or `6 GHz`.
  public var band: String?

  public init(rssi: Int, noise: Int, transmitRate: Double, channel: Int?, band: String?) {
    self.rssi = rssi
    self.noise = noise
    self.transmitRate = transmitRate
    self.channel = channel
    self.band = band
  }

  /// Signal-to-noise ratio in dB.
  public var snr: Int { rssi - noise }

  /// Below about −70 dBm or 20 dB above the noise, Wi-Fi itself becomes unreliable.
  public var isWeak: Bool { rssi < -70 || snr < 20 }

  /// `excellent`, `good`, `fair` or `weak`.
  public var quality: String {
    if isWeak { return "weak" }
    if rssi >= -55 && snr >= 35 { return "excellent" }
    return rssi >= -65 && snr >= 25 ? "good" : "fair"
  }

  public var summary: String {
    var text = "\(rssi) dBm (\(quality)) · SNR \(snr) dB · \(Int(transmitRate)) Mbit/s"
    if let channel { text += " · channel \(channel)" + (band.map { " (\($0))" } ?? "") }
    return text
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(rssi, forKey: .rssi)
    try container.encode(noise, forKey: .noise)
    try container.encode(transmitRate, forKey: .transmitRate)
    try container.encode(channel, forKey: .channel)
    try container.encode(band, forKey: .band)
  }
}
