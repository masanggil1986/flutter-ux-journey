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

Generate this from `journey.md`. The shape below is fixed; only the setup body and the per-step
target/expectation strings change.

```dart
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';   // MatrixUtils
import 'package:flutter/rendering.dart';  // Matrix4, SemanticsNode, SemanticsAction
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:<app_package>/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final steps = <Map<String, Object?>>[];

  testWidgets('ux journey', (WidgetTester tester) async {
    // Never assume semantics are already on. Cheap, and required by the docs.
    final SemanticsHandle handle = tester.ensureSemantics();

    app.main();
    // NOT pumpAndSettle. See "Bounded settle" below — it hangs for 10 minutes
    // on any app that animates continuously, which production apps do.
    final bool entrySettled = await _settle(tester, limit: const Duration(seconds: 12));

    // In-test screenshots are iOS-only. On Android the pair
    // convertFlutterSurfaceToImage() + takeScreenshot() DEADLOCKS — no error,
    // no timeout — whenever the app embeds platform views (a webview, a media
    // surface, a camera preview). Measured twice on a production app. The host
    // captures the visual layer instead; see the screenshot section below.
    if (Platform.isIOS) {
      await binding.convertFlutterSurfaceToImage();
    }

    // --- SETUP: excluded from measurement and scoring. -----------------------
    // Generated from `## Setup`. A throw here must surface as a setup failure,
    // not as a short journey, so it is deliberately NOT caught.
    // e.g. await _tapTarget(tester, 'Log in'); await tester.pumpAndSettle();
    // -------------------------------------------------------------------------

    for (final step in <List<String>>[
      // [target to tap, expected on screen afterwards] — one row per journey step
      <String>['Orders', 'Order list'],
    ]) {
      final int i = steps.length + 1;

      // Capture BEFORE the tap. The screen a step STARTS on is the screen that
      // holds the target being tapped, so that is the screen whose tap targets
      // and contrast this step is about. Capturing after the tap silently never
      // audits the journey's entry screen — measured on the demo fixture, it
      // dropped three of its six seeded defects while still reporting a green run.
      final Map<String, Object?> semantics = _dumpSemantics(tester);
      final List<Map<String, Object?>> guidelines = await _evaluateGuidelines(tester);
      if (Platform.isIOS) {
        await binding.takeScreenshot('step_$i');
      }

      final sw = Stopwatch()..start();
      String status = 'OK';
      String? error;
      bool settled = true;
      try {
        await _tapTarget(tester, step[0]);
        settled = await _settle(tester);
        _requireTarget(tester, step[1]); // the oracle: throws if the step did not land
      } catch (e) {
        status = 'FAILED';
        error = e.toString();
      }
      sw.stop();

      steps.add(<String, Object?>{
        'index': i,
        'target': step[0],
        'expected': step[1],
        'status': status,
        'error': error,
        'elapsedMs': sw.elapsedMilliseconds, // EVIDENCE ONLY — never scored, see below
        'settled': settled, // false = still animating when we gave up
        'screenshot': 'step_$i.png',
        'semantics': semantics,
        'guidelines': guidelines,
      });
      // Do NOT break on failure. A blocked step IS the finding, and the screens
      // after it are exactly where journey-level defects (dead ends, lost state)
      // live. Stopping early hides them.
    }

    // The screen the journey ENDS on is never audited otherwise: every step
    // captures the screen it STARTS from, so the final outcome — the error
    // state, the confirmation, the dead end — falls off the end. Measured:
    // without this, an audit of a failed sign-in never looks at the failure,
    // and the failure is the whole point of that journey.
    steps.add(<String, Object?>{
      'index': steps.length + 1,
      'action': 'outcome',
      'status': 'OK',
      'elapsedMs': 0,
      'settled': await _settle(tester),
      'semantics': _dumpSemantics(tester),
      'guidelines': await _evaluateGuidelines(tester),
    });

    handle.dispose();
    // MUTATE, never replace. takeScreenshot appends each PNG into
    // reportData['screenshots'], and that list is how the driver's onScreenshot
    // receives the bytes. Assigning a fresh map here deletes every screenshot —
    // the run still exits 0 with valid JSON and zero PNGs, with no error.
    (binding.reportData ??= <String, dynamic>{})['steps'] = steps;
  });
}
```

`elapsedMs` measures a host round-trip under a test harness, not user-perceived latency. Record it as
evidence, **never score it as a defect** — scoring it would be a lie. `binding.watchPerformance` costs
a forced 4-6 s per call and is not part of v0.1.

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

```dart
/// Pump until the frame queue is quiet or [limit] elapses, then carry on.
/// A screen that never settles is EVIDENCE, not a reason to stop walking.
Future<bool> _settle(
  WidgetTester tester, {
  Duration limit = const Duration(seconds: 5),
}) async {
  final Stopwatch sw = Stopwatch()..start();
  while (sw.elapsed < limit) {
    await tester.pump(const Duration(milliseconds: 100));
    if (!tester.binding.hasScheduledFrame) {
      return true;
    }
  }
  return false; // still animating — record it per step
}
```

Record the result as `settled` per step. `settled: false` is itself worth reporting: a screen that
is still animating after 5 s is either doing real work with no progress affordance, or animating
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

`enterText` needs a Finder, but the selector model is label-based, so map the resolved semantics
node to its `EditableText` by geometry:

```dart
Future<void> _typeInto(WidgetTester tester, String needle, String text) async {
  final Map<String, Object?> node = _resolve(tester, needle);
  final List<double> r = node['rect']! as List<double>;
  final Offset centre = Offset(r[0] + r[2] / 2, r[1] + r[3] / 2);

  Element? hit;
  for (final Element e in find.byType(EditableText).evaluate()) {
    final RenderBox? box = e.renderObject as RenderBox?;
    if (box == null || !box.hasSize) {
      continue;
    }
    if ((box.localToGlobal(Offset.zero) & box.size).inflate(24).contains(centre)) {
      hit = e;
      break;
    }
  }
  if (hit == null) {
    throw StateError('"$needle" resolves to a node with no editable field under it');
  }
  final Element target = hit;
  await tester.enterText(find.byElementPredicate((Element e) => e == target), text);
}
```

Text entered is always ARBITRARY — see "Credentials: never ask for them" in SKILL.md.

### Ambiguity: prefer an exact match, otherwise fail

A substring selector legitimately matches both a label and a longer label containing it — a
password field and a "forgot password" link, measured on a real app. When exactly one hit matches
**exactly**, that is unambiguously the one meant. Anything else stays an error: taking the first hit
silently audits a different widget and reports its measurements as the one you asked for.

```dart
  if (hits.length > 1) {
    final List<Map<String, Object?>> exact = hits.where((Map<String, Object?> node) {
      return <Object?>[node['label'], node['tooltip'], node['value']]
          .any((Object? v) => v is String && _norm(v) == n);
    }).toList();
    if (exact.length == 1) {
      return exact.single;
    }
    throw StateError('ambiguous: ${hits.length} nodes match "$needle" — '
        '${hits.map((Map<String, Object?> h) => h['label']).toList()}');
  }
```

### The semantics dump

```dart
Map<String, Object?> _dumpSemantics(WidgetTester tester) {
  final double dpr = tester.view.devicePixelRatio;
  final SemanticsNode root =
      tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!;
  final nodes = <Map<String, Object?>>[];

  void walk(SemanticsNode node, Matrix4 inherited) {
    final SemanticsData data = node.getSemanticsData();
    // Trap 1: rects are LOCAL. Accumulate the parent chain or everything nested reads (0,0).
    final Matrix4 t = inherited.clone();
    if (node.transform != null) {
      t.multiply(node.transform!);
    }
    final Rect g = MatrixUtils.transformRect(t, data.rect); // physical px
    nodes.add(<String, Object?>{
      'id': node.id,
      'label': data.attributedLabel.string,
      'value': data.attributedValue.string,
      'tooltip': data.tooltip,
      'identifier': data.identifier,
      'role': data.role.name,
      'flags': data.flagsCollection.toStrings(),
      'tappable': data.hasAction(SemanticsAction.tap), // Trap 3: action, not flag
      // logical px — guidelines measure in logical px, so findings must quote logical px
      'rect': <double>[g.left / dpr, g.top / dpr, g.width / dpr, g.height / dpr],
    });
    node.visitChildren((SemanticsNode child) {
      walk(child, t);
      return true;
    });
  }

  walk(root, Matrix4.identity());
  return <String, Object?>{'devicePixelRatio': dpr, 'nodes': nodes};
}
```

### The selector

```dart
String _norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

/// Matches over label ∪ tooltip ∪ value (Trap 2), normalised substring, and
/// ERRORS on ambiguity instead of silently taking the first hit.
Map<String, Object?> _resolve(WidgetTester tester, String needle) {
  final dump = _dumpSemantics(tester);
  final n = _norm(needle);
  final hits = (dump['nodes']! as List<Map<String, Object?>>).where((node) {
    final hay = _norm(<Object?>[node['label'], node['tooltip'], node['value']].join(' '));
    return hay.contains(n);
  }).toList();
  if (hits.isEmpty) {
    throw StateError('no semantics node matches "$needle"');
  }
  if (hits.length > 1) {
    throw StateError('ambiguous: ${hits.length} nodes match "$needle" — '
        '${hits.map((h) => h['label']).toList()}');
  }
  return hits.single;
}

Future<void> _tapTarget(WidgetTester tester, String needle) async {
  final node = _resolve(tester, needle);
  if (node['tappable'] != true) {
    throw StateError('"$needle" carries no tap action');
  }
  final r = (node['rect']! as List<double>);
  await tester.tapAt(Offset(r[0] + r[2] / 2, r[1] + r[3] / 2)); // logical px
}

void _requireTarget(WidgetTester tester, String needle) => _resolve(tester, needle);
```

`find.bySemanticsLabel(Pattern)`, `find.byTooltip(Pattern)`, `find.text(String)` and
`find.byIcon(IconData)` all work at runtime and are fine when one of them is unambiguous.
`find.byKey` is an **escape hatch only** — keys covered about 2% of tap targets in a real measured
app, so a key-based selector strategy finds almost nothing.

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

Per step: index, target, expectation, status, elapsed ms, the semantics node list with logical-px
rects, and the four guideline evaluations with their `reason` strings. The `reason` strings already
carry node id, rect, label, measured size or contrast ratio, and the required value — quote them into
findings verbatim instead of recomputing anything.

One caveat for step 4: `MinimumTextContrastGuideline` partitions foreground/background naively and
picked a nearby button's colour in the verification run while still flagging the correct node. Treat
its **node** as the signal and its **ratio** as advisory.
