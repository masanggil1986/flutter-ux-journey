// The step grammar beyond tap / type / back: `scroll until`, `long-press`,
// `system back`, and the absence oracle `expect no`. Each one is a gesture or
// an oracle the walk reports on, so each one is pinned by a small app built to
// make it fail the obvious way.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ux_audit/ux_journey_test.dart'
    show applyDevice, kIphoneSe, performStep, StepOutcome, walkJourney;

// No `Step` annotation: the walker's `Step` collides with Material's.
({
  String action,
  String target,
  int? nth,
  String? text,
  String expected,
  bool absent,
})
step(String action, String target, String expected, {bool absent = false}) => (
  action: action,
  target: target,
  nth: null,
  text: null,
  expected: expected,
  absent: absent,
);

/// 30 rows, ListTile-tall. On an iPhone SE surface row 25 sits far past the
/// cache extent, so it is not in the semantics tree when the walk starts.
Widget rows({int count = 30, void Function(int)? onTap}) => MaterialApp(
  home: Scaffold(
    body: ListView(
      children: <Widget>[
        for (int i = 1; i <= count; i++)
          ListTile(title: Text('Row $i'), onTap: () => onTap?.call(i)),
      ],
    ),
  ),
);

Future<SemanticsHandle> onPhone(WidgetTester tester, Widget app) async {
  applyDevice(tester, kIphoneSe);
  addTearDown(tester.view.reset);
  final SemanticsHandle handle = tester.ensureSemantics();
  await tester.pumpWidget(app);
  return handle;
}

void main() {
  group('scroll until — reach a declared target, never a crawl', () {
    testWidgets('drags row 25 onto the screen, and it is then tappable', (
      WidgetTester tester,
    ) async {
      int? tapped;
      final SemanticsHandle handle = await onPhone(
        tester,
        rows(onTap: (int i) => tapped = i),
      );
      expect(
        find.text('Row 25'),
        findsNothing,
        reason: 'the premise: the target is not even built yet',
      );

      final StepOutcome out = await performStep(
        tester,
        step('scroll', 'Row 25', 'Row 25'),
      );
      expect(out.status, 'OK', reason: '${out.error}');
      expect(out.drags, inInclusiveRange(1, 20));
      expect(out.dispatched, isTrue);
      expect(out.tapped, isFalse, reason: 'a drag is not reach cost');
      expect(out.resolved?['label'], 'Row 25');

      final StepOutcome tap = await performStep(
        tester,
        step('tap', 'Row 25', 'Row 25'),
      );
      expect(tap.status, 'OK', reason: '${tap.error}');
      expect(tapped, 25, reason: 'the scroll left it where a tap lands');
      handle.dispose();
    });

    testWidgets('gives up on the bound and says how far it went', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = await onPhone(tester, rows());
      final StepOutcome out = await performStep(
        tester,
        step('scroll', 'Row 99', 'Row 99'),
      );
      expect(out.status, 'FAILED');
      expect(out.drags, 20);
      expect(out.error, contains('"Row 99"'));
      expect(out.error, contains('20 drags'));
      handle.dispose();
    });

    testWidgets('a target already on screen costs no drag', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = await onPhone(tester, rows());
      final StepOutcome out = await performStep(
        tester,
        step('scroll', 'Row 2', 'Row 2'),
      );
      expect(out.status, 'OK', reason: '${out.error}');
      expect(out.drags, 0);
      expect(
        out.dispatched,
        isFalse,
        reason: 'nothing went out, so nothing can be called dead',
      );
      handle.dispose();
    });

    testWidgets('drags the list that holds the target, not the page', (
      WidgetTester tester,
    ) async {
      // A short inner list inside a page that does not scroll at all: the
      // target is in the tree (cache extent) but clipped by its own list.
      final SemanticsHandle handle = await onPhone(
        tester,
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                const SizedBox(height: 100, child: Text('Header')),
                SizedBox(
                  height: 200,
                  child: ListView(
                    children: <Widget>[
                      for (int i = 1; i <= 12; i++)
                        ListTile(title: Text('Item $i'), onTap: () {}),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final StepOutcome out = await performStep(
        tester,
        step('scroll', 'Item 9', 'Item 9'),
      );
      expect(out.status, 'OK', reason: '${out.error}');
      expect(out.drags, greaterThan(0));
      final Rect item = tester.getRect(find.text('Item 9'));
      expect(
        item.center.dy,
        inInclusiveRange(100, 300),
        reason: 'inside the inner list\'s own visible band',
      );
      handle.dispose();
    });

    testWidgets('a target nothing scrolls is refused without a drag', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = await onPhone(
        tester,
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                Positioned(
                  top: 700, // below the 667 fold, and no scrollable anywhere
                  left: 0,
                  child: TextButton(onPressed: () {}, child: const Text('Low')),
                ),
              ],
            ),
          ),
        ),
      );
      final StepOutcome out = await performStep(
        tester,
        step('scroll', 'Low', 'Low'),
      );
      expect(out.status, 'FAILED');
      expect(out.drags, 0);
      expect(out.error, contains('nothing on screen scrolls "Low"'));
      handle.dispose();
    });

    testWidgets('in a walk: taps do not move, drags are counted apart', (
      WidgetTester tester,
    ) async {
      applyDevice(tester, kIphoneSe);
      addTearDown(tester.view.reset);
      Map<String, Object?>? report;
      await walkJourney(
        tester,
        launch: () => runApp(rows()),
        journey:
            <
              ({
                String action,
                String target,
                int? nth,
                String? text,
                String expected,
                bool absent,
              })
            >[
              // First, and its target not built yet: the entry wait has to
              // settle for the list, or the walk never starts.
              step('scroll', 'Row 25', 'Row 25'),
              step('tap', 'Row 25', 'Row 25'),
              // Back UP: the target is in the tree, above the band.
              step('scroll', 'Row 1', 'Row 1'),
              step('tap', 'Row 1', 'Row 1'),
            ],
        publish: (Map<String, Object?> r) async => report = r,
      );
      expect(report!['entryReached'], isTrue);
      final List<Map<String, Object?>> steps =
          (report!['steps']! as List<Object?>).cast<Map<String, Object?>>();
      expect(
        steps.map((Map<String, Object?> s) => s['status']),
        everyElement('OK'),
        reason: '${steps.map((Map<String, Object?> s) => s['error'])}',
      );
      expect(steps.map((Map<String, Object?> s) => s['tapsSoFar']), <int>[
        0,
        1,
        1,
        2,
        2,
      ]);
      expect(steps[0]['drags'], greaterThan(0));
      expect(steps[1]['drags'], isNull);
      expect(steps[2]['drags'], greaterThan(0));
      expect(
        report!['drags'],
        (steps[0]['drags']! as int) + (steps[2]['drags']! as int),
      );
      expect(report!['taps'], 2);
    });

    testWidgets('an ambiguous target is refused before any drag', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = await onPhone(
        tester,
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: <Widget>[
                for (int i = 1; i <= 30; i++)
                  ListTile(title: Text(i.isEven ? 'Same' : 'Row $i')),
              ],
            ),
          ),
        ),
      );
      final StepOutcome out = await performStep(
        tester,
        step('scroll', 'Same', 'Same'),
      );
      expect(out.status, 'FAILED');
      expect(out.error, contains('ambiguous'));
      expect(out.drags, 0);
      handle.dispose();
    });
  });

  group('expect no — the absence oracle', () {
    Widget removable() => const MaterialApp(home: Scaffold(body: _Removable()));

    testWidgets('passes when the thing is gone, fails when it stays', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = await onPhone(tester, removable());
      final StepOutcome gone = await performStep(
        tester,
        step('tap', 'Delete first', 'Walnut', absent: true),
      );
      expect(gone.status, 'OK', reason: '${gone.error}');
      expect(
        gone.expectedBefore,
        isFalse,
        reason: 'it was there before, so the removal proved something',
      );

      final StepOutcome stays = await performStep(
        tester,
        step('tap', 'Delete first', 'Oak', absent: true),
      );
      expect(stays.status, 'FAILED');
      expect(stays.error, contains('"Oak" is still on screen'));
      handle.dispose();
    });

    testWidgets('an absence that already held proves nothing, and says so', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = await onPhone(tester, removable());
      final StepOutcome out = await performStep(
        tester,
        step('tap', 'Delete first', 'Pine', absent: true),
      );
      expect(out.status, 'OK');
      expect(out.expectedBefore, isTrue);
      handle.dispose();
    });
  });

  group('system back — the platform pop, not the on-screen arrow', () {
    Widget twoPages() => MaterialApp(
      home: Builder(
        builder: (BuildContext c) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(c).push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Detail page')),
              ),
            ),
            child: const Text('Open detail'),
          ),
        ),
      ),
    );

    testWidgets('pops a page that has no back button at all', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = await onPhone(tester, twoPages());
      await performStep(tester, step('tap', 'Open detail', 'Detail page'));
      final StepOutcome out = await performStep(
        tester,
        step('system back', '', 'Open detail'),
      );
      expect(out.status, 'OK', reason: '${out.error}');
      expect(out.popHandled, isTrue);
      expect(out.dispatched, isTrue);
      expect(out.tapped, isFalse);
      handle.dispose();
    });

    testWidgets('on the root, nothing takes it — the app would close', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = await onPhone(tester, twoPages());
      final StepOutcome out = await performStep(
        tester,
        step('system back', '', 'Open detail'),
      );
      expect(out.popHandled, isFalse);
      expect(
        out.status,
        'FAILED',
        reason:
            'the oracle would read the screen the user just left — a pass '
            'there is a pass on an app that is no longer open',
      );
      expect(out.error, contains('closes the app'));
      handle.dispose();
    });
  });

  group('long-press — resolved and refused like a tap', () {
    testWidgets('presses a control that only answers a long press', (
      WidgetTester tester,
    ) async {
      int pressed = 0;
      final SemanticsHandle handle = await onPhone(
        tester,
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                ListTile(
                  title: const Text('Hold to pin'),
                  onLongPress: () => pressed++,
                ),
                const Text('Just text'),
              ],
            ),
          ),
        ),
      );
      final StepOutcome out = await performStep(
        tester,
        step('long-press', 'Hold to pin', 'Hold to pin'),
      );
      expect(out.status, 'OK', reason: '${out.error}');
      expect(pressed, 1);
      expect(out.tapped, isTrue, reason: 'a long press is reach, like a tap');
      expect(out.centreHitsHandler, isTrue);

      final StepOutcome none = await performStep(
        tester,
        step('long-press', 'Just text', 'Just text'),
      );
      expect(none.status, 'FAILED');
      expect(none.dispatched, isFalse);
      expect(none.error, contains('"Just text" carries no long-press action'));
      handle.dispose();
    });

    testWidgets('a target off the surface is refused, as a tap is', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = await onPhone(
        tester,
        MaterialApp(
          home: Scaffold(
            body: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned(
                  top: 640, // centre at 668 on a 667 surface
                  left: 0,
                  width: 200,
                  child: ListTile(
                    title: const Text('Low hold'),
                    onLongPress: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final StepOutcome out = await performStep(
        tester,
        step('long-press', 'Low hold', 'Low hold'),
      );
      expect(out.status, 'FAILED');
      expect(out.dispatched, isFalse);
      expect(out.error, contains('"Low hold" is not reachable'));
      handle.dispose();
    });
  });
}

class _Removable extends StatefulWidget {
  const _Removable();

  @override
  State<_Removable> createState() => _RemovableState();
}

class _RemovableState extends State<_Removable> {
  bool walnut = true;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      if (walnut) const Text('Walnut'),
      const Text('Oak'),
      TextButton(
        onPressed: () => setState(() => walnut = false),
        child: const Text('Delete first'),
      ),
    ],
  );
}
