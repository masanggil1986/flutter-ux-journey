// Tests for the walker's measurement helpers — the parts that have logic.
//
// These pin the arithmetic the flow/IA findings stand on. Every number below
// either has a hand-checkable closed form (rect subtraction) or was measured on
// the fixture. Pure pass-through (dumping a field the SDK already computed) is
// not tested here; there is nothing to break.
//
// The helpers are public in the walker on purpose: a generated file the skill
// writes into someone else's app must stay ONE file, so the alternative to a
// public helper is an untested one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ux_demo_app/main.dart';

import '../integration_test/ux_journey_test.dart'
    show
        areaOf,
        coversPoint,
        dumpSemantics,
        hasSiblingNavigators,
        routeState,
        conditionsOf,
        screenSignature,
        settle,
        subtractRects,
        viewportOf;

void main() {
  // DEFECT 6 mutates a top-level list with no confirmation, so any test that
  // walks the removal flow destroys the fixture for every test after it —
  // which is exactly how the first run of this file failed.
  late List<Product> original;
  setUp(() => original = List<Product>.of(products));
  tearDown(() => products
    ..clear()
    ..addAll(original));

  group('subtractRects — the effective (unobscured) tap target', () {
    const Rect target = Rect.fromLTWH(0, 0, 100, 100);

    test('no overlap leaves the whole target', () {
      expect(areaOf(subtractRects(target, <Rect>[const Rect.fromLTWH(200, 200, 50, 50)])),
          10000.0);
    });

    test('full cover leaves nothing', () {
      expect(areaOf(subtractRects(target, <Rect>[const Rect.fromLTWH(-10, -10, 200, 200)])), 0.0);
    });

    test('half cover leaves half', () {
      expect(areaOf(subtractRects(target, <Rect>[const Rect.fromLTWH(0, 50, 100, 50)])), 5000.0);
    });

    test('two obscurers leave an L-shaped quarter', () {
      final List<Rect> free = subtractRects(target, <Rect>[
        const Rect.fromLTWH(0, 50, 100, 50), // bottom half
        const Rect.fromLTWH(50, 0, 50, 50), // top-right quarter
      ]);
      expect(areaOf(free), 2500.0);
    });

    test('an edge-touching obscurer takes nothing (no negative area)', () {
      // Rect.intersect returns a NEGATIVE-size rect for disjoint rects; a naive
      // implementation adds that area back and reports more than 100%.
      expect(areaOf(subtractRects(target, <Rect>[const Rect.fromLTWH(100, 0, 50, 100)])), 10000.0);
    });

    test('the free strips are disjoint, so the areas really do sum', () {
      final List<Rect> free = subtractRects(target, <Rect>[const Rect.fromLTWH(25, 25, 50, 50)]);
      for (int i = 0; i < free.length; i++) {
        for (int j = i + 1; j < free.length; j++) {
          final Rect o = free[i].intersect(free[j]);
          expect(o.width <= 0 || o.height <= 0, isTrue,
              reason: 'free rects $i and $j overlap: ${free[i]} ${free[j]}');
        }
      }
      expect(areaOf(free), 10000.0 - 2500.0);
    });

    test('reproduces the measured dogfood defect: a 48dp CTA left as a 16dp strip', () {
      // A full-width 48dp CTA with a banner over its lower 32dp. Every
      // size-only check passes this button: its own rect never changes.
      const Rect cta = Rect.fromLTWH(16, 536, 768, 48);
      const Rect banner = Rect.fromLTWH(0, 552, 800, 48);
      final List<Rect> free = subtractRects(cta, <Rect>[banner]);
      expect(areaOf(free) / (cta.width * cta.height), closeTo(1 / 3, 0.001));
      expect(free.single.height, 16.0);
      // And the walker taps the CENTRE, so this is not merely cosmetic.
      expect(coversPoint(cta.center, <Rect>[banner]), isTrue);
    });
  });

  group('coversPoint — would the walker\'s own tap land on the overlay', () {
    test('a point outside every obscurer is clear', () {
      expect(coversPoint(const Offset(5, 5), <Rect>[const Rect.fromLTWH(10, 10, 10, 10)]), isFalse);
    });
    test('a point inside an obscurer is covered', () {
      expect(coversPoint(const Offset(15, 15), <Rect>[const Rect.fromLTWH(10, 10, 10, 10)]), isTrue);
    });
  });

  group('viewportOf — the fold line', () {
    testWidgets('flags the widget-test default instead of reporting a fake fold',
        (WidgetTester tester) async {
      await tester.pumpWidget(const UxDemoApp());
      final Map<String, Object?> v = viewportOf(tester);
      // 800x600 @ dpr 3.0 is Flutter's hardcoded test viewport, not a device.
      // Anything computed against it would be a fold line for a phone that
      // does not exist, so the walker must say so and the report must blank
      // every fold column.
      expect(v['isTestDefault'], isTrue);
      expect(v['foldY'], isNull);
    });

    testWidgets('subtracts system padding so the fold is not the whole display',
        (WidgetTester tester) async {
      // An iPhone-SE-ish surface with a status bar and a home indicator.
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.devicePixelRatio = 2.0;
      tester.view.padding = const FakeViewPadding(top: 40, bottom: 68);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const UxDemoApp());

      final Map<String, Object?> v = viewportOf(tester);
      expect(v['isTestDefault'], isFalse);
      expect(v['height'], 667.0);
      expect(v['contentTop'], 20.0); // 40 physical / dpr 2
      expect(v['foldY'], 667.0 - 34.0); // minus the home indicator
    });

    testWidgets('the keyboard takes the fold, not the home indicator',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.devicePixelRatio = 2.0;
      tester.view.padding = const FakeViewPadding(top: 40, bottom: 68);
      tester.view.viewInsets = const FakeViewPadding(bottom: 600); // keyboard up
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const UxDemoApp());

      // max(padding.bottom, viewInsets.bottom) — a keyboard hides far more
      // than the home indicator, and a CTA under it is not on screen at all.
      expect(viewportOf(tester)['foldY'], 667.0 - 300.0);
    });
  });

  group('hasSiblingNavigators — the dump knows when it saw half a screen', () {
    Widget pane(String label) => Navigator(
          onGenerateRoute: (RouteSettings _) => MaterialPageRoute<void>(
            builder: (BuildContext _) => Scaffold(
              body: Center(child: ElevatedButton(onPressed: () {}, child: Text(label))),
            ),
          ),
        );

    testWidgets('a phone app with one Navigator is not flagged', (WidgetTester tester) async {
      await tester.pumpWidget(const UxDemoApp());
      expect(hasSiblingNavigators(tester), isFalse);
    });

    testWidgets('a NESTED Navigator — a tab shell — is not flagged either',
        (WidgetTester tester) async {
      // This is the case a naive navigatorCount > 1 gets wrong, and getting it
      // wrong would push every real finding on a perfectly ordinary tabbed app
      // to `not assessable`.
      await tester.pumpWidget(MaterialApp(home: pane('TAB')));
      await tester.pumpAndSettle();
      expect(tester.elementList(find.byType(Navigator)).length, greaterThan(1),
          reason: 'the root Navigator plus the tab one — nested, not siblings');
      expect(hasSiblingNavigators(tester), isFalse);
    });

    testWidgets('side-by-side panes are flagged, and the dump really is missing one',
        (WidgetTester tester) async {
      // iPad Pro 13", the surface the fold maths was verified on.
      tester.view.physicalSize = const Size(2064, 2752);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final SemanticsHandle handle = tester.ensureSemantics();

      await tester.pumpWidget(MaterialApp(
        home: Row(children: <Widget>[Expanded(child: pane('LEFT')), Expanded(child: pane('RIGHT'))]),
      ));
      await tester.pumpAndSettle();

      expect(hasSiblingNavigators(tester), isTrue);
      final Map<String, Object?> dump = dumpSemantics(tester);
      expect(dump['panesPossiblyBlocked'], isTrue);
      // The point of the flag: BlockSemantics has already deleted the
      // earlier-painted pane by the time the dump can reach the tree.
      final List<String> labels = (dump['nodes']! as List<Object?>)
          .map((Object? n) => (n! as Map<String, Object?>)['label']! as String)
          .where((String l) => l.isNotEmpty)
          .toList();
      expect(labels, contains('RIGHT'));
      expect(labels, isNot(contains('LEFT')),
          reason: 'if LEFT is back, Flutter changed and the flag can go');
      // addTearDown runs after the framework's end-of-test handle check.
      handle.dispose();
    });

    testWidgets('false is NOT a promise that the dump is whole', (WidgetTester tester) async {
      // One ModalRoute is enough to delete an earlier sibling, so a Row of
      // [plain Scaffold, Navigator] loses the Scaffold pane while the flag —
      // which asks about two NAVIGATORS — reads false. The flag is a declared
      // suspicion, never a clean bill, and the docs must not say otherwise.
      tester.view.physicalSize = const Size(2064, 2752);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final SemanticsHandle handle = tester.ensureSemantics();

      await tester.pumpWidget(MaterialApp(
        home: Row(children: <Widget>[
          const Expanded(
            child: Scaffold(body: Center(child: Text('LEFT'))),
          ),
          Expanded(child: pane('RIGHT')),
        ]),
      ));
      await tester.pumpAndSettle();

      final Map<String, Object?> dump = dumpSemantics(tester);
      expect(dump['panesPossiblyBlocked'], isFalse);
      final List<String> labels = (dump['nodes']! as List<Object?>)
          .map((Object? n) => (n! as Map<String, Object?>)['label']! as String)
          .where((String l) => l.isNotEmpty)
          .toList();
      expect(labels, contains('RIGHT'));
      expect(labels, isNot(contains('LEFT')),
          reason: 'the pane is gone with the flag false — that is the whole point of this test');
      handle.dispose();
    });
  });

  group('conditionsOf — the run reports what it was measured under', () {
    testWidgets('reads the live dispatcher, not a constant', (WidgetTester tester) async {
      // The failure this guards against is a conditions block wired to
      // defaults: it would read `light` / 1.0 on every run and be worse than
      // no block at all, because the report quotes it as measured fact.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      tester.platformDispatcher.textScaleFactorTestValue = 3.0;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(boldText: true, disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(const UxDemoApp());

      final Map<String, Object?> c = conditionsOf(tester);
      expect(c['platformBrightness'], 'dark');
      expect(c['textScaleFactor'], 3.0);
      expect(c['boldText'], isTrue);
      expect(c['disableAnimations'], isTrue);
      expect(c['highContrast'], isFalse);
    });

    testWidgets('text scale is invisible in the viewport, which is why it is here',
        (WidgetTester tester) async {
      // Measured on a booted iPhone SE: default vs accessibility-XXXL produce
      // an identical viewport while a product row leaves the semantics tree.
      // If that ever stops being true the conditions block is redundant and
      // this test should be the thing that says so.
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const UxDemoApp());
      final Map<String, Object?> plain = viewportOf(tester);

      tester.platformDispatcher.textScaleFactorTestValue = 3.0;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(const UxDemoApp());

      expect(viewportOf(tester), plain, reason: 'if this fails, drop conditionsOf');
      expect(conditionsOf(tester)['textScaleFactor'], 3.0);
    });
  });

  group('screenSignature — screen identity without a router', () {
    testWidgets('is stable across pumps and differs between screens',
        (WidgetTester tester) async {
      await tester.pumpWidget(const UxDemoApp());
      final SemanticsHandle handle = tester.ensureSemantics();

      final String list = screenSignature(dumpSemantics(tester));
      await tester.pump(const Duration(milliseconds: 400));
      expect(screenSignature(dumpSemantics(tester)), list, reason: 'unstable across pumps');

      await tester.tap(find.text('Walnut Side Table'));
      await tester.pumpAndSettle();
      final String detail = screenSignature(dumpSemantics(tester));
      expect(detail, isNot(list));

      await tester.tap(find.text('Remove from list'));
      await tester.pumpAndSettle();
      expect(screenSignature(dumpSemantics(tester)), isNot(detail));
      handle.dispose();
    });

    testWidgets('two products differ — a signature is an instance, not a template',
        (WidgetTester tester) async {
      // Documented on purpose: equal signatures mean the SAME screen state, so
      // "two screens are the same template" is NOT what this measures. The
      // research proposed a content-free variant for that and it was refuted
      // (text width is content), so the walker does not ship one.
      await tester.pumpWidget(const UxDemoApp());
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.tap(find.text('Walnut Side Table'));
      await tester.pumpAndSettle();
      final String walnut = screenSignature(dumpSemantics(tester));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oak Side Table'));
      await tester.pumpAndSettle();
      expect(screenSignature(dumpSemantics(tester)), isNot(walnut));
      handle.dispose();
    });
  });

  group('routeState — DEAD-END as a measurement instead of a selector miss', () {
    testWidgets('canPop is false on the dead end and true on the detail screen',
        (WidgetTester tester) async {
      await tester.pumpWidget(const UxDemoApp());
      final SemanticsHandle handle = tester.ensureSemantics();

      final Map<String, Object?> entry = routeState(tester);
      expect(entry['canPop'], isFalse, reason: 'the list screen is the entry');
      // Regression: every ModalRoute mounts a ModalBarrier, so a naive
      // find.byType(ModalBarrier) reads "a modal is open" on every ordinary
      // screen — measured here before the probe was narrowed.
      expect(entry['modalOpen'], isFalse, reason: 'no dialog is open on the list screen');

      await tester.tap(find.text('Walnut Side Table'));
      await tester.pumpAndSettle();
      expect(routeState(tester)['canPop'], isTrue);

      await tester.tap(find.text('Remove from list'));
      await tester.pumpAndSettle();
      final Map<String, Object?> dead = routeState(tester);
      expect(dead['canPop'], isFalse);
      // canPop false is not enough on its own: it is also false on the entry
      // screen. The DEAD-END predicate needs the second half — nothing on the
      // screen can move the journey forward either.
      expect(dead['tappableCount'], 0);
      handle.dispose();
    });

    testWidgets('a modal masks the dead end — recorded, so the report cannot be fooled',
        (WidgetTester tester) async {
      await tester.pumpWidget(const UxDemoApp());
      await tester.tap(find.text('Walnut Side Table'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from list'));
      await tester.pumpAndSettle();
      expect(routeState(tester)['canPop'], isFalse);

      showDialog<void>(
        context: tester.element(find.byType(RemovedScreen)),
        builder: (_) => const AlertDialog(content: Text('anything')),
      );
      await tester.pumpAndSettle();
      final Map<String, Object?> s = routeState(tester);
      // With a modal up, "can this route pop" answers "the dialog closes" —
      // which is why modalOpen ships next to it and the predicate ignores
      // canPop whenever it is true.
      expect(s['canPop'], isTrue);
      expect(s['modalOpen'], isTrue);
    });
  });

  group('dead-tap oracle — and the false positive it cannot see alone', () {
    testWidgets('a control that does nothing leaves the semantics identical',
        (WidgetTester tester) async {
      await tester.pumpWidget(const UxDemoApp());
      final SemanticsHandle handle = tester.ensureSemantics();
      final String before = screenSignature(dumpSemantics(tester));
      await tester.tap(find.byIcon(Icons.search)); // DEFECT 2's onPressed: () {}
      await tester.pumpAndSettle();
      expect(screenSignature(dumpSemantics(tester)), before);
      handle.dispose();
    });

    testWidgets('so does a tap that only repaints — hence the two-layer rule',
        (WidgetTester tester) async {
      // This is the measured false positive. A selection chip that changes
      // colour and nothing else is byte-identical in semantics to a control
      // that is wired to nothing. The walker records the fact; heuristics.md
      // forbids reporting FAKE-AFFORDANCE on this evidence alone.
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: _ColourOnlyToggle())));
      final SemanticsHandle handle = tester.ensureSemantics();
      final String before = screenSignature(dumpSemantics(tester));
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(screenSignature(dumpSemantics(tester)), before,
          reason: 'if this ever differs, the two-layer rule can be relaxed');
      handle.dispose();
    });
  });

  group('regressions — every one of these was measured wrong first', () {
    testWidgets('a node is never obscured by its own children', (WidgetTester tester) async {
      await tester.pumpWidget(const UxDemoApp());
      final SemanticsHandle handle = tester.ensureSemantics();
      final List<Map<String, Object?>> nodes =
          dumpSemantics(tester)['nodes']! as List<Map<String, Object?>>;
      for (final Map<String, Object?> n in nodes) {
        if (n['tappable'] != true) {
          continue;
        }
        expect(n['effectivePct'], isNotNull, reason: 'every tap target gets an effective area');
        expect(n['effectivePct']! as double, greaterThan(0.0),
            reason: '"${n['label']}" reads as fully obscured on a screen with no overlay');
      }
      handle.dispose();
    });

    testWidgets('a covered centre does NOT refuse the tap', (WidgetTester tester) async {
      // Measured counter-example: a badge whose padded LAYOUT box swallows a
      // button's centre while the button stays perfectly tappable. The first
      // version threw here, which fails the step and voids the whole audit on
      // an overlay that blocks nothing.
      int hits = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(children: <Widget>[
            Positioned(
              left: 0,
              top: 0,
              child: SizedBox(
                width: 300,
                height: 60,
                child: ElevatedButton(onPressed: () => hits++, child: const Text('Checkout')),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              // The Semantics wrapper takes the PADDED box as its rect, so a
              // corner badge reports a node covering the button's centre.
              child: Semantics(
                label: 'NEW',
                child: Padding(
                  padding: EdgeInsets.only(left: 250, top: 38),
                  child: Text('NEW'),
                ),
              ),
            ),
          ]),
        ),
      ));
      final SemanticsHandle handle = tester.ensureSemantics();
      final Map<String, Object?> cta = (dumpSemantics(tester)['nodes']! as List<Map<String, Object?>>)
          .firstWhere((Map<String, Object?> n) => (n['label'] as String?) == 'Checkout');
      expect(cta['centreCovered'], isTrue, reason: 'the geometry really does overlap');

      await tester.tapAt(Offset(
        (cta['rect']! as List<double>)[0] + (cta['rect']! as List<double>)[2] / 2,
        (cta['rect']! as List<double>)[1] + (cta['rect']! as List<double>)[3] / 2,
      ));
      expect(hits, 1, reason: 'ground truth: the overlay does not take the tap');
      handle.dispose();
    });

    testWidgets('a cache-extent row below the surface is not on screen',
        (WidgetTester tester) async {
      // A scrollable builds rows past the viewport, and their rects say so.
      // Tapping one dispatches into nothing: the gesture is recorded as sent,
      // the semantics do not change, and a working row reads as a dead
      // control — a false finding that passes both required evidence layers.
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_list(itemCount: 40));
      final SemanticsHandle handle = tester.ensureSemantics();

      final List<Map<String, Object?>> nodes =
          dumpSemantics(tester)['nodes']! as List<Map<String, Object?>>;
      final Iterable<Map<String, Object?>> offSurface =
          nodes.where((Map<String, Object?> n) => n['onScreen'] == false);
      expect(offSurface, isNotEmpty, reason: 'the cache extent should reach past the fold');
      for (final Map<String, Object?> n in offSurface) {
        expect(n['aboveFold'], isFalse, reason: 'off the surface cannot be above the fold');
      }
      handle.dispose();
    });

    testWidgets('a row scrolled off the TOP is not above the fold', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_list(itemCount: 40));
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();

      final List<Map<String, Object?>> nodes =
          dumpSemantics(tester)['nodes']! as List<Map<String, Object?>>;
      for (final Map<String, Object?> n in nodes) {
        final List<double> r = n['rect']! as List<double>;
        if (r[1] < 0 && n['label'] != '') {
          expect(n['aboveFold'], isFalse,
              reason: '"${n['label']}" at y=${r[1]} is scrolled off the top');
        }
      }
      handle.dispose();
    });

    testWidgets('a REORDER moves the screen signature', (WidgetTester tester) async {
      // The signature sorts its parts, so without a position prefix every
      // sort / move-up / shuffle control in existence reports "nothing
      // changed" — and then trips the a11y finding reserved for a state
      // change assistive tech cannot see.
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: _Reorderable())));
      final SemanticsHandle handle = tester.ensureSemantics();
      final String before = screenSignature(dumpSemantics(tester));
      await tester.tap(find.text('Sort'));
      await tester.pumpAndSettle();
      expect(screenSignature(dumpSemantics(tester)), isNot(before),
          reason: 'the same labels in a different order must not hash the same');
      handle.dispose();
    });

    testWidgets('a popup menu counts as a modal', (WidgetTester tester) async {
      // canPop flips to true whenever any route is pushed, including a popup
      // menu — and a popup menu builds a plain ModalBarrier, not the animated
      // one, so keying on the subclass missed the two commonest transient
      // surfaces and left canPop reading as "there is a way out".
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: <Widget>[
            PopupMenuButton<int>(
              itemBuilder: (BuildContext c) =>
                  <PopupMenuEntry<int>>[const PopupMenuItem<int>(value: 1, child: Text('One'))],
            ),
          ]),
          body: const Text('body'),
        ),
      ));
      final SemanticsHandle handle = tester.ensureSemantics();
      expect(routeState(tester)['modalOpen'], isFalse);

      await tester.tap(find.byType(PopupMenuButton<int>));
      await tester.pumpAndSettle();
      final Map<String, Object?> open = routeState(tester);
      expect(open['canPop'], isTrue, reason: 'the menu is a pushed route');
      expect(open['modalOpen'], isTrue, reason: 'so canPop must be cross-checked');
      handle.dispose();
    });

    testWidgets('canPop answers about the tab the user is in, not the shell',
        (WidgetTester tester) async {
      // The shell owns the Scaffold and each tab owns a Navigator. Resolving
      // from the deepest Scaffold lands back on the ROOT navigator and reports
      // "no way out" while the user is a page deep inside a tab.
      await tester.pumpWidget(MaterialApp(home: _TabShell()));
      final SemanticsHandle handle = tester.ensureSemantics();
      expect(routeState(tester)['canPop'], isFalse, reason: 'tab root');

      await tester.tap(find.text('Go deeper'));
      await tester.pumpAndSettle();
      expect(routeState(tester)['canPop'], isTrue,
          reason: 'one page deep inside the tab: there IS a way back');
      handle.dispose();
    });

    testWidgets('canPop answers even with no Scaffold on screen', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: ColoredBox(color: Color(0xFFFFFFFF))));
      expect(routeState(tester)['canPop'], isNotNull);
    });

    testWidgets('the whole dump is JSON — the driver encodes it, and encode throws',
        (WidgetTester tester) async {
      // jsonEncode throws on Infinity and on any non-primitive (a raw Rect),
      // at ENCODE, not decode — so one bad field loses the entire step's
      // measurements with no error anyone reads.
      await tester.pumpWidget(const UxDemoApp());
      final SemanticsHandle handle = tester.ensureSemantics();
      expect(() => _encodable(dumpSemantics(tester)), returnsNormally);
      expect(() => _encodable(routeState(tester)), returnsNormally);
      handle.dispose();
    });

    testWidgets('settle waits for the expectation, not for a quiet frame queue',
        (WidgetTester tester) async {
      // An awaiting Future schedules no frames, so the old "stop when the
      // frame queue is quiet" rule returned true while the screen was still
      // empty: the step then failed with a wrong reason AND recorded
      // settled: true, so nothing downstream voided its measurements.
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: _SlowLoad())));
      await tester.tap(find.text('Load'));

      final bool ok = await settle(
        tester,
        limit: const Duration(seconds: 4),
        until: () => find.text('Loaded').evaluate().isNotEmpty,
      );
      expect(ok, isTrue, reason: 'it must wait for the content, not for quiet');
      expect(find.text('Loaded'), findsOneWidget);
    });

    testWidgets('settle does not return mid-transition — rects must be final',
        (WidgetTester tester) async {
      // The regression this caught on a device: stopping at "the expectation
      // is on screen" returns while the route is still sliding in. Every rect
      // on that screen then comes back shifted — measured, by 244 lpx — the
      // placement numbers are nonsense, and the next tap lands off the surface
      // and hits nothing.
      await tester.pumpWidget(const UxDemoApp());
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.tap(find.text('Walnut Side Table'));

      final bool ok = await settle(
        tester,
        until: () => find.text('189,000 KRW').evaluate().isNotEmpty,
      );
      expect(ok, isTrue);
      final List<double> atSettle = _rectOf(dumpSemantics(tester), '189,000 KRW');

      await tester.pumpAndSettle();
      expect(_rectOf(dumpSemantics(tester), '189,000 KRW'), atSettle,
          reason: 'the transition was still running when settle returned');
      handle.dispose();
    });

    testWidgets('a bottom-pinned CTA is still above the fold', (WidgetTester tester) async {
      // The over-correction: requiring the WHOLE rect inside the fold fails
      // every bottom-pinned CTA and every hero taller than the fold, on any
      // device with a home indicator — and aboveFold is the only term in
      // HIERARCHY-FLAT's first clause, so it manufactured the finding.
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.devicePixelRatio = 2.0;
      tester.view.padding = const FakeViewPadding(top: 40, bottom: 68);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomSheet: SizedBox(
            height: 88,
            width: double.infinity,
            child: FilledButton(onPressed: () {}, child: const Text('Pay now')),
          ),
        ),
      ));
      final SemanticsHandle handle = tester.ensureSemantics();
      final Map<String, Object?> cta =
          (dumpSemantics(tester)['nodes']! as List<Map<String, Object?>>)
              .firstWhere((Map<String, Object?> n) => (n['label'] as String?) == 'Pay now');
      expect(cta['aboveFold'], isTrue, reason: 'the user can see it without scrolling');
      expect(cta['fullyVisible'], isFalse, reason: 'and the stricter question is still asked');
      handle.dispose();
    });

    testWidgets('the in-Scaffold keyboard-dismiss GestureDetector is flagged',
        (WidgetTester tester) async {
      // It is written INSIDE the Scaffold, so its rect starts below the app
      // bar — asking "is this rect the whole surface" read false on exactly
      // the screens the flag exists for.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Sign in')),
          body: GestureDetector(
            onTap: () {},
            child: Column(children: <Widget>[
              const TextField(),
              FilledButton(onPressed: () {}, child: const Text('Continue')),
            ]),
          ),
        ),
      ));
      final SemanticsHandle handle = tester.ensureSemantics();
      final List<Map<String, Object?>> nodes =
          dumpSemantics(tester)['nodes']! as List<Map<String, Object?>>;
      final Iterable<Map<String, Object?>> covers =
          nodes.where((Map<String, Object?> n) => n['coversSurface'] == true);
      expect(covers, hasLength(1), reason: 'the unnamed body-sized tappable');
      expect((covers.single['label'] as String?) ?? '', isEmpty);
      // And a NAMED full-screen control must not be swept up with it.
      expect(
          nodes.any((Map<String, Object?> n) =>
              (n['label'] as String?) == 'Continue' && n['coversSurface'] == true),
          isFalse);
      handle.dispose();
    });

    testWidgets('settle reports success when the content arrived but the screen never quiets',
        (WidgetTester tester) async {
      // A shimmer, a sync spinner, an indeterminate bar: quiet never comes.
      // Returning false there voids every geometric measurement on the screen
      // via heuristics.md rule 5 — including the flagship covered-CTA finding.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Column(children: <Widget>[
            Text('Ready'),
            SizedBox(width: 40, height: 40, child: CircularProgressIndicator()),
          ]),
        ),
      ));
      final bool ok = await settle(
        tester,
        limit: const Duration(milliseconds: 600),
        until: () => find.text('Ready').evaluate().isNotEmpty,
      );
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'it really never quiets');
      expect(ok, isTrue, reason: 'the content DID arrive; that is what settled must mean');
    });

    testWidgets('a CLOSED drawer is not an open modal', (WidgetTester tester) async {
      // DrawerController is mounted whenever Scaffold.drawer != null, open or
      // shut. Probing for the widget reported "a modal is open" on every
      // screen of an app with a global drawer — which would suppress DEAD-END
      // everywhere, because its predicate requires modalOpen == false.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Home')),
          drawer: const Drawer(child: Text('menu')),
          body: const Text('body'),
        ),
      ));
      final SemanticsHandle handle = tester.ensureSemantics();
      expect(routeState(tester)['modalOpen'], isFalse, reason: 'the drawer is shut');

      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();
      final Map<String, Object?> open = routeState(tester);
      expect(open['modalOpen'], isTrue, reason: 'now it really is open');
      expect(open['canPop'], isTrue, reason: 'a drawer adds a local-history entry');
      handle.dispose();
    });

    testWidgets('settle gives up on the bound and says so', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: _SlowLoad())));
      await tester.tap(find.text('Load'));
      final bool ok = await settle(
        tester,
        limit: const Duration(milliseconds: 300),
        until: () => find.text('Loaded').evaluate().isNotEmpty,
      );
      expect(ok, isFalse, reason: 'a bound that expires must not report success');
      await tester.pumpAndSettle(const Duration(seconds: 3)); // drain the future
    });
  });
}

List<double> _rectOf(Map<String, Object?> dump, String label) =>
    (dump['nodes']! as List<Map<String, Object?>>)
        .firstWhere((Map<String, Object?> n) => (n['label'] as String?) == label)['rect']!
        as List<double>;

/// A scrollable taller than the test viewport.
Widget _list({int? itemCount}) => MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          itemCount: itemCount,
          itemBuilder: (BuildContext c, int i) => SizedBox(height: 40, child: Text('row $i')),
        ),
      ),
    );

/// Round-trips the dump the way the driver will, so a non-encodable value
/// (Infinity, NaN, a raw Rect) fails here rather than in a device run.
void _encodable(Object? o) {
  if (o is Map) {
    o.forEach((Object? k, Object? v) {
      if (k is! String) {
        throw StateError('non-string key $k');
      }
      _encodable(v);
    });
  } else if (o is List) {
    o.forEach(_encodable);
  } else if (o is double) {
    if (!o.isFinite) {
      throw StateError('non-finite double $o');
    }
  } else if (o != null && o is! String && o is! int && o is! bool) {
    throw StateError('not JSON: ${o.runtimeType}');
  }
}

/// A tap that changes only paint: the measured false-positive shape.
class _ColourOnlyToggle extends StatefulWidget {
  @override
  State<_ColourOnlyToggle> createState() => _ColourOnlyToggleState();
}

class _ColourOnlyToggleState extends State<_ColourOnlyToggle> {
  bool _on = false;

  @override
  Widget build(BuildContext context) => Center(
        child: InkWell(
          onTap: () => setState(() => _on = !_on),
          child: ColoredBox(
            color: _on ? const Color(0xFF2962FF) : const Color(0xFFEEEEEE),
            child: const SizedBox(width: 120, height: 48, child: Text('Filter')),
          ),
        ),
      );
}

/// Same labels, different order — the shape a sorted-multiset signature cannot see.
class _Reorderable extends StatefulWidget {
  @override
  State<_Reorderable> createState() => _ReorderableState();
}

class _ReorderableState extends State<_Reorderable> {
  List<String> _rows = <String>['Zebra 900', 'Apple 100', 'Mango 500'];

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          TextButton(
            onPressed: () => setState(() => _rows = List<String>.of(_rows)..sort()),
            child: const Text('Sort'),
          ),
          for (final String r in _rows) SizedBox(height: 40, child: Text(r)),
        ],
      );
}

/// The shell owns the Scaffold; each tab owns a Navigator. Resolving canPop
/// from the deepest Scaffold lands back on the root navigator here.
class _TabShell extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Navigator(
          onGenerateRoute: (RouteSettings s) => MaterialPageRoute<void>(
            builder: (BuildContext c) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(c).push(
                  MaterialPageRoute<void>(builder: (_) => const Center(child: Text('Deeper'))),
                ),
                child: const Text('Go deeper'),
              ),
            ),
          ),
        ),
        bottomNavigationBar: const SizedBox(height: 56),
      );
}

/// A tap that starts an awaiting Future schedules no frames, so the frame
/// queue goes quiet while the screen is still empty.
class _SlowLoad extends StatefulWidget {
  @override
  State<_SlowLoad> createState() => _SlowLoadState();
}

class _SlowLoadState extends State<_SlowLoad> {
  bool _loaded = false;

  @override
  Widget build(BuildContext context) => Center(
        child: _loaded
            ? const Text('Loaded')
            : TextButton(
                onPressed: () async {
                  await Future<void>.delayed(const Duration(seconds: 2));
                  if (mounted) {
                    setState(() => _loaded = true);
                  }
                },
                child: const Text('Load'),
              ),
      );
}
