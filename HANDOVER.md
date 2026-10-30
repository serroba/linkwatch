# LinkWatch — implementation plan and session handover

## Goal

Build a native macOS menu bar application that compares latency to an access
point (AP) and router. Show live numbers and a coloured health indicator near
the clock. Monitor only explicitly selected Wi-Fi networks. Establish good
engineering fundamentals for a potential free, open-source release.

## User instructions

- Set up and verify CI **before implementing the application**.
- Use Git for source control and make regular, small commits after checks pass.
- Use the `gh` CLI for most GitHub actions.
- Include meaningful tests, formatting/lint checks and CI from the beginning.
- Work autonomously towards a working app once CI is established.
- Repository must be public under `serroba`, with the MIT licence.
- Do not spawn parallel agents unless subsequently authorised.

## Repository and current state

- GitHub: https://github.com/serroba/linkwatch
- Local project: `/Users/sebastian/linkwatch`
- Branch: `main`, tracking `origin/main`.
- Last observed commit: `5d5f4d3 Initial commit`.
- GitHub repository exists, is public and has an MIT licence and README.
- No app source, Swift package, installed app or launched app exists here yet.
- Earlier work mentioned in the prior conversation was in another workspace;
  it has not been recovered or moved into this repository. Do not assume that
  monitoring implementation exists here.

These files were prepared locally and remain untracked/uncommitted:

- `.github/workflows/ci.yml`
- `scripts/check_repository.py`
- `.editorconfig`
- `.gitignore`
- `CONTRIBUTING.md`
- `HANDOVER.md` (this handover)

The CI configuration has **not** been validated end to end or run on GitHub.
Review it before committing; do not describe CI as working yet.

## First priority: restore execution access and complete CI

1. Confirm the session runs locally on the Mac in the project folder. An earlier
   attempt temporarily switched to an empty cloud environment without `gh` or
   the local repository.
2. Read any applicable `AGENTS.md`, inspect Git status and preserve existing work.
3. Verify Git writes and `gh` connectivity directly. The previous session could
   edit source files but could not create `.git/index.lock`; its policy explicitly
   marked `.git` read-only. It also could not connect to `api.github.com`.
4. Do not assume the GitHub token is invalid just because sandboxed
   `gh auth status` says so alongside a network connection failure. Check with
   working network access before asking the user to reauthenticate.
5. Review and validate the existing CI bootstrap. It currently provides:
   - Repository whitespace and conflict-marker checks on Ubuntu.
   - A conditional macOS Swift job that activates when `Package.swift` exists.
   - Swift formatting lint, build and tests with warnings treated as errors.
   - A stable aggregate `CI required` check.
   - Read-only workflow permissions, SHA-pinned checkout, timeouts and cancellation.
6. Ensure the bootstrap checks are meaningful and verify the workflow syntax.
   Consider workflow linting and automated dependency updates. Avoid adding
   unnecessary dependencies or tests that simply mirror implementation.
7. Stage files before running the repository checker: it uses `git ls-files` and
   therefore does not check untracked files.
8. Commit the CI bootstrap, push with Git and inspect the actual run using
   `gh run list`, `gh run watch` and logs. Resolve failures before app development.
9. Configure a suitable required CI check/branch protection if supported, reporting
   any account limitations. Keep a practical contribution path for a solo owner.
10. Introduce the Swift package and meaningful tests as the next checked commit;
    verify that the conditional Swift job runs and passes. The bootstrap alone
    does not establish a successful macOS build/test run.

The proposed workflow pins macOS 15 / Xcode 16.4. Verify runner availability and
toolchain compatibility. The Mac previously reported Swift 6.4 and only Command
Line Tools selected. A prior workspace could not resolve XCTest; reassess that
with a concrete build rather than assuming it remains broken.

## Agreed first-version experience

Menu bar example: `● AP 1 · R 62 ms`.

- Live AP/router numbers, with monospaced digits and stable layout.
- A coloured dot indicates health; clicking opens details and controls.
- Details include latency, packet loss, short history/sparklines, difference,
  active network/profile and how long degradation has persisted.
- Controls include pause, network profiles and alert thresholds.
- Unselected networks show a grey paused state and generate no probes.
- Desktop notifications are off by default; menu bar colour is the main alert.

### Starting defaults

| Setting | Default |
| --- | --- |
| Probe interval | Every 2 seconds, both targets together |
| Displayed latency | Median of the last 5 samples |
| Difference alert | Router exceeds AP by 20 ms for 10 seconds |
| Recovery | Separate lower threshold and sustained healthy samples |
| Failed/unreachable target | Explicit failure state and `—`, never zero latency |
| History | Short, bounded in-memory history |
| Other networks | Paused |

Thresholds are configurable starting values, not proven diagnostic boundaries.
Specify exact alert and recovery timing semantics before implementing tests.

### Health states

| Observation | Presentation |
| --- | --- |
| Both targets respond quickly | Green |
| AP fast, router persistently slower | Red with descriptive difference |
| Both persistently slow | Amber; possible local Wi-Fi/laptop delay |
| Target unreachable | Distinct red/error state; identify target |
| Unselected network, permission missing or manual pause | Grey with reason |

## Network profiles and privacy

- Require explicit network selection; never monitor arbitrary networks by default.
- Match SSID, optionally reinforced by gateway identity.
- Home example: AP `192.168.0.42`, router `192.168.0.1`.
- Treat these addresses as user configuration, not public baked-in defaults or
  necessary public fixtures. Do not publish the user's real SSID/BSSID.
- Support configurable AP address and router address/default-gateway detection.
- Track association/BSSID so roaming does not misleadingly label a configured
  device as the AP currently carrying traffic.
- macOS may require Location permission to expose SSID/BSSID. Verify current API
  requirements, explain the reason in the UI and pause safely if unavailable.
- No need to request location coordinates, collect telemetry or scan subnets.
- Keep settings local. Validate addresses and threshold inputs.

## Architecture and implementation sequence

1. Use native Swift/SwiftUI with an appropriate macOS status-item/menu bar API.
2. Separate monitoring decisions and statistics from networking and UI so they
   can be tested deterministically without a live network.
3. Define paired probe results with monotonic timing and explicit success,
   timeout, failure and cancellation outcomes. Do not overlap probe cycles.
4. Implement rolling statistics, loss, sustained degradation and hysteresis.
5. Implement profile matching, active Wi-Fi detection and lifecycle handling.
6. Implement a minimal, unprivileged probe adapter. Prefer native APIs without
   shell interpolation or a privileged helper. Verify real macOS ICMP behaviour
   and distribution constraints before committing to the implementation.
7. Bind probes to the intended Wi-Fi interface where supported; account for VPNs,
   Ethernet changes and routing. Do not silently measure a different interface.
8. Cancel probes and clear old history on sleep/wake, profile, network or radio
   changes. Reject stale results using a session/generation identity.
9. Add the menu bar display, accessible status text and detail panel.
10. Add profile/threshold settings and local persistence.
11. Package a runnable `.app`, document local build/run steps and test on the Mac.
12. Verify real paired measurements, pause behaviour and network transitions.
    Provide a clear release-readiness list for signing/notarisation and packaging;
    do not imply an unsigned prototype is ready for public distribution.

Make small commits along this sequence. Keep CI green after each meaningful step.

## Meaningful verification

- Rolling median and bounded history under irregular sampling.
- Sustained degradation timing and hysteresis; no alert from a single spike.
- Packet loss and unreachable states cannot accidentally look healthy.
- Missing permissions and unselected networks cause zero probe activity.
- Cancellation, sleep/wake and network transitions discard stale results.
- Invalid/corrupt profiles and settings fail safely.
- Build, test and formatting checks run in macOS CI once the package is present.
- Manual UI check: readable stable numbers, distinguishable states and useful
  accessibility labels; colour must not be the only explanation.

## Diagnostic background and limits

The motivating network measurements showed approximately 0.8 ms to the AP and
60–70 ms to the router, with external destinations sometimes similarly delayed.
Measurements were taken at different times and a direct Ethernet test was not
confirmed. No specific failing component was established.

AP management ICMP and router ICMP measure different device response paths.
Their difference is useful evidence but does not prove an Ethernet uplink fault.
Strong signal and high negotiated Wi-Fi rates do not rule out latency problems.
Use observational descriptions in the UI rather than definitive fault attribution.

## Permission troubleshooting history

The user enabled Full access in global app settings, but this existing chat still
received a restrictive execution policy. The interface shown did not expose the
documented per-chat permission selector. Previous advice repeatedly guessed UI
locations and was unhelpful. Do not repeat it. Verify actual access and report
precise blockers. Do not bypass restrictions using alternate Git metadata paths
or browser-controlled terminal commands.

## Completion criteria

- CI is committed, published and observed passing before application features.
- All subsequent app work is committed regularly with passing relevant checks.
- A locally runnable macOS app shows live AP/router numbers and sustained alerts.
- Monitoring runs only for approved network profiles and pauses safely elsewhere.
- Settings, lifecycle handling, meaningful tests and build documentation exist.
- Public repository remains MIT licensed; remaining distribution work is explicit.
