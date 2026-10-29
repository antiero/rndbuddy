# Validation — 28 October 2026

## Environment

- Xcode 27.1 (27A9275), Swift 6 language mode.
- Deployment targets explicitly set to iOS 18 and macOS 15; visionOS removed.
- Native Mac review build signed with Apple Development, CloudKit entitlement
  overrides disabled for local verification only.
- Dedicated iPhone 15 Pro simulator on iOS 18.5 and iPad simulator on iOS 27.0.
- A physical USB RND Synth connected to the Mac reported v1.3-JGpatch-023.

## Completed checks

| Check | Evidence |
| --- | --- |
| Shared protocol/mapping/archive tests | 21 Swift Testing tests passed. Includes firmware-specific golden messages, official lock packing, fragmented/large/bounded SysEx, scales, mappings and CSV/JSON round trips. |
| MIDIVision package | 2 geometry/palm-helper tests passed. This is not a real-camera accuracy test. |
| Native session/library tests on Mac | Six fake-MIDI/in-memory tests passed; two opt-in hardware checks also passed on the direct Core Audio implementation. |
| Session/library tests on iOS 18.5 | Seven runtime tests passed, including the added manual-disconnect/hot-plug case; hardware-only cases were disabled. |
| Actual JG USB MIDI | The app transport identified JGpatch-023, read seed/global/track messages, requested a second dump and retained the same seed. No generated patch or note was requested by this check. |
| Mac native monitoring | Silent test: stereo mix monitor started, stayed running and processed 96,256 output frames in two seconds. Output gain was zero. Last measured peak was zero while the selected patch was a one-shot; this is pipeline validation, not an audible-quality or signal-integrity claim. |
| Pixels embedding | Live website loaded in native Mac WKWebView and its own control table identified the native Demo MIDI port. |
| Native UI | Running Mac, iPhone and iPad screenshots inspected. Compact performance controls were adjusted after screenshot review. |
| Regression fixes | Eliminated inherited main-actor isolation from CoreMIDI callback blocks; removed a strong new-WebKit-overlay dependency that failed on iOS 18; guarded CloudKit entitlement access; renamed a persisted attribute that collided with older SwiftData deletion behaviour. |

Representative app-produced hardware state is in `hardware-read-example.json`.
The synth's physical button/settings may change after that capture.

The Core Audio monitor replaces the earlier AVAudioEngine aggregate approach,
which failed hardware tests. Old failing logs do not describe the shipped Mac
path. macOS audio authorization initially remained pending in the test host;
the later successful run is the evidence above.

## Review screenshots

- `screenshots/mac-perform.png`: live Pixels in the native Mac app, Demo mode.
- `screenshots/iphone-perform.png`: iOS 18.5 native compact layout, Demo mode.
- `screenshots/ipad-perform.png`: native iPad layout, Demo mode.

These are runtime captures, not the earlier generated concept images. The Mac
app was left open for review; subsequent user interactions may differ from the
captured screen.

## Outstanding acceptance gates

- Official 1.4 physical hardware: command/lock compatibility, exact seed recall
  constraints, engine/track selection and native/WebMIDI state reconciliation.
  Current official codecs are based on the delivered Pixels MIDI client and
  protocol fixtures, not a physical official-firmware acceptance run.
- JG edited-patch sound/recall acceptance and real controller timing under load.
  Read-only query success does not prove every edit or note mode.
- Real multi-touch, hand tracking, camera mirroring/orientation, tracking loss,
  gyro calibration and accessible gesture alternatives across physical devices.
- iOS USB audio routing, interruptions and background monitoring on real phones
  and iPads. Mac audible output quality and sustained capture remain unverified.
- External-display attachment/removal on physical iOS and Mac displays; full
  screen and reparenting are implemented but not a proven live stage setup.
- Provisioned CloudKit container, two-device offline/concurrent edits, deletion
  convergence and production schema deployment. Local tests are not sync proof.
- Physical hot-plug, repeated disconnect/reconnect and Mac sleep/wake.
- Dynamic Type/VoiceOver/contrast/reduced-motion acceptance on representative
  hardware, plus the smallest supported phone and Mac window.
- 30-minute simultaneous MIDI + audio + Pixels + hands run, with measured
  latency, frame pacing, energy/thermal behaviour and bounded memory.
- Fully provisioned Release archive, distribution validation and TestFlight.

No firmware was flashed and no build was distributed. Do not mark the whole v1
hardware/release acceptance complete from the checks performed so far.

## Capture and window updates — 29 October 2026

- Native Mac suite succeeded: 13 discovered tests, 11 passed and two opt-in
  hardware tests skipped. iOS 18.5 simulator suite succeeded: 11 discovered
  tests, 10 passed and one opt-in hardware test skipped. These runs include new WAV channel/sample checks, file finalisation,
  repeated takes, dry sums and oversized-callback rejection.
- External window test ran against the connected SAMSUNG display. Screen and
  window frames both measured `(-764, 982, 3008, 1692)` points; the live web view
  measured `(0, 0, 3008, 1692)`. Switching to a resizable floating window and
  returning the same web view passed. The live app's external output menus were
  also exercised. This establishes native window sizing, not visual-engine
  quality or frame pacing at every display scale.
- In the running Mac app, Capture recorded and finalised 1,086,464 frames from
  the RND USB route: 22.634667 seconds, stereo 48 kHz Float32 WAV, 8,691,712 audio
  bytes. Monitoring was muted. The idle one-shot patch produced zero-valued
  samples: this proves route/file operation, not audible signal quality.
- The separate Hands window opened and its Preview toggle was exercised.
  Camera tracking, physical iOS recording, screen unplug/replug during capture,
  extended recording and audible monitoring still need hardware validation.
- Running-interface captures: [Mac Capture](screenshots/mac-capture.png) and
  [Mac Perform with Hands selected](screenshots/mac-perform-hands.png), plus
  [iPhone simulator with the Capture toolbar](screenshots/iphone-perform-capture-toolbar.png).

## Mac audio and external Escape diagnosis

See [AudioDiagnostics.md](AudioDiagnostics.md) for the sampled Debug callback
fault, vectorised replacement, clean 60-second RND USB stress results and the
remaining audible/volume-overlay validation. Escape over the external stage
now exits fill-screen mode into its floating window.

## Play vertical expression — 29 October 2026

Play now defaults to continuous track volume (CC7 on the selected takeover
channel), with fixed note-on velocity. Assignments retains an explicit velocity
at note-on option. RND documents per-track CC7 in its
[MIDI manual](https://www.cymaforma.com/pages/rnd-synth-manual).

Six new fake-transport tests verify same-pitch vertical movement without note
retrigger, duplicate-CC suppression, full range including silence, shared volume
for multiple contacts, restoration and preservation of later mixer edits,
unknown initial levels, onset velocity and old/new mapping archive decoding.
Mac suite succeeded (22 discovered; three hardware tests skipped), and iOS 18.5
simulator suite succeeded (17 discovered; one hardware test skipped). This is
MIDI-message and local persistence evidence; audible response on RND hardware
has not been verified for this change.
