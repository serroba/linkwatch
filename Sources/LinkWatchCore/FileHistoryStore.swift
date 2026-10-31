public import Foundation

/// Reads stored history without ever writing it, for processes other than the menu bar app:
/// a concurrent rewrite (pruning) could otherwise drop a minute the app just appended.
public struct ReadOnlyHistoryStore: HistoryStore {
  private let store: FileHistoryStore

  public init(directory: URL) { store = FileHistoryStore(directory: directory) }

  public func load(since date: Date) throws -> [MinuteSummary] { try store.load(since: date) }
  public func append(_ summary: MinuteSummary) throws {}
  public func prune(before date: Date) throws {}
  public func clear() throws {}
}

/// Stores minute summaries as JSON Lines in a private file.
///
/// Appends add one line, so an interrupted write loses at most that minute. Unreadable
/// lines are skipped rather than discarding the rest of the week.
public struct FileHistoryStore: HistoryStore {
  public let file: URL

  public init(directory: URL) {
    file = directory.appendingPathComponent("history.jsonl")
  }

  public func load(since date: Date) throws -> [MinuteSummary] {
    guard FileManager.default.fileExists(atPath: file.path) else { return [] }
    let decoder = Self.decoder
    return try String(contentsOf: file, encoding: .utf8)
      .split(separator: "\n")
      .compactMap { try? decoder.decode(MinuteSummary.self, from: Data($0.utf8)) }
      .filter { $0.start >= date }
  }

  public func append(_ summary: MinuteSummary) throws {
    try prepare()
    var line = try Self.encoder.encode(summary)
    line.append(0x0A)
    let handle = try FileHandle(forWritingTo: file)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: line)
  }

  public func prune(before date: Date) throws {
    try rewrite(with: load(since: date))
  }

  public func clear() throws {
    try rewrite(with: [])
  }

  private func rewrite(with summaries: [MinuteSummary]) throws {
    try prepare()
    var data = Data()
    for summary in summaries {
      data.append(try Self.encoder.encode(summary))
      data.append(0x0A)
    }
    try data.write(to: file, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
  }

  /// Creates the directory (0700) and file (0600) so history is readable only by this user.
  private func prepare() throws {
    let directory = file.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    if !FileManager.default.fileExists(atPath: file.path) {
      guard
        FileManager.default.createFile(
          atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
      else { throw CocoaError(.fileWriteNoPermission) }
    }
  }

  private static var encoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }

  private static var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
