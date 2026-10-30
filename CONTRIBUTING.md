# Contributing

CI comes before application implementation. Make small commits and keep checks green.

Run repository checks from the repository root after staging new files:

```sh
python3 scripts/check_repository.py
```

Once the Swift package exists, run the same checks used by macOS CI:

```sh
swift format lint --strict --recursive Package.swift Sources Tests
swift build -Xswiftc -warnings-as-errors
swift test --parallel -Xswiftc -warnings-as-errors
```

The initial CI bootstrap intentionally has no application code. The Swift job
activates when `Package.swift` is introduced; that commit must include `Sources`
and `Tests`. Do not remove package detection to skip a failing Swift build.
Add meaningful tests for monitoring decisions, failed probes and network changes.

The macOS job uses Xcode 16.4 on macOS 15. Keep the package compatible with that
toolchain and update CI deliberately when raising the minimum Swift version.
Third-party actions must be pinned to a full commit SHA. CI uses read-only
repository access and does not retain checkout credentials.

Configure branch protection to require `CI required` after the first successful
workflow run. This stable check includes repository and applicable Swift results.
