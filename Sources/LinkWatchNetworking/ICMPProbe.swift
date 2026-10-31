import Darwin
import Foundation
public import LinkWatchCore

struct EchoPacket {
  let identifier: UInt16
  let payload: [UInt8]

  var request: [UInt8] {
    var bytes: [UInt8] =
      [
        8, 0, 0, 0, UInt8(identifier >> 8), UInt8(identifier & 255), 0, 1,
      ] + payload
    let checksum = Self.checksum(bytes)
    bytes[2] = UInt8(checksum >> 8)
    bytes[3] = UInt8(checksum & 255)
    return bytes
  }

  func matches(_ bytes: [UInt8]) -> Bool {
    guard bytes.count >= 20, bytes[0] >> 4 == 4, bytes[9] == 1 else { return false }
    let offset = Int(bytes[0] & 15) * 4
    guard offset >= 20, bytes.count == offset + 8 + payload.count else { return false }
    let message = Array(bytes.dropFirst(offset))
    return message[0] == 0 && message[1] == 0
      && message[4] == UInt8(identifier >> 8) && message[5] == UInt8(identifier & 255)
      && message[6] == 0 && message[7] == 1
      && Array(message.dropFirst(8)) == payload && Self.checksum(message) == 0
  }

  static func checksum(_ bytes: [UInt8]) -> UInt16 {
    var sum: UInt32 = 0
    for index in stride(from: 0, to: bytes.count, by: 2) {
      sum += UInt32(bytes[index]) << 8
      if index + 1 < bytes.count { sum += UInt32(bytes[index + 1]) }
    }
    while sum >> 16 != 0 { sum = (sum & 65_535) + (sum >> 16) }
    return ~UInt16(sum)
  }
}

enum ICMPProbe {
  static func measure(address: String, interface: String) async -> ProbeOutcome {
    let worker = Task.detached(priority: .utility) {
      perform(address: address, interface: interface)
    }
    return await withTaskCancellationHandler {
      await worker.value
    } onCancel: {
      worker.cancel()
    }
  }

  private static func perform(address: String, interface: String) -> ProbeOutcome {
    guard !Task.isCancelled else { return .cancelled }
    var destination = sockaddr_in()
    destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    destination.sin_family = sa_family_t(AF_INET)
    guard inet_pton(AF_INET, address, &destination.sin_addr) == 1,
      let descriptor = openSocket(interface: interface)
    else { return .failure }
    defer { close(descriptor) }
    let packet = EchoPacket(
      identifier: UInt16.random(in: 1...UInt16.max),
      payload: Array(UUID().uuidString.utf8))
    let started = ProcessInfo.processInfo.systemUptime
    guard !Task.isCancelled else { return .cancelled }
    guard send(packet.request, to: destination, on: descriptor) else { return .failure }
    return awaitReply(for: packet, from: destination, on: descriptor, started: started)
  }

  /// Opens a non-blocking unprivileged ICMP socket bound to the named interface.
  private static func openSocket(interface: String) -> Int32? {
    var interfaceIndex = if_nametoindex(interface)
    guard interfaceIndex > 0 else { return nil }
    let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
    guard descriptor >= 0 else { return nil }
    guard
      setsockopt(
        descriptor, IPPROTO_IP, IP_BOUND_IF, &interfaceIndex,
        socklen_t(MemoryLayout<UInt32>.size)) == 0,
      fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0
    else {
      close(descriptor)
      return nil
    }
    return descriptor
  }

  private static func send(_ request: [UInt8], to destination: sockaddr_in, on descriptor: Int32)
    -> Bool
  {
    var destination = destination
    let sent = withUnsafePointer(to: &destination) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
        request.withUnsafeBytes { buffer in
          sendto(
            descriptor, buffer.baseAddress, buffer.count, 0, socketAddress,
            socklen_t(MemoryLayout<sockaddr_in>.size))
        }
      }
    }
    return sent == request.count
  }

  private static func awaitReply(
    for packet: EchoPacket, from destination: sockaddr_in, on descriptor: Int32,
    started: TimeInterval
  ) -> ProbeOutcome {
    while ProcessInfo.processInfo.systemUptime - started < 1 {
      if Task.isCancelled { return .cancelled }
      switch waitForReadable(descriptor) {
      case .idle: continue
      case .failed: return .failure
      case .readable: break
      }
      switch receive(on: descriptor) {
      case .retry: continue
      case .failed: return .failure
      case .received(let bytes, let sender):
        guard sender == destination.sin_addr.s_addr, packet.matches(bytes) else { continue }
        guard !Task.isCancelled else { return .cancelled }
        return .success(milliseconds: (ProcessInfo.processInfo.systemUptime - started) * 1000)
      }
    }
    return Task.isCancelled ? .cancelled : .timeout
  }

  private enum Readiness {
    case readable
    case idle
    case failed
  }

  /// Waits up to 50 ms so cancellation and the deadline are checked regularly.
  private static func waitForReadable(_ descriptor: Int32) -> Readiness {
    var event = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
    let ready = poll(&event, 1, 50)
    if ready < 0 { return errno == EINTR ? .idle : .failed }
    if ready == 0 { return .idle }
    return event.revents & Int16(POLLIN) != 0 ? .readable : .failed
  }

  private enum Reception {
    case received([UInt8], sender: in_addr_t)
    case retry
    case failed
  }

  private static func receive(on descriptor: Int32) -> Reception {
    var buffer = [UInt8](repeating: 0, count: 2048)
    var sender = sockaddr_in()
    var senderLength = socklen_t(MemoryLayout<sockaddr_in>.size)
    let count = withUnsafeMutablePointer(to: &sender) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
        buffer.withUnsafeMutableBytes { bytes in
          recvfrom(descriptor, bytes.baseAddress, bytes.count, 0, socketAddress, &senderLength)
        }
      }
    }
    guard count >= 0 else { return errno == EAGAIN || errno == EINTR ? .retry : .failed }
    return .received(Array(buffer.prefix(count)), sender: sender.sin_addr.s_addr)
  }
}

/// Measures latency with native ICMP echo requests.
public struct ICMPLatencyProbe: LatencyProbe {
  public init() {}

  public func measure(address: String, interface: String) async -> ProbeOutcome {
    await ICMPProbe.measure(address: address, interface: interface)
  }
}
