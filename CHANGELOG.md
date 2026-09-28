# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.2.0]: https://github.com/masanggil1986/flutter-ux-journey/releases/tag/v0.2.0
[0.1.0]: https://github.com/masanggil1986/flutter-ux-journey/releases/tag/v0.1.0
