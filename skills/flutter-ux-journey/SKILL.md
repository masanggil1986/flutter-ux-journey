---
name: flutter-ux-journey
description: Audits a running Flutter app one user journey at a time and reports heuristic UX defects scored against that journey's goal, merging static analysis, runtime measurement (real pixel rects, real contrast ratios, real semantics labels pulled from the live app) and screenshots into a single report. Use when the user asks to audit or review a Flutter app's UX, to walk a user journey such as onboarding, sign-up or checkout, or to find usability and accessibility problems in a running Flutter app rather than in its source alone.
license: MIT
compatibility: Requires the Flutter SDK (Dart included) and a booted iOS simulator with the app buildable on it. Verified on the iOS simulator only; Android is untested.
---

# Flutter UX Journey Audit

Audit a **journey**, not a screen. A journey is one task the user is trying to finish; page-level
polish falls out of it and never leads.

Three rules hold for the whole run:

1. **No finding without evidence.** Every finding carries an evidence layer
   (`STATIC` / `RUNTIME` / `VISUAL` / `JOURNEY`) and a confidence. Measurements are quoted with units.
2. **Severity is relative to the goal.** The same defect is 4 when it blocks the goal and 2 when
   there is a way around it. See `references/heuristics.md`.
3. **What was not observed is stated, never omitted.** Anything the run did not reach goes in the
   report's mandatory "Not Assessable" section.

## Inputs

- `journey.md` — the journey to walk (format below). If the user has not written one, draft it from
  what they describe and get it confirmed in step 0.
- The Flutter app's project root.
- A device id from `flutter devices` (a booted iOS simulator for v0.1).

### journey.md format

```markdown
# Goal
See that a failed sign-in tells the user what to do next. Done = the message is on screen.

## Setup (excluded from measurement and scoring)
1. dismiss the notification permission dialog

## Steps
1. type "ux-audit@example.invalid" into "email" — expect the field to hold it
2. type "not-a-real-password" into "password" — expect the sign-in button
3. tap "Sign in" — expect an error the user can act on
```

`## Setup` is mandatory when the app gates the journey (a permission dialog, an onboarding sheet,
a PIN pad). It is excluded from measurement and from scoring. Without it, a run that dies in setup
gets reported as a short successful journey.

## Credentials: never ask for them

**Do not ask the user for a username, password, PIN, or token. Not in the journey file, not in an
environment variable, not in a prompt.** An audit tool that asks for a password is a phishing
shape, it blocks adoption, and it puts a real account one bug away from a report file. It is also
unnecessary — the walk runs *inside* the app process, so it can control what the app sees.

Two mechanisms, in order of preference:

### 1. Offline + arbitrary data (default; no setup, works on any app)

Cut the device off the network, type obviously-fake values, and audit what the app does when the
call fails. This needs no credentials, no stub, and **no request ever leaves the device** — an
audit tool must never throw sign-in attempts at production.

```bash
adb shell cmd connectivity airplane-mode enable      # Android
# iOS simulator: it shares the host network; use the stub below instead.
...run the walk...
adb shell cmd connectivity airplane-mode disable     # always restore
```

This is not a lesser fallback. The failure path — wrong password, no signal, server down — is the
path every real user eventually hits, and it is the one nobody tests. Measured on a production app,
this alone surfaced a severity-3 defect that the happy path cannot show.

### 2. A network stub, authored from the app's own models (to walk past a gate)

To walk *past* sign-in, stub the HTTP layer from inside the test, before `app.main()`. The app is
not modified: `HttpOverrides.global` intercepts `dart:io` `HttpClient`, which is what Dio, `http`,
and most clients sit on.

Response shapes are app-specific, so this is model work, not a fixed script: read the app's own
auth service and response models, then write a stub that returns the success shape they parse.
Reuse the app's existing test fixtures when it has them.

Set it before the app boots:

```dart
HttpOverrides.global = _StubOverrides();   // before app.main()
```

If the stub is wrong, the journey step fails and says so — the oracle still holds. Never reach for
a real account to make a red step go green.

## Output location

Write every artifact to `<app-root>/ux-audit-out/` — `report.md`, `findings.json`, `screens/*.png`,
`static.json`, `walk.json`.

Never write output into the skill or plugin directory: it is shared, it is overwritten on update,
and a screenshot dropped there is one `git add -A` away from being published. Tell the user to add
to the audited app's `.gitignore`:

```
ux-audit-out/
integration_test/ux_journey_test.dart
test_driver/integration_test.dart
```

Screenshots and semantics labels are verbatim product copy. They stay in the audited project.

---

## [0] PREFLIGHT — restate, then stop

Read `journey.md` and restate it back as a checklist: the goal in one sentence, the setup steps, the
numbered journey steps with their expected outcome, the app path, the device id, the output dir.
Name anything ambiguous (which tab is "Orders"? what proves the goal is reached?).

**Then stop and wait for confirmation. Do not touch a simulator in this step.**

A wrong journey costs a full build-and-drive cycle to discover, and a journey whose steps do not
match the app produces a confident report about a path the user never takes.

## [1] STATIC — candidates from the source

```bash
dart pub get -C "${CLAUDE_PLUGIN_ROOT}/tools/astprobe"    # once: the probe imports package:analyzer
dart run "${CLAUDE_PLUGIN_ROOT}/tools/astprobe/bin/probe.dart" <app-root>/lib > <out>/static.json
```

Four rules: unlabeled `GestureDetector`/`InkWell` with `onTap`, `IconButton`/`Icon` with neither
`tooltip` nor `semanticLabel`, `Image` without `semanticLabel`, unlabeled `TextField`.

The probe matches on widget *names* with no type resolution, so a same-named non-widget is a possible
false positive — that is why each hit carries a confidence. **`STATIC` alone proves a candidate in
the code, not a defect on the journey.** It becomes a finding when step 2 or 3 shows it on a screen
the journey actually visits; otherwise it is reported at low confidence and says so.

Contrast and tap-target size are absent by design: neither is decidable statically, and step 2
measures both for real.

## [2] WALK — run the journey inside the app

Follow `references/walking.md`. It is the exact recipe: the two files to generate into the audited
app, the verified SDK calls, and the three traps that look fine on the happy path.

Summary of what happens: generate `integration_test/ux_journey_test.dart` and
`test_driver/integration_test.dart` into the audited app, add the two SDK dev_dependencies, run

```bash
flutter drive --driver=test_driver/integration_test.dart \
              --target=integration_test/ux_journey_test.dart -d <device-id>
```

then collect `build/integration_response_data.json` and `screenshots/*.png` into the output dir.

**The exit code is NOT the oracle. Read the JSON.** `flutter drive` exits 0 even when every journey
step failed — by design, because the walker collects Evaluations and step errors instead of
asserting (asserting would also discard the JSON and the PNGs, since `writeResponseOnFailure`
defaults to false). Judge the run by reading `steps[].status` in
`build/integration_response_data.json`, never by `$?`. A green exit with three `FAILED` steps is the
normal shape of a journey that hit a real defect.

**No PNGs but a green run** means the recipe was mis-copied: `takeScreenshot` appends into
`reportData['screenshots']`, so assigning a fresh map to `reportData` at the end deletes them all
silently. See the MUTATE-never-replace note in `references/walking.md`.

**If the run dies during `## Setup`, stop.** Report a setup failure with what blocked it. Do not
report the steps that did run as a journey — a journey that never started has no findings.

If a journey step fails (the target is not on screen, or the expected outcome never appears), that is
itself a finding — record the step as `FAILED`, keep its screenshot, and continue only if the next
step does not depend on it.

## [3] VISUAL — look at the screenshots

Read every `screens/step_*.png`. No script; the model does this.

Look for what the semantics tree cannot say: overflow stripes and clipped text, content hidden behind
a keyboard or a sheet, an empty state that looks like a failure, a primary action that is not the most
prominent thing on screen, an element styled as tappable that carries no tap action in the walk data
(and the reverse), a screen that gives no way back.

When eye and measurement disagree, **geometry is settled by the measurement** (rects, ratios) and
**meaning is settled by the eye** (is this actually the primary action?).

## [4] MERGE + RESCORE — one report

Follow `references/heuristics.md`: assign each observation a Named Check ID, merge the layers, dedupe,
then rescore every finding **against the journey's goal**. No script; the scoring is the judgement.

Write `report.md` and `findings.json` in the exact shapes given in `references/report-format.md`.
Screenshots are referenced by relative path so the report reads on its own when shared without them.

Finish by filling the "Not Assessable" section honestly: steps not reached, checks not run, the
platform limit (iOS simulator only, one device size, one theme), and anything the run skipped.
