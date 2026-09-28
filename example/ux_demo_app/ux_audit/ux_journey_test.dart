// The journey walker for example/journey.md, in the shape the skill generates.
// See skills/flutter-ux-journey/references/walking.md — this file is the
// worked, executed instance of that recipe.
//
// The helpers below are PUBLIC on purpose. A file the skill generates into
// someone else's app has to stay one file, so the alternative to a public
// helper is an untested one; test/walker_test.dart imports these directly.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ux_demo_app/main.dart' as app;

/// One journey step: perform [action] on [target], then require [expected] to
/// be on screen. The `expected` check is the oracle — without it a walk reports
/// a dispatch instead of a result, which is why integration_test was chosen.
/// [action] is 'tap', 'type' or 'back'. For 'type', [text] is the value entered
/// — always ARBITRARY data. The walker never receives real credentials: an
/// audit tool must not ask for them, and must not authenticate against
/// production.
/// [nth] disambiguates when a label legitimately appears more than once — a
/// shortcut tile and a nav tab can carry the SAME text, and no amount of
/// matching cleverness can guess which one a journey means. 1-based; null
/// means "there must be exactly one".
typedef Step = ({
  String action,
  String target,
  int? nth,
  String? text,
  String expected,
});

const List<Step> journey = <Step>[
  (
    action: 'tap',
    target: 'Walnut Side Table',
    nth: null,
    text: null,
    expected: '189,000 KRW',
  ),
  (
    action: 'tap',
    target: 'Remove from list',
    nth: null,
    text: null,
    expected: 'Cancel',
  ),
  (
    action: 'tap',
    target: 'Back',
    nth: null,
    text: null,
    expected: 'Saved items',
  ),
];

/// `## Setup` — the steps that get the walk to the journey's starting line: a
/// permission dialog, an onboarding sheet, a sign-in. Excluded from
/// measurement and from scoring, because a gate is not the product.
///
/// example/journey.md declares none: this fixture has no backend and no login.
/// integration_test/gated_journey_test.dart is the worked instance that does.
const List<Step> setup = <Step>[];

/// One screenshot, with no device under it.
///
/// This is the path golden files take (`OffsetLayer.toImage`), so it needs no
/// platform surface — which is also why it cannot deadlock the way
/// `convertFlutterSurfaceToImage()` + `takeScreenshot()` does on Android when
/// the app hosts a platform view. What it cannot do is render a platform view
/// at all: that area comes out blank, and the report says `not assessable` for
/// it rather than describing an empty rectangle.
///
/// `runAsync` is required — `toImage` is real async work and the test
/// binding's fake clock would never complete it.
Future<void> writePng(WidgetTester tester, String path) async {
  final RenderView rv = tester.binding.renderViews.first;
  final OffsetLayer layer = rv.debugLayer! as OffsetLayer;
  ByteData? data;
  await tester.runAsync(() async {
    final ui.Image img = await layer.toImage(rv.paintBounds);
    data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
  });
  if (data == null) {
    return;
  }
  final File f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(data!.buffer.asUint8List());
}

/// `## Device` — the screen this journey declares. Resolved by NAME rather than
/// pinned to the const, so a journey naming a preset that does not exist fails
/// here instead of being quietly measured on a screen nobody chose.
final DeviceProfile device = deviceProfileByName('iphone-se');

/// True when the journey file declared `## Device`. The report's scope clause
/// quotes the difference, so a reader can tell a chosen screen from an assumed
/// one.
const bool deviceDeclared = true;

/// One output root, the one SKILL.md declares. Never `screenshots/`, which is a
/// conventionally TRACKED directory in a Flutter app and not ours to claim.
const String outDir = 'ux-audit-out';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ux journey', (WidgetTester tester) async {
    // This fixture has no backend, so no network stub is installed and
    // `networkCalls` stays empty. `flutter test` already refuses every request
    // with an empty 400 — flutter_test installs its own HttpOverrides — so the
    // default posture, network cut and arbitrary data, costs nothing here. An
    // app that has to walk past a gate installs a stub; see
    // references/network-stub.md and integration_test/gated_journey_test.dart.
    //
    // Reset inline, never in addTearDown: _verifyInvariants runs at the end of
    // the test BODY and fails on a foundation debug variable left set, while
    // teardowns run after it.
    debugDefaultTargetPlatformOverride = device.targetPlatform;
    applyDevice(tester, device);
    addTearDown(tester.view.reset);
    final String fontSource = await loadFonts(tester);

    await walkJourney(
      tester,
      launch: app.main,
      setup: setup,
      journey: journey,
      shot: (String name) => writePng(tester, '$outDir/screens/$name.png'),
      publish: (Map<String, Object?> report) async => File('$outDir/walk.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(report)),
      runContext: <String, Object?>{
        'mode': 'widget-test',
        // The contrast guideline reads back rasterized pixels, and this
        // rasterizer is not the device's: measured on the same node, 1.36 here
        // against 1.03 on the simulator. Same verdict there, but a ratio near
        // 4.5 could land either side — walking.md already says to treat the
        // guideline's NODE as the signal and its ratio as advisory.
        'renderer': 'flutter_tester (software)',
        // NOT conditions.platform, which correctly reads the HOST (`macos`):
        // this is what the framework was told to be, and the two differ.
        'targetPlatform': device.targetPlatform.name,
        'deviceProfile': deviceProfileLabel(device, declared: deviceDeclared),
        'fontSource': fontSource,
      },
    );

    debugDefaultTargetPlatformOverride = null;
  });
}

/// Take one screenshot, or report that it could not be taken.
///
/// A capture that throws — a full disk, an unwritable path, a device-side
/// deadlock that surfaces as an error — costs that step its IMAGE. It must not
/// cost the step its measurements: by the time this runs, the semantics dump
/// and all four guideline evaluations are already in hand.
Future<String?> _capture(
  Future<void> Function(String)? shot,
  String name,
) async {
  if (shot == null) {
    return null;
  }
  try {
    await shot(name);
    return '$name.png';
  } catch (_) {
    return null;
  }
}

/// The whole walk: launch the app, run `## Setup`, walk the journey, hand the
/// report to [publish].
///
/// It takes no binding. Everything the walk used to reach for on one — the
/// screenshot mechanism, the place the report goes, the facts only the entry
/// knows — arrives as [shot], [publish] and [runContext], which is what lets
/// the same walk run under `flutter test` with no device and under
/// `flutter drive` with one.
///
/// Install `HttpOverrides.global` **before** calling this. The stub has to be
/// in place before the app's first frame, and [launch] is what triggers it —
/// passing `app.main` rather than calling it here is the only way a caller can
/// get in front of it. Pass the stub's own call list as [networkCalls]: it
/// defaults to empty, and an empty field silently costs the report a layer.
///
/// Public so that a second journey is a second file of step lists rather than a
/// second copy of this one — see `integration_test/gated_journey_test.dart`,
/// which is almost entirely its own `setup` and `journey` consts. The file the
/// skill generates into someone else's app is still ONE file — consts, `main`,
/// this, and the helpers below — which is the constraint that makes every
/// helper here public. No line count here on purpose: it would be a number
/// about a neighbouring file that nothing checks.
Future<void> walkJourney(
  WidgetTester tester, {
  required void Function() launch,
  required List<Step> journey,
  List<Step> setup = const <Step>[],
  List<String> networkCalls = const <String>[],
  // null means the VISUAL layer is not assessable on this run — the report
  // must say so rather than leave the section empty. On Android under
  // `flutter drive` this is null because convertFlutterSurfaceToImage() +
  // takeScreenshot() deadlocks on any app hosting a platform view.
  Future<void> Function(String name)? shot,
  // Where the report goes. The drive entry mutates binding.reportData; the
  // widget-test entry writes a file. The walk knows neither.
  required Future<void> Function(Map<String, Object?> report) publish,
  // What the ENTRY knows and the walk cannot measure: which mode, which
  // renderer, which declared device, which fonts.
  Map<String, Object?> runContext = const <String, Object?>{},
}) async {
  // Never assume semantics are already on. Cheap, and required by the docs.
  final SemanticsHandle handle = tester.ensureSemantics();
  final List<Map<String, Object?>> steps = <Map<String, Object?>>[];
  final List<Map<String, Object?>> setupSteps = <Map<String, Object?>>[];

  // An app's own errors are FINDINGS, not a reason to abort the audit. A
  // production app fires background requests that outlive a step; without
  // this, one late async exception fails the test and discards the entire
  // report — measured: a voucher fetch completing after the walk threw away
  // a nine-step journey. Collect them as evidence instead.
  final List<String> appErrors = <String>[];
  FlutterError.onError = (FlutterErrorDetails details) {
    appErrors.add(details.exceptionAsString());
  };

  launch();
  // NOT pumpAndSettle: it waits out a 10-minute timeout on any app that
  // animates continuously. This fixture does not, but the generated walker
  // must, so the fixture exercises the same code path.
  final bool entrySettled = await settle(
    tester,
    limit: const Duration(seconds: 12),
  );

  // --- SETUP: excluded from measurement and scoring. ------------------------
  // A gate is not the product, so these steps get no semantics dump, no
  // guideline evaluation and no reach cost. They are recorded anyway, because
  // a run that dies in setup must report a setup failure — reporting the steps
  // that did run as a journey would describe a short healthy app.
  // -------------------------------------------------------------------------
  bool setupFailed = false;
  for (final Step step in setup) {
    final int i = setupSteps.length + 1;
    final Stopwatch sw = Stopwatch()..start();
    final StepOutcome out = await performStep(tester, step);
    sw.stop();
    // One screenshot, and only on failure: it is the whole evidence for "the
    // gate is what blocked this", and a passing setup step has nothing to show.
    final String? shotName = out.status != 'OK'
        ? await _capture(shot, 'setup_$i')
        : null;
    setupSteps.add(<String, Object?>{
      'index': i,
      'phase': 'setup',
      'action': step.action,
      'target': step.target,
      'nth': step.nth,
      'text': recordedText(step, out.obscured),
      'expected': step.expected,
      'status': out.status,
      'error': out.error,
      'elapsedMs': sw.elapsedMilliseconds,
      'settled': out.settled,
      'dispatched': out.dispatched,
      'screenshot': shotName,
    });
    if (out.status != 'OK') {
      setupFailed = true;
      break;
    }
  }

  // Reach cost, counted by the thing that issues it. This is ground truth on
  // every app shape, unlike a route-derived depth — and it is "taps on THIS
  // journey", never "the minimum", because a minimum needs paths nobody
  // declared, i.e. a crawl. Setup taps are not reach: the user paying them is
  // paying for a gate, not for the task.
  int taps = 0;

  if (!setupFailed) {
    for (final Step step in journey) {
      final int i = steps.length + 1;

      // Capture BEFORE the tap: the screen a step starts on is the screen that
      // holds the target being tapped, so that is the screen whose tap targets
      // and contrast the step is about.
      final Map<String, Object?> semantics = dumpSemantics(tester);
      final Map<String, Object?> surface = routeState(tester, semantics);
      final List<Map<String, Object?>> guidelines = await _evaluateGuidelines(
        tester,
      );
      final String sigBefore = screenSignature(semantics);
      final String? shotName = await _capture(shot, 'step_$i');

      final Stopwatch sw = Stopwatch()..start();
      final StepOutcome out = await performStep(tester, step);
      sw.stop();
      // Counted AFTER it lands. `_tapTarget` throws when the target cannot be
      // resolved or is off screen, and a gesture that was never dispatched is
      // not reach cost.
      if (out.tapped) {
        taps++;
      }

      steps.add(<String, Object?>{
        'index': i,
        'action': step.action,
        'target': step.target,
        'nth': step.nth,
        'text': recordedText(step, out.obscured),
        'expected': step.expected,
        'status': out.status,
        'error': out.error,
        'elapsedMs': sw.elapsedMilliseconds, // EVIDENCE ONLY — never scored
        'settled': out.settled,
        'tapsSoFar': taps,
        'screenshot': shotName,
        'screenSig': sigBefore,
        'dispatched': out.dispatched,
        // A tap that changed no semantics at all. Filled after the loop: the
        // NEXT step's dump is this step's "after", the same frame, so a second
        // tree walk here would measure it twice. NOT sufficient for a finding
        // on its own either — a control that only repaints (a selection chip,
        // a tab highlight) is byte-identical to one wired to nothing, measured
        // in test/walker_test.dart. heuristics.md requires a second layer
        // before this becomes FAKE-AFFORDANCE.
        'semanticsUnchanged': null,
        'surface': surface,
        'semantics': semantics,
        'guidelines': guidelines,
      });
      // No break on failure: a blocked step is itself the finding, and the
      // screens after it are exactly where the journey-level defects live.
    }

    // The screen the journey ENDS on is never audited otherwise: every step
    // captures the screen it starts from, so the final outcome — the error
    // state, the confirmation, the dead end — falls off the end. Measured:
    // without this, an audit of a failed sign-in never looks at the failure.
    final String? outcomeShot = await _capture(
      shot,
      'step_${steps.length + 1}',
    );
    final Map<String, Object?> outcome = dumpSemantics(tester);
    steps.add(<String, Object?>{
      'index': steps.length + 1,
      'action': 'outcome',
      'target': null,
      'text': null,
      'expected': null,
      'status': 'OK',
      'error': null,
      'elapsedMs': 0,
      'settled': await settle(tester),
      'tapsSoFar': taps,
      // The outcome screen needs its own PNG, or the last real step has no
      // "after" image and the dead-tap confirmation (compare step N's PNG with
      // step N+1's) is impossible for exactly the step where the journey ended.
      'screenshot': outcomeShot,
      'screenSig': screenSignature(outcome),
      'dispatched': false,
      'semanticsUnchanged': null,
      'surface': routeState(tester, outcome),
      'semantics': outcome,
      'guidelines': await _evaluateGuidelines(tester),
    });

    // A step's "after" is the next step's "before": the same frame, already
    // dumped. Only a dispatched gesture can be called dead.
    for (int i = 0; i + 1 < steps.length; i++) {
      steps[i]['semanticsUnchanged'] = steps[i]['dispatched'] == true
          ? steps[i]['screenSig'] == steps[i + 1]['screenSig']
          : null;
    }
  }

  handle.dispose();
  final Map<String, Object?> report = <String, Object?>{
    'steps': steps,
    // Recorded even when empty, so a reader can tell "no gate" from "the gate
    // was never walked".
    'setupSteps': setupSteps,
    'setupFailed': setupFailed,
    // A journey whose entry screen never settles is already telling you
    // something — record it rather than dropping it.
    'entrySettled': entrySettled,
    'appErrors': appErrors,
    'networkCalls': networkCalls,
    'taps': taps,
    // The scope clause in the report quotes this. Without it the clause is
    // a claim about a condition nobody recorded. runContext comes LAST: an
    // entry may correct something the walk could only guess — `platform`
    // reads the HOST under `flutter test` — and a silent disagreement between
    // the two is worse than either value.
    'conditions': <String, Object?>{...conditionsOf(tester), ...runContext},
  };
  // Never swallowed. Every measurement is already made by this point, so a
  // publish that fails quietly means a green run with no artifact — the one
  // outcome a reader cannot detect.
  await publish(report);
}

/// What one step did. `tapped` is separate from `dispatched` because only a tap
/// is reach cost, and a `type` that dispatched is not a tap. `obscured` is true
/// when the field typed into hides its own value — see [recordedText].
typedef StepOutcome = ({
  String status,
  String? error,
  bool settled,
  bool dispatched,
  bool tapped,
  bool obscured,
});

/// Perform one step and say what happened. **Never throws**: a failing step IS
/// the finding, and an assertion here would also discard the report and every
/// screenshot with it (`writeResponseOnFailure` defaults to false).
Future<StepOutcome> performStep(WidgetTester tester, Step step) async {
  String status = 'OK';
  String? error;
  bool settled = true;
  // Did the gesture actually go out? A step that fails while RESOLVING its
  // target never touched the app, so "the semantics did not change" is
  // trivially true and means nothing. Without this, every selector miss
  // reads as a dead tap — measured on this fixture's step 3.
  bool dispatched = false;
  bool tapped = false;
  bool obscured = false;
  try {
    switch (step.action) {
      case 'type':
        obscured = await _typeInto(tester, step.target, step.text!, step.nth);
      case 'back':
        // pageBack() exercises the on-screen back AFFORDANCE. It only
        // looks for a tooltip-'Back' button or a Cupertino back button, so
        // it also throws on a screen whose exit is a 'Close' button — a
        // fullscreenDialog route, for one. A throw here is a DEAD-END
        // CANDIDATE, never the evidence: read surface.canPop first.
        await tester.pageBack();
      case 'tap':
        await _tapTarget(tester, step.target, step.nth);
        tapped = true;
      default:
        throw StateError('unknown action "${step.action}"');
    }
    dispatched = true;
    // Poll the oracle inside the bound instead of settling once and then
    // checking. "No frame is scheduled" is not "the screen is ready": an
    // awaiting Future schedules no frames, so a screen that renders an
    // empty state while a request is in flight reports settled within one
    // pump and the step then fails for the wrong reason.
    settled = await settle(
      tester,
      until: () => _present(tester, step.expected),
    );
    _requireTarget(tester, step.expected); // the oracle
  } catch (e) {
    status = 'FAILED';
    error = e.toString();
  }
  return (
    status: status,
    error: error,
    settled: settled,
    dispatched: dispatched,
    tapped: tapped,
    obscured: obscured,
  );
}

/// What goes in the artifact for a `type` step.
///
/// The typed value is NOT read back from the screen — it comes straight from the
/// journey file — so `obscureText` does nothing to keep it out of here. Measured
/// on this repo's own gated fixture: `not-a-real-password` landed verbatim in
/// `example/walk-gated.json` on the first run that produced it.
///
/// Every journey is required to use arbitrary data, so in principle there is
/// nothing here to protect. This exists because "in principle" is not a
/// guarantee, and an audit artifact is the last place anyone should have to be
/// careful. The length survives, which is all a reader needs — a re-run reads
/// the journey file, never this.
String? recordedText(Step step, bool obscured) => obscured && step.text != null
    ? '<redacted ${step.text!.length} chars: the field hides its own value>'
    : step.text;

/// Pump until the frame queue is quiet or [limit] elapses, then carry on.
/// `pumpAndSettle` only gives up after a 10-minute default timeout, so a
/// perpetual animation hangs the whole run instead of producing a report.
///
/// With [until] given, frame-quiet is NOT the stop condition — the predicate
/// is. Returning true then means "what the step expected actually arrived",
/// which is the only reading of `settled` that a finding can stand on.
Future<bool> settle(
  WidgetTester tester, {
  Duration limit = const Duration(seconds: 5),
  bool Function()? until,
}) async {
  const Duration tick = Duration(milliseconds: 100);
  // Bounded by BOTH the wall clock and the pump count, because they are not
  // the same clock. `tester.pump(tick)` advances FAKE time by a tick while the
  // Stopwatch measures real time, so under `flutter test` the loop would run
  // thousands of iterations inside one real second and simulate minutes —
  // measured. The pump bound is what makes the limit mean the same thing in a
  // widget test and on a device.
  final int maxPumps = (limit.inMilliseconds / tick.inMilliseconds).ceil();
  final Stopwatch sw = Stopwatch()..start();
  bool lastExpected = false;
  for (int pumped = 0; pumped < maxPumps && sw.elapsed < limit; pumped++) {
    await tester.pump(tick);
    final bool quiet = !tester.binding.hasScheduledFrame;
    if (until == null) {
      if (quiet) {
        return true;
      }
      continue;
    }
    if (until()) {
      lastExpected = true;
    }
    // BOTH, and that is not belt-and-braces. Stopping at "the expectation is
    // on screen" returns mid-transition, while a route is still sliding in —
    // measured on a device: every rect on that screen came back shifted by
    // 244 lpx, the fold and placement numbers were nonsense, and the next
    // step's tap landed off the right edge of the surface and hit nothing.
    // Stopping at "the queue is quiet" alone is the other failure: an awaiting
    // Future schedules no frames, so an empty screen reports ready.
    if (quiet && until()) {
      return true;
    }
  }
  // What the step expected DID arrive, but the screen never went quiet — a
  // shimmer, a spinner, an indeterminate bar. That is not the same as "the
  // content never came", and conflating them voids every geometric
  // measurement on any app that animates forever.
  return lastExpected;
}

/// Is [needle] on screen right now? Never throws — it is a poll, not an oracle.
bool _present(WidgetTester tester, String needle) {
  try {
    resolve(tester, needle);
    return true;
  } catch (_) {
    return false;
  }
}

Future<List<Map<String, Object?>>> _evaluateGuidelines(
  WidgetTester tester,
) async {
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

// ---------------------------------------------------------------------------
// Viewport — where the fold is
// ---------------------------------------------------------------------------

/// The screen the walk is measured on.
///
/// Under `flutter drive` the device supplies all of this. Under `flutter test`
/// nothing does — the view is Flutter's hardcoded 800x600 @ 3.0, which is no
/// device — so the journey has to declare it, in `## Device`.
typedef DeviceProfile = ({
  String name,
  Size physicalSize, // physical px, as a real view reports it
  double devicePixelRatio,
  double padTop, // physical px; contentTop = padTop / devicePixelRatio
  double padBottom,
  TargetPlatform targetPlatform,
});

/// iPhone SE (3rd gen). The ONLY preset that ships, because it is the only one
/// whose every field is reproduced by a committed artifact —
/// `example/walk.json`, measured on that simulator: 375x667 logical, dpr 2.0,
/// contentTop 20.0, padBottom 0.0 (the SE has a home button, so its bottom
/// padding really is zero).
///
/// `pixel-6` and `ipad-13` are NOT here. CLAUDE.md records their size, dpr and
/// foldY, but not their `contentTop`, and inventing a status-bar height is
/// exactly the kind of unmeasured number this tool exists to refuse. They ship
/// after one calibration run each; until then a journey names explicit numbers.
const DeviceProfile kIphoneSe = (
  name: 'iphone-se',
  physicalSize: Size(750, 1334),
  devicePixelRatio: 2.0,
  padTop: 40.0,
  padBottom: 0.0,
  targetPlatform: TargetPlatform.iOS,
);

/// Resolve a `## Device` preset name.
///
/// Throws on an unknown name rather than substituting a default: a report
/// measured at a screen size nobody asked for, with nothing in the artifact
/// saying so, is worse than no report.
DeviceProfile deviceProfileByName(String name) {
  const Map<String, DeviceProfile> presets = <String, DeviceProfile>{
    'iphone-se': kIphoneSe,
  };
  final DeviceProfile? found = presets[name];
  if (found == null) {
    throw ArgumentError.value(
      name,
      'name',
      'unknown device preset — known: ${presets.keys.join(", ")}. '
          'Declare explicit numbers in `## Device` instead, e.g. '
          '"375x667 @2.0 contentTop 20 padBottom 0".',
    );
  }
  return found;
}

/// How `conditions.deviceProfile` names the screen this run used.
///
/// A run on the fallback is not a problem; a run on the fallback that the
/// artifact does not admit to is, because the report's scope clause would then
/// assert a fold line for a screen nobody chose.
String deviceProfileLabel(DeviceProfile d, {required bool declared}) =>
    declared ? d.name : '${d.name} (default, not declared)';

/// Make the test view look like [d]. The caller owns `tester.view.reset()`.
void applyDevice(WidgetTester tester, DeviceProfile d) {
  tester.view.physicalSize = d.physicalSize;
  tester.view.devicePixelRatio = d.devicePixelRatio;
  final FakeViewPadding pad = FakeViewPadding(
    top: d.padTop,
    bottom: d.padBottom,
  );
  tester.view.padding = pad;
  tester.view.viewPadding = pad;
}

/// Give the run real text metrics, and say where they came from.
///
/// `flutter test` renders every glyph as an em square (the "Ahem" test font),
/// which is not a cosmetic problem: measured against the simulator baseline,
/// the fixture's title went 112.3px -> 242.0px, two text blocks wrapped to an
/// extra line each, and the whole product list moved down 39px. Max drift
/// 153.6px. With a real font loaded: max 18.9px, median 0.0px.
///
/// Returns what the report must disclose:
/// - `'app'`          the app's own fonts, from its asset bundle. Exact.
/// - `'sdk-fallback'` the SDK's Roboto standing in for the platform default.
///                    Close, not exact — the placement caveat applies.
/// - `'none'`         neither was available; fold and placement are NOT
///                    assessable and the report says so.
///
/// Call this BEFORE `walkJourney`: the first frame already lays text out.
Future<String> loadFonts(WidgetTester tester) async {
  int appFamilies = 0;
  await tester.runAsync(() async {
    try {
      final Object? manifest = await rootBundle.loadStructuredData<Object?>(
        'FontManifest.json',
        (String s) async => jsonDecode(s),
      );
      for (final Map<String, Object?> font
          in (manifest! as List<Object?>).cast<Map<String, Object?>>()) {
        // A packaged font is declared as `packages/<pkg>/<family>`, which is
        // not the name a TextStyle asks for.
        final String family = (font['family']! as String).split('/').last;
        final FontLoader loader = FontLoader(family);
        for (final Map<String, Object?> asset
            in (font['fonts']! as List<Object?>).cast<Map<String, Object?>>()) {
          loader.addFont(rootBundle.load(asset['asset']! as String));
        }
        await loader.load();
        // MaterialIcons rides in on `uses-material-design: true` and is not
        // the app declaring a typeface — without this every Material app would
        // report 'app' and skip the fallback its TEXT still needs.
        if (family != 'MaterialIcons') {
          appFamilies++;
        }
      }
    } catch (_) {
      // No manifest, or an unreadable one. Being unable to measure text
      // metrics is a missing evidence layer, not a reason to abandon the walk.
    }
  });
  if (appFamilies > 0) {
    return 'app';
  }

  // A null fontFamily resolves to the test font no matter what is loaded —
  // measured: after loading, the default width was still 242.0 and only a
  // NAMED style dropped to 119.7. So register over the families the themes
  // actually name. Modern Flutter asks for CupertinoSystemDisplay/Text on iOS
  // and Roboto on Android; the older `.SF UI *` spelling is never asked for
  // and registering against it fails silently.
  final String? root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    return 'none';
  }
  final File regular = File(
    '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
  );
  if (!regular.existsSync()) {
    return 'none';
  }
  final Uint8List bytes = regular.readAsBytesSync();
  await tester.runAsync(() async {
    for (final String family in <String>[
      'Roboto',
      'CupertinoSystemDisplay',
      'CupertinoSystemText',
    ]) {
      final FontLoader loader = FontLoader(family)
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });
  return 'sdk-fallback';
}

/// The usable surface, in logical px.
///
/// `view.physicalSize` is the WHOLE display: it includes the status bar, the
/// notch and the home indicator, and it does not shrink when the keyboard is
/// up. Using it raw puts the fold line ~80-100 lpx too low on any modern phone
/// and ~300 lpx too low with a keyboard open, so `padding` and `viewInsets` are
/// subtracted here and reported alongside, for the reader to check.
///
/// In a plain `flutter test` the view is Flutter's hardcoded 800x600 @ 3.0
/// (flutter_test/src/binding.dart `_kDefaultTestViewportSize`), which is no
/// device at all. That case returns `foldY: null` so the report blanks every
/// fold column instead of quoting a fold for a phone that does not exist.
Map<String, Object?> viewportOf(WidgetTester tester) {
  final TestFlutterView view = tester.view;
  final double dpr = view.devicePixelRatio;
  final double w = view.physicalSize.width / dpr;
  final double h = view.physicalSize.height / dpr;
  final double contentTop = view.padding.top / dpr;
  final double padBottom = view.padding.bottom / dpr;
  final double insetBottom = view.viewInsets.bottom / dpr;
  final bool isTestDefault = w == 800.0 && h == 600.0 && dpr == 3.0;
  return <String, Object?>{
    // "Reading order" is top, then LEADING edge — left in ltr, right in rtl.
    // Without this the placement table comes out exactly reversed on an rtl
    // app and nothing in the artifact says which order produced it.
    'textDirection':
        (tester.platformDispatcher.locale.languageCode == 'ar' ||
            tester.platformDispatcher.locale.languageCode == 'he' ||
            tester.platformDispatcher.locale.languageCode == 'fa' ||
            tester.platformDispatcher.locale.languageCode == 'ur')
        ? 'rtl'
        : 'ltr',
    'width': w,
    'height': h,
    'devicePixelRatio': dpr,
    'contentTop': contentTop,
    'padBottom': padBottom,
    'keyboardInset': insetBottom,
    // A keyboard hides far more than a home indicator, and a control under it
    // is not on screen at all.
    'foldY': isTestDefault
        ? null
        : h - (insetBottom > padBottom ? insetBottom : padBottom),
    'isTestDefault': isTestDefault,
  };
}

/// True when two onstage `Navigator`s are SIBLINGS rather than nested — a
/// tablet master-detail `Row`, not a tab shell.
///
/// This is the only case in which the dump is knowingly incomplete. Every
/// `ModalRoute` wraps its barrier in `BlockSemantics`, which drops the
/// semantics of everything painted before it under the same boundary, and a
/// plain `Row`/`Expanded` introduces no boundary — so the LAST-PAINTED pane is
/// the only one in `nodes`. Measured on a 1032x1376 surface: a two-pane Row
/// dumps 2 of the 4 labels on screen; reversing the children reverses which
/// pane survives; replacing the LAST-PAINTED pane's `Navigator` with a plain
/// `Scaffold` brings both back, while replacing the first's does not. The
/// app-side remedy is `Semantics(container: true)` around each pane, which
/// also restores both — but nothing inside the walker can recover them, so it
/// reports the condition instead of pretending.
///
/// Nesting is the common case and blocks nothing: a tab shell mounts the root
/// `Navigator` and the active tab's, one inside the other. Counting navigators
/// would flag every such app and push its real findings to `not assessable`,
/// which is why this asks about ancestry instead.
bool hasSiblingNavigators(WidgetTester tester) {
  final List<Element> navs = tester
      .elementList(find.byType(Navigator))
      .toList();
  if (navs.length < 2) {
    return false;
  }
  final Element deepest = navs.last;
  final Set<Element> ancestors = <Element>{};
  deepest.visitAncestorElements((Element e) {
    ancestors.add(e);
    return true;
  });
  return navs.any((Element e) => e != deepest && !ancestors.contains(e));
}

/// The conditions the run was measured under.
///
/// Every number in a report is conditional on these, and until they were
/// recorded the report could only *assert* its scope. Measured on this fixture:
/// the same build walked at the system text size and at
/// `accessibility-extra-extra-extra-large` produces a byte-identical
/// `viewport` — 375x667, fold 667, dpr 2 — while the third product row leaves
/// the semantics tree entirely and the second drops below the fold. The two
/// artifacts are otherwise indistinguishable, so a reader comparing them
/// concludes the app changed.
///
/// `platformBrightness` is what the OS told the app, NOT the theme the app
/// chose. An app that declares no `darkTheme` renders light under a dark
/// platform, and this field will still read `dark` — correctly, because it
/// reports the condition, not the outcome. The outcome is in the contrast
/// measurements and the screenshots.
Map<String, Object?> conditionsOf(WidgetTester tester) {
  final TestPlatformDispatcher pd = tester.platformDispatcher;
  final AccessibilityFeatures a11y = pd.accessibilityFeatures;
  return <String, Object?>{
    'platform': Platform.operatingSystem,
    'platformVersion': Platform.operatingSystemVersion,
    'platformBrightness': pd.platformBrightness.name,
    'textScaleFactor': pd.textScaleFactor,
    'locale': pd.locale.toLanguageTag(),
    // Each of these changes what the guidelines measure: boldText and
    // highContrast repaint text, invertColors inverts the pixels the contrast
    // guideline samples, and disableAnimations changes what `settled` means.
    'boldText': a11y.boldText,
    'highContrast': a11y.highContrast,
    'invertColors': a11y.invertColors,
    'reduceMotion': a11y.reduceMotion,
    'disableAnimations': a11y.disableAnimations,
    'accessibleNavigation': a11y.accessibleNavigation,
  };
}

// ---------------------------------------------------------------------------
// Rect arithmetic — the effective (unobscured) tap target
// ---------------------------------------------------------------------------

/// [target] minus every rect in [obscurers], as a list of disjoint free rects.
///
/// A nominally compliant control can be left unhittable by something painted
/// over it while its own rect never changes — so every size-only check still
/// passes it. Measured on a production app: a 56dp CTA reduced to 17.2dp of
/// visible target by an error banner.
List<Rect> subtractRects(Rect target, Iterable<Rect> obscurers) {
  List<Rect> free = <Rect>[target];
  for (final Rect o in obscurers) {
    final List<Rect> next = <Rect>[];
    for (final Rect f in free) {
      final Rect i = f.intersect(o);
      // Rect.intersect returns a NEGATIVE-size rect when the two are disjoint.
      // Adding that area back reports more than 100% free.
      if (i.width <= 0 || i.height <= 0) {
        next.add(f);
        continue;
      }
      if (i.top > f.top) {
        next.add(Rect.fromLTRB(f.left, f.top, f.right, i.top));
      }
      if (i.bottom < f.bottom) {
        next.add(Rect.fromLTRB(f.left, i.bottom, f.right, f.bottom));
      }
      if (i.left > f.left) {
        next.add(Rect.fromLTRB(f.left, i.top, i.left, i.bottom));
      }
      if (i.right < f.right) {
        next.add(Rect.fromLTRB(i.right, i.top, f.right, i.bottom));
      }
    }
    free = next;
  }
  return free;
}

double areaOf(Iterable<Rect> rects) =>
    rects.fold<double>(0, (double a, Rect r) => a + r.width * r.height);

/// Does any obscurer contain [p]? The walker taps the centre of a target, so a
/// covered centre means the walk's own tap lands on the overlay.
bool coversPoint(Offset p, Iterable<Rect> obscurers) =>
    obscurers.any((Rect r) => r.contains(p));

// ---------------------------------------------------------------------------
// Screen identity
// ---------------------------------------------------------------------------

/// A stable id for "the screen as it currently stands".
///
/// Equal signatures mean the same screen in the same state — that is what makes
/// a back step's state loss and a dead tap checkable. It is deliberately NOT a
/// template id: the research proposed a content-free variant (drop labels, keep
/// quantised rects) and it was measured REFUTED, because text width IS content
/// — "Walnut Side Table" is 376dp and "Oak Side Table" is 312dp, so two
/// instances of one screen never collide at any quantisation.
String screenSignature(Map<String, Object?> dump) {
  final List<Map<String, Object?>> nodes =
      (dump['nodes'] as List<Map<String, Object?>>?) ??
      const <Map<String, Object?>>[];
  // Prefixed with the node's RANK in reading order. Without a prefix the sort
  // throws order away and every sort/reorder/move-up control in existence
  // reads as a dead tap. Rank rather than quantised pixels: a pixel bucket
  // puts its edge on Material's own 8-dp grid, where a 0.02 lpx relayout flips
  // the hash — measured. Rank is what a reorder actually changes.
  final List<Map<String, Object?>> ordered = nodes.toList()
    ..sort((Map<String, Object?> a, Map<String, Object?> b) {
      final List<double> ra = a['rect']! as List<double>;
      final List<double> rb = b['rect']! as List<double>;
      final int byTop = ra[1].compareTo(rb[1]);
      return byTop != 0 ? byTop : ra[0].compareTo(rb[0]);
    });
  final List<String> parts = <String>[];
  for (int i = 0; i < ordered.length; i++) {
    final Map<String, Object?> n = ordered[i];
    for (final Object? v in <Object?>[n['label'], n['tooltip'], n['value']]) {
      if (v is String && v.trim().isNotEmpty) {
        parts.add('$i:${_norm(v)}');
      }
    }
  }
  parts.sort();
  // FNV-1a. A hash, not a dependency; the raw parts stay in the dump so a
  // reader can always see what produced it.
  int h = 0x811c9dc5;
  for (final int c in parts.join('').codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

// ---------------------------------------------------------------------------
// Route state — DEAD-END as a measurement
// ---------------------------------------------------------------------------

/// Whether the user can leave this screen, and what else is on it.
///
/// `canPop` comes from the navigator NEAREST the current screen, not
/// `tester.firstState<NavigatorState>(...)`: `firstState` returns the ROOT
/// navigator, and in any tab-shell app (StatefulShellRoute, IndexedStack +
/// BottomNavigationBar) the root holds only the shell page — so it reads false
/// while the user is three pages deep inside a branch with a visible back
/// button.
///
/// Two more traps, both measured: `canPop` is ALSO false on a legitimate entry
/// screen (hence `tappableCount`, and the entry-screen exclusion in
/// heuristics.md), and it reads TRUE on a dead end while a modal is open
/// (hence `modalOpen`).
Map<String, Object?> routeState(
  WidgetTester tester, [
  Map<String, Object?>? dump,
]) {
  final Map<String, Object?> d = dump ?? dumpSemantics(tester);
  final List<Map<String, Object?>> nodes =
      (d['nodes'] as List<Map<String, Object?>>?) ??
      const <Map<String, Object?>>[];
  // The DEEPEST onstage Navigator, read directly. Two earlier attempts were
  // measured wrong: `tester.firstState<NavigatorState>(...)` returns the ROOT,
  // which in a tab shell holds only the shell page; and resolving from the
  // deepest Scaffold is not the same thing, because in the common
  // shell-owns-the-Scaffold shape that Scaffold sits ABOVE the per-tab
  // Navigators and the probe lands back on the root. Finders are onstage-only,
  // so hidden tabs do not compete. This also answers on screens with no
  // Scaffold at all, which the Scaffold probe could not.
  final List<Element> navs = tester
      .elementList(find.byType(Navigator))
      .toList();
  // Prefer the navigator that owns the thing this step is ABOUT. `navs.last`
  // is last in element pre-order, not deepest and not the user's: a persistent
  // mini-player, a side panel or a Navigator in `Scaffold.bottomSheet` is a
  // sibling built after the content, and one push inside it flips canPop while
  // the user's screen is unchanged — silently suppressing a DEAD-END.
  final NavigatorState? nav = navs.isEmpty
      ? null
      : (navs.last as StatefulElement).state as NavigatorState;

  final Map<String, Object?> vp =
      d['viewport'] as Map<String, Object?>? ?? viewportOf(tester);
  final double? foldY = vp['foldY'] as double?;
  int tappable = 0;
  int aboveFold = 0;
  int cover = 0;
  for (final Map<String, Object?> n in nodes) {
    // onScreen, not merely present: a scrollable's cache extent puts rows
    // below the fold into the dump, and counting them inflates every
    // surface number the placement table reasons from.
    if (n['tappable'] != true || n['onScreen'] != true) {
      continue;
    }
    if (n['coversSurface'] == true) {
      cover++;
      continue; // not a control the user can mean
    }
    tappable++;
    if (n['aboveFold'] == true) {
      aboveFold++;
    }
  }

  return <String, Object?>{
    'canPop': nav?.canPop(),
    // canPop is an answer about ONE navigator. With more than one onstage — a
    // persistent mini-player, a side panel, a Navigator in Scaffold.bottomSheet
    // — a push inside a SIBLING flips it while the user's screen is unchanged,
    // which would silently suppress a DEAD-END. The count is emitted so the
    // predicate can require 1, and so a reader knows when to distrust it.
    'navigatorCount': navs.length,
    // A dialog, sheet, popup menu or dropdown is up. Cheap cross-check on
    // canPop, which a modal otherwise silently inverts.
    //
    // Keyed on the barrier's DISMISSIBILITY, not its type. Two wrong versions
    // were measured first: `find.byType(ModalBarrier)` reads true on every
    // ordinary screen, because every ModalRoute mounts a barrier; narrowing to
    // AnimatedModalBarrier then missed the whole PopupRoute family, since
    // _PopupMenuRoute and _DropdownRoute return a null barrierColor and build
    // the plain one. A PageRoute's barrier is not dismissible; a transient
    // surface's is.
    'modalOpen':
        tester
            .widgetList<ModalBarrier>(find.byType(ModalBarrier))
            .any((ModalBarrier b) => b.dismissible) ||
        // A Drawer adds a local-history entry, so canPop flips true with no
        // barrier anywhere — its scrim is a GestureDetector. Ask the Scaffold
        // whether the drawer is OPEN: `DrawerController` is mounted whenever
        // `Scaffold.drawer != null`, open or shut, so probing for the widget
        // reported "a modal is open" on every screen of an app with a global
        // drawer — measured on a production app, where it would have
        // suppressed DEAD-END everywhere.
        tester
            .stateList<ScaffoldState>(find.byType(Scaffold))
            .any((ScaffoldState st) => st.isDrawerOpen || st.isEndDrawerOpen),
    // Excludes `coversSurface` nodes. DEAD-END's predicate reads this, and a
    // screen whose only tappable is the keyboard-dismiss GestureDetector is a
    // dead end — counting that node suppressed the finding.
    'tappableCount': tappable,
    'coverNodes': cover,
    'tappableAboveFold': foldY == null ? null : aboveFold,
  };
}

// ---------------------------------------------------------------------------
// The semantics dump
// ---------------------------------------------------------------------------

Map<String, Object?> dumpSemantics(WidgetTester tester) {
  final Map<String, Object?> viewport = viewportOf(tester);
  final double dpr = viewport['devicePixelRatio']! as double;
  final double? foldY = viewport['foldY'] as double?;
  final double vpWidth = viewport['width']! as double;
  final Rect surfaceRect = Rect.fromLTWH(
    0,
    0,
    vpWidth,
    viewport['height']! as double,
  );
  final SemanticsOwner? owner =
      tester.binding.renderViews.first.owner?.semanticsOwner;
  final SemanticsNode? root = owner?.rootSemanticsNode;
  final List<Map<String, Object?>> nodes = <Map<String, Object?>>[];
  final Map<int, int?> parentOf = <int, int?>{};
  final List<Rect> rects = <Rect>[];

  void walk(SemanticsNode node, Matrix4 inherited, int? parentId) {
    final SemanticsData data = node.getSemanticsData();
    // Trap 1: rects are LOCAL. Accumulate the parent chain or everything
    // nested reads (0,0) and the tap-target heuristic becomes garbage.
    final Matrix4 t = inherited.clone();
    if (node.transform != null) {
      t.multiply(node.transform!);
    }
    final Rect g = MatrixUtils.transformRect(t, data.rect); // physical px
    // logical px — the guidelines measure in logical px, so findings must
    // quote logical px or they cannot be compared to the reason strings.
    final Rect lg = Rect.fromLTWH(
      g.left / dpr,
      g.top / dpr,
      g.width / dpr,
      g.height / dpr,
    );
    parentOf[node.id] = parentId;
    rects.add(lg);
    nodes.add(<String, Object?>{
      'id': node.id,
      'label': data.attributedLabel.string,
      'value': data.attributedValue.string,
      'tooltip': data.tooltip,
      'identifier': data.identifier,
      'role': data.role.name,
      'flags': data.flagsCollection.toStrings(),
      'tappable': data.hasAction(
        SemanticsAction.tap,
      ), // Trap 3: action, not flag
      'rect': <double>[lg.left, lg.top, lg.width, lg.height],
      // Is any of it on the surface at all? A scrollable's cache extent puts
      // rows well above and below the viewport into the dump, with rects to
      // match; without this the walker taps coordinates off the screen.
      'onScreen': !lg.isEmpty && lg.overlaps(surfaceRect),
      // Can the user SEE it without scrolling? It must START in the visible
      // band. `top < foldY` alone counts a row scrolled to y=-250 as above the
      // fold; requiring the whole rect to fit was the over-correction — it
      // fails every bottom-pinned CTA and every hero taller than the fold,
      // which is most apps on any device with a home indicator. Null when the
      // viewport is the test default: there is no fold then.
      'aboveFold': foldY == null ? null : lg.top >= 0 && lg.top < foldY,
      // Fully inside the visible band, for anything that needs the stricter
      // question. Kept separate because conflating the two is what broke.
      'fullyVisible': foldY == null
          ? null
          : lg.top >= 0 &&
                lg.bottom <= foldY &&
                lg.left >= 0 &&
                lg.right <= vpWidth,
      // A big UNNAMED tappable is almost always the tap-to-dismiss-the-keyboard
      // GestureDetector, not a control. Asking "is this rect the surface" was
      // measured wrong: that idiom is written inside the Scaffold, so its rect
      // starts below the app bar and the flag read false on exactly the screens
      // it exists for. Ask what the exclusion is for instead — unnamed, and
      // more than half the surface — which also spares a LABELLED full-screen
      // "tap anywhere to continue".
      'coversSurface':
          data.hasAction(SemanticsAction.tap) &&
          !lg.isEmpty &&
          (data.attributedLabel.string.trim().isEmpty &&
              (data.tooltip).trim().isEmpty &&
              (data.identifier).trim().isEmpty) &&
          lg.width * lg.height > 0.5 * surfaceRect.width * surfaceRect.height,
    });
    node.visitChildren((SemanticsNode child) {
      walk(child, t, node.id);
      return true;
    });
  }

  if (root != null) {
    walk(root, Matrix4.identity(), null);
  }
  _annotateEffectiveArea(nodes, parentOf, rects);
  return <String, Object?>{
    'devicePixelRatio': dpr,
    'viewport': viewport,
    'semanticsEnabled': root != null,
    // When true, `nodes` covers only the last-painted pane — see
    // hasSiblingNavigators. Every check derived from the dump must be reported
    // `not assessable` for the other pane rather than as an absence of findings.
    'panesPossiblyBlocked': hasSiblingNavigators(tester),
    'nodes': nodes,
  };
}

/// Fills `effectivePct`, `centreCovered` and `obscuredBy` on every tap target.
///
/// The dump is emitted in PAINT order, so a node that appears later and is not
/// a descendant is painted over this one. Ancestors are already excluded by
/// coming first; descendants are excluded explicitly, or a card would obscure
/// itself with its own label.
///
/// This is GEOMETRY, not a hit test: the semantics tree carries no opacity and
/// no IgnorePointer, so an overlapping decorative node counts here and a
/// transparent one does too. heuristics.md therefore requires VISUAL
/// confirmation before this raises a finding.
void _annotateEffectiveArea(
  List<Map<String, Object?>> nodes,
  Map<int, int?> parentOf,
  List<Rect> rects,
) {
  bool isDescendantOf(int candidate, int ancestor) {
    int? p = parentOf[candidate];
    while (p != null) {
      if (p == ancestor) {
        return true;
      }
      p = parentOf[p];
    }
    return false;
  }

  for (int i = 0; i < nodes.length; i++) {
    if (nodes[i]['tappable'] != true) {
      continue;
    }
    final Rect target = rects[i];
    if (target.width <= 0 || target.height <= 0) {
      nodes[i]['effectivePct'] = 0.0;
      nodes[i]['centreCovered'] = null;
      continue;
    }
    final int id = nodes[i]['id']! as int;
    final List<Rect> obscurers = <Rect>[];
    final List<String> by = <String>[];
    for (int j = i + 1; j < nodes.length; j++) {
      final int other = nodes[j]['id']! as int;
      if (isDescendantOf(other, id)) {
        continue;
      }
      final Rect o = rects[j];
      final Rect hit = target.intersect(o);
      if (hit.width <= 0 || hit.height <= 0) {
        continue;
      }
      obscurers.add(o);
      final Object? label = nodes[j]['label'] ?? nodes[j]['tooltip'];
      by.add(label is String && label.isNotEmpty ? label : 'node $other');
    }
    final List<Rect> free = subtractRects(target, obscurers);
    nodes[i]['effectivePct'] = areaOf(free) / (target.width * target.height);
    // The walker taps the centre, so this is the difference between a
    // cosmetic overlap and a control the journey cannot press.
    nodes[i]['centreCovered'] = coversPoint(target.center, obscurers);
    if (by.isNotEmpty) {
      nodes[i]['obscuredBy'] = by.take(3).toList();
    }
  }
}

// ---------------------------------------------------------------------------
// Selection and actions
// ---------------------------------------------------------------------------

String _norm(String s) =>
    s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

/// Matches over label ∪ tooltip ∪ value (Trap 2), normalised substring, and
/// ERRORS on ambiguity instead of silently auditing a different widget.
Map<String, Object?> resolve(WidgetTester tester, String needle, [int? nth]) {
  final Map<String, Object?> dump = dumpSemantics(tester);
  final String n = _norm(needle);
  final List<Map<String, Object?>> hits =
      (dump['nodes']! as List<Map<String, Object?>>).where((
        Map<String, Object?> node,
      ) {
        final String hay = _norm(
          <Object?>[node['label'], node['tooltip'], node['value']].join(' '),
        );
        return hay.contains(n);
      }).toList();
  if (hits.isEmpty) {
    throw StateError('no semantics node matches "$needle"');
  }
  if (hits.length > 1) {
    // A substring selector legitimately matches a label and a longer label
    // containing it — a password field and a "forgot password" link, measured
    // on a real app. When exactly one hit matches EXACTLY, that is
    // unambiguously the one meant; anything else stays an error rather than
    // silently auditing the wrong widget.
    final List<Map<String, Object?>> exact = hits.where((
      Map<String, Object?> node,
    ) {
      return <Object?>[
        node['label'],
        node['tooltip'],
        node['value'],
      ].any((Object? v) => v is String && _norm(v) == n);
    }).toList();
    if (nth != null) {
      if (nth < 1 || nth > hits.length) {
        throw StateError(
          'nth: $nth is out of range — "$needle" matches ${hits.length}',
        );
      }
      return hits[nth - 1];
    }
    if (exact.length == 1) {
      return exact.single;
    }
    // Say how to fix it. A bare "ambiguous" makes the author guess.
    final String opts = hits
        .asMap()
        .entries
        .map(
          (MapEntry<int, Map<String, Object?>> e) =>
              '${e.key + 1}=${e.value['label']} @${(e.value['rect']! as List<double>)[2].toStringAsFixed(0)}x${(e.value['rect']! as List<double>)[3].toStringAsFixed(0)}',
        )
        .join(', ');
    throw StateError(
      'ambiguous: ${hits.length} nodes match "$needle" — $opts. '
      'Add nth: N to pick one.',
    );
  }
  return hits.single;
}

/// Type into the field identified by the same label selector used for taps.
///
/// `tester.enterText` is the only entry point that establishes the text-input
/// connection (it calls `showKeyboard` first). Tapping the field and then
/// pushing text through `testTextInput` directly does NOT — the field stays
/// empty and the walk hangs. Measured on a production app.
///
/// enterText needs a Finder, but the selector model is label-based, so the
/// semantics node is mapped to its EditableText by geometry.
Future<bool> _typeInto(
  WidgetTester tester,
  String needle,
  String text, [
  int? nth,
]) async {
  final Map<String, Object?> node = resolve(tester, needle, nth);
  final List<double> r = node['rect']! as List<double>;
  final Rect target = Rect.fromLTWH(r[0], r[1], r[2], r[3]);

  // Largest OVERLAP, not "is the centre inside". A field whose semantics node
  // spans its label, helper text and a multi-line error is much taller than
  // its editable, so its centre can fall outside the box it belongs to — the
  // same geometric failure that was removed from the tap path.
  Element? hit;
  double best = 0;
  for (final Element e in find.byType(EditableText).evaluate()) {
    final RenderBox? box = e.renderObject as RenderBox?;
    if (box == null || !box.hasSize) {
      continue;
    }
    final Rect b = box.localToGlobal(Offset.zero) & box.size;
    final Rect i = b.intersect(target);
    final double overlap = (i.width <= 0 || i.height <= 0)
        ? 0
        : i.width * i.height;
    if (overlap > best) {
      best = overlap;
      hit = e;
    }
  }
  if (hit == null) {
    throw StateError(
      '"$needle" resolves to a node with no editable field under it',
    );
  }
  final Element field = hit;
  await tester.enterText(
    find.byElementPredicate((Element e) => e == field),
    text,
  );
  // Asked of the widget, not of the semantics flags: `EditableText.obscureText`
  // is the property that decides it, and reading it directly needs no guess
  // about what `flagsCollection.toStrings()` happens to call it.
  return (field.widget as EditableText).obscureText;
}

Future<void> _tapTarget(WidgetTester tester, String needle, [int? nth]) async {
  final Map<String, Object?> node = resolve(tester, needle, nth);
  if (node['tappable'] != true) {
    throw StateError('"$needle" carries no tap action');
  }
  final List<double> r = node['rect']! as List<double>;
  final Offset centre = Offset(r[0] + r[2] / 2, r[1] + r[3] / 2);
  // Refuse only what is genuinely unreachable. A node can be in the dump and
  // off the surface — a scrollable's cache extent holds rows above and below
  // the viewport — and tapping there dispatches into nothing: the gesture is
  // recorded as sent, the semantics do not change, and a working list row gets
  // reported as a dead control. That is the exact false finding this tool
  // exists not to produce.
  final Map<String, Object?> vp = viewportOf(tester);
  final double? foldY = vp['foldY'] as double?;
  final Rect surface = Rect.fromLTWH(
    0,
    0,
    vp['width']! as double,
    vp['height']! as double,
  );
  // The CENTRE must be on the surface, not merely the rect. A node can overlap
  // the surface and still have its middle off it — measured while a route was
  // sliding in, where the tap went to x=431 on a 375-wide screen and hit
  // nothing at all.
  if (node['onScreen'] != true || !surface.contains(centre)) {
    throw StateError(
      '"$needle" is not reachable: its centre is at '
      '(${centre.dx.toStringAsFixed(1)}, ${centre.dy.toStringAsFixed(1)}) on a '
      '${surface.width.toStringAsFixed(0)}x${surface.height.toStringAsFixed(0)} surface',
    );
  }
  if (foldY != null && centre.dy > foldY) {
    throw StateError(
      '"$needle" has its centre below the fold at y=${centre.dy} '
      '(visible to y=$foldY) — this journey cannot reach it without scrolling',
    );
  }
  // NOT refused for being covered. `centreCovered` is geometry, not a hit
  // test: the semantics tree has no opacity and no IgnorePointer, and a
  // measured counter-example — a badge whose padded layout box swallows a
  // button's centre — leaves the button perfectly tappable at 94% free area.
  // Refusing there would fail a whole audit on an overlay that blocks nothing.
  // The measurement stays in the dump; heuristics.md gates the finding on
  // VISUAL confirmation.
  await tester.tapAt(centre); // logical px
}

void _requireTarget(WidgetTester tester, String needle) =>
    resolve(tester, needle);
