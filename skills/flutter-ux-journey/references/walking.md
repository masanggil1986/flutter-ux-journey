# walking.md — the runtime recipe

Every API call below was executed — the measurements against an iOS simulator (iPhone SE 3rd gen,
iOS 18.6, Flutter 3.47.2 stable), and the headless path under `flutter test` on the same fixture,
checked step by step against that simulator run. Signatures are verbatim from the SDK. Do not
substitute remembered ones.

- [Why the walker runs inside the app](#why-the-walker-runs-inside-the-app)
- [Prerequisites in the audited app](#prerequisites-in-the-audited-app)
- [Two modes, and which files each one needs](#two-modes-and-which-files-each-one-needs)
- [File 1 — test_driver/integration_test.dart (fallback only)](#file-1--test_driverintegration_testdart-fallback-only)
- [File 2 — ux_audit/ux_journey_test.dart](#file-2--ux_auditux_journey_testdart)
- [Trap 1 — semantics rects are local and physical](#trap-1--semantics-rects-are-local-and-physical)
- [Trap 2 — tooltip is not the label](#trap-2--tooltip-is-not-the-label)
- [Trap 3 — InkWell has no isButton flag](#trap-3--inkwell-has-no-isbutton-flag)
- [Trap 4 — a step that never dispatched is not a dead tap](#trap-4--a-step-that-never-dispatched-is-not-a-dead-tap)
- [Trap 5 — the Rect inside a guideline reason is not the screen rect](#trap-5--the-rect-inside-a-guideline-reason-is-not-the-screen-rect)
- [Trap 6 — Infinity reaches the JSON](#trap-6--infinity-reaches-the-json)
- [More traps, measured](#more-traps-measured)
- [Running it and collecting the artifacts](#running-it-and-collecting-the-artifacts)
- [What the walk data must contain](#what-the-walk-data-must-contain)

## Why the walker runs inside the app

Structured semantics is reachable **only from inside the test process**. Over the VM service there are
exactly two semantics extensions and both return one prose string; the 32 `ext.flutter.inspector.*`
extensions contain no semantics at all and no global geometry. So the walker is a generated
`integration_test`, not an external driver.

The payoff: `tester.tap` throws when the finder does not match, so the walk reports a **result**, not
a dispatch. And the four built-in accessibility guidelines run in-process and return node-level
failures with the measured value and the required value already attached.

**Never reimplement tap-target size or contrast checking.** It exists, it is calibrated, it is free.

## Prerequisites in the audited app

`pubspec.yaml`:

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:   # only for the `flutter drive` fallback
    sdk: flutter
```

Nothing else. No third-party package is needed at any point.

Tell the user to gitignore the generated paths (see SKILL.md) — including `net_stub.dart` when a
stub is used, which is the only one that holds their real endpoints. They are regenerated on every
run; a team that wants them as a regression test promotes them deliberately.

## Two modes, and which files each one needs

| | default | fallback |
|---|---|---|
| run | `flutter test ux_audit/ux_journey_test.dart` | `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/ux_journey_drive.dart -d <id>` |
| device | none | a booted simulator or emulator |
| files in the app | `ux_audit/ux_journey_test.dart` (+ `ux_audit/net_stub.dart` for a gate) | those, plus `integration_test/ux_journey_drive.dart` and `test_driver/integration_test.dart` |
| dev_dependencies | `flutter_test` | `flutter_test` and `integration_test` |
| screenshots | `OffsetLayer.toImage()`, any host | `takeScreenshot`, iOS only |
| network | already cut: `flutter_test` answers every request with an empty 400 | cut it yourself (`adb shell cmd connectivity airplane-mode enable`) |
| artifacts | the walk writes `ux-audit-out/walk.json` and `screens/*.png` itself | `build/integration_response_data.json`, copied to `ux-audit-out/walk.json` |

**`ux_audit/` is not a style choice.** `flutter test` routes anything under `integration_test/` to a
device runner on the directory NAME alone (`flutter_tools/commands/test.dart`,
`_kIntegrationTestDirectory`) and there is no flag to stop it, so a walker placed there fails with
"No devices are connected". `ux_audit/` is also outside `test/`, so a bare `flutter test` in the
audited app does not sweep the walker into that app's own suite.

The fallback exists for one measured reason: the walk has not been run against an app whose plugins
throw `MissingPluginException`, and platform views do not render headlessly at all. Neither mode
changes a line of the app's source.

## File 1 — test_driver/integration_test.dart (fallback only)

Verbatim, whole file. The `responseDataCallback` strip is not optional: `takeScreenshot` also stuffs
every PNG into `reportData['screenshots']` as a JSON int array, which turned a 45 KB PNG into a
561 KB JSON in the verification run.

```dart
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      // ONE output root, the one SKILL.md declares. `screenshots/` — the
      // default this file used to write — is a conventionally TRACKED
      // directory in a Flutter app, so a walk against somebody's repo dropped
      // their product screenshots where `git add -A` would take them.
      final File f = File('ux-audit-out/screens/$name.png');
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(bytes);
      return true;
    },
    // The PNGs already went to disk above. takeScreenshot ALSO stuffs each one
    // into reportData['screenshots'] as a JSON int array, which inflated a
    // 45 KB PNG into 561 KB of JSON in the Day 1 run.
    responseDataCallback: (Map<String, dynamic>? data) async {
      data?.remove('screenshots');
      await writeResponseData(data);
    },
  );
}
```

SDK signatures this relies on (`packages/integration_test/lib/integration_test_driver_extended.dart`):

```dart
typedef ResponseDataCallback = FutureOr<void> Function(Map<String, dynamic>?);
typedef ScreenshotCallback =
    Future<bool> Function(String name, List<int> image, [Map<String, Object?>? args]);

Future<void> integrationDriver({
  FlutterDriver? driver,
  ScreenshotCallback? onScreenshot,
  ResponseDataCallback? responseDataCallback = writeResponseData,
  bool writeResponseOnFailure = false,
});

Future<void> writeResponseData(Map<String, dynamic>? data,
    {String testOutputFilename = 'integration_response_data', String? destinationDirectory});
```

## File 2 — ux_audit/ux_journey_test.dart

**The source of truth is the file that actually runs:**

```
<root>/example/ux_demo_app/ux_audit/ux_journey_test.dart
```

`<root>` is the directory SKILL.md's probe command runs from — the one holding `skills/`, `tools/`
and `example/`, two levels above the skill's own folder. Claude Code substitutes
`${CLAUDE_PLUGIN_ROOT}` in SKILL.md only, never in this file, so the token is not written here.

Read it and copy it. It is not sketched here on purpose — a second copy in prose drifts from the one
that was executed, and every trap below was found by executing it. It is over a thousand lines, it
has no dependency outside the Flutter SDK, and it carries its own comments explaining every
non-obvious line.

**Five things change per app, and nothing else:**

1. the `package:<app>/main.dart` import,
2. the `journey` list, generated from `## Steps` in `journey.md`,
3. the `setup` list, generated from `## Setup`, plus `HttpOverrides.global = StubHttpOverrides();`
   ahead of the launch if the journey has to pass a gate (`references/network-stub.md`),
4. `networkCalls`, wired to the stub's own call list when there is a stub,
5. `device` and `deviceDeclared`, generated from `## Device`. Name the preset through
   `deviceProfileByName('<name>')` rather than pinning a const, so a journey that names a screen
   the walker does not know fails there instead of being measured on one nobody chose. When the
   journey declares no `## Device`, keep `iphone-se` and set `deviceDeclared = false` — the report's
   scope clause quotes the difference, and `test/recipe_sync_test.dart` checks the two agree.

   Only `iphone-se` is a preset. Any other screen is written as a record literal, in the SAME units
   the journey uses — **logical px**, which is also what `viewportOf` reports back. `applyDevice`
   does the `devicePixelRatio` multiplication; nothing here is physical px:

   ```dart
   // ## Device: 411.4x731.4 @2.625 contentTop 24 padBottom 24, android
   final DeviceProfile device = (
     name: '411.4x731.4@2.625',
     logicalSize: Size(411.4, 731.4),
     devicePixelRatio: 2.625,
     contentTop: 24.0,
     padBottom: 24.0,
     targetPlatform: TargetPlatform.android,
   );
   const bool deviceDeclared = true;
   ```

   `targetPlatform` has no `## Device` field because it follows from the screen; pick the one the
   journey is about. It is what the framework is told to be, and it changes which typography the
   theme asks for — which is what `loadFonts` registers against.

The rest of this file explains *why* the parts that look replaceable are not.

### The walk is entered through `walkJourney`, which does not launch the app

`walkJourney(tester, launch:, journey:, setup:, networkCalls:, shot:, publish:, runContext:)` takes
the launch as a CALLBACK and calls it itself.

It takes **no binding**. Everything the walk used to reach for on one arrives injected: `shot`
takes a screenshot or is null (and null means the VISUAL layer is `not assessable`, which the
report must say), `publish` receives the finished report, and `runContext` carries what only the
entry knows — `mode`, `renderer`, `targetPlatform`, `deviceProfile`, `fontSource`. That is what
lets one walk serve both modes, and `test/recipe_sync_test.dart` pins it: the walk must not import
`package:integration_test/` at all. That is not indirection for its own sake: a network stub has to be in
place before the app's first frame, and handing over `app.main` rather than calling it is the only
way a caller gets in front of that. Measured on the gated fixture, whose session probe fires on the
first frame — an override installed after the launch is already too late.

`walkJourney`, `performStep` and `resolve` are public, as are the measurement helpers. This changes
nothing about what the skill generates: the file it writes into somebody else's app is still ONE
file — consts, `main`, the walk and the helpers together — because an app under audit should gain
one file and no structure.

What it buys is a SECOND journey in a repo that already has one. That file imports `Step` and
`walkJourney` from the first and adds only what is genuinely per-journey: the stub, the `setup`
list, the `journey` list, and a `main` that installs the override and calls the walk. The worked
instance is `example/ux_demo_app/integration_test/gated_journey_test.dart` — 105 lines, 67 of them
code, and nearly all of that is the two step lists. Run it by pointing `--target` at it.

### The Setup phase — a gate is not the product

`## Setup` becomes the `setup` list, walked before the journey and kept out of the score. Setup
steps get no semantics dump, no guideline evaluation and no reach cost. Measured, that exclusion
holds: the gated fixture run and the ungated one report the same `taps: 2` and the same per-step
`tapsSoFar` (1, 2, 2, 2), although the gated one also tapped once to get through the gate.

They are recorded anyway, in `setupSteps[]` beside `steps[]`. A run that dies at the gate must say
`setupFailed: true` and ship an EMPTY `steps[]`; reporting the steps that did run as a journey
describes a short healthy app that does not exist.

A setup step is screenshotted only when it FAILS, as `setup_N.png`. That one image is the whole
evidence for "the gate is what blocked this", and a setup step that passed has nothing to show.

A `type` step's recorded `text` comes from the journey file and not from the screen, so
`obscureText` does nothing to keep it out of the artifact — measured: `not-a-real-password` landed
verbatim in the first run that produced `example/walk-gated.json`. When the resolved field hides its
own value the walker now records `<redacted N chars: ...>` and keeps the length. Journeys are
required to use arbitrary data anyway; this exists because "required" is not "guaranteed", and an
audit artifact is the last place anyone should have to be careful.

### Collecting the four built-in guidelines

Never re-implement these. They return a pixel Rect, the measured value and the required value in
one string, and they are `const` in `package:flutter_test` — zero dependencies, already calibrated.
Collect the `Evaluation`; do not assert on it, or the first violation aborts the walk and throws
away the JSON and the PNGs.

```dart
Future<List<Map<String, Object?>>> _evaluateGuidelines(WidgetTester tester) async {
  final List<Map<String, Object?>> out = <Map<String, Object?>>[];
  for (final AccessibilityGuideline g in <AccessibilityGuideline>[
    iOSTapTargetGuideline,
    androidTapTargetGuideline,
    textContrastGuideline,
    labeledTapTargetGuideline,
  ]) {
    final Evaluation e = await g.evaluate(tester); // collect, never assert
    out.add(<String, Object?>{
      'guideline': g.description,
      'passed': e.passed,
      'reason': e.reason,
    });
  }
  return out;
}
```

### The app's own errors are findings, not a reason to abort

A production app fires background requests that outlive a step. One late async exception fails the
test and **discards the entire report** — measured: a voucher fetch completing after the walk threw
away a nine-step journey. Collect them instead, before `app.main()`:

```dart
final List<String> appErrors = <String>[];
final FlutterExceptionHandler? previousOnError = FlutterError.onError;
FlutterError.onError = (FlutterErrorDetails details) {
  appErrors.add(details.exceptionAsString());
};
...
FlutterError.onError = previousOnError; // the moment the walk ends
report['appErrors'] = appErrors;
```

Hand the handler back. Kept, it swallows every failure after the walk — a timer the app left
running, an `expect` in the same test — into a list that is already published, and flutter_test
waits out its ten-minute timeout and then blames whoever last touched `FlutterError.onError`.
Measured: an `expect(1, 2)` after the walk hung past 60 s; handed back, it failed in 2 s with the
real message.

What lands there is evidence in its own right. An app that shows the user
`type 'Null' is not a subtype of type ...` is leaking internals into the UI — a real severity-3
finding, measured on a production app.

### Bounded settle — never call `pumpAndSettle` on a real app

`pumpAndSettle` waits for the frame queue to go quiet, and only gives up after a
**10-minute default timeout**. Any app that animates continuously — a spinner, a looping splash, a
network-wait indicator, a shimmer placeholder — never goes quiet, so the walk hangs and produces
nothing. A purpose-built demo fixture has no such animation, which is why this surfaces only when
the tool meets a production app. Measured: a real app hung here until killed.

`settle()` replaces it with a bound. Two things about that bound were wrong in the obvious version:

**"No frame is scheduled" is not "the screen is ready."** An awaiting `Future` schedules no frames,
so a screen that renders an empty state while a request is in flight reports settled on the first
pump. The step then fails to find what it expected, is recorded FAILED **with the wrong reason**,
and carries `settled: true` — which is also the flag that is supposed to void its measurements.
Measured. So when the step declares an expectation, that expectation is the stop condition: the
loop polls it and returns true only when the content really arrived.

**The Stopwatch is not the same clock as the pump.** `tester.pump(tick)` advances FAKE time while a
`Stopwatch` measures real time, so under `flutter test` the loop runs thousands of iterations inside
one real second and simulates minutes of app time. Bound by the pump COUNT as well as the wall
clock, or the limit means something different in a widget test than it does on a device.

Record the result as `settled` per step. `settled: false` is worth reporting on its own: a screen
still working after the bound is either doing real work with no progress affordance, or animating
forever for no reason.

### Screenshots deadlock on Android when the app hosts platform views

**This is the fallback path's problem alone.** The default mode captures through
`OffsetLayer.toImage()` — the path golden files take — which needs no platform surface and cannot
deadlock. What it cannot do is render a platform view at all: that area comes out blank, and the
report says `not assessable` for it rather than describing an empty rectangle.

`convertFlutterSurfaceToImage()` + `takeScreenshot()` **hangs** — no error, no timeout — on Android
when the app embeds platform views (a webview, a video/media surface, a camera preview). Measured
on a production app: the four guidelines and the semantics dump completed normally, and the run
then stopped dead at the first `takeScreenshot`.

There is no in-test workaround. Capture the VISUAL layer from the HOST instead:

```bash
adb exec-out screencap -p > step_1.png          # Android
xcrun simctl io <udid> screenshot step_1.png    # iOS simulator
```

If neither is available for the run, the VISUAL layer is **not assessable** and the report says so.
Do not silently ship a report whose visual section is empty — an empty section reads as "nothing
wrong here", which is the one thing this tool exists not to do.

### Typing: `tester.enterText`, never `testTextInput` directly

Only `tester.enterText(finder, text)` establishes the text-input connection — it calls
`showKeyboard` first. Tapping a field and then pushing text through `tester.testTextInput.enterText`
leaves the field **empty and the walk hanging**, with no error. Measured on a production app.

`enterText` needs a `Finder`, but the selector model is label-based, so the walker maps the resolved
semantics node to its `EditableText` by geometry. Text entered is always ARBITRARY — see
"Credentials: never ask for them" in SKILL.md.

### Ambiguity: exact match, then `nth`, then fail loudly

A substring selector legitimately matches both a label and a longer label containing it — a password
field and a "forgot password" link, measured on a real app. When exactly one hit matches **exactly**,
that is the one meant.

But two nodes can match EXACTLY and both be real: a shortcut tile and a bottom-nav tab often carry
the same word. No matching cleverness can guess which; the journey must say, with `nth: N`
(1-based). Taking the first hit silently audits a different widget and reports its measurements as
the one you asked for.

Make the error name the candidates and the fix, because each re-run is a full build:

```
ambiguous: 5 nodes match "Orders" — 1=Your Orders @85x27, 2=No orders yet @149x21,
3=View orders @371x56, 4=Orders @79x53 ... Add nth: N to pick one.
```

### Measuring placement — the fold, and controls that are covered

Three cheap fields turn "where is this control" from an impression into arithmetic. All three were
wrong in their obvious form; each is wrong in a way that looks right.

**The fold.** `view.physicalSize / devicePixelRatio` is the WHOLE display: it includes the status
bar, the notch and the home indicator, and it does not shrink when the keyboard is up. Subtract
`view.padding` and `view.viewInsets`, and take the LARGER of the two bottoms — a keyboard hides far
more than a home indicator, and a control under it is not on screen at all.

And in a plain `flutter test` the view is Flutter's hardcoded `Size(800, 600)` at dpr 3.0
(`flutter_test/src/binding.dart`, `_kDefaultTestViewportSize`). That is no device. The walker
reports `isTestDefault: true` and `foldY: null` so the report blanks every fold column rather than
quoting a fold line for a phone that does not exist.

Which is why the default mode does not leave the view alone: `applyDevice` sets it from the
journey's `## Device` section, and `iphone-se` is defined to reproduce `example/walk.json`'s own
numbers exactly — 375.0 x 667.0 @ 2.0, contentTop 20.0, padBottom 0.0, foldY 667.0, asserted in
`test/walker_test.dart`. It is the only preset that ships, because it is the only one a committed
artifact reproduces in every field. An unknown preset name THROWS rather than substituting a
default: a report measured at a screen nobody asked for says nothing about where that screen's
fold is. For anything else a journey names explicit numbers, and the walker takes them as a record
literal — see item 5 above for the worked shape. `DeviceProfile` speaks logical px throughout for
exactly this reason: the journey writes `375x667`, the profile says `375x667`, and no transcription
can quietly turn it into a 187.5x333.5 surface.

**Text metrics are the other thing the device used to supply.** `flutter test` draws every glyph as
an em square, and that is not cosmetic — measured against the simulator baseline, the fixture's
title went 112.3px to 242.0px, two text blocks wrapped to an extra line each, and the whole product
list moved down 39px. Max drift 153.6px. `loadFonts` brings it to a median of 0.0px. Loading a font
is not enough on its own: a null `fontFamily` keeps resolving to the test font whatever is
registered, so the registration has to name the families the THEME asks for
(`CupertinoSystemDisplay`/`CupertinoSystemText` on iOS, `Roboto` on Android). The older `.SF UI *`
spelling is never asked for and registering against it fails silently. `conditions.fontSource`
reports which fonts the run actually got, and `none` makes fold and placement `not assessable`. Measured on an iPhone SE (3rd gen) the same
code returns `375.0 x 667.0 @ 2.0, contentTop 20.0, padBottom 0.0, foldY 667.0` — the SE has a home
button, so its bottom padding really is zero.

**Effective (unobscured) tap area.** A control can pass every size check and still be unhittable:
its own rect never changes when something lands on top of it. Measured on a production app, an
error banner cut a 56 dp CTA to 17.2 dp of visible target while the CTA still reported 56 dp.
`subtractRects` splits the target around every later-painted, non-descendant node that intersects
it, and `centreCovered` answers the question the walk actually depends on — the walker taps the
CENTRE, so a covered centre means its own tap lands on the overlay. The fixture reproduces the same
failure SHAPE, not the same number: a 48 dp CTA under a banner keeps a 16 dp strip, 33.3% of its
area, against production's 17.2 dp of a 56 dp CTA, which is 30.7%. What repeats is the part that
matters — the control's own rect never moves, so every size-only check still passes it, and the
centre is covered. `test/walker_test.dart` pins the fixture case.

Two exclusions are load-bearing. Ancestors are excluded by coming first in paint order; descendants
have to be excluded explicitly by walking the parent chain, or every card obscures itself with its
own label.

This is **geometry, not a hit test**: the semantics tree carries no opacity and no `IgnorePointer`.
It needs the screenshot to confirm before it becomes a finding, and it is void on any step where
`settled` is false.

**Screen identity.** A hash of every non-empty label ∪ tooltip ∪ value, each part prefixed with its
RANK in reading order (top, then left) before the parts are sorted. Equal signatures mean the same
screen in the same state, which is what makes state loss after a back step and a dead tap checkable.

The prefix is not decoration: without one, sorting throws order away and every sort, reorder and
move-up control in existence reads as a dead tap. It is a rank and not a quantised pixel position
because a pixel bucket puts its edge on Material's own 8-dp grid, where a 0.02 lpx relayout flips
the hash — measured. Rank is what a reorder actually changes. And the signature is deliberately NOT
a template id: see `references/heuristics.md` → **Mechanisms measured and refuted**.

### Route state — DEAD-END as a measurement

`DEAD-END` used to ride on a selector miss ("no semantics node matches \"Back\""), which is evidence
that the journey's author guessed a label, not evidence about the app. The predicate is now measured:
`canPop == false` and `tappableCount == 0` and `modalOpen == false`, on a screen that is not the
journey's entry. On the fixture's removal screen all four terms hold, and every one of the four
accessibility guidelines passes on that same screen — which is the whole argument for auditing
journeys instead of screens.

`canPop` comes from the **deepest onstage `Navigator`**, read directly. Two earlier versions were
measured wrong: `tester.firstState<NavigatorState>(...)` returns the ROOT navigator, which in a tab
shell holds only the shell page; and resolving from the deepest `Scaffold` is a different thing,
because in the common shell-owns-the-Scaffold shape that Scaffold sits *above* the per-tab
Navigators. Finders are onstage-only, so hidden tabs do not compete, and reading the Navigator
directly also answers on screens with no Scaffold at all.

Nothing in the walker calls `ModalRoute.of`: it registers an inherited dependency on the audited
app's element, so reading it can make the app rebuild. An audit must not perturb what it measures.
`Navigator.maybeOf` and the element-list probe do not.

`modalOpen` keys on the barrier's **dismissibility**, not its type. Every `ModalRoute` mounts a
barrier, so `find.byType(ModalBarrier)` is true on every ordinary screen; narrowing to
`AnimatedModalBarrier` then misses popup menus and dropdowns, which return a null `barrierColor`.
A page route's barrier is not dismissible; a transient surface's is.

## Trap 1 — semantics rects are local and physical

`SemanticsNode.rect` is in the node's own coordinate space and `SemanticsNode.transform` maps it into
its parent. Without accumulating the chain with `MatrixUtils.transformRect`, every nested element
reports `(0,0)` and the whole tap-target heuristic becomes garbage — and it looks fine on a flat
happy-path screen. The accumulated rect is in **physical** pixels: divide by
`tester.view.devicePixelRatio` for logical px, exactly as `MinimumTapTargetGuideline` does.

## Trap 2 — tooltip is not the label

`tooltip:` does **not** populate the semantics label; it lands in a separate `tooltip` field. A matcher
that reads only `label` misses every tooltip-only icon button. Sibling `Text` widgets are also merged
into one label joined by `\n`, so exact-match on label fails on ordinary cards. Hence: match over
label ∪ tooltip ∪ value, whitespace- and newline-normalised, substring — and **error on ambiguity**
rather than picking the first match, because picking the first match silently audits a different
widget than the user meant.

## Trap 3 — InkWell has no isButton flag

`InkWell` exposes a tap action but not the `isButton` flag. Enumerate tap targets by
`data.hasAction(SemanticsAction.tap)`, never by flag — filtering on `isButton` deletes most of a real
app's tap targets and leaves a report that looks clean.

## Trap 4 — a step that never dispatched is not a dead tap

A step that fails while RESOLVING its target never touched the app, so "the semantics did not
change" is trivially true. Record `dispatched` and leave `semanticsUnchanged` null when it is false,
or every selector miss reads as a control that does nothing — measured on the fixture's step 3.

And a dispatched tap whose semantics did not change is still only a candidate: a control that merely
repaints is byte-identical to one wired to nothing. Confirm against the screenshots.

## Trap 5 — the Rect inside a guideline `reason` is not the screen rect

`SemanticsNode.toStringDeep` prints `rect.shift(offset)` — the node's own rect plus **one**
transform, not the accumulated chain. So the `Rect.fromLTRB(...)` inside a guideline's `reason`
string and the walker's own `rect` field disagree on position for any nested node, and the fixture
shows it: the same control reads `Rect.fromLTRB(319.0, 12.0, 343.0, 36.0)` in the reason and
`[335.0, 104.0, 24.0, 24.0]` in the dump.

**Sizes are comparable; positions are not.** Quote the reason for the node, the measured value and
the required value; take the POSITION from the dump. A report that prints both without saying so
looks like it contradicts itself — and a reader who notices stops trusting the rest.

## Trap 6 — Infinity reaches the JSON

`jsonEncode` throws on a non-finite double — at encode, not decode — and a throw there loses the
whole step's dump and every measurement on that screen with it. Found the expensive way: a
scrollable's `scrollExtentMax` is `Infinity` on any `ListView.builder` with no `itemCount`, and
dumping it lost the step. Keep the dump to JSON primitives and finite doubles;
`test/walker_test.dart` round-trips it, so a future field cannot quietly break a run.

## More traps, measured

`scopesRoute` as depth, `namesRoute` as a screen name, quantised-rect "template" signatures,
`find.byType(ModalBarrier)`, `AnimatedModalBarrier`, `firstState<NavigatorState>`, resolving the
navigator from the deepest `Scaffold`, refusing a tap on a covered centre, a sorted-multiset
signature, a wall-clock-only settle bound, counting a tap before it lands — each of these looks
right, is cheap, and is wrong. They are recorded with what actually happens in
`references/heuristics.md` → **Mechanisms measured and refuted**. Read that before re-proposing one.

## Running it and collecting the artifacts

Default — no device:

```bash
cd <app-root>
flutter test ux_audit/ux_journey_test.dart
```

Artifacts land at `ux-audit-out/walk.json` and `ux-audit-out/screens/step_*.png`, written by the
walk itself. Nothing has to be moved afterwards.

Fallback — on a device:

```bash
cd <app-root>
flutter drive --driver=test_driver/integration_test.dart \
              --target=integration_test/ux_journey_drive.dart -d <device-id>
```

Its artifacts land at:

- `build/integration_response_data.json` (`$FLUTTER_TEST_OUTPUTS_DIR` overrides `build/`)
- `ux-audit-out/screens/step_*.png`
- `ux-audit-out/screens/setup_N.png`, and only for a setup step that FAILED. A gated run that got
  through its gate produces none, so their absence is the success case, not a missing artifact.

Move both into `<app-root>/ux-audit-out/` (`walk.json`, `screens/`). Sanity check: the JSON should be
well under 100 KB for a short journey — if it is hundreds of KB, the screenshot strip did not take.

## What the walk data must contain

Per step: index, action, target, expectation, status, elapsed ms, `settled`, the semantics node list
with logical-px rects, and the four guideline evaluations with their `reason` strings. The `reason`
strings already carry node id, rect, label, measured size or contrast ratio, and the required value
— quote them into findings verbatim instead of recomputing anything.

Plus, for the flow and placement half of the report:

| Field | Where | What it answers |
|---|---|---|
| `viewport` (`foldY`, `contentTop`, `keyboardInset`, `isTestDefault`, `textDirection`) | per dump | what is on screen without scrolling, when that is unknowable, and which way reading order runs |
| `onScreen`, `aboveFold` | per node | is it on the surface at all, and visible without scrolling |
| `coversSurface` | per node | the full-screen tap-to-dismiss `GestureDetector`, so placement checks can exclude it |
| `effectivePct`, `centreCovered`, `obscuredBy` | per tap target | is this control actually hittable |
| `surface.canPop`, `tappableCount`, `tappableAboveFold`, `modalOpen` | per step | can the user leave, and what else is here |
| `tapsSoFar` | per step | reach cost on the declared path — never a minimum |
| `dispatched`, `semanticsUnchanged`, `screenSig` | per step | dead taps, revisits, state loss |
| `panesPossiblyBlocked` | per dump | **true** means `nodes` is only the LAST-PAINTED pane: two SIBLING `Navigator`s (a tablet master-detail `Row`) let the later pane's `BlockSemantics` delete the earlier one before the dump can reach it — nested navigators, i.e. a tab shell, do not, which is why this asks about ancestry and not about a count. **False is not a promise the dump is whole**: measured, a `Row` of `[Scaffold, Navigator]` dumps only the `Navigator` pane while this reads false, because one `ModalRoute` is enough to delete an earlier sibling. It is a declared *suspicion*, never a clean bill |
| `setupSteps`, `setupFailed` | per run | did the walk reach the journey's starting line, and if not which gate step stopped it. Never merged into `steps`: setup is recorded, not scored |
| `taps`, `networkCalls`, `appErrors`, `entrySettled` | per run | totals and the app's own complaints |
| `conditions` | per run | `mode`, `deviceProfile`, `fontSource`, `renderer`, `targetPlatform`, plus `platformBrightness`, `textScaleFactor`, locale and the accessibility flags. `platform` is the HOST under `flutter test` (`macos`), which is correct and is why `targetPlatform` is a separate field. The report's scope clause quotes these; measured, the same build at `accessibility-extra-extra-extra-large` produces a byte-identical `viewport` while a product row leaves the tree, so nothing else in the artifact distinguishes the two runs |

**`screenSig` is not portable across platforms.** It is built from the screen's labels, and
platform-adaptive widgets label themselves differently: measured on the same build and the same
screen, Material's `BackButton` carries `label: "Back"` **and** `tooltip: "Back"` on Android, but on
iOS only the tooltip — so the detail screen hashes to `4ddc18db` on an iPhone SE and `70ed0c2e` on an
Android emulator. Nothing in the audit compares signatures across runs, so no check is affected; a
*golden file* pinned to one platform's signatures is, and must say which platform produced it.

One caveat for step 4: `MinimumTextContrastGuideline` partitions foreground/background naively and
picked a nearby button's colour in the verification run while still flagging the correct node. Treat
its **node** as the signal and its **ratio** as advisory. That holds twice over in the default mode:
the guideline reads back rasterized pixels and the headless rasterizer is not the device's —
measured on the same node, 1.36 under `flutter test` against 1.03 on the simulator. Same verdict
both times, and the font is not the cause (the em-square run and the real-font run both report
1.36), but a ratio near 4.5 could land either side. `conditions.renderer` says which one produced
the number.
