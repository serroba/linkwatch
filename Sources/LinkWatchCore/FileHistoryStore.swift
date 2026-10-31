public import Foundation

/// A private append-only JSON Lines file.
///
/// Appends add one line, so an interrupted write loses at most that record. Unreadable
/// lines are skipped rather than discarding the rest of the file.
struct JSONLinesFile<Record: Codable> {
  let file: URL

  func load() throws -> [Record] {
    guard FileManager.default.fileExists(atPath: file.path) else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try String(contentsOf: file, encoding: .utf8)
      .split(separator: "\n")
      .compactMap { try? decoder.decode(Record.self, from: Data($0.utf8)) }
  }

  func append(_ record: Record) throws {
    try prepare()
    var line = try Self.encoder.encode(record)
    line.append(0x0A)
    let handle = try FileHandle(forWritingTo: file)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: line)
  }

  func rewrite(with records: [Record]) throws {
    try prepare()
    var data = Data()
    for record in records {
      data.append(try Self.encoder.encode(record))
      data.append(0x0A)
    }
    try data.write(to: file, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
  }

  /// Creates the directory (0700) and file (0600) so records are readable only by this user.
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
}

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
public struct FileHistoryStore: HistoryStore {
  private let lines: JSONLinesFile<MinuteSummary>

  public init(directory: URL) {
    lines = JSONLinesFile(file: directory.appendingPathComponent("history.jsonl"))
  }

  public func load(since date: Date) throws -> [MinuteSummary] {
    try lines.load().filter { $0.start >= date }
  }

  public func append(_ summary: MinuteSummary) throws { try lines.append(summary) }

  public func prune(before date: Date) throws { try lines.rewrite(with: load(since: date)) }

  public func clear() throws { try lines.rewrite(with: []) }
}
