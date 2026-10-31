# Contributing

The project objective lives in [README.md](README.md), the plan in
[docs/roadmap.md](docs/roadmap.md) and the code structure in
[docs/architecture.md](docs/architecture.md).
Make small commits and keep checks green. Do not spawn parallel agents unless
explicitly authorised.

Use a feature branch and pull request for every change. Do not push directly to
`main`. Wait for the PR's latest commit to pass all CI jobs before merging; never
bypass required checks. Main requires a PR and `CI required`, including for admins.
No approving review is required, so the solo owner can merge a green PR.

Run repository checks from the repository root after staging new files:

```sh
python3 scripts/check_repository.py
```

Run the same checks used by macOS CI:

```sh
swift format lint --strict --recursive Package.swift Sources Tests
swift build -Xswiftc -warnings-as-errors
LINKWATCH_TEST_LOOPBACK=1 swift test --parallel --enable-code-coverage -Xswiftc -warnings-as-errors
python3 scripts/check_coverage.py "$(swift test --show-codecov-path)" Sources/LinkWatchCore 90
LINKWATCH_TEST_LOOPBACK=1 swift test --sanitize=thread --scratch-path .build/tsan
swiftlint lint --strict --quiet
periphery scan
```

`.swift-format` owns layout and forbids force unwraps, force `try` and implicitly
unwrapped optionals. `.swiftlint.yml` adds semantic and complexity rules; split a
function rather than raising a limit. Periphery fails on unused code. All targets
enable the `ExistentialAny`, `InternalImportsByDefault` and `MemberImportVisibility`
upcoming features. CI installs SwiftLint and Periphery from pinned releases and
verifies their SHA-256 checksums with `scripts/install_tool.sh`; update the version
and checksum together. With only Command Line Tools installed, run SwiftLint with
`TOOLCHAIN_DIR=/Library/Developer/CommandLineTools`. Periphery in CI also indexes
the test targets, so scan them locally too. With Swift 6.4 and only Command Line
Tools, build the index with the native build system and the Testing framework path:

```sh
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift build --build-tests --build-system native --scratch-path .build/native-tests \
  -Xswiftc -F -Xswiftc "$FW" -Xlinker -F -Xlinker "$FW" \
  -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
periphery scan --skip-build --index-store-path .build/native-tests/arm64-apple-macosx/debug/index/store
```

CI uses Swift 6.1, which type-checks large expressions more slowly than 6.4; build
with `-Xswiftc -Xfrontend -Xswiftc -warn-long-expression-type-checking=150` (tests
too, with `--build-tests`) to find expressions to split before CI rejects them.

Do not remove package detection to skip a failing Swift build. Add meaningful
tests for monitoring decisions, failed probes and network changes. Keep pure
monitoring logic separate from networking and UI, use monotonic timing, avoid
overlapping probe cycles and reject results from obsolete sessions.

Use `gh` for GitHub operations. Keep real SSIDs, BSSIDs and local network addresses
out of source, fixtures and public logs. Use documentation-only addresses such as
`192.0.2.1` in tests. Keep settings local and fail safely on invalid configuration.
See [monitoring semantics](docs/monitoring.md) for timing and probe behavior,
including the verified local Swift 6.4 macro-plugin workaround.

The macOS job uses Xcode 16.4 on macOS 15. Keep the package compatible with that
toolchain and update CI deliberately when raising the minimum Swift version.
Third-party actions must be pinned to a full commit SHA. CI uses read-only
repository access and does not retain checkout credentials.

Branch protection requires `CI required`. This stable check includes repository
and applicable Swift results. Check the latest PR commit and all pipeline jobs
before merging. Routine tests are authorised; reuse approved commands instead of
requesting repeated permission. Actual execution-policy blocks must be reported
accurately, without treating sandbox network failures as invalid credentials.

## Running the app locally

```sh
bash scripts/build_app.sh
osascript -e 'quit app "LinkWatch"'; open dist/LinkWatch.app
scripts/linkwatch diagnose
```

Quit and reopen the app after every rebuild. `build_app.sh` replaces the bundle in
place, and a copy that keeps running from the replaced bundle no longer matches its
code signature, so macOS stops granting it Local Network access and the router looks
silent. Use `scripts/linkwatch`, not the bare executable, for commands; see
[docs/cli.md](docs/cli.md).

Never launch a differently signed copy on the same Mac as your development build,
for example a release downloaded to test the installer. Both share the bundle
identifier, and macOS moves the Location and Local Network grants to whichever copy
asked last, so the development build silently stops monitoring. Test installs on
another Mac or user account, then re-grant permissions from the development build's
Settings if it happened.

`build_app.sh` draws the app icon with `scripts/make_icon.swift` and converts it with
`iconutil`; change the drawing there rather than adding image files.

## Documentation

Behaviour changes update the documents that describe them in the same pull request:
[monitoring semantics](docs/monitoring.md) for rules, the [user guide](docs/user-guide.md)
for anything a user sees, [command line](docs/cli.md) for commands,
[privacy](docs/privacy.md) for anything measured, sent or stored, and the
[roadmap](docs/roadmap.md) when an item ships. Keep the
[`diagnose-network` skill](.claude/skills/diagnose-network/SKILL.md) in step with
verdicts and commands.

## Releases

Push a `vX.Y.Z` tag to publish a release; see
[docs/install.md](docs/install.md#for-maintainers-publishing-a-release), including
the optional signing identity.

## Local signing

macOS ties privacy grants such as Location to the code signature. To keep them
across rebuilds, create a local code-signing identity named
`LinkWatch Local Development` in the login keychain (a self-signed certificate with
the code-signing extended key usage), then allow `codesign` to use its key without a
dialog by running this once in Terminal.app, which asks for the login password:

```sh
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -t private \
  -D "LinkWatch Local Development" ~/Library/Keychains/login.keychain-db
```

`scripts/build_app.sh` uses that identity, or `LINKWATCH_SIGN_IDENTITY`, and falls
back to ad-hoc signing, as in CI. The identity is not trusted by other Macs and is
not a distribution signature.
