# rndbuddy — contributor guide

## Product and scope

Build a responsive native SwiftUI companion for the Cyma Forma RND synth on
iPhone, iPad and macOS. Prioritise musical immediacy, reliable hardware
communication and a calm interface.

- Native performance controls and patch library; multi-touch, camera-based hand
  input and device motion are complementary input methods.
- Explore RND pixels (https://pixels.cymaforma.com) in WKWebView using a
  MIDIWeb-derived WebMIDI bridge. Embedding compatibility is not yet validated.
- Firmware flashing, WebUSB and bootloader development are out of scope.
- Support official firmware first. Add JG firmware features through explicit
  capability detection; do not assume the protocols are interchangeable.
- Treat `../../design/mockups/04-pixels-native.png` as the starting layout,
  `01-tactile.png` as the light visual direction, and `02-field.png` as a hand
  and motion interaction study. Mockups are inspiration, not implementation
  specifications or proof that pictured parameters are supported.

## Project baseline and decisions

- Work within this Xcode project; preserve unrelated repository changes.
- Agreed minimum targets: iOS 18 and macOS 15. Swift 6 language mode with
  strict concurrency. visionOS is excluded. Do not raise minimum versions
  without an explicit product decision.
- Validate newer APIs against these deployment targets; native appearance
  follows the running OS rather than requiring the latest OS.
- Ship a native macOS target, not an iPad-only interface running on Mac.
- visionOS is not part of the current requested scope.
- Do not add third-party dependencies without discussing the concrete need.
- Make routine reversible implementation decisions autonomously. Ask about
  choices that materially change supported devices, distribution or data loss.

## SwiftUI and code organisation

- Use Apple frameworks and public APIs. Keep SwiftUI as the presentation layer;
  use small UIKit/AppKit adapters when required for accurate input or WebKit.
- Prefer Observation (`@Observable`) for UI-facing models, isolated to
  `@MainActor`. Keep MIDI processing, parsing, storage I/O and camera work out
  of view bodies and off the main actor where appropriate.
- Own local observable models with private `@State`; inject dependencies and use
  `@Bindable` or `@Binding` only where editing is needed.
- Use structured concurrency, explicit ownership and cancellation. Clean up
  callbacks, tasks, observers, sensors and WebKit handlers with their lifecycle.
- Respect callback threading. Do not hide isolation errors with unchecked
  sendability or indiscriminate actor hops.
- Keep files below 500 lines where practical; split by responsibility early.
  Prefer small named View types over a monolithic ContentView.
- Organise by feature, with focused shared services: app composition, device
  session, MIDI transport, RND protocol, library, performance input and Pixels.
  Avoid speculative frameworks or a generic dependency-container architecture.
- Use stable model identities, pure view bodies, native navigation and controls.
  Avoid duplicated derived state and whole-screen invalidation at event rate.
- Provide previews with deterministic fixtures and no hardware side effects.
- Use available modern APIs, with availability handling matching agreed targets.
  Check current Apple documentation when API behaviour is uncertain.

## MIDI architecture and RND protocol

- One native MIDI service owns CoreMIDI connections. Native controls and the
  web bridge share routing; neither creates a competing hardware session.
- Separate raw transport, message parsing, firmware-specific codecs and UI
  state. Test codecs without requiring a connected synth.
- Represent reported hardware state, pending edits and unknown values distinctly.
  A transmitted message is not proof that the hardware accepted it.
- Discover and reconnect endpoints using persistent identity where available;
  do not rely on endpoint ordering or display names alone. Handle duplicates,
  hot-plug, sleep/wake and device replacement without stale references.
- Never send patch-changing defaults merely because a view appears or a device
  connects. Reconcile state through supported queries and explicit user edits.
- Keep firmware capability tables explicit. In particular, official 1.4 scale
  values and patch-type CC 14 differ from JG's 1.3-based mappings/bitmask.
  Unknown firmware gets only verified compatible operations.
- Verify channel routing: global control on channel 1; per-track takeover on
  2–5; external solo playing on 6–9; generated output on 1–4. Note input can
  alter sequencing behaviour; do not use note messages as harmless probes.
- Preserve message ordering and timestamps. Serialise multi-message operations;
  coalesce continuous CC edits where appropriate, never note-offs or SysEx bytes.
- Track active notes by source. Release owned notes on gesture cancellation,
  tracking loss, disconnect and session shutdown. Prevent MIDI feedback loops.
- Parse MIDI streams correctly across callback boundaries, including fragmented
  SysEx and interleaved realtime bytes. Never treat one callback as one message.
- Bound buffers and queues, validate messages, and fail malformed transfers
  without crashing. Do not silently truncate large SysEx payloads.

## MIDIWeb learnings and Pixels integration

- Reference the sibling MIDIWeb repository at `../MIDIWeb` relative to the
  JG-RND repository root. Useful sources are `MIDI/WebMidiBridge.swift`,
  `MIDI/WebMidiAccessCoordinator.swift`, `Browser/JavaScript/WebMidiJS.swift`,
  `MIDI/MIDIByteStreamParser.swift` and their tests.
- Inspect current source before reuse. Extract the smallest maintainable bridge
  core; do not copy browser navigation, download or unrelated WebUSB features.
  Check licensing and preserve attribution for reused code.
- Install the polyfill at document start before site scripts request MIDI access.
  Verify injection order, required frame coverage and reload/process recovery.
- Preserve WebMIDI semantics used by Pixels: access promises, port IDs and maps,
  connection state events, open/close, incoming data and scheduled outgoing data.
- Normal MIDI and SysEx access are distinct grants. Honour the requested grant;
  never advertise SysEx support while silently dropping its messages.
- Authorise web access by validated origin and frame, with an explicit policy
  for the Pixels origin. Redirects or unrelated pages must not inherit grants.
  Do not trust an origin supplied in a JavaScript message as authentication.
- Validate bridge payload types, sizes, byte ranges and destinations. Use safe
  structured JS communication rather than interpolating untrusted script text.
- Resolve each permission request once. Cancel pending requests on navigation
  or teardown; do not leave promises hanging or prompt repeatedly on retries.
- Reassemble inbound SysEx and preserve outgoing bytes across transport chunking.
  Transport fragmentation must not insert extra F0/F7 markers or change payloads.
- Test origin denial, SysEx denial, request deduplication, reconnect, reload,
  web-process termination, oversized messages and concurrent native/web input.
- Keep WKWebView identity stable across SwiftUI updates. Do not reload Pixels
  when a slider moves or the layout changes. Detach handlers on teardown.
- Use a native MIDI session as the routing authority; prevent duplicate sends
  and duplicate input delivery between native and web components.
- Treat Pixels as an external integration. Verify permitted use before bundling
  or modifying its assets; preserve Cyma Forma attribution. Do not depend on
  undocumented DOM manipulation for core native features.
- Provide useful native controls if Pixels is offline or fails to load. Do not
  promise offline visuals until a supported caching/bundling route is validated.
- MIDI bridge support does not establish Web Audio capture support. Validate
  Pixels audio monitoring separately, including permissions and routing.

## Expressive input and timing

- Route touch, hand, motion and pointer input through a shared mapping layer
  with ranges, inversion, smoothing, dead zones and explicit target ownership.
- True multi-touch needs stable per-contact identity and independent lifetimes.
  Use a focused native touch adapter if SwiftUI gestures cannot provide it.
- Use Vision/AVFoundation for camera hand tracking and Core Motion where
  available. MIDIVision-style means an interaction reference, not an assumed SDK.
- Request camera access when enabling Hands. Process locally by default; do not
  store or upload camera frames. Handle denied access and tracking confidence.
- Arm hand/motion output deliberately; support calibration, hold and disarm.
  Tracking loss must release notes and stop unintended modulation.
- Do not assume Macs have touchscreens or gyroscopes. Provide pointer, keyboard
  and camera alternatives; expose only capabilities the device actually has.
- Use timestamped MIDI events as musical timing input. Smooth/interpolate visuals
  at display cadence; never use SwiftUI animation or JS timers as a MIDI clock.
- Bound jitter buffering and define clock source ownership, start/stop/continue
  and clock-loss behaviour. Do not echo an incoming clock back to its source.
- Stop unused camera, motion and rendering work. Measure latency, CPU/GPU load,
  memory, energy and thermal behaviour on hardware before claiming optimisation.

## Design principles

- Keep the UI zen: Apple clarity, Teenage Engineering precision, Dieter Rams
  restraint. Every visible control must earn its space.
- Let the visual stage and performance surface dominate. Use compact native
  chrome, generous touch areas and progressive disclosure for assignments.
- Keep technical diagnostics in development logging or a dedicated diagnostic
  view. Prefer tooltips on Mac and accessible labels/values over debug text.
- Use semantic type, adaptive light/dark colours, restrained orange accents and
  consistent spacing tokens. Glass belongs in native chrome, not every surface.
- Respect safe areas, iPad multitasking, window resizing and platform conventions.
  Do not stretch the phone layout into a desktop window.
- Support Dynamic Type, VoiceOver, keyboard focus, Increase Contrast and Reduce
  Motion. Touch targets should be at least 44 points. Never rely on colour alone.
- Provide accessible alternatives to continuous gestures and camera/motion input.
  Keep essential state visible; a tooltip cannot be the only way to find a feature.
- Make connection failures actionable and concise. Do not show a connected or
  recording state unless the corresponding service is actually running.

## Persistence and audio

- Store library data locally with versioned schemas and stable IDs. Preserve
  seeds, firmware/protocol provenance, locks and overrides needed for recall.
  A seed alone may not recreate an edited patch.
- Keep import/export independent from live hardware. Validate imported data and
  preserve user records through migrations; never overwrite silently.
- Plan compatibility with JG-RND CSV through explicit fixtures, not assumptions.
- If audio capture is implemented, use native audio services and validate channel
  layouts/sample rates. Official 1.4 reports stereo wet mix on 1–2 and four dry
  mono tracks on 3–6; verify the connected firmware rather than hard-coding it.
- Handle audio route changes, interruptions and unavailable devices. Keep audio
  callbacks free of blocking I/O, UI updates and unbounded allocation.

## Validation and completion evidence

- Build both iOS and native macOS after shared-code changes. Discover actual
  schemes/destinations with xcodebuild; do not invent a passing command or SDK.
- Add meaningful tests for codecs, stream parsing, routing, permissions, mapping,
  clock behaviour and persistence. Use UI tests for lifecycle/integration flows
  that unit tests cannot establish, not for every visual detail.
- Exercise compact/large iPhones, iPad portrait/landscape and split layouts, plus
  small/large Mac windows. Include dark mode, accessibility type and VoiceOver.
- Hardware validation must cover RND USB MIDI in/out, SysEx round trips, repeated
  connect/disconnect, multiple simultaneous touches, hand loss, motion calibration,
  background/foreground and Mac sleep/wake. Test audio and Pixels separately.
- Record OS, device, app revision, RND firmware and connection path for hardware
  results. Distinguish simulator fixtures, local tests and real-device evidence.
- A build passing is not proof of signing, installation, TestFlight, MIDI timing
  or physical-device behaviour. Report untested cases plainly.
- For visual work capture actual running screens on representative platforms;
  generated mockups are not runtime validation. For performance claims provide
  measured conditions and results rather than subjective claims.
- Keep validation proportional to the change. Documentation-only edits need a
  content/diff check, not an application test run. Never claim tests not run.
