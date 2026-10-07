// `## Device` conditions — text scale, brightness, locale, bold text — and
// what they do to a walk. One set per run: a matrix inside one process is
// unsound, because app globals leak from one walk into the next (measured).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ux_demo_app/main.dart' as app;

import '../ux_audit/ux_journey_test.dart'
    show
        applyConditions,
        applyDevice,
        conditionsOf,
        kIphoneSe,
        loadFonts,
        walkJourney;

void main() {
  group('applyConditions — what `## Device` sets', () {
    testWidgets('nothing declared leaves every condition as it was', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const app.UxDemoApp());
      final Map<String, Object?> before = conditionsOf(tester);
      applyConditions(tester.platformDispatcher, (
        textScale: null,
        brightness: null,
        locale: null,
        boldText: false,
      ));
      await tester.pumpWidget(const app.UxDemoApp());
      expect(conditionsOf(tester), before);
    });

    testWidgets('every declared condition is what conditions then reports', (
      WidgetTester tester,
    ) async {
      applyConditions(tester.platformDispatcher, (
        textScale: 3.0,
        brightness: Brightness.dark,
        locale: const Locale('ko', 'KR'),
        boldText: true,
      ));
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(const app.UxDemoApp());
      final Map<String, Object?> c = conditionsOf(tester);
      expect(c['textScaleFactor'], 3.0);
      expect(c['platformBrightness'], 'dark');
      expect(c['locale'], 'ko-KR');
      expect(c['boldText'], isTrue);
      // And the app sees them, not just the dispatcher.
      // A body text: an AppBar title clamps its own scale to 1.34.
      final BuildContext ctx = tester.element(
        find.text('Free returns within 14 days'),
      );
      expect(MediaQuery.textScalerOf(ctx).scale(10), 30);
      expect(MediaQuery.boldTextOf(ctx), isTrue);
      expect(MediaQuery.platformBrightnessOf(ctx), Brightness.dark);
    });

    testWidgets('text scale 3.0 changes the layout the walk measures', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const app.UxDemoApp());
      final double plain = tester
          .getSize(find.text('Free returns within 14 days'))
          .height;
      applyConditions(tester.platformDispatcher, (
        textScale: 3.0,
        brightness: null,
        locale: null,
        boldText: false,
      ));
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(const app.UxDemoApp());
      expect(
        tester.getSize(find.text('Free returns within 14 days')).height,
        greaterThan(plain * 2),
      );
    });
  });

  group('the fixture at text scale 3.0', () {
    // Measured here: at 3.0 the list's first card still has its centre above
    // the 667 fold (y 579.5), the second sits wholly past it (y 800) and the
    // third is not in the semantics tree at all — the same shape CLAUDE.md
    // records for accessibility-XXXL on the simulator. The committed journey
    // only ever taps the first card, so it does not move; these do.
    late List<app.Product> original;
    setUp(() => original = List<app.Product>.of(app.products));
    tearDown(
      () => app.products
        ..clear()
        ..addAll(original),
    );

    ({
      String action,
      String target,
      int? nth,
      String? text,
      String expected,
      bool absent,
    })
    s(String action, String target, String expected) => (
      action: action,
      target: target,
      nth: null,
      text: null,
      expected: expected,
      absent: false,
    );

    Future<Map<String, Object?>> walk(
      WidgetTester tester,
      List<
        ({
          String action,
          String target,
          int? nth,
          String? text,
          String expected,
          bool absent,
        })
      >
      steps,
    ) async {
      // Reset inline, never in addTearDown — see main() in the walker.
      debugDefaultTargetPlatformOverride = kIphoneSe.targetPlatform;
      applyDevice(tester, kIphoneSe);
      addTearDown(tester.view.reset);
      applyConditions(tester.platformDispatcher, (
        textScale: 3.0,
        brightness: null,
        locale: null,
        boldText: false,
      ));
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await loadFonts(tester);
      Map<String, Object?>? report;
      await walkJourney(
        tester,
        launch: app.main,
        journey: steps,
        publish: (Map<String, Object?> r) async => report = r,
      );
      debugDefaultTargetPlatformOverride = null;
      return report!;
    }

    List<Object?> field(Map<String, Object?> report, String key) =>
        (report['steps']! as List<Object?>)
            .map((Object? s) => (s! as Map<String, Object?>)[key])
            .toList();

    testWidgets('without scrolling, the cards past the fold are unreachable', (
      WidgetTester tester,
    ) async {
      final Map<String, Object?> r = await walk(tester, <
        ({
          String action,
          String target,
          int? nth,
          String? text,
          String expected,
          bool absent,
        })
      >[
        s('tap', 'Oak Side Table', '164,000 KRW'),
        s('tap', 'Linen Floor Cushion', '72,000 KRW'),
      ]);
      expect(field(r, 'status'), <String>['FAILED', 'FAILED', 'OK']);
      expect(
        field(r, 'error')[0],
        contains('"Oak Side Table" is not reachable'),
      );
      expect(
        field(r, 'error')[1],
        contains('no semantics node matches "Linen Floor Cushion"'),
      );
      expect(
        (r['conditions']! as Map<String, Object?>)['textScaleFactor'],
        3.0,
      );
    });

    testWidgets('`scroll until` reaches both, and system back returns', (
      WidgetTester tester,
    ) async {
      final Map<String, Object?> r = await walk(tester, <
        ({
          String action,
          String target,
          int? nth,
          String? text,
          String expected,
          bool absent,
        })
      >[
        s('scroll', 'Oak Side Table', 'Oak Side Table'),
        s('tap', 'Oak Side Table', '164,000 KRW'),
        s('system back', '', 'Saved items'),
        s('scroll', 'Linen Floor Cushion', 'Linen Floor Cushion'),
        s('tap', 'Linen Floor Cushion', '72,000 KRW'),
      ]);
      expect(field(r, 'status'), <String>['OK', 'OK', 'OK', 'OK', 'OK', 'OK']);
      expect(field(r, 'drags')[0], greaterThan(0));
      expect(field(r, 'popHandled')[2], isTrue);
      expect(field(r, 'tapsSoFar'), <int>[0, 1, 1, 1, 2, 2]);
      expect(r['drags'], greaterThan(0));
    });
  });
}
