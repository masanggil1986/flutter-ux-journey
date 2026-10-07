# ux_demo_app

The public fixture for [flutter-ux-journey](../../README.md). No backend, no real data — a
`com.example.*` scaffold that exists to be audited. Two entrypoints: `lib/main.dart` opens straight
onto the saved list, and `lib/main_gated.dart` puts the same screens behind a sign-in gate.

**Do not fix the defects below.** They are seeded on purpose, and they are what
[`../expected-findings.json`](../expected-findings.json) is pinned against. "Fixing" one silently
invalidates the golden and the worked report; `test/fixture_test.dart` fails loudly when you do.

## The six seeded defects

Line numbers point at the `// DEFECT n:` marker comment that introduces each one, not at the widget
under it. The marker is what survives a reformat, and `grep -n 'DEFECT [0-9]:' lib/main.dart`
re-derives the whole column in one command.

| # | Defect | Where | What it exercises |
|---|---|---|---|
| 1 | The promo dismiss `×` is 24×24 lpx | `lib/main.dart:136` | `iOSTapTargetGuideline` / `androidTapTargetGuideline` |
| 2 | The search `IconButton` has neither `tooltip:` nor `semanticLabel:` | `lib/main.dart:73` | `labeledTapTargetGuideline`, and the static probe |
| 3 | A product card is one merged semantics node with a tap action and no `isButton` | `lib/main.dart:157` | tap targets enumerated by *action*, not by flag |
| 4 | `#DDDDDD` body text on a white scaffold | `lib/main.dart:89` | `textContrastGuideline` |
| 5 | The screen after a removal has no way back and nothing on the stack | `lib/main.dart:239` (`RemovedScreen`) | `DEAD-END`, measured as `canPop == false` |
| 6 | Removal destroys the product on the first tap, with no confirmation | `lib/main.dart:215` (`DetailScreen`) | `TRUST-GAP` — only visible at journey level |

Two traps are seeded alongside them, for the walker rather than for the report: the `Sort` button is
labelled by `tooltip:` only (a matcher reading `label` alone never finds it), and two products share
the substring "Side Table" (a selector must report ambiguity, not take the first hit).

## Run it

```bash
flutter pub get
flutter test                                  # the suites below
flutter test ux_audit/ux_journey_test.dart    # the walk itself — no device
```

The walk writes `ux-audit-out/walk.json` and `ux-audit-out/screens/step_*.png`. Steps 2 and 3 are
meant to fail; the run still exits 0, so read `steps[].status`, never `$?`.

On a device instead, for an app whose plugins or platform views need one:

```bash
flutter drive --driver=test_driver/ux_journey_driver.dart \
              --target=integration_test/ux_journey_drive.dart -d <device-id>
```

`flutter test` holds six suites, and between them they pin every part of the walk that was measured
wrong at least once: `walker_test.dart` (rect maths, the fold line, screen signatures, route state,
the dead-tap oracle, the settle bound), `fixture_test.dart` (the six defects are still seeded),
`recipe_sync_test.dart` (the reference docs and both journey files still describe the walker that
exists), `golden_diff_test.dart` ([`../expected-findings.json`](../expected-findings.json) still
agrees with [`../walk.json`](../walk.json), and with a fresh run when one has left an artifact
behind) and `gated_gate_test.dart` (the gate's failure paths: a wrong route table, a stub that
answers everything, no stub at all).

The drive writes its walk to `build/integration_response_data.json` and its screenshots to
`ux-audit-out/screens/`. Both are gitignored; the four PNGs pinned for the public example live in
[`../screens/`](../screens) and the raw walk in [`../walk.json`](../walk.json).

The journey being walked is [`../journey.md`](../journey.md); the report it produces is
[`../report.md`](../report.md).

Steps 2 and 3 are **expected to fail** — that is the fixture working. `flutter drive` exits 0 either
way, so read `steps[].status` in `build/integration_response_data.json`, never `$?`.

Verified on an iPhone SE (3rd gen) simulator and an Android emulator (API 36). On Android the walk
records `screenshot: null` on every step by design; capture from the host with
`adb exec-out screencap -p` instead.

## The gated entrypoint

`lib/main_gated.dart` is the same fixture behind a sign-in screen. Past the gate it hands over to
`ListScreen` from `main.dart`, so the six defects and the golden that pins them are untouched. The
gate itself is deliberately **clean** — labelled fields, 48 lpx targets, readable contrast, an error
message that names its own recovery. It adds no seventh seeded defect, because the six are pinned by
a golden and a seventh would have to be pinned too.

It exists because `## Setup`, an `HttpOverrides` stub and `networkCalls` were documented and never
publicly exercised: the ungated fixture has no HTTP layer at all, so the one mechanism that gets an
audit past a real app's front door had only ever been verified in private.

```bash
flutter drive --driver=test_driver/ux_journey_driver.dart \
              --target=integration_test/gated_journey_test.dart -d <device-id>
```

Measured on an iPhone SE (3rd gen) simulator, iOS 18.6: setup 3/3 OK,
`networkCalls: ["/session", "/auth/login"]` in request order, `taps: 2`, and the same three screen
signatures as the ungated run (`a9582ba2`, `4ddc18db`, `3afe0168`) — the gate changes the way in and
nothing past it. The journey is [`../journey-gated.md`](../journey-gated.md), the stub is
`integration_test/gate_stub.dart`, and the walk is
[`../walk-gated.json`](../walk-gated.json).

No credential is asked for or used. The address is `ux-audit@example.invalid`, which RFC 2606
guarantees cannot resolve, and the stub answers both calls from inside the test process. Get the
route table wrong and the gate stays shut: `gated_gate_test.dart` runs exactly that, and the step
that needs the server goes red naming what it could not find, while the user-facing error renders
too. That is the intended outcome — the fix is the route table, never a real account.

Its first run found two traps that the ungated fixture could not reach:

- The AppBar title and the primary button both read "Sign in", and the selector refused the whole
  setup phase: `ambiguous: 2 nodes match "Sign in"`. The fixture's title is "Welcome back" now,
  with the reason left at the call site, because a real app hits this constantly and the fix there
  is a journey's `nth:`, not a cleverer matcher.
- The `type` step's text landed in the artifact. `obscureText` keeps a value out of the semantics
  tree, but the walk records a `type` step's text from the journey file, so the first gated run
  wrote the password into the walk data. The walker now asks the field and records
  `<redacted 19 chars: the field hides its own value>`.
