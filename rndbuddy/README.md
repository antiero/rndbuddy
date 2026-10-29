# rndbuddy

Native SwiftUI companion for Cyma Forma RND on iOS 18+ and macOS 15+.
Swift 6, Apple frameworks, no third-party runtime dependencies.

## Run

Open `rndbuddy.xcodeproj` and select the shared `rndbuddy` scheme. Choose a Mac,
iPhone or iPad destination. Use your development team for device signing.

The app connects automatically when exactly one RND MIDI endpoint is available.
If firmware detection is inconclusive, select the correct profile in Settings.
Never choose a profile merely to unlock controls: official 1.4 and JGpatch-023
reuse some SysEx opcodes for different operations.

Settings → Demo provides simulated MIDI without producing sound or sending
hardware messages. A development launch with `--demo` starts the same mode.

This app directory is a separate Git repository created with the Xcode project.
Run Git commands here to inspect the native application's changes.

## Implemented

- Native Perform, Library and Settings screens with adaptive phone, tablet and
  Mac layouts, a four-track mixer, patch generation and seed recall.
- Official 1.4 and JGpatch-023 protocol profiles, with reported/requested state
  kept distinct. JG engine rerolls, exact reroll seeds, generation masks, deeper
  reverb and freeze are supported by the native editor.
- Independent touch contacts, scale-aware playing, pointer/musical keyboard
  input, camera pinch control using MIDIVision's tracking core, and calibrated
  Core Motion input on supported iOS devices.
- Shared assignments, smoothing, inversion, range limits, dead zones, hold and
  note ownership. Modulate and Play are separate; entering Play asks before
  taking over a generated track.
- Live RND pixels in a stable WKWebView, using an origin-scoped WebMIDI/SysEx
  bridge. Its own visual selector/control table remain available. Native full
  screen and external-display transfer share the same web view.
- Stereo USB audio monitoring, initially off. Mac uses a private drift-corrected
  aggregate and direct Core Audio I/O; iOS uses AVAudioSession/AVAudioEngine.
  A four-channel device can use a labelled dry sum. Monitoring can continue in
  the background; hands/motion stop and gesture-owned notes are released.
- Versioned SwiftData patch/mapping library, private CloudKit configuration,
  favourites, tags, search, duplicates, JSON archive and JG CSV import/export.
  Immutable revisions and tombstones provide deterministic newest-edit merging.
  Unsupported CSV columns survive round trips.
- Bounded local recent history and a non-sounding interactive Demo.

## iCloud and signing

The configured private container is `iCloud.com.5of12.rndbuddy`. Enable iCloud /
CloudKit and Push Notifications for the app identifier in your Apple developer
team and provision that container before validating sync or making a TestFlight
archive. The iOS plist includes the audio background mode. Release APNs uses the
production environment; debug uses development.

Unprovisioned Mac and simulator builds intentionally use local storage. They do
not prove CloudKit is syncing. Startup does not call CloudKit without the needed
entitlement, avoiding an asynchronous framework trap in unsigned builds.

The locally signed Mac review build was produced with CloudKit entitlements
overridden off; open the project normally for a fully provisioned device build.

## Validation

See [docs/Validation.md](docs/Validation.md) for actual results and remaining
hardware/release gates. A successful build is not a release or device acceptance.

```sh
swift test
swift test --package-path Packages/MIDIVisionHandTrackingCore
xcodebuild -project rndbuddy.xcodeproj -scheme rndbuddy \
  -destination 'platform=macOS' test
```

Use `xcodebuild -showdestinations` to select an installed iOS simulator. The
runtime tests default to fake MIDI and in-memory storage. Physical tests require
explicit `TEST_RUNNER_RNDBUDDY_HARDWARE=1` and/or
`TEST_RUNNER_RNDBUDDY_AUDIO=1` environment flags. The MIDI hardware test only
queries firmware and patch state; the audio check sets monitor gain to zero.

Firmware flashing, recording, a built-in synth, visionOS and live phone-to-Mac
remote control are not included. Official firmware engine/track edits can take
patches off-seed; the UI identifies approximate recall where known. General
browser features and Pixels audio/camera capture are deliberately not bridged.

[Source acknowledgements](docs/ThirdPartyNotices.md)
