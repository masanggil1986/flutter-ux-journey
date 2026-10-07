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
  the one difference, in-test screenshots on Android, is in step [3].

### journey.md format

```markdown
# Goal
See that a failed sign-in tells the user what to do next. Done = the message is on screen.

## Setup (excluded from measurement and scoring)
1. tap "Skip" — expect "Sign in"

## Device (optional)
`iphone-se`
- textScale 3.0
- dark

## Steps
1. type "ux-audit@example.invalid" into "email" — expect the field to hold it
2. type "not-a-real-password" into "password" — expect the sign-in button
3. tap "Sign in" — expect an error the user can act on
4. back — expect the email still filled in
5. scroll until "Forgot password?" — expect "Forgot password?"
6. tap "Forgot password?" — expect no "Sign in"
7. system back — expect "Sign in"

## Priorities (optional)
1. sign in
2. recover a forgotten password
```

`## Setup` is mandatory when the app gates the journey (an onboarding sheet, a sign-in form, a PIN
pad the app draws itself). It is excluded from measurement and from scoring. Without it, a run that
dies in setup gets reported as a short successful journey. An OS permission dialog cannot be a setup
step: under `flutter test` there is no OS to show one, and under `flutter drive` it is native UI
outside the semantics tree the walk reads. The heading is matched on the word `Setup`; the
parenthetical above is a reminder to whoever reads the file, so a bare `## Setup` is the same
heading. Nothing parses this file but the agent reading it — the lists it produces are the ones it
generates into the walker.

A step is `tap "X"`, `long-press "X"`, `type "…" into "X"`, `scroll until "X"`, `back` or
`system back`, followed by `— expect "Y"` or `— expect no "Y"` (the absence oracle: Y must be gone).
`back` presses the on-screen back affordance; it fails when
there is none, which is a DEAD-END **candidate**, not the evidence — `tester.pageBack` only looks
for a tooltip-"Back" or Cupertino back button, so it also fails on a screen whose exit is a "Close"
button. Confirm with the measured predicate. `system back` is the platform's back button instead;
it fails when nothing in the app takes the pop, because on Android that closes the app.
`long-press` resolves and refuses exactly as `tap` does and counts as reach the same way.
`scroll until "X"` drags the vertical list that holds X, at most 20 times, until X can be tapped
where it stands; it reaches a declared target and is never a crawl, and its drags are recorded
apart from taps. It is vertical only, and a row drawn under a floating bar can still end with its
centre under the bar. A `tap` on a target wholly below the fold, with no `scroll until` before it,
FAILS with "cannot reach it without scrolling": that is the journey's missing step, a tool limit,
not a finding about the app. Add `nth: N` (1-based) to a step whose TARGET legitimately matches
more than one node; the walker's ambiguity error lists the candidates and their sizes so one re-run
is enough. The expectation needs no `nth`: it only has to be on screen, once or more. `scroll
until`, `long-press`, `system back` and `expect no` are verified headless only, not yet on a device.

**Choose an expectation that is not on the screen the step starts from.** The oracle is what turns
a dispatch into a result, but only if the action is what put the text there. A price that a list
row already shows, a title that persists across screens, a nav label: each passes before the tap
lands. The walk records `expectedBefore` per step, and when it is true the step stays `OK` but
proves nothing about its action — the report treats it as **not proven** (see
`references/report-format.md`).

`## Device` names the screen (`iphone-se`, or explicit logical-px numbers) and may add one
condition per line: `- textScale 3.0`, `- dark`, `- locale ko-KR`, `- boldText`. Leave a line out
and that condition stays at the test default. One set per run — a second condition set is a
second run, because app globals leak between walks in one process.

`## Priorities` is **optional and never inferred.** It is a ranked list of what the app is for, in
the user's own words. It is the only legitimate source of "this feature matters more than that
one" — nothing in the source, the semantics tree or the router carries importance, so without a
declaration the report says `not declared` rather than guessing. See
`references/heuristics.md` → *Placement vs priority*.

## Credentials: never ask for them

**Do not ask the user for a username, password, PIN, or token. Not in the journey file, not in an
environment variable, not in a prompt.** An audit tool that asks for a password is a phishing
shape, it blocks adoption, and it puts a real account one bug away from a report file. It is also
unnecessary — the walk runs *inside* the app process, so it can control what the app's
`HttpClient` gets back.

Two mechanisms, in order of preference, and one boundary both share.

**The boundary.** The walk controls the `dart:io` `HttpClient` that the app builds in the walk's
isolate — which is what Dio, `package:http`'s `IOClient` and `NetworkImage` sit on. Nothing else.
WebSockets (under `flutter test`), raw sockets (gRPC, MQTT), other isolates (`Isolate.run`,
`compute`), native HTTP clients (`cupertino_http`, `cronet_http`, `native_dio_adapter`) and native
plugin SDKs (Firebase Auth and the like) go round it and can reach the real backend. WebSockets, raw
sockets, other isolates and `cupertino_http` were measured doing so with `networkCalls` reading
`[]`; the rest are outside by construction. Never
tell anyone a run was offline without the pre-walk check in step
[0]; the list and the search are in `references/network-stub.md` → *What the stub cannot see*.

### 1. Network cut + arbitrary data (default; no setup, works on any app)

Type obviously-fake values and audit what the app does when its requests fail. This needs no
credentials and no stub, and sends no sign-in attempt to production through the app's `HttpClient`.

The cut is already in place in both modes. The walk pins whichever override is current at launch
for everything it runs, so an app whose `main` assigns its own `HttpOverrides.global` does not swap
in a real client; the walk records `conditions.httpOverridesReplacedByApp: true` when one tried.
Code the app runs inside its own `HttpOverrides.runZoned` keeps its own, and the pin is verified
headless, not yet on a device.

- **`flutter test` (default):** flutter_test installs its own `HttpOverrides` and answers every
  request with an empty 400. Nothing to run, nothing to put back. `networkCalls` stays `[]` — that
  mock records nothing, so an empty list here does not mean "no requests".
- **`flutter drive` (fallback):** the drive entry installs `NetworkCut`, the real `HttpClient` with a
  `connectionFactory` that records the path and fails with `SocketException` before any DNS lookup
  or socket, as airplane mode would. `networkCalls` lists the paths it refused.

On an **Android emulator** under `flutter drive` you can go further and cut the device too, which is
the only posture that also stops the traffic listed above:

```bash
adb shell cmd connectivity airplane-mode enable      # Android emulator only
...run the walk...
adb shell cmd connectivity airplane-mode disable     # always restore
```

Airplane mode is a change to somebody's device, not to the audit. Restore it in the same turn,
before writing the report, whether the walk passed, failed or threw. The iOS simulator shares the
host's network and has no equivalent: there `NetworkCut` is the only cut, and it covers the
`HttpClient` alone.

**Start a `flutter drive` run from a clean install.** `flutter drive` installs over the existing app
and keeps its data, so a debug build that someone signed into earlier walks THEIR account — real
labels in the dump and the screenshots, real taps against production. Clear it first:
`adb shell pm clear <applicationId>` on Android, `xcrun simctl uninstall <udid> <bundleId>` (or a
fresh simulator) on iOS. Drive uninstalls the app when it finishes, so this matters for the first
run on a device that already had the app.

This is not a lesser fallback. The failure path — wrong password, no signal, server down — is the
path every real user eventually hits, and it is the one nobody tests. Measured on a production app,
this alone surfaced a severity-3 defect that the happy path cannot show.

### 2. A network stub, authored from the app's own models (to walk past a gate)

To walk *past* sign-in, stub the HTTP layer from inside the test, before `app.main()`. The app is
not modified: `HttpOverrides.global` replaces the `HttpClient` described above, and the boundary
above is the stub's boundary too.

`references/network-stub.md` carries the working template and the mistakes that each cost a run.
The route table is the app-specific part: stub the sign-in endpoint, run, read `networkCalls` and
the failing step, add what it names, repeat. Three or four rounds is typical — that loop is faster
than reading the app's API surface up front. Routing matches a substring of the request PATH and
ignores method, query and body, so a single-endpoint GraphQL or JSON-RPC app gets one answer for
every operation; this template cannot stub it per operation.

Where the stub goes depends on the entry that runs:

- **Default mode:** in the generated `ux_audit/ux_journey_test.dart`'s `main`, put
  `HttpOverrides.global = StubHttpOverrides();` before `walkJourney`, and pass
  `networkCalls: stubCalls`. The stub file is `ux_audit/net_stub.dart`.
- **Drive fallback:** in `integration_test/ux_journey_drive.dart`, replace the `NetworkCut` line with
  the stub **and** change `networkCalls: calls` to `networkCalls: stubCalls`. The walker's own
  `main` never runs under drive.

There is a worked instance to copy rather than re-derive: `example/journey-gated.md` against
`example/ux_demo_app/lib/main_gated.dart`, with the stub in `integration_test/gate_stub.dart`.
Its walker, `integration_test/gated_journey_test.dart`, is a **`flutter drive` fallback** entry —
it builds the drive binding and publishes into `reportData`, so run under `flutter test` it passes
green and writes nothing. Measured on a simulator: `networkCalls: ["/session", "/auth/login"]`,
setup 3/3 OK, and the same three journey screen signatures as the ungated run. The same gate is
walked headless by `test/gated_gate_test.dart`, through the real `walkJourney`, once through the
stub and once with a route table that refuses the sign-in. A second journey can be this small
because `walkJourney` is public: it imports the walk from the first rather than copying it. (The
fixture names its stub `gate_stub.dart` because this repo gitignores `net_stub.dart`; in the
audited app the stub goes in `ux_audit/`, which the `.gitignore` lines below cover.)

To check that the stub is what answered, read `networkCalls` and the setup steps: a stub installed
in a `main` that never ran shows as a red setup step. On an Android emulator under drive, airplane
mode turns that into proof — a response arriving at all means the stub answered, because a real
request could not have.

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
test_driver/ux_journey_driver.dart
```

The default mode writes ONE file into the app — `ux_audit/ux_journey_test.dart` — plus
`ux_audit/net_stub.dart` when the journey has a gate to walk past. The other two exist only when
the run falls back to `flutter drive`. Together they are everything a run writes into the app. It
needs no fifth line: the default walk writes `ux-audit-out/walk.json` itself, the drive fallback's
JSON lands in `build/`, which Flutter's own `.gitignore` template already covers, and the
screenshots go to `ux-audit-out/screens/` in both modes — never to `screenshots/`, which is a
conventionally tracked directory in a Flutter app and not ours to claim.

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

What the probe reads, and nothing else: `GoRoute` trees; `MaterialApp`/`CupertinoApp` `routes:`
and `onGenerateRoute`, which it reports as present rather than reading; the `Navigator` push verbs
(`push`, `pushReplacement`, `pushAndRemoveUntil`, `replace(newRoute:)`) carrying an inline
`MaterialPageRoute`/`CupertinoPageRoute`/`PageRouteBuilder`; and the string-route verbs —
`go`/`goNamed`/`pushNamed` and Navigator's named and restorable verbs. `declared` is a GoRouter
route table. `pushed` is what reaches a screen: `inline-push` for a route pushed inline — the
bundled `example/ux_demo_app` has no declarative router, and its whole graph comes out as three
`inline-push` edges — and `go-nav` for a literal `context.go`/`pushNamed` target.

A path or target can be a constant: a top-level or `static` `const`/`final` string literal,
resolved as Dart would (parameter or local first, then the enclosing type's statics, then the top
level). Anything else — a function-local constant, an interpolation, a field — is not read.
`screen` and `to` are the constructor's name as written, dotted when it is dotted
(`EditScreen.create`, `BlocProvider.value`), without type arguments, and `null` when a builder can
return more than one thing. A `pageBuilder` route names the page's `child:`, not its transition.

**Read `notAssessable` before reading either.** An `onGenerateRoute`, an interpolated path, a
builder that is a torn-off function, a nested route under a parent whose path cannot be read, a
`goBranch`, a GetX app, a generated route table (`@AutoRouterConfig`, `@TypedGoRoute`): each is
navigation the probe can see exists and cannot read, and each belongs in the report's Not
Assessable section. `declared: []` with a non-empty `notAssessable` means the router is
unreadable, not that the app has no routes.

**Empty everywhere means "no route table this probe can read"**, not "no router". Before writing
that the app has no declarative router, read `pubspec.yaml`: Beamer, routemaster, fluro and
`Navigator(pages:)` produce no line at all. Only when pubspec names no router either does the report
say the app has no route table to reconcile the walk against. `example/report.md` does exactly this
under *Feature map* and *Not Assessable*; copy its shape.

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
Name anything ambiguous (which tab is "Orders"? what proves the goal is reached?), and any step
whose expectation is already on the screen it starts from — that step can pass without its action
doing anything.

**PRE-WALK WARNING — what the network cut does not cover.** Read the app's `pubspec.yaml` and grep
its `lib/` for the search in `references/network-stub.md` → *What the stub cannot see*
(`web_socket_channel`, `WebSocket.connect`, `grpc`, `mqtt`, `socket_io`, `Socket.connect`,
`SecureSocket`, `Isolate.run`, `compute(`, `cupertino_http`, `cronet_http`, `native_dio_adapter`,
`firebase_`, `webview`). This is reading files, not running anything. If any of them is there, say so
in the checklist, before the walk, in plain words: that traffic is neither cut nor stubbed, and
during the walk it may reach the app's real backend from this machine (or from the simulator, which
shares its network). Name the package and, where the grep shows it, the journey step it sits on.
The only posture that cuts it is a `flutter drive` run on an Android emulator in airplane mode. Do
not describe the run as offline afterwards when this check found something.

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
cache and the one thing that lands in the skill directory — no audit output ever does. So the first
run needs that directory to be writable (a read-only install fails with `PathAccessException`) and
needs pub.dev or a warm `~/.pub-cache`.

Four rules, each held to what the runtime would call named:

- an unlabeled `GestureDetector`/`InkWell` with `onTap`;
- an `IconButton` or `Icon` with neither `tooltip` nor `semanticLabel`. An `IconButton` counts its
  icon's `semanticLabel`. An `Icon` is decorative, and not reported, when it sits in a slot of a
  control that names itself (`label:`, `labelText:`, `hintText:`, `title:`, `text:`, or a
  `tooltip:` on the owner), or when its nearest tap owner is a `GestureDetector`/`InkWell` the
  first rule already reports;
- an `Image` without `semanticLabel`, unless it has `excludeFromSemantics: true` or sits under
  `ExcludeSemantics`;
- an unlabeled `TextField` or `TextFormField`.

A `Semantics` ancestor names its subtree only with `label:`, `tooltip:` or `excludeSemantics: true`.
A call chained on a widget (`.animate()`) and `IconButton.styleFrom` are not widgets. Known holes,
each a candidate the runtime may refute: an `Icon` in an `InkWell` under `MergeSemantics`, an icon
in a control named by its `child:` (`MenuItemButton`) or by a default tooltip (`PopupMenuButton`),
and an `IconButton` under a labelled `Semantics`, which is still reported.

Read `filesScanned` before reading the findings: `0 findings` with `filesScanned: 0` means the path
was wrong, not that the code is clean. And pass `<app-root>/lib`, never `<app-root>` — the probe
scans every `.dart` file under whatever directory it is given, `test/` included, so on the bundled
fixture `<app-root>` reports 3 candidates inside `test/`, which is not the app, and would scan the
walker this skill just generated as well. Generated `*.g.dart` files and macOS `._*.dart` files are
skipped and not counted; a source with a stray non-UTF-8 byte is read leniently, as Dart reads it.
Each finding's `file` is relative to the directory passed in, so with
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
and `test_driver/ux_journey_driver.dart` (never over an existing file of that name — see
`references/walking.md`, File 1), add `integration_test` to dev_dependencies, start from a clean
install (see *Credentials* above), and run:

```bash
flutter drive --driver=test_driver/ux_journey_driver.dart \
              --target=integration_test/ux_journey_drive.dart -d <device-id>
```

then copy `build/integration_response_data.json` into the output dir as `walk.json`. The PNGs are
already there: the driver empties `ux-audit-out/screens/` and writes them straight into it. The
drive entry is offline by default — `NetworkCut` refuses every `HttpClient` request and lists it in
`networkCalls`.

Per step the walk records, besides the semantics dump and the four guidelines:

| Field | What it is for |
|---|---|
| `surface.canPop` / `tappableCount` / `modalOpen` / `navigatorCount` | `DEAD-END` as a measurement instead of a selector miss. `modalOpen` is true for a dismissible barrier, for any barrier the SDK labels (a dialog that must be answered) and for an open drawer |
| `semantics.viewport` (`foldY`, `contentTop`, `keyboardInset`, `isTestDefault`, `textDirection`) | what is on screen without scrolling — and when that is not knowable. Under `flutter test` a `type` step raises a test keyboard with no height, so while it is up `keyboardInset` and `foldY` are **null**, not a measurement. `textDirection` is the app's own `Directionality` |
| per-node `onScreen`, `aboveFold`, `coversSurface` | what is really on the surface — cache-extent rows and nodes clipped to nothing (`isHidden`) are in the dump too, and the full-screen keyboard-dismiss `GestureDetector` must be excluded from placement. A merged child (a `SwitchListTile`'s `Switch`) is part of its parent's node, not a second entry |
| per-node `effectivePct`, `centreCovered`, `obscuredBy` | controls that are nominally big enough but partly covered |
| `tapsSoFar` | reach cost on the declared path: landed taps and long presses |
| `drags` | a `scroll until` step's drags; the run total is top-level `drags`, kept apart from `taps` because scrolling is not reach cost |
| `dispatched`, `semanticsUnchanged`, `screenSig` | dead taps, revisits, state loss. The signature hashes labels, tooltips, values and the state flags `isChecked`, `isCheckStateMixed`, `isToggled`, `isSelected`, `isExpanded`, so a working checkbox or chip reads as a change |
| `expectedBefore` | the oracle already held before the action — `expected` on screen, or for `expect no`, already gone. The status is unchanged; the report treats the step as **not proven** |
| `absent` | the step's tail was `expect no "Y"`: the oracle required Y to be gone |
| `resolved` | `{label, tooltip}` of the node the target resolved to, so a mis-resolution leaves a trace. Null for `back`, `system back` and a selector miss |
| `centreHitsHandler` | tap and long-press only: did a real hit test at the press point cross a matching handler? `false` is a press into dead space (a merged row whose centre falls between its label and its switch) |
| `popHandled` | `system back` only: did anything in the app take the pop? `false` fails the step, because on Android the app would close |
| `settled` | did the step's expectation arrive and the frame queue go quiet within the bound, AFTER its action. `null` when nothing was dispatched, so no settle ran. Because each step's dump is taken before its own action, step N's `settled` describes step N+1's dump — see [3] |
| `semantics.panesPossiblyBlocked` | true: the dump saw only the last-painted pane — two sibling `Navigator`s, so the report says `not assessable` for the other rather than clean. False is a declared *suspicion*, not a guarantee the dump is whole |
| `conditions` (top level, once per run) | the brightness, text scale, locale and accessibility flags the numbers above were measured under — the ones `## Device` declared, or the test defaults — plus `mode` (`widget-test` or `drive`), `deviceProfile` (or `<name> (default, not declared)`), `fontSource`, `renderer` and `targetPlatform`. `fontSource` is `app` (the app's own fonts are loaded; text in a family the app does not declare still uses the SDK stand-in, so close, not exact), `sdk-fallback` (the SDK's Roboto standing in — close, not exact) or `none` (fold and placement **not assessable**). `appErrorHandlerReplaced` and `httpOverridesReplacedByApp` say the app installed its own error handler or HTTP override during the walk; `appErrors` is complete either way, and the walk kept its network barrier. The scope clause quotes all of it. `platform` is the HOST under `flutter test`, which is why `targetPlatform` is separate |
| `setupSteps` (top level) | the `## Setup` phase, recorded beside `steps` and never merged into it: no semantics dump, no guidelines, no reach cost. A setup step carries a `screenshot` only when it failed (`setup_N.png`) |
| `setupFailed` (top level) | true: the walk never reached the journey's starting line, and `steps` is empty by construction |
| `entryReached`, `entryScreenshot` (top level) | `false`: the first setup or journey target never reached the semantics tree within 12 s of launch. With `steps` empty, no app came up at all (no `Navigator`) and `entry.png` shows what was there instead. With steps, the app was up and the walk went on: the target is unlabelled or not there, which step 1 reports. `null`: there was nothing to wait for |

`networkCalls` means something different per posture, and the report says which:

- a stub installed: the paths the stub answered — wire `networkCalls: stubCalls`, or the field
  ships empty (`references/network-stub.md`);
- the drive entry's `NetworkCut`: the paths it refused;
- `flutter test` with no stub: always `[]`, because flutter_test's 400 records nothing. Empty there
  does not mean the app made no requests; `appErrors` usually shows the ones that failed.

None of the three sees the traffic listed under *Credentials* → *The boundary*.

**Neither mode's exit code is the oracle. Read the JSON.** Both exit 0 even when every journey step
failed — by design, because the walker collects Evaluations and step errors instead of asserting
(asserting would also discard the JSON and, under `flutter drive`, the PNGs, since
`writeResponseOnFailure` defaults to false). Judge the run by reading `steps[].status` in
`walk.json`, never by `$?`. A green exit with three `FAILED` steps is the normal shape of a journey
that hit a real defect.

**No PNGs but a green run**, in the `flutter drive` fallback **on iOS**, means the recipe was
mis-copied: `takeScreenshot` appends into `reportData['screenshots']`, so assigning a fresh map to
`reportData` at the end deletes them all silently. See the MUTATE-never-replace note in
`references/walking.md`. On Android under drive there are no in-test PNGs by design (see [3]). In
the default mode there is no such hazard — the walk writes each PNG straight to disk, after
deleting the previous run's — but a step whose `screenshot` is null still means its capture failed,
and the VISUAL layer for that step is `not assessable`.

**If `entryReached` is false and `steps` is empty, stop.** No app came up within 12 s, so no step was
walked; `entryScreenshot` is what showed instead — a splash, a loading screen, a gate the journey
did not declare. Report that, not an empty journey. If `entryReached` is false but steps were
walked, the app was up and the first target never appeared: an icon-only control with no label is
the usual cause, and step 1's failure plus `labeledTapTargetGuideline` are the finding.

**If the run dies during `## Setup`, stop.** The walk says so itself: `setupFailed: true`, the last
entry in `setupSteps` carries the error and its `setup_N.png`, and `steps` is empty. Report a setup
failure with what blocked it. Do not report the setup steps that did run as a journey — a journey
that never started has no findings.

If a journey step fails (the target is not on screen, or the expected outcome never appears), that is
itself a finding — record the step as `FAILED`, keep its screenshot, and continue only if the next
step does not depend on it. Two failures are about the journey file, not the app: a target wholly
below the fold with no `scroll until` before it, and `ambiguous: N nodes match` (add `nth:`). Fix the
journey and re-run rather than reporting either.

## [3] VISUAL — look at the screenshots

Read every `screens/step_*.png`. No script; the model does this.

**In the default mode every step has a PNG, whatever `targetPlatform` says** — the capture is the
golden-file path and needs no device. Only a platform view's area comes out blank; say
`not assessable` for that area, not for the screen.

**In the `flutter drive` fallback on Android there are none.** The drive entry gates in-test
screenshots on `Platform.isIOS`, so every step's `screenshot` is null and this whole layer is
`not assessable` — say that, and say which checks it takes down with it. Two cannot fire without a
pixel comparison: `FAKE-AFFORDANCE` in its dead-tap mode, whose second layer is `cmp` on consecutive
PNGs, and the effective-area variant of `TOUCH-TARGET`, whose `effectivePct` is geometry until an
image confirms it. A host capture (the `adb exec-out screencap` form is in `references/walking.md`)
documents the end state only, one frame after the walk, so it supplies neither — it is evidence for
the last screen, not for a transition.

Look for what the semantics tree cannot say: overflow stripes and clipped text, content hidden behind
a sheet, an empty state that looks like a failure, a primary action that is not the most prominent
thing on screen, an element styled as tappable that carries no tap action in the walk data (and the
reverse), a screen that gives no way back. Content hidden behind the keyboard is **not assessable**
in the default mode: the headless PNGs have no keyboard in them.

Two things in the PNGs are the walk, not the app. Flutter's red image-error box, carrying text like
`HTTP request failed, statusCode: 400, <url>` or `Exception: Invalid image data`, is what a debug
build paints when a network image fails under the cut or the stub; a release user never sees it. It
is also in the semantics dump, so never raise `JARGON-LEAK` or `ERROR-VAGUE` on a label that equals
an `appErrors` entry. Flutter's red `ErrorWidget` for a build exception shows only in the PNG, never in
the dump; its cause is in `appErrors`.

When eye and measurement disagree, **geometry is settled by the measurement** (rects, ratios) and
**meaning is settled by the eye** (is this actually the primary action?).

Two things the visual pass is now the second layer for, and must actually be run:

- **Dead taps.** A `tap` or `long-press` step with `dispatched: true`, `semanticsUnchanged: true`
  and `centreHitsHandler: true` is a candidate, not a finding: a control that only repaints is
  byte-identical in semantics to one wired to nothing. `cmp -s screens/step_N.png
  screens/step_N+1.png` settles it for free. Identical pixels AND identical semantics →
  `FAKE-AFFORDANCE`. Differing pixels with identical semantics is its own finding: a state change
  assistive technology cannot see. `centreHitsHandler: false` is a press into dead space between a
  control's parts — report the target's geometry, not a dead control. On a screen whose labels
  change on their own (a countdown, a clock, a "resend in 59s"), `semanticsUnchanged: false` proves
  nothing, so the dead-tap check is `not assessable` there.
- **Partly covered controls.** `effectivePct < 1.0` is geometry, not a hit test — the semantics tree
  has no opacity and no `IgnorePointer`. Look at the screenshot before reporting it. **Void a
  dump's geometry when the screen it was taken on had not settled**: step N's dump comes after step
  N−1's action, so it is void when step N−1's `settled` is `false` (step 1's when `entrySettled` is
  false). The outcome entry settles before its own capture, so its own `settled` speaks for it.
  `settled: null` means nothing was dispatched and the screen did not change, so the next dump is
  as good as the one before it.

## [4] MERGE + RESCORE — one report, scored, with a direction

Follow `references/heuristics.md`: assign each observation a Named Check ID, merge the layers,
dedupe, then rescore every finding **against the journey's goal**. No script; the scoring is the
judgement. Five checks now have a **measurement predicate** and do not fire without it.

**Open with a verdict, not a table.** Two or three sentences in the words a user would use, naming
what happens to the person trying to do this and what stops them — no check IDs, no widget names.
Then one clause of scope, quoting `conditions` from the walk data rather than asserting it: one
declared path, walked once, one device size, the brightness, text scale and locale the run recorded,
whether `## Device` declared them, and the network posture (cut, stubbed, and anything the pre-walk
check found outside the cut). A reader who meets a feature map and a score table before a single
defect stops reading.

**An `OK` step with `expectedBefore: true` is not proven.** Its expectation was on screen (or, for
`expect no`, already gone) before the action, so the oracle passing says nothing about what the
action did. Keep its status, mark it `OK (not proven)` in the step table, never cite it as evidence
that the journey reached its goal, and list it under Not Assessable.

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
| Screen stability | steps that settled / steps with a non-null `settled` (a never-dispatched step settled nothing) |
| Reach | taps on the declared path; screens with a way out / screens visited |
| Error handling | qualitative — mark it as such |

`appErrors` is evidence for Error handling, quoted with care: paraphrase it rather than pasting it,
because an entry can carry a full request URL, query string included. An image that failed under the
cut or the stub is a walk artifact (see [3]), not an error-handling finding.

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
