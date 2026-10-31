public import Foundation

/// A shareable report: a readable diagnosis, the same as JSON, and every stored minute.
public struct ExportedReport: Equatable, Sendable {
  /// A dated folder name without characters that file systems reject.
  public let folderName: String
  /// File names and contents, written into the folder.
  public let files: [String: Data]

  public init(
    report: DiagnoseReport, minutes: [MinuteSummary], bridgeNames: [String: String],
    hotspots: Set<String> = [], redact: Bool
  ) {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH-mm"
    folderName = "LinkWatch report \(formatter.string(from: report.generatedAt))"
    let redactor = redact ? Redactor(report: report, minutes: minutes) : nil
    let header =
      redact
      ? "Network names, local addresses and hardware addresses are replaced with placeholders."
      : "This report contains the network name and local addresses. Share it only with people you trust."
    let text = header + "\n\n" + report.text(bridgeNames: bridgeNames, hotspots: hotspots)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let reportJSON = (try? encoder.encode(report)) ?? Data()
    let minutesJSON = (try? encoder.encode(minutes)) ?? Data()
    func clean(_ text: String) -> Data { Data((redactor?.apply(text) ?? text).utf8) }
    files = [
      "report.txt": clean(text),
      "report.json": clean(String(bytes: reportJSON, encoding: .utf8) ?? ""),
      "minutes.json": clean(String(bytes: minutesJSON, encoding: .utf8) ?? ""),
    ]
  }

  /// Writes the folder into a directory and returns its location.
  public func write(into directory: URL) throws -> URL {
    let folder = directory.appendingPathComponent(folderName, isDirectory: true)
    try FileManager.default.createDirectory(
      at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    for (name, data) in files {
      let file = folder.appendingPathComponent(name)
      try data.write(to: file, options: [.atomic])
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    return folder
  }
}

/// Replaces identifying values with stable placeholders, keeping public reference hosts.
struct Redactor {
  private var replacements: [(String, String)] = []

  static let publicReferences: Set<String> = Set(InternetReference.all.map(\.address))

  init(report: DiagnoseReport, minutes: [MinuteSummary]) {
    var names = Set(minutes.map(\.ssid) + report.status.profiles.map(\.ssid))
    if let network = report.status.network { names.insert(network.ssid) }
    self.init(replacing: names.sorted())
  }

  init(replacing names: [String]) {
    for (index, name) in names.enumerated() where !name.isEmpty {
      replacements.append((name, "network-\(index + 1)"))
    }
  }

  func apply(_ text: String) -> String {
    var result = text
    // Longest names first, so a name containing another is replaced whole.
    for (name, placeholder) in replacements.sorted(by: { $0.0.count > $1.0.count }) {
      result = result.replacingOccurrences(of: name, with: placeholder)
      let escaped = Self.jsonEscaped(name)
      if escaped != name { result = result.replacingOccurrences(of: escaped, with: placeholder) }
    }
    result = Self.replace(
      #"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])"#, in: result, prefix: "address"
    ) {
      Self.publicReferences.contains($0)
    }
    result = Self.replace(
      #"(?i)(?<![0-9a-f:])(?:[0-9a-f]{1,2}:){5}[0-9a-f]{1,2}(?![0-9a-f:])"#, in: result,
      prefix: "device"
    ) { _ in false }
    return result
  }

  /// The name as it appears inside the report's JSON strings, which keep slashes unescaped.
  private static func jsonEscaped(_ name: String) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let quoted = String(bytes: (try? encoder.encode(name)) ?? Data(), encoding: .utf8) ?? ""
    return String(quoted.dropFirst().dropLast())
  }

  /// Replaces each distinct match with `prefix-N`, numbered in order of appearance.
  private static func replace(
    _ pattern: String, in text: String, prefix: String, keep: (String) -> Bool
  ) -> String {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
    let source = text as NSString
    var numbers: [String: Int] = [:]
    var result = ""
    var cursor = 0
    for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
      let value = source.substring(with: match.range)
      result += source.substring(
        with: NSRange(location: cursor, length: match.range.location - cursor))
      if keep(value) {
        result += value
      } else {
        let number = numbers[value] ?? numbers.count + 1
        numbers[value] = number
        result += "\(prefix)-\(number)"
      }
      cursor = match.range.location + match.range.length
    }
    return result + source.substring(from: cursor)
  }
}
