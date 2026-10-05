---
name: flutter-ux-journey
description: Audits a running Flutter app one user journey at a time and reports heuristic UX defects scored against that journey's goal, merging static analysis, runtime measurement (real pixel rects, real contrast ratios, real semantics labels pulled from the live app) and screenshots into a single report. Use when the user asks to audit or review a Flutter app's UX, to walk a user journey such as onboarding, sign-up or checkout, or to find usability and accessibility problems in a running Flutter app rather than in its source alone.
license: MIT
compatibility: "Requires the Flutter SDK: Flutter 3.47+ / Dart 3.13+, verified on 3.47.2 / 3.13.2; the static probe needs Dart 3.11+. The default walk runs under flutter test with no device and records the font source and rasterizer it measured with, so a contrast ratio near the threshold is advisory. An app whose plugins or platform views need a real platform falls back to flutter drive on a booted iOS simulator or Android emulator. Real devices are untested."
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
- Nothing else for the default mode. Only the `flutter drive` fallback needs a device id from
  `flutter devices` — a booted iOS simulator or Android emulator. Measurement is verified on both;
  see the frontmatter for the one difference (screenshots).

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
4. back — expect the email still filled in

## Priorities (optional)
1. sign in
2. recover a forgotten password
```

`## Setup` is mandatory when the app gates the journey (a permission dialog, an onboarding sheet,
a PIN pad). It is excluded from measurement and from scoring. Without it, a run that dies in setup
gets reported as a short successful journey. The heading is matched on the word `Setup`; the
parenthetical above is a reminder to whoever reads the file, so a bare `## Setup` is the same
heading. Nothing parses this file but the agent reading it — the lists it produces are the ones it
generates into the walker.

A step is `tap`, `type` or `back`. `back` presses the on-screen back affordance; it fails when
there is none, which is a DEAD-END **candidate**, not the evidence — `tester.pageBack` only looks
for a tooltip-"Back" or Cupertino back button, so it also fails on a screen whose exit is a "Close"
button. Confirm with the measured predicate. Add `nth: N` (1-based) to a step whose label
legitimately matches more than one node; the walker's ambiguity error lists the candidates and
their sizes so one re-run is enough.

`## Priorities` is **optional and never inferred.** It is a ranked list of what the app is for, in
the user's own words. It is the only legitimate source of "this feature matters more than that
one" — nothing in the source, the semantics tree or the router carries importance, so without a
declaration the report says `not declared` rather than guessing. See
`references/heuristics.md` → *Placement vs priority*.

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

In the default mode this needs no command at all: `flutter test` installs its own `HttpOverrides`
and answers every request with an empty 400, so nothing leaves the host and there is no device
setting to put back. The commands below are for the `flutter drive` fallback.

```bash
adb shell cmd connectivity airplane-mode enable      # Android
# iOS simulator: it shares the host network; use the stub below instead.
...run the walk...
adb shell cmd connectivity airplane-mode disable     # always restore
```

Airplane mode is a change to somebody's device, not to the audit. Restore it in the same turn,
before writing the report, whether the walk passed, failed or threw.

This is not a lesser fallback. The failure path — wrong password, no signal, server down — is the
path every real user eventually hits, and it is the one nobody tests. Measured on a production app,
this alone surfaced a severity-3 defect that the happy path cannot show.

### 2. A network stub, authored from the app's own models (to walk past a gate)

To walk *past* sign-in, stub the HTTP layer from inside the test, before `app.main()`. The app is
not modified: `HttpOverrides.global` intercepts `dart:io` `HttpClient`, which is what Dio, `http`,
and most clients sit on.

`references/network-stub.md` carries the working template and the two mistakes that each cost a
run. Only the route table is app-specific: stub the sign-in endpoint, run, read `networkCalls` and
the failing step, add what it names, repeat. Three or four rounds is typical — that loop is faster
than reading the app's API surface up front.

There is a worked instance to copy rather than re-derive: `example/journey-gated.md` walked against
`example/ux_demo_app/lib/main_gated.dart` with `integration_test/gate_stub.dart`, measured on a
simulator — `networkCalls: ["/session", "/auth/login"]`, setup 3/3 OK, and a journey byte-identical
to the ungated run's. Its walker, `integration_test/gated_journey_test.dart`, is 105 lines against
the first walker's 1155, and 67 of those are code — nearly all of it the two step lists. That is
because `walkJourney` is public: a second journey imports the walk from the first rather than
copying it. (The public copy is named `gate_stub.dart` because `net_stub.dart` is the generated
name and is gitignored.)

Run it with the device offline (`adb shell cmd connectivity airplane-mode enable`). If a response
arrives at all, the stub is intercepting — a real request could not have succeeded. That is also
the guarantee that the audit never touches production.

If the stub is wrong, the journey step fails and says so — the oracle still holds. Never reach for
a real account to make a red step go green.

**Walk the whole app, not the doorstep.** A journey that stops at sign-in measures a login form,
not a product. Once past the gate, walk the tabs and flows a real user moves between: the defects
that only a journey can find — a control that is too small on *every* screen, terminology that
drifts between tabs, state lost on return — are invisible from any single screen.

## Output location

Write every artifact to `<app-root>/ux-audit-out/` — `report.md`, `findings.json`, `screens/*.png`,
`static.json`, `walk.json`.

Never write output into the skill or plugin directory: it is shared, it is overwritten on update,
and a screenshot dropped there is one `git add -A` away from being published. Tell the user to add
to the audited app's `.gitignore`:

```
ux-audit-out/
ux_audit/
integration_test/ux_journey_drive.dart
test_driver/integration_test.dart
```

The default mode writes ONE file into the app — `ux_audit/ux_journey_test.dart` — plus
`ux_audit/net_stub.dart` when the journey has a gate to walk past. The other two exist only when
the run falls back to `flutter drive`. Together they are everything a run writes into the app. It needs no fifth line: the walk's JSON lands
in `build/`, which Flutter's own `.gitignore` template already covers, and the screenshots go to
`ux-audit-out/screens/` — never to `screenshots/`, which is a conventionally tracked directory in a
Flutter app and not ours to claim.

`net_stub.dart` matters most of them: it is the only generated file that holds the app's real
endpoints and real response bodies.

Screenshots and semantics labels are verbatim product copy. They stay in the audited project.

---

## [0a] FEATURE MAP — what the app says it does

Before any journey, list what the app says its feature surface is. That is the app's own statement
— no crawling, no guessing — and the probe reads it for you. Run step [1]'s command now; it takes
seconds, needs no device, and its `routes` block is this step's input:

```json
"routes": {
  "declared":  [{"kind":"go-route","path":"/detail","name":"detail","screen":"DetailScreen","file":"router.dart","line":12}],
  "pushed":    [{"kind":"inline-push","from":"_ListScreenState","to":"DetailScreen","method":"push","file":"main.dart","line":167},
                {"kind":"go-nav","from":"HomePage","target":"/detail","method":"go","file":"home.dart","line":40}],
  "notAssessable": [{"reason":"onGenerateRoute resolves its routes from a runtime string …"}]
}
```

`declared` is a GoRouter route table. `pushed` is what reaches a screen: `inline-push` for an app
with no declarative router — the bundled `example/ux_demo_app` is one, and its whole graph comes
out as three `inline-push` edges — and `go-nav` for a literal `context.go`/`pushNamed` target.

**Read `notAssessable` before reading either.** An `onGenerateRoute`, an interpolated path, a
builder that is a torn-off function: each is navigation the probe can see exists and cannot read,
and each belongs in the report's Not Assessable section. `declared: []` with a non-empty
`notAssessable` means the router is unreadable, not that the app has no routes — and an app with no
declarative router at all has no route table to reconcile the walk against, which the report says
out loud. `example/report.md` does exactly this under *Feature map* and *Not Assessable*; copy its
shape.

`from` is the enclosing class declaration verbatim — `_ListScreenState`, not `ListScreen`. The probe
does not strip the underscore or the `State` suffix, because that is a guess about naming
convention. Label the table by what reaches a screen (`to`), which is what a reader cares about.

Group the routes into feature areas and present the map with a coverage column. **The coverage
column is yours, not the probe's** — whether the walk reached a screen is a comparison against
`walk.json`, and the probe never sees it. A route the walk
never reached is **not audited**, and the report must say so — a score over 20% of an app that
reads like a score over the app is the single most misleading thing this tool could produce.

Use the map to choose journeys: the revenue path and the daily path first, then settings and edge
flows. Personas matter — an app with a second persona behind a profile switch has a second map.

The map is **what exists**. `## Priorities` in `journey.md` is **what matters**, and only a human
supplies it. Step 4 reports where the two disagree; it never derives one from the other.

## [0] PREFLIGHT — restate, then stop

Read `journey.md` and restate it back as a checklist: the goal in one sentence, the setup steps, the
numbered journey steps with their expected outcome, the app path, the device id, the output dir.
Name anything ambiguous (which tab is "Orders"? what proves the goal is reached?).

**Then stop and wait for confirmation. Do not run anything in this step.**

A wrong journey costs a full build-and-drive cycle to discover, and a journey whose steps do not
match the app produces a confident report about a path the user never takes.

## [1] STATIC — candidates from the source

```bash
mkdir -p <out>/screens          # nothing else creates <out>, and the redirect below needs it
PROBE="${CLAUDE_PLUGIN_ROOT}/tools/astprobe/bin/probe.dart"
dart run "$PROBE" <app-root>/lib > <out>/static.json
```

Two blocks come out: `findings` (the four rules below) and `routes` (the feature surface, consumed
by step [0a] above — run this command before that step, not after).

`${CLAUDE_PLUGIN_ROOT}` is not an environment variable. When the skill runs as a Claude Code
plugin, that exact token is replaced in this file's text, so the command above already carries the
real path — a shell default such as `${CLAUDE_PLUGIN_ROOT:-…}` is not replaced and expands to
nothing in Bash. If the token is still there literally, the skill was copied rather than installed
as a plugin: read it as the clone root, the directory holding `skills/`, `tools/` and `example/`,
two levels above this skill's folder. There is no `pub get` step: `dart run` resolves the
probe's dependencies itself. It does write a `.dart_tool/` beside the probe, which is a resolution
cache and the one thing that lands in the skill directory — no audit output ever does.

Four rules: unlabeled `GestureDetector`/`InkWell` with `onTap`, `IconButton`/`Icon` with neither
`tooltip` nor `semanticLabel`, `Image` without `semanticLabel`, unlabeled `TextField`.

Read `filesScanned` before reading the findings: `0 findings` with `filesScanned: 0` means the path
was wrong, not that the code is clean. And pass `<app-root>/lib`, never `<app-root>` — the probe
scans whatever directory it is given, so on the bundled fixture `<app-root>` scans 11 files and
reports 3 candidates inside `test/`, which is not the app, and would scan the walker this skill just
generated as well. Each finding's `file` is relative to the directory passed in, so with
`<app-root>/lib` it reads `main.dart`; quote it as `lib/main.dart:126`, the form every other document
uses.

The probe matches on widget *names* with no type resolution, so a same-named non-widget is a possible
false positive — that is why each hit carries a confidence. **`STATIC` alone proves a candidate in
the code, not a defect on the journey.** It becomes a finding when step 2 or 3 shows it on a screen
the journey actually visits; otherwise it is reported at low confidence and says so.

Contrast and tap-target size are absent by design: neither is decidable statically, and step 2
measures both for real.

## [2] WALK — run the journey inside the app

Follow `references/walking.md`. It is the exact recipe: the files to generate into the audited app,
the verified SDK calls, and the traps that look fine on the happy path.

Generate `ux_audit/ux_journey_test.dart` into the audited app and add `flutter_test` to its
dev_dependencies. Then:

```bash
flutter test ux_audit/ux_journey_test.dart
```

The walk writes `ux-audit-out/walk.json` and `ux-audit-out/screens/step_*.png` itself; nothing has
to be copied afterwards. The journey's `## Device` section supplies the screen, because nothing
else does — leave it out and the walk falls back to `iphone-se` and records that it was not
declared.

**The directory name is load-bearing.** `flutter test` routes anything under `integration_test/`
to a device runner on the name alone, so a walker placed there fails with "No devices are
connected". `ux_audit/` is outside it, and outside `test/` too, so the audited app's own
`flutter test` never sweeps the walker up.

**Fallback** — the app needs a real device under it (plugins that throw `MissingPluginException`,
platform views that must actually render). Also generate `integration_test/ux_journey_drive.dart`
and `test_driver/integration_test.dart`, add `integration_test` to dev_dependencies, and run:

```bash
flutter drive --driver=test_driver/integration_test.dart \
              --target=integration_test/ux_journey_drive.dart -d <device-id>
```

then copy `build/integration_response_data.json` into the output dir as `walk.json`. The PNGs are
already there: the driver writes them straight to `ux-audit-out/screens/`.

Per step the walk records, besides the semantics dump and the four guidelines:

| Field | What it is for |
|---|---|
| `surface.canPop` / `tappableCount` / `modalOpen` | `DEAD-END` as a measurement instead of a selector miss |
| `semantics.viewport` (`foldY`, `contentTop`, `keyboardInset`, `isTestDefault`) | what is on screen without scrolling — and when that is not knowable |
| per-node `onScreen`, `aboveFold`, `coversSurface` | what is really on the surface — cache-extent rows are in the dump too, and the full-screen keyboard-dismiss `GestureDetector` must be excluded from placement |
| per-node `effectivePct`, `centreCovered`, `obscuredBy` | controls that are nominally big enough but partly covered |
| `tapsSoFar` | reach cost on the declared path |
| `dispatched`, `semanticsUnchanged`, `screenSig` | dead taps, revisits, state loss |
| `semantics.panesPossiblyBlocked` | true: the dump saw only the last-painted pane — two sibling `Navigator`s, so the report says `not assessable` for the other rather than clean. False is a declared *suspicion*, not a guarantee the dump is whole |
| `conditions` (top level, once per run) | the brightness, text scale and accessibility flags the numbers above were measured under, plus `mode` (`widget-test` or `drive`), `deviceProfile` (or `<name> (default, not declared)`), `fontSource` (`app` exact / `sdk-fallback` close / `none` — fold and placement **not assessable**), `renderer` and `targetPlatform`. The scope clause quotes all of it. `platform` is the HOST under `flutter test`, which is why `targetPlatform` is separate |
| `setupSteps` (top level) | the `## Setup` phase, recorded beside `steps` and never merged into it: no semantics dump, no guidelines, no reach cost. A setup step carries a `screenshot` only when it failed (`setup_N.png`) |
| `setupFailed` (top level) | true: the walk never reached the journey's starting line, and `steps` is empty by construction |

`report['networkCalls']` must be filled from the stub's own call list when a stub is installed
(`references/network-stub.md`) — the field is documented and the template's list is named
`stubCalls`, so copying it across is a step, not an assumption.

**Neither mode's exit code is the oracle. Read the JSON.** Both exit 0 even when every journey step
failed — by design, because the walker collects Evaluations and step errors instead of asserting
(asserting would also discard the JSON and, under `flutter drive`, the PNGs, since
`writeResponseOnFailure` defaults to false). Judge the run by reading `steps[].status` in
`walk.json`, never by `$?`. A green exit with three `FAILED` steps is the normal shape of a journey
that hit a real defect.

**No PNGs but a green run**, in the `flutter drive` fallback, means the recipe was mis-copied:
`takeScreenshot` appends into `reportData['screenshots']`, so assigning a fresh map to `reportData`
at the end deletes them all silently. See the MUTATE-never-replace note in
`references/walking.md`. In the default mode there is no such hazard — the walk writes each PNG
straight to disk — but a step whose `screenshot` is null still means its capture failed, and the
VISUAL layer for that step is `not assessable`.

**If the run dies during `## Setup`, stop.** The walk says so itself: `setupFailed: true`, the last
entry in `setupSteps` carries the error and its `setup_N.png`, and `steps` is empty. Report a setup
failure with what blocked it. Do not report the setup steps that did run as a journey — a journey
that never started has no findings.

If a journey step fails (the target is not on screen, or the expected outcome never appears), that is
itself a finding — record the step as `FAILED`, keep its screenshot, and continue only if the next
step does not depend on it.

## [3] VISUAL — look at the screenshots

Read every `screens/step_*.png`. No script; the model does this.

**On Android there are none.** The walk gates in-test screenshots on `Platform.isIOS`, so every
step's `screenshot` is null and this whole layer is `not assessable` — say that, and say which checks
it takes down with it. Two cannot fire without a pixel comparison: `FAKE-AFFORDANCE` in its dead-tap
mode, whose second layer is `cmp` on consecutive PNGs, and the effective-area variant of
`TOUCH-TARGET`, whose `effectivePct` is geometry until an image confirms it. A host capture (the
`adb exec-out screencap` form is in `references/walking.md`) documents the end state only, one frame
after the walk, so it supplies neither — it is evidence for the last screen, not for a transition.

Look for what the semantics tree cannot say: overflow stripes and clipped text, content hidden behind
a keyboard or a sheet, an empty state that looks like a failure, a primary action that is not the most
prominent thing on screen, an element styled as tappable that carries no tap action in the walk data
(and the reverse), a screen that gives no way back.

When eye and measurement disagree, **geometry is settled by the measurement** (rects, ratios) and
**meaning is settled by the eye** (is this actually the primary action?).

Two things the visual pass is now the second layer for, and must actually be run:

- **Dead taps.** A step with `dispatched: true` and `semanticsUnchanged: true` is a candidate, not a
  finding: a control that only repaints is byte-identical in semantics to one wired to nothing.
  `cmp -s screens/step_N.png screens/step_N+1.png` settles it for free. Identical pixels AND
  identical semantics → `FAKE-AFFORDANCE`. Differing pixels with identical semantics is its own
  finding: a state change assistive technology cannot see.
- **Partly covered controls.** `effectivePct < 1.0` is geometry, not a hit test — the semantics tree
  has no opacity and no `IgnorePointer`. Look at the screenshot before reporting it, and drop it
  when the step's `settled` is false.

## [4] MERGE + RESCORE — one report, scored, with a direction

Follow `references/heuristics.md`: assign each observation a Named Check ID, merge the layers,
dedupe, then rescore every finding **against the journey's goal**. No script; the scoring is the
judgement. Five checks now have a **measurement predicate** and do not fire without it.

**Open with a verdict, not a table.** Two or three sentences in the words a user would use, naming
what happens to the person trying to do this and what stops them — no check IDs, no widget names.
Then one clause of scope, quoting `conditions` from the walk data rather than asserting it: one
declared path, walked once, one device size, the brightness and text scale the run recorded. A reader who
meets a feature map and a score table before a single defect stops reading.

**Flow and placement.** Report reach cost as `N taps on the declared path`, never "N taps deep" and
never a minimum — the walk knows the path it was given, and the shortest one needs paths nobody
declared. Then compare the two declarations: `## Priorities` (or the goal) against the entry
screen's tap targets in reading order, with their rects and `aboveFold`. Print **only the rows that
disagree**. Where nothing was declared, print `not declared` and cap the affected findings at
severity 2, naming which were capped. Never infer a ranking.

**Score only what was measured**, and make the arithmetic visible:

| Dimension | Measurement |
|---|---|
| Tap target ≥44/48 lpx | screens with zero violations / screens measured; plus unique nodes passing |
| Text contrast | screens passing `textContrastGuideline` / screens measured |
| Accessible name | screens passing `labeledTapTargetGuideline` / screens measured |
| Screen stability | steps that settled / steps measured |
| Reach | taps on the declared path; screens with a way out / screens visited |
| Error handling | qualitative — mark it as such |

Publish the weighting inline so a reader can disagree with it, state plainly what the score does NOT
cover, and **publish no composite number** — a single figure over these would imply a measurement
nobody performed. A number without its method is a claim.

**Direction** is the only section anyone acts on and the only one allowed to propose. Order by
effort against reach, not severity alone: a theme-level colour fix that clears two contrast findings
on every screen outranks a severity-3 defect on one. Three buckets — now (S, global), next (M),
structural (L or needs a decision). The new measurements reorder it: a control the journey needs
that is only partly hittable outranks three contrast findings.

At most **one proposal per audit**, inside Direction, carrying no severity, naming the measurement
it stands on and what would disprove it. Findings state contradictions; only Direction may say
"arrange it differently". That split is deliberate — measurement reaches as far as the
contradiction and no further.

Write `report.md` and `findings.json` in the exact shapes given in `references/report-format.md`,
including its rendering for a run that found nothing. Screenshots are referenced by relative path so
the report reads on its own when shared without them.

Finish by filling **Not Assessable**, split two ways by what the reader can do about it:
`Not declared` (say the word and the next run measures it) and `Not reached / not measurable here`
(nothing they can do). Steps never reached are *untested*, not clean — say so, or a short walk reads
as a healthy app.
