// The journey walker for example/journey.md, in the shape the skill generates.
// See skills/flutter-ux-journey/references/walking.md — this file is the
// worked, executed instance of that recipe.

import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:ux_demo_app/main.dart' as app;

/// One journey step: tap [target], then require [expected] to be on screen.
/// The `expected` check is the oracle — without it a walk reports a dispatch
/// instead of a result, which is why integration_test was chosen at all.
/// [action] is 'tap' or 'type'. For 'type', [text] is the value entered —
/// always ARBITRARY data. The walker never receives real credentials: an audit
/// tool must not ask for them, and must not authenticate against production.
typedef Step = ({String action, String target, String? text, String expected});

const List<Step> journey = <Step>[
  // 1. Open a saved product.
  (action: 'tap', target: 'Walnut Side Table', text: null, expected: '189,000 KRW'),
  // 2. Remove it — the journey demands a confirmation before data is destroyed.
  (action: 'tap', target: 'Remove from list', text: null, expected: 'Cancel'),
  // 3. Get back to the list to keep browsing.
  (action: 'tap', target: 'Back', text: null, expected: 'Saved items'),
];

/// iOS only. See the note at convertFlutterSurfaceToImage below.
final bool _inTestScreenshots = Platform.isIOS;

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final List<Map<String, Object?>> steps = <Map<String, Object?>>[];

  testWidgets('ux journey', (WidgetTester tester) async {
    // Never assume semantics are already on. Cheap, and required by the docs.
    final SemanticsHandle handle = tester.ensureSemantics();

    // An app's own errors are FINDINGS, not a reason to abort. Without this, a
    // late async exception fails the test and discards the whole report.
    final List<String> appErrors = <String>[];
    FlutterError.onError = (FlutterErrorDetails details) {
      appErrors.add(details.exceptionAsString());
    };

    app.main();
    // NOT pumpAndSettle: it waits out a 10-minute timeout on any app that
    // animates continuously. This fixture does not, but the generated walker
    // must, so the fixture exercises the same code path.
    final bool entrySettled = await _settle(tester, limit: const Duration(seconds: 12));

    // In-test screenshots are iOS-only here. On Android,
    // convertFlutterSurfaceToImage() + takeScreenshot() deadlocks — no error,
    // no timeout — whenever the app embeds platform views (webview, media,
    // camera). Measured twice on a production app. Guidelines and the
    // semantics dump are unaffected, so the walk still measures; the host
    // captures the visual layer with `adb exec-out screencap` instead.
    if (_inTestScreenshots) {
      await binding.convertFlutterSurfaceToImage();
    }

    // --- SETUP: excluded from measurement and scoring. -----------------------
    // example/journey.md declares no setup: no backend, no login.
    // -------------------------------------------------------------------------

    for (final Step step in journey) {
      final int i = steps.length + 1;

      // Capture BEFORE the tap: the screen a step starts on is the screen that
      // holds the target being tapped, so that is the screen whose tap targets
      // and contrast the step is about.
      final Map<String, Object?> semantics = _dumpSemantics(tester);
      final List<Map<String, Object?>> guidelines = await _evaluateGuidelines(tester);
      if (_inTestScreenshots) {
        await binding.takeScreenshot('step_$i');
      }

      final Stopwatch sw = Stopwatch()..start();
      String status = 'OK';
      String? error;
      bool settled = true;
      try {
        switch (step.action) {
          case 'type':
            await _typeInto(tester, step.target, step.text!);
          case 'tap':
            await _tapTarget(tester, step.target);
          default:
            throw StateError('unknown action "\${step.action}"');
        }
        settled = await _settle(tester);
        _requireTarget(tester, step.expected); // the oracle
      } catch (e) {
        status = 'FAILED';
        error = e.toString();
      }
      sw.stop();

      steps.add(<String, Object?>{
        'index': i,
        'action': step.action,
        'target': step.target,
        'text': step.text,
        'expected': step.expected,
        'status': status,
        'error': error,
        'elapsedMs': sw.elapsedMilliseconds, // EVIDENCE ONLY — never scored
        'settled': settled,
        'screenshot': _inTestScreenshots ? 'step_$i.png' : null,
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
    steps.add(<String, Object?>{
      'index': steps.length + 1,
      'action': 'outcome',
      'target': null,
      'text': null,
      'expected': null,
      'status': 'OK',
      'error': null,
      'elapsedMs': 0,
      'settled': await _settle(tester),
      'screenshot': null,
      'semantics': _dumpSemantics(tester),
      'guidelines': await _evaluateGuidelines(tester),
    });

    handle.dispose();
    // MUTATE, never replace: takeScreenshot appends each PNG into
    // reportData['screenshots'], and that list is how the driver's
    // onScreenshot gets the bytes. Assigning a fresh map here silently
    // deletes every screenshot and the run still passes.
    final Map<String, dynamic> report = binding.reportData ??= <String, dynamic>{};
    report['steps'] = steps;
    // A journey whose entry screen never settles is already telling you
    // something — record it rather than dropping it.
    report['entrySettled'] = entrySettled;
    report['appErrors'] = appErrors;
  });
}

/// Pump until the frame queue is quiet or [limit] elapses, then carry on.
/// `pumpAndSettle` only gives up after a 10-minute default timeout, so a
/// perpetual animation hangs the whole run instead of producing a report.
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
  return false;
}

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

Map<String, Object?> _dumpSemantics(WidgetTester tester) {
  final double dpr = tester.view.devicePixelRatio;
  final SemanticsNode root =
      tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!;
  final List<Map<String, Object?>> nodes = <Map<String, Object?>>[];

  void walk(SemanticsNode node, Matrix4 inherited) {
    final SemanticsData data = node.getSemanticsData();
    // Trap 1: rects are LOCAL. Accumulate the parent chain or everything
    // nested reads (0,0) and the tap-target heuristic becomes garbage.
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
      // logical px — the guidelines measure in logical px, so findings must
      // quote logical px or they cannot be compared to the reason strings.
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

String _norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

/// Matches over label ∪ tooltip ∪ value (Trap 2), normalised substring, and
/// ERRORS on ambiguity instead of silently auditing a different widget.
Map<String, Object?> _resolve(WidgetTester tester, String needle) {
  final Map<String, Object?> dump = _dumpSemantics(tester);
  final String n = _norm(needle);
  final List<Map<String, Object?>> hits =
      (dump['nodes']! as List<Map<String, Object?>>).where((Map<String, Object?> node) {
    final String hay = _norm(<Object?>[node['label'], node['tooltip'], node['value']].join(' '));
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

Future<void> _tapTarget(WidgetTester tester, String needle) async {
  final Map<String, Object?> node = _resolve(tester, needle);
  if (node['tappable'] != true) {
    throw StateError('"$needle" carries no tap action');
  }
  final List<double> r = node['rect']! as List<double>;
  await tester.tapAt(Offset(r[0] + r[2] / 2, r[1] + r[3] / 2)); // logical px
}

void _requireTarget(WidgetTester tester, String needle) => _resolve(tester, needle);
