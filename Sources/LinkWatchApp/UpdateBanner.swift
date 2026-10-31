import LinkWatchCore
import SwiftUI

/// "LinkWatch X is available", with one button to install it or open the release page.
struct UpdateBanner: View {
  @ObservedObject var updates: UpdateChecker

  var body: some View {
    if let update = updates.available {
      VStack(alignment: .leading, spacing: 4) {
        Text("LinkWatch \(update.version) is available").font(.caption).bold()
        HStack {
          if updates.canInstall {
            Button("Install update") { updates.install() }
          }
          Button("What's new") { updates.openReleasePage() }
        }
        .font(.caption)
        Text(
          updates.message
            ?? "After updating, macOS may ask again for Location and Local Network access."
        )
        .font(.caption2).foregroundStyle(.secondary)
      }
    }
  }
}
