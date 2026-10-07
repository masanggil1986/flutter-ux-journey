// The walk, run with no device, checked against the run that had one.
//
// example/walk.json was measured on an iPhone SE (3rd gen) simulator. This
// reproduces its conditions under `flutter test` and asserts the things that
// must not move: what each step did, which screen it was on, and what the four
// guidelines decided. Rects are compared only within a bound — the fallback
// font is Roboto where the simulator had SF — and the contrast RATIO not at all,
// because the headless rasterizer reports 1.36 where the device reported 1.03
// on the same node. Both conditions are recorded in the artifact instead.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ux_demo_app/main.dart' as app;

import '../ux_audit/ux_journey_test.dart'
    show applyDevice, journey, kIphoneSe, loadFonts, walkJourney, writePng;

const String _baseline = '../walk.json';

void main() {
  testWidgets('the headless walk decides what the simulator walk decided', (
    WidgetTester tester,
  ) async {
    final File file = File(_baseline);
    if (!file.existsSync()) {
      markTestSkipped('$_baseline not present — running outside the repo');
      return;
    }
    final Map<String, Object?> sim =
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

    // Reset inline, never in addTearDown: _verifyInvariants runs at the end of
    // the test BODY and fails on a foundation debug variable left set, while
    // teardowns run after it.
    debugDefaultTargetPlatformOverride = kIphoneSe.targetPlatform;
    applyDevice(tester, kIphoneSe);
    addTearDown(tester.view.reset);
    final String fontSource = await loadFonts(tester);

    // A real `shot`, into a scratch dir: the entry's capture path is otherwise
    // unexecuted by the suite, and a step that records `step_1.png` for a file
    // nobody wrote points step 4 of the audit at nothing.
    final Directory shots = Directory.systemTemp.createTempSync(
      'ux-walk-shots',
    );
    addTearDown(() => shots.deleteSync(recursive: true));

    Map<String, Object?>? here;
    await walkJourney(
      tester,
      launch: app.main,
      journey: journey,
      shot: (String name) => writePng(tester, '${shots.path}/$name.png'),
      publish: (Map<String, Object?> r) async => here = r,
      runContext: <String, Object?>{
        'mode': 'widget-test',
        'fontSource': fontSource,
      },
    );

    final List<Object?> a = sim['steps']! as List<Object?>;
    final List<Object?> b = here!['steps']! as List<Object?>;
    expect(b, hasLength(a.length));

    for (int i = 0; i < a.length; i++) {
      final Map<String, Object?> x = a[i]! as Map<String, Object?>;
      final Map<String, Object?> y = b[i]! as Map<String, Object?>;
      final String at = 'step ${i + 1} (${x['action']} ${x['target']})';

      // The oracle. If this moves, the headless walk is auditing a different
      // app than the simulator walk did.
      expect(y['status'], x['status'], reason: '$at: status');
      // Screen identity is built from labels, not geometry, so it survives the
      // font substitution — and if it did not, every state-loss and dead-tap
      // check would be reading a different screen.
      expect(y['screenSig'], x['screenSig'], reason: '$at: screenSig');
      // The chain a dead-tap finding stands on. Each link was measured wrong
      // once, and none of them moved a status or a signature when it broke.
      // NOT `settled`: a step that never dispatched now records null where
      // the simulator run recorded true.
      for (final String field in <String>[
        'error',
        'dispatched',
        'semanticsUnchanged',
        'tapsSoFar',
        'surface',
      ]) {
        expect(y[field], x[field], reason: '$at: $field');
      }

      final List<Object?> gx = x['guidelines']! as List<Object?>;
      final List<Object?> gy = y['guidelines']! as List<Object?>;
      expect(gy, hasLength(gx.length), reason: '$at: guideline count');
      for (int g = 0; g < gx.length; g++) {
        final Map<String, Object?> gxm = gx[g]! as Map<String, Object?>;
        final Map<String, Object?> gym = gy[g]! as Map<String, Object?>;
        expect(gym['guideline'], gxm['guideline'], reason: '$at: guideline $g');
        expect(
          gym['passed'],
          gxm['passed'],
          reason: '$at: ${gxm['guideline']} changed its verdict',
        );
      }

      final List<Object?> nx =
          (x['semantics']! as Map<String, Object?>)['nodes']! as List<Object?>;
      final List<Object?> ny =
          (y['semantics']! as Map<String, Object?>)['nodes']! as List<Object?>;
      expect(ny, hasLength(nx.length), reason: '$at: semantics node count');

      // Rects within a bound, not equal: the stand-in font moves text a little
      // (max 18.9 lpx, median 0.0 measured), while text left in the test
      // font's em squares moves it a lot (153.6) — and fontSource cannot tell
      // the two apart, because it reports what was registered, not what the
      // theme ended up asking for.
      for (int n = 0; n < nx.length; n++) {
        final List<Object?> rx =
            (nx[n]! as Map<String, Object?>)['rect']! as List<Object?>;
        final List<Object?> ry =
            (ny[n]! as Map<String, Object?>)['rect']! as List<Object?>;
        for (int k = 0; k < 4; k++) {
          expect(
            ((ry[k]! as num) - (rx[k]! as num)).abs(),
            lessThan(25.0),
            reason: '$at: node $n rect $ry against the simulator\'s $rx',
          );
        }
      }
    }

    expect(here!['taps'], sim['taps']);
    expect(here!['entrySettled'], sim['entrySettled']);

    final Map<String, Object?> vx =
        (a.first! as Map<String, Object?>)['semantics']!
            as Map<String, Object?>;
    final Map<String, Object?> vy =
        (b.first! as Map<String, Object?>)['semantics']!
            as Map<String, Object?>;
    expect(vy['viewport'], vx['viewport']);

    // Every step that names a PNG has one, and it is not empty. The name is a
    // claim the report acts on.
    for (final Object? raw in b) {
      final Map<String, Object?> step = raw! as Map<String, Object?>;
      final String? shot = step['screenshot'] as String?;
      expect(shot, isNotNull, reason: 'step ${step['index']} captured nothing');
      final File png = File('${shots.path}/$shot');
      expect(
        png.existsSync(),
        isTrue,
        reason: '$shot was named but not written',
      );
      expect(png.lengthSync(), greaterThan(0), reason: '$shot is empty');
    }

    // The run must disclose that it was not the simulator's.
    final Map<String, Object?> c = here!['conditions']! as Map<String, Object?>;
    expect(c['mode'], 'widget-test');
    expect(c['fontSource'], isNotNull);

    debugDefaultTargetPlatformOverride = null;
  });
}
