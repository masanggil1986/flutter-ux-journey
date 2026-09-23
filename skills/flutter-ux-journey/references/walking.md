# walking.md — the runtime recipe

Every API call below was executed on a real iOS simulator (iPhone SE 3rd gen, iOS 18.6,
Flutter 3.47.2 stable). Signatures are verbatim from the SDK. Do not substitute remembered ones.

- [Why the walker runs inside the app](#why-the-walker-runs-inside-the-app)
- [Prerequisites in the audited app](#prerequisites-in-the-audited-app)
- [File 1 — test_driver/integration_test.dart](#file-1--test_driverintegration_testdart)
- [File 2 — integration_test/ux_journey_test.dart](#file-2--integration_testux_journey_testdart)
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
  integration_test:
    sdk: flutter
```

Nothing else. No third-party package is needed at any point.

Tell the user to gitignore the two generated paths (see SKILL.md). They are regenerated on every run;
a team that wants them as a regression test promotes them deliberately.

## File 1 — test_driver/integration_test.dart

Verbatim, whole file. The `responseDataCallback` strip is not optional: `takeScreenshot` also stuffs
every PNG into `reportData['screenshots']` as a JSON int array, which turned a 45 KB PNG into a
561 KB JSON in the verification run.

```dart
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final File f = File('screenshots/$name.png');
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(bytes);
      return true;
    },
    // PNGs already went to disk above; keeping them in the JSON inflates it ~12x.
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

## File 2 — integration_test/ux_journey_test.dart

**The source of truth is the file that actually runs:**

```
${CLAUDE_PLUGIN_ROOT}/example/ux_demo_app/integration_test/ux_journey_test.dart
```

Read it and copy it. It is not sketched here on purpose — a second copy in prose drifts from the
one that was executed, and every trap below was found by executing it. It is ~480 lines, it has no
dependency outside the Flutter SDK, and it carries its own comments explaining every non-obvious
line.

**Four things change per app, and nothing else:**

1. the `package:<app>/main.dart` import,
2. the `journey` list, generated from `## Steps` in `journey.md`,
3. the SETUP block, generated from `## Setup`, and a network stub before `app.main()` if the
   journey has to pass a gate (`references/network-stub.md`),
4. `networkCalls`, wired to the stub's own call list when there is a stub.

The rest of this file explains *why* the parts that look replaceable are not.

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
FlutterError.onError = (FlutterErrorDetails details) {
  appErrors.add(details.exceptionAsString());
};
...
report['appErrors'] = appErrors;
```

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
quoting a fold line for a phone that does not exist. Measured on an iPhone SE (3rd gen) the same
code returns `375.0 x 667.0 @ 2.0, contentTop 20.0, padBottom 0.0, foldY 667.0` — the SE has a home
button, so its bottom padding really is zero.

**Effective (unobscured) tap area.** A control can pass every size check and still be unhittable:
its own rect never changes when something lands on top of it. Measured on a production app, an
error banner cut a 56 dp CTA to 17.2 dp of visible target while the CTA still reported 56 dp.
`subtractRects` splits the target around every later-painted, non-descendant node that intersects
it, and `centreCovered` answers the question the walk actually depends on — the walker taps the
CENTRE, so a covered centre means its own tap lands on the overlay. The fixture reproduces the
production number exactly: a 48 dp CTA under a banner keeps 33.3% of its area and a 16 dp strip.

Two exclusions are load-bearing. Ancestors are excluded by coming first in paint order; descendants
have to be excluded explicitly by walking the parent chain, or every card obscures itself with its
own label.

This is **geometry, not a hit test**: the semantics tree carries no opacity and no `IgnorePointer`.
It needs the screenshot to confirm before it becomes a finding, and it is void on any step where
`settled` is false.

**Screen identity.** A sorted hash of every non-empty label ∪ tooltip ∪ value. Equal signatures mean
the same screen in the same state, which is what makes state loss after a back step and a dead tap
checkable. It is deliberately NOT a template id — see Trap 5.

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

```bash
cd <app-root>
flutter drive --driver=test_driver/integration_test.dart \
              --target=integration_test/ux_journey_test.dart -d <device-id>
```

Plain `flutter test integration_test/...` does **not** write the JSON — only stdout. It must be
`flutter drive`.

Artifacts land at:

- `build/integration_response_data.json` (`$FLUTTER_TEST_OUTPUTS_DIR` overrides `build/`)
- `screenshots/step_*.png`

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
| `taps`, `networkCalls`, `appErrors`, `entrySettled` | per run | totals and the app's own complaints |

One caveat for step 4: `MinimumTextContrastGuideline` partitions foreground/background naively and
picked a nearby button's colour in the verification run while still flagging the correct node. Treat
its **node** as the signal and its **ratio** as advisory.
