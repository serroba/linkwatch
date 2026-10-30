import Foundation
import Testing

@testable import LinkWatchNetworking

@Test func echoReplyValidation() {
  let packet = EchoPacket(identifier: 1234, payload: [1, 2, 3, 4, 5])
  #expect(EchoPacket.checksum(packet.request) == 0)
  var reply = packet.request
  reply[0] = 0
  reply[2] = 0
  reply[3] = 0
  let checksum = EchoPacket.checksum(reply)
  reply[2] = UInt8(checksum >> 8)
  reply[3] = UInt8(checksum & 255)
  var header = [UInt8](repeating: 0, count: 20)
  header[0] = 0x45
  header[9] = 1
  #expect(packet.matches(header + reply))
  #expect(!packet.matches(header + packet.request))
  #expect(!EchoPacket(identifier: 4321, payload: packet.payload).matches(header + reply))
  reply[reply.count - 1] ^= 1
  #expect(!packet.matches(header + reply))
  for count in 0..<28 { #expect(!packet.matches(Array((header + reply).prefix(count)))) }
}

@Test func invalidInterfaceFailsWithoutSending() async {
  let result = await ICMPProbe.measure(address: "192.0.2.1", interface: "invalid-interface")
  #expect(result == .failure)
}

@Test func loopbackProbeWhenExplicitlyEnabled() async throws {
  guard ProcessInfo.processInfo.environment["LINKWATCH_TEST_LOOPBACK"] == "1" else { return }
  let result = await ICMPProbe.measure(address: "127.0.0.1", interface: "lo0")
  #expect(result.latency != nil)
}
