---
name: flutter-ux-journey
description: Audits a running Flutter app one user journey at a time and reports heuristic UX defects scored against that journey's goal, merging static analysis, runtime measurement (real pixel rects, real contrast ratios, real semantics labels pulled from the live app) and screenshots into a single report. Use when the user asks to audit or review a Flutter app's UX, to walk a user journey such as onboarding, sign-up or checkout, or to find usability and accessibility problems in a running Flutter app rather than in its source alone.
license: MIT
compatibility: Requires the Flutter SDK (Dart included) and a booted iOS simulator or Android emulator with the app buildable on it. Measurement is verified on both; screenshots differ — on Android takeScreenshot deadlocks when the app embeds platform views, so capture from the host. Real devices are untested.
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
4. back — expect the email still filled in

## Priorities (optional)
1. sign in
2. recover a forgotten password
```

`## Setup` is mandatory when the app gates the journey (a permission dialog, an onboarding sheet,
a PIN pad). It is excluded from measurement and from scoring. Without it, a run that dies in setup
gets reported as a short successful journey.

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

`references/network-stub.md` carries the working template and the two mistakes that each cost a
run. Only the route table is app-specific: stub the sign-in endpoint, run, read `networkCalls` and
the failing step, add what it names, repeat. Three or four rounds is typical — that loop is faster
than reading the app's API surface up front.

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
integration_test/ux_journey_test.dart
test_driver/integration_test.dart
```

Screenshots and semantics labels are verbatim product copy. They stay in the audited project.

---

## [0a] FEATURE MAP — what the app says it does

Before any journey, read the app's **router** and list its declared routes. That is the app's own
statement of its feature surface — no crawling, no guessing, and it is static so it costs nothing.
For GoRouter, that is usually a file of route constants plus the `GoRoute` tree.

Group the routes into feature areas and present the map with a coverage column. A route the walk
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

Per step the walk records, besides the semantics dump and the four guidelines:

| Field | What it is for |
|---|---|
| `surface.canPop` / `tappableCount` / `modalOpen` | `DEAD-END` as a measurement instead of a selector miss |
| `semantics.viewport` (`foldY`, `contentTop`, `keyboardInset`, `isTestDefault`) | what is on screen without scrolling — and when that is not knowable |
| per-node `onScreen`, `aboveFold`, `coversSurface` | what is really on the surface — cache-extent rows are in the dump too, and the full-screen keyboard-dismiss `GestureDetector` must be excluded from placement |
| per-node `effectivePct`, `centreCovered`, `obscuredBy` | controls that are nominally big enough but partly covered |
| `tapsSoFar` | reach cost on the declared path |
| `dispatched`, `semanticsUnchanged`, `screenSig` | dead taps, revisits, state loss |

`report['networkCalls']` must be filled from the stub's own call list when a stub is installed
(`references/network-stub.md`) — the field is documented and the template's list is named
`stubCalls`, so copying it across is a step, not an assumption.

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
Then one clause of scope: one declared path, walked once, one device size, one theme. A reader who
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
