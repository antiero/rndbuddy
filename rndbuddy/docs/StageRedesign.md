# Stage redesign — implementation plan

Mockups: [rndbuddy Stage Redesign](https://claude.ai/artifact/SnmhFhzgyySbKkaXstUV1W)
(private until shared). They are design intent, not runtime evidence.

## Status and handover — 29 October 2026

**Phase 1 is done. Nothing in the app uses it yet**, so behaviour is unchanged.

- `rndbuddy/Core/PerformancePage.swift`: `ControlKind`, `TrackScope`,
  `ResponseCurve`, `TriggerAction`, `InputSource`, `ControlBinding`
  (invert → curve → range, scope → CC/channel), `ControlSpec`, `Placement`,
  `LayoutClass` (with per-class grids), and `PerformancePage`, which has
  `validate()`, the `drift`/`keys` defaults and `init(legacy:name:)`.
  `FirmwareCapabilities` is the single place that gates firmware support.
- `rndbuddy/Core/PerformanceLayout.swift`: `PerformanceLayout.flow(page, in:)`.
  It keeps valid stored placements and flows the rest into thumb zones
  (deterministically). Controls that don't fit are reported in `overflow`.
- `Tests/RNDBuddyCoreTests/PerformancePageTests.swift`: 11 tests. They cover
  Codable round trips, defaults, legacy conversion, curves, scope→channel,
  validation, firmware gating, no overlap for every `LayoutClass`, and overflow.
- Verified: `swift test` in `rndbuddy/` (32 tests passed), plus
  `xcodebuild -scheme rndbuddy` for macOS and for the generic iOS Simulator
  (built with signing disabled). The new Core files join the app target
  automatically through the synchronised folder. Not run: RuntimeTests, devices
  and hardware.

Known simplifications to revisit in Phase 2:

- `InputSource` is coarse (`touch/hands/motion/keys`). Each binding takes its
  own axis from the source. Named hand features (pinch, left-hand height) are
  not modelled yet.
- `MappingEngine` still smooths per `MappingTarget`. The router needs a key per
  control and binding, and must call `ControlBinding.mapped` instead of
  `AxisMapping.mapped` so curves take effect.
- `FirmwareCapabilities` replaces nothing yet: the `deep` checks in
  `PerformanceController` and `MappingView` still exist. Switch them over when
  the router lands.
- The auto-flow grid sizes in `LayoutClass.grid` are first guesses. Tune them
  against the mockups once the views exist.

**Next step: Phase 2.** Build `Performance/ControlRouter.swift` behind the
current `PerformancePad`: treat the pad as the `drift` page's XY control, and
keep `RuntimeTests/PlayExpressionTests` passing.

## Goal

Replace the fixed Perform screen (Pixels card + single XY pad + Assignments
sheet) with a **Stage**: Pixels fills the Perform area and a **performance
layer** of artist-arranged controls sits on top. Controls are grouped into
**pages** that the artist builds in an **Edit layout** mode.

Must hold throughout (from `AGENTS.md`):

- One `PixelsWebView`/`WKWebView` identity. Moving between card, stage and
  full screen must never reload Pixels.
- All input still routes through the shared mapping layer, with explicit target
  ownership, release on cancel/loss, and no MIDI from view appearance.
- Firmware-gated targets stay gated (deep reverb, freeze and reroll are JG only).
- Native controls remain usable when Pixels is disabled, offline or external.
- iOS 18 / macOS 15 minimums, no third-party dependencies, files under ~500 lines.

## Current code this replaces or extends

| Area | Today | After |
| --- | --- | --- |
| `UI/PerformView.swift` | Scrolling stack: `PixelsStage`, `TrackSelector`, `PerformancePad`, `PatchBar` | `StageView` = Pixels background + `PerformanceLayer` + adaptive chrome |
| `UI/PerformancePad.swift` | One XY surface, mode/method pickers, Hold | Split into `XYFieldControl`, `FaderControl`, `TriggerControl`, `ScaleKeysControl` |
| `UI/MappingView.swift` | Sheet with 2 axes | `ControlInspector` (edit mode); sheet kept as compact-width fallback |
| `Core/MappingEngine.swift` | `PerformanceMapping { x, y, playYAxis }` | Adds `ControlBinding`, `PerformancePage`; `PerformanceMapping` kept for decoding old data |
| `Performance/PerformanceController.swift` | First contact drives both axes | `ControlRouter`: one engine per binding, with ownership per contact and per control |
| `Library/LibraryStore.swift` | `LibrarySchemaV1` (`SavedPatch`, `SavedMapping`) | `LibrarySchemaV2` adds `SavedPage`; lightweight migration |
| `Core/PatchArchive.swift` | `version 1`, optional `mappings` | Adds optional `pages`; stays at version 1 because the field is additive |

## Phase 1 — Core model (`RNDBuddyCore`, testable without UI)

New file `Core/PerformancePage.swift`:

```swift
enum ControlKind: String, Codable { case xy, fader, trigger, toggle, keys, tracks, patchBar, camera }
enum TrackScope: Codable, Hashable { case selected, fixed(Int) }   // 0...3
enum ResponseCurve: String, Codable { case linear, soft, exponential }
enum TriggerAction: String, Codable { case generate, hold, freeze, reroll, mute, solo }

struct ControlBinding: Codable, Equatable {
    var target: MappingTarget
    var scope: TrackScope = .selected       // ignored for master targets
    var axis: AxisMapping                   // existing min/max/invert/smoothing/deadZone
    var curve: ResponseCurve = .linear
    var sources: Set<InputSource> = [.touch] // .touch, .hands(HandFeature), .motion(MotionAxis), .keys
}
struct ControlSpec: Codable, Identifiable, Equatable {
    let id: UUID
    var kind: ControlKind
    var title: String
    var bindings: [ControlBinding]          // xy = 2, fader = 1, keys = play-mode y
    var action: TriggerAction?
}
struct Placement: Codable, Equatable { var column, row, width, height: Int }  // grid units
enum LayoutClass: String, Codable, CaseIterable { case mac, padLandscape, padPortrait, phonePortrait, phoneLandscape, foldOpen, foldTabletop }
struct PerformancePage: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var controls: [ControlSpec]
    var placements: [LayoutClass: [UUID: Placement]]  // missing → auto-flow
    var schemaVersion = 1
}
```

- `ResponseCurve.apply(_:)` sits in front of `AxisMapping.mapped`.
- `FirmwareCapabilities.available(_ target:, _ action:, firmware:)` is the single
  gate used by the router, the inspector and the "unavailable" control state.
  It replaces the inline `deep` and `firmware == .jg023` checks.
- `PerformancePage.defaults` are **Drift** (today's XY: track volume/reverb, plus
  master faders and Hold) and **Keys** (Play mode: scale keys and the vertical
  axis). Existing users therefore keep today's behaviour.
- `PerformancePage(legacy: PerformanceMapping)` turns saved mappings into a page.
- **Auto-flow**: a pure function `layout(page, class, gridSize) -> [UUID: CGRect]`
  places unplaced controls using per-class thumb-zone rules (faders at leading
  edge, triggers trailing, XY centre). It is tested with fixtures.

Tests (`Tests/RNDBuddyCoreTests/PerformancePageTests.swift`): Codable round
trip, legacy conversion, curve endpoints and monotonicity, capability gating per
firmware, auto-flow covers every control without overlap for each `LayoutClass`.

## Phase 2 — Routing (`Performance/ControlRouter.swift`)

Refactor `PerformanceController` into a router that several controls feed at
the same time:

- `update(control: UUID, contacts: [Contact], sensor: Bool)`. Contact IDs are
  namespaced by control, so two fingers on two controls never collide.
- One `MappingEngine` per (control, binding). `engine.reset()` on page switch,
  track change, disconnect and background.
- **Target ownership**: a `[ResolvedTarget: UUID]` table keyed by
  `(cc, channel)`. The most recent touch owns the target; the other control shows
  "overridden" until it is released. The inspector warns when two controls on
  one page bind the same target.
- Keep the existing Play-mode logic (`updatePlayVolume` / `restorePlayVolume`,
  per-source notes, takeover confirmation), now scoped to a `keys` or XY control
  in Play mode.
- **Triggers** call existing `DeviceSession` APIs (`generate`, `toggleMute`,
  `toggleSolo`, `reroll`, freeze via CC 90 as `MixerView` does). Hold is
  router-wide, as today.
- **Hands and motion** become *sources* on bindings instead of a global
  `InputMethod`. `HandInput.onContacts` publishes named features (right-hand
  XY, left-hand height, pinch). The router fans them out only to bindings that
  subscribe to them, and only while armed. Tracking loss releases what they own.

Tests (`RuntimeTests/ControlRouterTests.swift`, `FakeMIDITransport`): two
simultaneous controls emit independent CCs; ownership hand-off; release on
cancel, disconnect and page switch; gated targets emit nothing; existing
`PlayExpressionTests` still pass unchanged.

## Phase 3 — Stage and performance layer (UI)

New `UI/Stage/` folder:

- `StageView.swift`: a `ZStack` with `PixelsBackdrop` (the existing
  `PixelsWebView`, or `DotSculpture` plus the Enable button when Pixels is off,
  or a "Pixels is on your external display" plate), then `PerformanceLayer`,
  then chrome. Replaces the body of `PerformView`.
- `PerformanceLayer.swift`: lays out the current page through `GeometryReader`
  and the auto-flow function. It owns overlay visibility
  (`OverlayVisibility { off, ghost, show }`, stored per device in `@AppStorage`).
- Controls, one file each: `XYFieldControl` (wraps the existing `TouchSurface`
  and draws contacts in a `Canvas`), `FaderControl`, `TriggerControl`,
  `ScaleKeysControl`, `TrackStrip` (from `TrackSelector`), and `PatchBar`
  (existing, restyled).
- **Hit testing**: only control frames accept touches. Elsewhere, the stage
  passes touches to Pixels when overlay is **Off** and swallows them otherwise.
  This needs a decision (see Open decisions).
- **Ghost mode**: outline-only style. A touched control animates to full
  opacity at display cadence. Respect Reduce Motion (no fade, just a solid
  touched state).
- **Accessibility**: each control keeps an `accessibilityRepresentation`
  (`Slider`, `Button`, `Stepper` for keys), as `PerformancePad` does today.
  VoiceOver ignores the Pixels layer. Values are read as numbers and state is
  written in text ("Muted", "Held").
- `Design.swift` gains tokens (`scrim`, `chrome`, `line`, `stageTrack(i)`).
  The lifted track 2 and 4 colours are used only on the dark stage. Light-mode
  stage chrome follows the system, and the Pixels area stays dark.

## Phase 4 — Adaptive layouts

Choose `LayoutClass` from `horizontalSizeClass`, platform and aspect ratio. Use
size, not device model, so iPad multitasking and resizable Mac windows work.

- **macOS**: `NavigationSplitView` sidebar collapses by default on Perform.
  The toolbar holds the page segmented control, overlay picker, Edit, Mixer,
  Capture, Save, display and connection. The Hands preview becomes a small
  floating overlay in the stage; the existing `HandsWindow` is kept as the
  "pop out" option. Keyboard: 1–4 select tracks, G generates, Space holds. Show
  these in tooltips and the menu bar, not on the stage.
- **iPad landscape**: floating capsule chrome and thumb-zone placement.
  `TabView(.sidebarAdaptable)` hides its bar while on Stage.
- **iPad portrait**: stage on top, controls below, with a draggable divider
  (height stored per device). Play-mode takeover becomes the inline banner with
  "Hand back" instead of `confirmationDialog`. Keep the dialog the first time
  only.
- **iPhone portrait**: pages in `TabView(.page)` below a fixed visuals band.
  Generate sits beside the tab bar (use the iOS 26 tab bar accessory where
  available, with an overlay button as the iOS 18 fallback).
- **iPhone landscape**: full-bleed stage, thumb zones, minimal chrome, page
  stepper.
- **iPhone Duo / foldables**: open = visuals | controls split at the fold.
  Tabletop = visuals on the upper half, controls on the lower. See Open decisions.

## Phase 5 — Edit layout and persistence

- `UI/Stage/EditLayout/`: `EditModeOverlay` (grid guides, selection, drag and
  resize with snapping), `ControlPalette` (the `ControlKind`s), and
  `ControlInspector` (binding form built from `MappingView`'s axis section, plus
  scope, curve, sources and delete/duplicate). On Mac and iPad the inspector is
  a trailing inspector (`.inspector`). On iPhone it is a sheet. Edits use an
  undo manager.
- Keyboard and VoiceOver editing: arrow keys move the selected control by one
  grid unit; inspector fields for position and size.
- `LibrarySchemaV2` adds a `SavedPage` (recordID, name, order, modifiedAt,
  payload JSON). `LibraryMigration` gets a lightweight V1→V2 stage.
  `SavedMapping` stays readable. On first launch after migration, seed the
  default pages and add one page per existing saved mapping. Never overwrite
  silently.
- `PatchArchive` gains `pages: [PageDocument]?`, validated with bounds (at most
  1,000 pages and 64 controls per page) like `mappings`.
- Placements are stored per `LayoutClass` inside the page, so an iPhone
  arrangement never disturbs the Mac arrangement.

## Phase 6 — Validation (per `AGENTS.md`)

- Build the iOS and macOS schemes. Run the Core, Runtime and MIDIVision tests.
- Capture running screens: compact and large iPhone in both orientations, iPad
  portrait, landscape and Split View, small and large Mac windows, dark and
  light, accessibility type sizes, and VoiceOver passes on the Stage and the
  inspector.
- Hardware: multi-touch across two controls, hand loss mid-gesture, motion
  calibration, page switch while notes are held, and Pixels staying loaded
  through layout changes and full screen. Record OS, device, firmware and
  connection in `Validation.md`.

## Suggested order and size

1. Phase 1 + tests (1 PR, no UI change).
2. Phase 2 behind the existing `PerformancePad` (it becomes a one-control page),
   then confirm `PlayExpressionTests`.
3. Phase 3 with the default pages only. This ships the new look with no editor.
4. Phase 4 layouts, one platform per PR.
5. Phase 5 editor and schema V2.

## Open decisions

1. **Touch pass-through to Pixels.** Should the Pixels site receive touches in
   the gaps between controls? Recommendation: only when overlay is Off.
   Otherwise stray touches change the visuals.
2. **iPhone Duo.** Confirm the device, its inner display size and whether a
   public posture or hinge API exists at our deployment target. Without one,
   tabletop is a manual "Deck layout" toggle plus an aspect-ratio heuristic.
3. **Sources on bindings vs global input method.** Removing the Touch / Hands /
   Motion picker changes how users arm sensors. Keep a global Arm button
   (recommended) or arm per control?
4. **Page sync.** Pages are local per device. Should they ride the existing
   CloudKit entitlement later? This affects the V2 schema (CloudKit needs
   optional attributes and no unique constraints).
5. **Curve and dual-control ownership semantics** should be checked with an
   artist on hardware before freezing the schema.
