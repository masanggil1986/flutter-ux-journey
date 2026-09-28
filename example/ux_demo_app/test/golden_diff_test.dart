// The golden auto-diff. CLAUDE.md calls example/expected-findings.json a
// regression oracle, but nothing ever compared it to a run: recipe_sync_test.dart
// checks its SHAPE only, so every measured number in it was trusted on sight.
//
// GROUP 1 needs no device. example/walk.json is raw walk data committed from a
// verified iPhone SE (3rd gen) / iOS 18.6 run, so the golden's numbers can be
// checked against the measurement they claim to come from on every
// `flutter test`. The reading-order assertion is the reason this file exists:
// "your rank-1 task is the 6th of 8" is arithmetic a model does by hand and
// labels RUNTIME, and this test is what makes that label true.
//
// GROUP 2 is the only thing that closes the last link — that the committed walk
// data is still what a run produces. Group 1 can only prove the golden agrees
// with walk.json; if walk.json itself went stale, both would agree and both
// would be wrong. Group 2 is closed whenever someone drives, not on every
// `flutter test`: it reads build/integration_response_data.json and skips when
// no run has left one behind.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _walk = '../walk.json';
const String _golden = '../expected-findings.json';
const String _run = 'build/integration_response_data.json';

const String _driveCommand =
    'flutter drive --driver=test_driver/integration_test.dart '
    '--target=integration_test/ux_journey_test.dart -d <device-id>';

/// The golden re-keys exactly two of the walker's viewport fields, to say the
/// unit in the name. Everything else — devicePixelRatio, contentTop, padBottom,
/// foldY, isTestDefault, textDirection — carries the SAME name on both sides,
/// so a golden key that is not in this map and not in the walk data is a
/// mismatch, not a rename. (The walk data also carries keyboardInset, which the
/// golden omits; the golden is a subset, checked one-directionally below.)
const Map<String, String> _viewportGoldenToWalk = <String, String>{
  'widthLogicalPx': 'width',
  'heightLogicalPx': 'height',
};

/// Step fields that mean the same thing on any device. `elapsedMs` is wall
/// clock and `screenSig`/rects are platform-dependent, so neither is here.
const List<String> _portableStepFields = <String>[
  'status',
  'error',
  'settled',
  'dispatched',
  'semanticsUnchanged',
  'tapsSoFar',
];

const List<String> _conditionFields = <String>[
  'platform',
  'platformVersion',
  'platformBrightness',
  'textScaleFactor',
  'locale',
  'boldText',
  'highContrast',
  'invertColors',
  'reduceMotion',
  'disableAnimations',
  'accessibleNavigation',
];

Map<String, Object?>? _readJson(String path) {
  final File file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

List<Map<String, Object?>> _mapsAt(Map<String, Object?> report, String key) =>
    (report[key]! as List<Object?>).cast<Map<String, Object?>>();

Map<String, Object?> _stepByIndex(Map<String, Object?> walk, int index) =>
    _mapsAt(
      walk,
      'steps',
    ).firstWhere((Map<String, Object?> s) => s['index'] == index);

List<Map<String, Object?>> _nodesOf(Map<String, Object?> step) =>
    ((step['semantics']! as Map<String, Object?>)['nodes']! as List<Object?>)
        .cast<Map<String, Object?>>();

/// What the entry surface promotes, in the order a reader meets it: top edge
/// first, then the leading edge. `coversSurface` nodes are excluded because a
/// full-screen keyboard-dismiss GestureDetector is not a promoted control.
List<Map<String, Object?>> _readingOrder(Map<String, Object?> step) {
  final List<Map<String, Object?>> tappable = _nodesOf(step)
      .where(
        (Map<String, Object?> n) =>
            n['tappable'] == true &&
            n['onScreen'] == true &&
            n['coversSurface'] != true,
      )
      .toList();
  tappable.sort((Map<String, Object?> a, Map<String, Object?> b) {
    final List<Object?> ra = a['rect']! as List<Object?>;
    final List<Object?> rb = b['rect']! as List<Object?>;
    final int byTop = (ra[1]! as num).compareTo(rb[1]! as num);
    return byTop != 0 ? byTop : (ra[0]! as num).compareTo(rb[0]! as num);
  });
  return tappable;
}

/// A node's name is label ∪ tooltip ∪ value: `tooltip:` does not fill label, so
/// a matcher that reads label alone misses every tooltipped icon button.
String? _nameOf(Map<String, Object?> node) {
  for (final String field in <String>['label', 'tooltip', 'value']) {
    final String v = (node[field] as String? ?? '').trim();
    if (v.isNotEmpty) {
      return v;
    }
  }
  return null;
}

List<String> _failingGuidelines(Map<String, Object?> step) =>
    (step['guidelines']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .where((Map<String, Object?> g) => g['passed'] != true)
        .map((Map<String, Object?> g) => g['guideline']! as String)
        .toList();

List<String> _failingGuidelineReasons(Map<String, Object?> step) =>
    (step['guidelines']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .where((Map<String, Object?> g) => g['passed'] != true)
        .map((Map<String, Object?> g) => '${g['guideline']}: ${g['reason']}')
        .toList();

void main() {
  /// Registers a test that needs both fixtures. The demo app also ships
  /// standalone; outside the repo there is nothing to check and that is not a
  /// failure.
  void goldenTest(
    String description,
    void Function(Map<String, Object?> golden, Map<String, Object?> walk) body,
  ) {
    test(description, () {
      for (final String path in <String>[_golden, _walk]) {
        if (!File(path).existsSync()) {
          markTestSkipped('$path not present — running outside the repo');
          return;
        }
      }
      body(_readJson(_golden)!, _readJson(_walk)!);
    });
  }

  group('the golden agrees with the walk data it was measured from', () {
    goldenTest('conditions', (
      Map<String, Object?> golden,
      Map<String, Object?> walk,
    ) {
      final Map<String, Object?> g =
          golden['conditions']! as Map<String, Object?>;
      final Map<String, Object?> w =
          walk['conditions']! as Map<String, Object?>;
      // Pinned to a list, not to each other: a condition dropped from BOTH
      // sides would otherwise pass silently, and the report's scope clause
      // quotes all eleven.
      expect(g.keys.toSet(), _conditionFields.toSet());
      expect(w.keys.toSet(), _conditionFields.toSet());
      for (final String field in _conditionFields) {
        expect(g[field], w[field], reason: 'conditions.$field');
      }
    });

    goldenTest('viewport, modulo the two renamed keys', (
      Map<String, Object?> golden,
      Map<String, Object?> walk,
    ) {
      final Map<String, Object?> g =
          golden['viewport']! as Map<String, Object?>;
      final Map<String, Object?> w =
          (_stepByIndex(walk, 1)['semantics']!
                  as Map<String, Object?>)['viewport']!
              as Map<String, Object?>;
      for (final MapEntry<String, Object?> entry in g.entries) {
        final String walkKey = _viewportGoldenToWalk[entry.key] ?? entry.key;
        expect(
          w.containsKey(walkKey),
          isTrue,
          reason:
              'viewport.${entry.key} has no counterpart "$walkKey" in the walk data',
        );
        expect(entry.value, w[walkKey], reason: 'viewport.${entry.key}');
      }
    });

    goldenTest('steps, field by field', (
      Map<String, Object?> golden,
      Map<String, Object?> walk,
    ) {
      final List<Map<String, Object?>> g = _mapsAt(golden, 'steps');
      final List<Map<String, Object?>> w = _mapsAt(walk, 'steps');
      expect(g.length, w.length, reason: 'step count');
      for (int i = 0; i < g.length; i++) {
        final String where = 'steps[$i] (${g[i]['action']})';
        expect(g[i]['index'], w[i]['index'], reason: '$where.index');
        for (final String field in _portableStepFields) {
          // The golden stores the walker's error string verbatim and omits the
          // key entirely when there was none, so absent normalises to null and
          // nothing else needs normalising.
          expect(g[i][field], w[i][field], reason: '$where.$field');
        }
        expect(
          g[i]['surface'],
          equals(w[i]['surface']),
          reason: '$where.surface',
        );
      }
    });

    goldenTest('reach.tapsLanded is the walk taps', (
      Map<String, Object?> golden,
      Map<String, Object?> walk,
    ) {
      expect(
        (golden['reach']! as Map<String, Object?>)['tapsLanded'],
        walk['taps'],
      );
    });

    goldenTest('entrySurface is step 1 in reading order', (
      Map<String, Object?> golden,
      Map<String, Object?> walk,
    ) {
      final Map<String, Object?> entry =
          golden['entrySurface']! as Map<String, Object?>;
      final Map<String, Object?> step1 = _stepByIndex(walk, 1);
      final Map<String, Object?> surface =
          step1['surface']! as Map<String, Object?>;
      expect(entry['tappableCount'], surface['tappableCount']);
      expect(entry['tappableAboveFold'], surface['tappableAboveFold']);

      final List<Map<String, Object?>> derived = _readingOrder(step1);
      final List<Map<String, Object?>> order =
          (entry['order']! as List<Object?>).cast<Map<String, Object?>>();
      expect(order.length, derived.length, reason: 'entrySurface.order length');
      for (int i = 0; i < order.length; i++) {
        final String where = 'entrySurface.order[$i]';
        expect(order[i]['n'], i + 1, reason: '$where.n');
        expect(
          order[i]['rectLogicalPx'],
          equals(derived[i]['rect']),
          reason: '$where.rectLogicalPx',
        );
        expect(order[i]['name'], _nameOf(derived[i]), reason: '$where.name');
      }

      // The claim the whole placement finding rests on: the journey's rank-1
      // target is Nth of M. Derived here, not copied from the golden.
      final Map<String, Object?> flat = _mapsAt(
        golden,
        'findings',
      ).firstWhere((Map<String, Object?> f) => f['check'] == 'HIERARCHY-FLAT');
      final Map<String, Object?> m =
          flat['measurement']! as Map<String, Object?>;
      final int ordinal =
          derived.indexWhere(
            (Map<String, Object?> n) =>
                '${n['rect']}' == '${m['rectLogicalPx']}',
          ) +
          1;
      expect(
        ordinal,
        greaterThan(0),
        reason: 'HIERARCHY-FLAT rect is not on the entry surface',
      );
      expect(m['ordinal'], ordinal, reason: 'HIERARCHY-FLAT.ordinal');
      expect(
        m['ofTappable'],
        derived.length,
        reason: 'HIERARCHY-FLAT.ofTappable',
      );
    });

    goldenTest('every finding rect was measured on a step it names', (
      Map<String, Object?> golden,
      Map<String, Object?> walk,
    ) {
      for (final Map<String, Object?> finding in _mapsAt(golden, 'findings')) {
        final Map<String, Object?> m =
            finding['measurement']! as Map<String, Object?>;
        final Object? rect = m['rectLogicalPx'];
        if (rect == null) {
          continue; // A surface-shaped finding (DEAD-END) measures no rect.
        }
        final List<Object?> named = finding['steps']! as List<Object?>;
        final bool found = named.any(
          (Object? index) => _nodesOf(_stepByIndex(walk, index! as int))
              .any((Map<String, Object?> node) => '${node['rect']}' == '$rect'),
        );
        expect(
          found,
          isTrue,
          reason:
              '${finding['check']} #${finding['id']}: rect $rect is on no node of '
              'step(s) $named — the measurement cites a step it was not measured on',
        );
      }
    });

    goldenTest('screenSig, on the platform it was hashed on', (
      Map<String, Object?> golden,
      Map<String, Object?> walk,
    ) {
      final Object? platform =
          (walk['conditions']! as Map<String, Object?>)['platform'];
      if (platform != 'ios') {
        // The golden says why near its end: Material's BackButton carries both
        // a label and a tooltip on Android but only a tooltip on iOS, so the
        // detail screen hashes to 70ed0c2e there against 4ddc18db here.
        markTestSkipped(
          'screenSig is not portable across platforms and this walk data is from '
          '"$platform", not ios',
        );
        return;
      }
      final List<Map<String, Object?>> g = _mapsAt(golden, 'steps');
      final List<Map<String, Object?>> w = _mapsAt(walk, 'steps');
      for (int i = 0; i < g.length; i++) {
        expect(
          g[i]['screenSig'],
          w[i]['screenSig'],
          reason: 'steps[$i].screenSig',
        );
      }
    });
  });

  group('a fresh run agrees with the committed walk data', () {
    test('build/integration_response_data.json matches $_walk', () {
      final Map<String, Object?>? run = _readJson(_run);
      if (run == null) {
        markTestSkipped(
          '$_run not present — this half needs a device. Run: $_driveCommand',
        );
        return;
      }
      final Map<String, Object?>? walk = _readJson(_walk);
      if (walk == null) {
        markTestSkipped('$_walk not present — running outside the repo');
        return;
      }
      // One output path, two committed journeys. gated_journey_test.dart writes
      // here too, and comparing its result against the ungated walk data would
      // print a wall of differences that mean nothing.
      if ((run['setupSteps']! as List<Object?>).isNotEmpty &&
          (walk['setupSteps']! as List<Object?>).isEmpty) {
        markTestSkipped(
          '$_run is from a run with `## Setup` steps, so it is the gated '
          'journey, not the one $_walk records. Re-run: $_driveCommand',
        );
        return;
      }

      final bool samePlatform =
          (run['conditions']! as Map<String, Object?>)['platform'] ==
          (walk['conditions']! as Map<String, Object?>)['platform'];

      for (final String key in <String>['steps', 'setupSteps']) {
        final List<Map<String, Object?>> got = _mapsAt(run, key);
        final List<Map<String, Object?>> want = _mapsAt(walk, key);
        expect(got.length, want.length, reason: '$key length');
        for (int i = 0; i < want.length; i++) {
          for (final String field in _portableStepFields) {
            expect(got[i][field], want[i][field], reason: '$key[$i].$field');
          }
          expect(
            got[i]['surface'],
            equals(want[i]['surface']),
            reason: '$key[$i].surface',
          );
        }
      }

      expect(run['setupFailed'], walk['setupFailed']);
      expect(run['networkCalls'], equals(walk['networkCalls']));
      expect(run['taps'], walk['taps']);

      final List<Map<String, Object?>> got = _mapsAt(run, 'steps');
      final List<Map<String, Object?>> want = _mapsAt(walk, 'steps');
      for (int i = 0; i < want.length; i++) {
        expect(
          _failingGuidelines(got[i]),
          equals(_failingGuidelines(want[i])),
          reason: 'steps[$i] failing guidelines',
        );
        if (samePlatform) {
          // The reason strings embed pixel Rects, so they only compare on the
          // platform the committed walk data came from.
          expect(
            _failingGuidelineReasons(got[i]),
            equals(_failingGuidelineReasons(want[i])),
            reason: 'steps[$i] guideline reasons',
          );
          expect(
            got[i]['screenSig'],
            want[i]['screenSig'],
            reason: 'steps[$i].screenSig',
          );
        }
      }
    });
  });
}
