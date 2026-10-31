# Contributing

The project objective and product boundaries live in [README.md](README.md).
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
`TOOLCHAIN_DIR=/Library/Developer/CommandLineTools`. Periphery needs an index store,
so with Swift 6.4 build with `swift build --build-system native --scratch-path
.build/native` and scan with `--skip-build --index-store-path
.build/native/debug/index/store`.

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
