# Installing LinkWatch

LinkWatch runs on macOS 14 or later. Releases are published on
[GitHub Releases](https://github.com/serroba/linkwatch/releases) as a zip containing
`LinkWatch.app` and a SHA-256 checksum.

## Install or update

In Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/serroba/linkwatch/main/scripts/install.sh | bash
```

The installer downloads the latest release, verifies its checksum, quits a running
LinkWatch, installs it in `/Applications` (or `~/Applications` when `/Applications`
is not writable) and opens it. Running the same command later updates it.

Prefer to read the script first? Download it, review it, then run it:

```sh
curl -fsSLO https://raw.githubusercontent.com/serroba/linkwatch/main/scripts/install.sh
less install.sh
bash install.sh                      # or: bash install.sh --version 0.2.0
```

To install by hand, download `LinkWatch-X.Y.Z.zip` from the release, check it with
`shasum -a 256 LinkWatch-X.Y.Z.zip` against the `.sha256` file, unzip it and move
`LinkWatch.app` to `/Applications`. A browser download is quarantined, so macOS asks
for confirmation: Control-click the app, choose **Open**, then **Open** again.

## First run

LinkWatch appears in the menu bar, not the Dock, and opens at login so monitoring
resumes after a restart (switch this off in Settings). It needs two permissions,
both granted once:

1. **Location**: click the menu bar icon → **Settings…** → **Allow Wi-Fi
   identification**, then allow the prompt. macOS uses Location to reveal the Wi-Fi
   name; LinkWatch never reads coordinates.
2. **Local Network**: if the panel says the router is not answering while the
   internet works, open **System Settings › Privacy & Security › Local Network** and
   switch **LinkWatch** on.

Then choose **Monitor this network** when LinkWatch suggests it, or set up the
network in Settings. The [user guide](user-guide.md) explains what you will see.

## Permissions after updates

macOS ties permissions to the app's code signature. Releases signed with the
project's stable signing identity keep Location and Local Network access across
updates. Releases built without it are signed *ad hoc*, which changes with every
build, so after updating you may need to grant both permissions again. The release
notes say which applies.

## Uninstall

```sh
/Applications/LinkWatch.app/Contents/MacOS/LinkWatch open-at-login off   # stop opening at login
osascript -e 'quit app "LinkWatch"'
rm -rf /Applications/LinkWatch.app
rm -rf ~/Library/Application\ Support/io.github.serroba.LinkWatch   # stored history
defaults delete io.github.serroba.LinkWatch                          # saved networks
```

Then remove LinkWatch from **System Settings › Privacy & Security › Location
Services** and **Local Network** if you like.

## Security notes

- The checksum protects against a corrupted or truncated download. It comes from the
  same release, so it does not prove who built the app; only Apple notarisation of a
  Developer ID signature does that, which is not set up yet.
- Files downloaded with `curl` are not quarantined, so Gatekeeper does not check the
  app. You are trusting this repository's releases, as with any `curl | bash` install;
  review the script first if that matters to you.
- The installer only writes `LinkWatch.app` to the chosen folder. It needs no
  administrator rights and installs no background services.

## For maintainers: publishing a release

Push a version tag; the release workflow runs the tests, builds and signs the app,
and publishes the zip, its checksum and install notes:

```sh
git tag -a v0.2.0 -m "LinkWatch 0.2.0"
git push origin v0.2.0
```

### Optional stable signing identity

To keep users' permissions across updates without an Apple Developer ID, the
workflow can sign with a self-signed code-signing certificate stored in repository
secrets. The private key then lives in GitHub secrets, so only do this if you accept
that anyone with admin access to the repository could sign builds as LinkWatch.

1. Create a code-signing certificate and key (for example with `openssl`, using
   `extendedKeyUsage = critical, codeSigning`) and export them as a `.p12` with a
   password. Keep the `.p12` out of the repository.
2. Add three repository secrets:
   - `LINKWATCH_SIGNING_P12`: the `.p12`, base64-encoded (`base64 -i identity.p12`)
   - `LINKWATCH_SIGNING_PASSWORD`: its password
   - `LINKWATCH_SIGNING_IDENTITY`: the certificate's common name
3. Delete local copies of the `.p12` you no longer need.

Without these secrets, releases are signed ad hoc. A Developer ID certificate with
notarisation (Apple Developer Program, USD 99 per year) would replace this and remove
the quarantine prompt for browser downloads; see the [roadmap](roadmap.md).
