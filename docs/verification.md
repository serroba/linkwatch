# Verification and release readiness

Automated tests exercise rolling statistics, sustained degradation and recovery,
invalid profiles, permission and network selection gates, stale-result rejection,
ICMP packet validation and an opt-in real loopback probe. CI enables that probe
and builds and verifies the ad-hoc-signed application bundle.

## Manual acceptance

- Start with no profiles: grey state and no probes.
- Grant Wi-Fi identification permission; save only the network you want monitored.
- Verify AP and router numbers against contemporaneous independent measurements.
- Check failure states identify the affected target and display `—` rather than zero.
- Pause and resume; verify history clears and no probes are sent while paused.
- Change network, roam, disable Wi-Fi, and sleep/wake. Old measurements must not
  appear after the transition. Confirm only selected profiles resume monitoring.
- Check VPN and Ethernet route changes: probes must remain on the Wi-Fi interface
  or fail, never silently measure a different interface.
- Check readable menu bar values, history, profile editing, keyboard navigation
  and VoiceOver explanations. Verify colour is not the only state information.
- Deny Location and Local Network access and verify clear paused/error states.
- Restart the app and verify local profiles persist without leaking to logs.

These checks require user-approved network details and macOS permission prompts.
The automated loopback test alone does not establish real-network correctness.

## Before public distribution

- Complete the manual acceptance checks on supported macOS versions.
- Verify settings, cancellation and UI with a wider set of devices and VPNs.
- Choose a stable signing identity and sign with Developer ID and hardened runtime.
- Notarise and staple the distributable; verify Gatekeeper on a clean Mac.
- Provide versioned release packaging, an app icon, installation/removal instructions
  and a documented update process. No updater or launch-at-login service exists yet.
- Recheck privacy descriptions, accessibility and the MIT licensing of bundled code.
