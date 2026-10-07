# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-10-07

Journeys can scroll, long-press, press the system back button and expect something to be gone,
and declare the text size, theme and locale they are measured under. Every step now says whether
its own oracle proved anything, and the docs state the network boundary the walk really has.

**Upgrading a generated `flutter drive` fallback:** the driver is now
`test_driver/ux_journey_driver.dart`, passed with `--driver`. If an earlier run wrote the skill's
driver to `test_driver/integration_test.dart`, restore your own file there (or delete it if you had
none) and update the `.gitignore` line.

### Added

- **Four step lines.** `scroll until "X"` drags the vertical list that holds X, at most 20 times,
  until X can be pressed where it stands; its drags are recorded per step and per run, apart from
  taps, because scrolling is not reach cost. `long-press "X"` resolves and refuses as a tap does.
  `system back` sends what Android's back button sends and records `popHandled`; a pop nothing
  takes fails the step. `— expect no "Y"` is the absence oracle. All four are verified headless,
  not yet on a device.
- **`## Device` conditions.** `- textScale 3.0`, `- dark`, `- locale ko-KR` and `- boldText` set the
  test platform dispatcher before launch, and `conditions` reads the same dispatcher back. Large-text
  failures no longer need a simulator. One set per run.
- **Each step says what its oracle proved.** `expectedBefore` is true when the expectation already
  held before the action — the fixture's own step 1 expects a price its list row already shows. The
  status is unchanged, and the report now renders such a step as `OK (not proven)`, never as
  evidence the goal was reached. `resolved` records which node the target resolved to, and
  `centreHitsHandler` whether a hit test at the press point reached a handler at all; a dead-tap
  finding now requires it.
- **The walk waits for the app.** Launch is followed by a bounded wait (12 s) for the first target
  to reach the semantics tree, so an async `main` or a splash on a timer is no longer measured as
  the entry screen. `entryReached: false` with no steps means no app came up (no `Navigator`), and
  `entry.png` shows what was there instead. With steps, the app was up but the first target never
  appeared — often a control with no accessible label — and step 1 reports it.
- **`conditions.appErrorHandlerReplaced` and `conditions.httpOverridesReplacedByApp`** say the app
  installed its own error handler or HTTP override during the walk. The walk keeps hearing errors
  and keeps its network barrier either way.
- **The `flutter drive` entry cuts the network.** `NetworkCut` is the real `HttpClient` with a
  `connectionFactory` that records the path and fails before any DNS lookup, as airplane mode would.
  A drive run on the iOS simulator used to send the journey's requests wherever the app pointed
  them. `networkCalls` lists what it refused.
- **A pre-walk network warning.** SKILL.md's preflight now greps the app's `pubspec.yaml` and code
  for WebSockets, sockets, background isolates, native HTTP clients and native SDKs, and tells the
  user before walking that such traffic is neither cut nor stubbed.
- **The probe names the routers it cannot read.** A GetX app and a generated route table
  (`@AutoRouterConfig` and older auto_route annotations, `@TypedGoRoute` and its shell twins) each
  leave one not-assessable line instead of an empty block that read as "no declarative router".
  `goBranch`, the restorable `Navigator` verbs, `Navigator.replace(newRoute:)` and
  `PageRouteBuilder` are now read or reported.

### Changed

- **The `flutter drive` driver is `test_driver/ux_journey_driver.dart`.** The old name is the file
  Flutter's `integration_test` README tells every app to create, so the fallback overwrote a
  tracked file. The recipe now refuses to write over an existing driver of the new name.
- **The oracle asks presence; only the target is asked identity.** An expectation that appears
  twice no longer fails as ambiguous after burning the settle bound, and one that is only in a
  scrollable's cache extent fails as "in the semantics tree but not on screen". For targets, `nth`
  is range-checked whatever the hit count, and a lone hit that holds the needle only inside a word
  ("back" in "Send feedback") is no match. Hangul and CJK keep substring matching.
- **`settled` is `null` on a step that never dispatched**, so a selector miss no longer counts as
  a settled screen. The docs now void a dump's geometry when the step BEFORE it did not settle: each
  step dumps before its action and settles after, so the old rule voided the wrong screen.
- **No keyboard height is invented.** Under `flutter test` the test keyboard has no inset, so while
  it is up `keyboardInset` and `foldY` are `null` and placement after a `type` step reads not
  assessable instead of 0.0.
- **`viewport.textDirection` is the app's own `Directionality`**, not the platform locale, which is
  `en_US` under `flutter test` whatever the app forces.
- **`modalOpen` counts a dialog that must be answered** — any barrier the SDK labels, not only a
  dismissible one — and **the screen signature reads state flags** (`isChecked`, `isToggled`,
  `isSelected`, `isExpanded`, `isCheckStateMixed`), so a working checkbox or chip is a change.
  Signatures of screens with none of these set are unchanged.
- **Fonts.** The SDK stand-in is always registered under `Roboto`, `CupertinoSystemDisplay` and
  `CupertinoSystemText`, except over a family the app declares, and a dependency's font keeps its
  `packages/<pkg>/` name. `fontSource: app` now means the app's fonts plus the stand-in — close, not
  exact — and the docs say so.
- **The static label rules agree with the runtime on named controls.** An `Icon` in a slot of a
  control that names itself, or under a tap owner the tap rule already reports, is decorative; an
  `IconButton` counts its icon's `semanticLabel`; a `Semantics` ancestor names only with `label:`,
  `tooltip:` or `excludeSemantics:`; `excludeFromSemantics` and `ExcludeSemantics` opt an `Image`
  out; `TextFormField` is held to the `TextField` rule. Over Flutter's own `examples/api` the
  findings went from 433 to 298 (icons 290 to 139, plus 16 `TextFormField`s).
- **The route map stops inventing edges.** Only top-level or static `const`/`final` string literals
  are resolved as constants, in Dart's lookup order; `screen` and `to` are the dotted constructor
  name (`EditScreen.create`) and null for a builder that can return more than one thing; a
  `pageBuilder` route names its page's `child:`; a route under a parent whose path cannot be read is
  not assessable rather than printed as an absolute path the app does not answer.
- **The docs state the network boundary.** The cut and the stub control the `dart:io`
  `HttpClient` built in the walk's isolate and nothing else; WebSockets under `flutter test`, raw
  sockets, other isolates, native HTTP clients and native SDKs were measured going round it. No doc
  now says that nothing leaves the device, as 0.2.0's notes did.
- **Both entries empty `ux-audit-out/screens/` before walking**, so an earlier run's PNG — a
  `setup_3.png` from a failed gate above all — no longer reads as this run's evidence.
- The setup examples no longer use an OS permission dialog, which no mode can walk: there is no OS
  under `flutter test`, and under drive it is outside the semantics tree.
- The probe declares Dart 3.11, the floor its locked `analyzer` and `test` already required.
- Blank issues are off, and anything that can only be shown with a private app is pointed at
  private reporting.
- CI runs the README's walk and reads its JSON back, checks that nothing a run writes is
  committable, parses SKILL.md's frontmatter as strict YAML within the spec's limits, upgrades
  dependencies on the weekly run, and runs the leak guard first, over every file name.

### Fixed

- **Nodes clipped to nothing are no longer on screen.** A row behind a bottom bar kept its full
  rect, read as visible and tappable, and the walk's tap landed on the bar. Merged children are no
  longer dumped as a second control, sub-0.001 lpx intersections are no longer overlaps, and
  `obscuredBy` names an icon button by its tooltip.
- **A failed `type` step no longer writes its value into the artifact.** A step is now hidden until
  the walk sees the field show its value, and the value is cut out of `expected` and `error` too.
  A `type` step chooses only among the fields its resolved node owns, so a page editor behind a
  dialog no longer takes the dialog field's text.
- **The outcome entry is one frame**: it settles first and captures everything back to back.
- **An app that installs its own `FlutterError.onError` no longer empties `appErrors`.** The walk
  records first and forwards to the app's handler; an error arriving by two routes is kept once.
- **An app that assigns `HttpOverrides.global` no longer swaps a real client into the walk.** The
  override in place at launch is pinned for the whole walk (verified headless).
- **The stub template answers every `HttpClient` method.** It implemented only `openUrl`, so
  `NetworkImage` (which calls `getUrl`) recorded a `TypeError` the app does not have and painted it
  on screen. Cookies are mutable, `flush()` completes, and a request awaited twice is recorded once.
- **One stray file no longer aborts the static pass.** A macOS `._*.dart` file is skipped and a
  non-UTF-8 byte is read leniently, as Dart reads it; both used to exit 255 with an empty
  `static.json`.
- `main_gated.dart`'s drive command gained the `--driver` it needs.

## [0.3.1] - 2026-10-05

Three fixes found by a full review of 0.3.0, released ahead of the rest because each one breaks a
run or an install on its own.

### Fixed

- **A failure after the walk no longer hangs the run for ten minutes.** The walk borrows
  `FlutterError.onError` to collect the app's own errors and never handed it back, so anything that
  failed after it — a timer the app left running, an `expect` in the same test — went into a list
  that was already published. flutter_test then waited out its ten-minute timeout and blamed
  whoever last touched the handler. It is handed back the moment the walk ends: the same failure
  now reports in about 2 s with its real message.
- **The static probe's path works after a marketplace install.** SKILL.md wrote
  `${CLAUDE_PLUGIN_ROOT:-<clone-root>}`. Claude Code replaces only the exact `${CLAUDE_PLUGIN_ROOT}`
  token in skill text, and the variable is never in the Bash environment, so step [1] pointed at a
  literal `<clone-root>`. The exact token is back, as 0.1.0 had it, and the docs say what to read it
  as when nothing substituted it. The install note for other agents now keeps the clone, which the
  skill reads `tools/` and `example/` from.
- **SKILL.md's frontmatter parses as YAML again.** An unquoted `compatibility` value containing
  `: ` made strict parsers reject the file — `npx skills add` found no skill and the Agent Skills
  validator failed — and at 1,028 characters it was over the spec's 500. Claude Code loaded it
  anyway, which is why nothing here noticed. It is now quoted and 448 characters, and states the
  static probe's real floor, Dart 3.11, which its `package:analyzer` requires.

## [0.3.0] - 2026-10-05

No device needed. The walk runs under plain `flutter test`, and the probe reads the app's routes
the way real routers are written.

### Added

- **The default walk runs under `flutter test`, with no simulator or emulator.** It is checked in
  this repo's own suite against the committed simulator run, `example/walk.json`: every step
  status, every screen signature, all sixteen guideline verdicts, the node counts and the viewport.
  About 2 s a run warm, against the simulator walk's 70 s first and 20 s after. `flutter drive` on
  a booted simulator or emulator stays as the fallback for apps whose plugins or platform views
  need a real device.
- **`## Device` in a journey file**, so a headless run says which screen it was measured on
  instead of quoting a fold for Flutter's default 800x600. One preset ships, `iphone-se`, the only
  one whose every field a committed artifact reproduces; an unknown preset name throws.
- **Real text metrics headless.** The run loads the app's own fonts, or the SDK's Roboto when the
  app declares none, over the families its themes actually name — the test font's em squares
  drifted layout by up to 153.6 px. `conditions.fontSource` and `conditions.renderer` say which
  font and rasterizer the numbers came from, and the report quotes them.
- **The probe reads the feature map.** A `routes` block beside `findings`: GoRoute declarations,
  MaterialApp named routes, and the navigation edges that reach each screen. Paths and targets
  written as string constants are resolved through the package, with `via` naming the constant.
  Anything built at runtime is reported as not assessable rather than guessed.

### Changed

- The walker lives in `ux_audit/`, not `integration_test/`: `flutter test` sends anything under
  `integration_test/` to a device runner by directory name alone, and `test/` would be swept into
  the audited app's own suite.
- The README leads with the demo — screenshots and a no-device command — and the platform
  statement moves to its own section. The pitch no longer claims to be the only Flutter UX audit
  that measures; the README's own Prior art section says otherwise.

### Fixed

- **A failure the app never awaited no longer poisons the run.** An unawaited request that fails —
  every request does under `flutter test` — escaped `FlutterError.onError` and made a finished walk
  read as a framework failure. It is now caught and recorded in `appErrors`.
- **A dependency's icon font is no longer reported as the app's own typeface.** On the stock
  template `cupertino_icons` made `fontSource` read `app`, which the report defines as exact, while
  every number was measured at the test font.
- A screenshot whose bytes never came back is now an error rather than a step that records a PNG
  nobody wrote.
- The network stub template no longer tells you to write it into `integration_test/`.

## [0.2.0] - 2026-09-28

The first release that can audit a whole product rather than whatever screen the app opens on.

### Added

- **Walk past a sign-in gate with no credentials.** The `## Setup` block in a journey file now runs.
  Setup steps are reported apart from journey steps, their taps are not counted as reach cost, a
  failing setup step stops the run and says so instead of reporting a short healthy journey, and a
  screenshot is taken only when setup fails — the one moment it is evidence.
  `references/network-stub.md` carries a working `HttpOverrides` template that gets a walk past the
  gate with your app unmodified and no request leaving the device.
- **Feature map.** Before journeys are chosen, the skill reads the app's router and lists its
  declared routes — the app's own statement of its feature surface, with a coverage column, because a
  score over a fifth of an app must not read like a score over the app.
- **A score and a direction.** Each dimension is a pass/fail count from the framework's own
  guidelines, with the weighting published inline so you can disagree with it and a line naming what
  the score does not cover. Exactly one proposal per audit, ordered by effort against reach rather
  than by severity alone.
- **Flow evidence, per step.** Viewport with the fold, per-node on-screen / above-fold / obscured,
  `canPop`, tappable count, modal state, taps so far, whether the tap changed anything, and a screen
  signature. `networkCalls` is finally written by something. A `back` step action.
- **`## Priorities`.** Declare the order you believe your screens have and the report compares it
  against the tap targets of each visited screen in reading order, then reports the disagreement.
  Declare nothing and it says `not declared` rather than inferring an order.
- **`conditions`, recorded once per run** — platform, brightness, text scale factor, locale and six
  accessibility flags. Two runs at different text sizes used to produce byte-identical artifacts; the
  report's scope clause now quotes the conditions instead of asserting them.
- **`nth` on a step selector**, 1-based, for when two nodes legitimately match the same label. The
  ambiguity error lists every candidate with its size, so finding out costs one run rather than two.
- **The app's own runtime errors are findings**, collected as `appErrors`, not a reason to discard the
  report.
- **The screen a journey ends on is audited.** Every step used to capture the screen it started from,
  so the outcome — the error state, the confirmation, the dead end — fell off the end.
- **Measurement predicates** for the five flow- and layout-shaped checks. A check listed there does
  not fire unless its predicate holds over fields the walk actually recorded.
- A worked example that resolves: `example/screens/`, `example/walk.json`, `example/walk-gated.json`
  and `example/journey-gated.md`, all from verified runs. The demo fixture gained an Android target,
  so the Android half of the README is reproducible by a reader.
- `CONTRIBUTING.md`, this changelog, a CI workflow and a bug report template.

### Changed

- One output root, `ux-audit-out/`, which is what SKILL.md always claimed.
- `pumpAndSettle` is banned. Its default timeout is ten minutes, so one perpetual animation hung a
  whole walk; settling is bounded and each step records whether it settled.
- Severity is no longer described as "Nielsen 0–4", which it never was. See `CREDITS.md`.
- Depth alone carries no severity. The three-click rule is disproved and the citation is in
  `CREDITS.md`.

### Fixed

- **A `type` step's text went into the artifact verbatim**, so a password typed into a gate was
  written to a file. An obscured field's value is now redacted to a length.
- **Screenshots were written to `<app>/screenshots/`**, a conventionally tracked directory in a
  Flutter app — a walk against your repository left its screens one `git add -A` from being
  published. They go to `ux-audit-out/screens/`.
- The gitignore guidance did not cover the generated network stub, the only generated file that holds
  the audited app's real endpoints.
- A tablet master-detail layout silently measured half a screen. Flutter's own `BlockSemantics`
  deletes the earlier-painted pane, which cannot be recovered from inside the walk, so the dump now
  declares `panesPossiblyBlocked` and the affected checks report `not assessable`.
- Guideline results beat the hand-accumulated semantics dump when they disagree; a size the dump
  reports and no guideline flags is an artifact of the dump.
- Two checks could never fire: `FAKE-AFFORDANCE`'s predicate gated only one of its two modes, and
  `STATE-GAP`'s predicate row sat outside the table.

## [0.1.0] - 2026-09-23

Initial release.

- Audits a running Flutter app at the **journey** level. A journey file declares the goal and the
  steps; the skill generates one `integration_test`, runs it with `flutter drive`, and merges static,
  runtime and visual evidence into a heuristic report scored against that goal.
- Zero third-party dependencies. Everything used ships in the Flutter and Dart SDKs.
- Sixteen Named Checks and the report skeleton, adapted from
  [EliaAlberti/ux-audit-skill](https://github.com/EliaAlberti/ux-audit-skill) (MIT). See
  `CREDITS.md`.
- The framework's four accessibility guidelines — Android and iOS tap target, labeled tap target,
  text contrast — reported with real pixel rects, the measured value and the required value.
- A static probe over `package:analyzer` (`tools/astprobe`) with four rules: taps, icons, images and
  input fields without labels.
- **Never asks for a credential.** The default is a blocked network and arbitrary data, so the
  failure paths get audited with no configuration and nothing leaves the device.
- Verified on an iOS simulator and an Android emulator. Real devices are not verified and are not
  claimed. On Android, `takeScreenshot` deadlocks when the app embeds a platform view, so the visual
  layer is captured from the host.
- `example/ux_demo_app`, a public fixture with six seeded defects, each proven to fire through the
  framework's own guidelines.

[0.4.0]: https://github.com/masanggil1986/flutter-ux-journey/releases/tag/v0.4.0
[0.3.1]: https://github.com/masanggil1986/flutter-ux-journey/releases/tag/v0.3.1
[0.3.0]: https://github.com/masanggil1986/flutter-ux-journey/releases/tag/v0.3.0
[0.2.0]: https://github.com/masanggil1986/flutter-ux-journey/releases/tag/v0.2.0
[0.1.0]: https://github.com/masanggil1986/flutter-ux-journey/releases/tag/v0.1.0
