// Three ways the 0.4.0 walker reported something false, each found by a
// pre-release review with a small app built to make it happen, and each pinned
// here by that app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ux_audit/ux_journey_test.dart'
    show applyDevice, kIphoneSe, walkJourney;

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

Future<List<Map<String, Object?>>> walk(
  WidgetTester tester,
  Widget app,
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
  journey, {
  void Function(Map<String, Object?>)? report,
}) async {
  applyDevice(tester, kIphoneSe);
  addTearDown(tester.view.reset);
  Map<String, Object?>? r;
  await walkJourney(
    tester,
    launch: () => runApp(app),
    journey: journey,
    publish: (Map<String, Object?> x) async => r = x,
  );
  report?.call(r!);
  return (r!['steps']! as List<Object?>).cast<Map<String, Object?>>();
}

/// A screen that asks before it lets the user leave — the shape of every
/// editor with unsaved changes.
Widget confirmOnLeave() => MaterialApp(
  home: Builder(
    builder: (BuildContext ctx) => Scaffold(
      body: TextButton(
        onPressed: () => Navigator.of(ctx).push(
          MaterialPageRoute<void>(
            // WillPopScope, deprecated but everywhere, and the shape go_router's
            // onExit shares: the pop's Future waits on the user's answer.
            // ignore: deprecated_member_use
            builder: (BuildContext c) => WillPopScope(
              onWillPop: () async =>
                  await showDialog<bool>(
                    context: c,
                    builder: (BuildContext d) => AlertDialog(
                      title: const Text('Discard changes?'),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.pop(d, true),
                          child: const Text('Discard'),
                        ),
                      ],
                    ),
                  ) ??
                  false,
              child: const Scaffold(body: Text('Editor')),
            ),
          ),
        ),
        child: const Text('Open editor'),
      ),
    ),
  ),
);

/// A row whose removal fails — as every request does under the network cut —
/// and says so in a dialog. The row stays.
class _FailedRemoval extends StatelessWidget {
  const _FailedRemoval();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListView(
      children: <Widget>[
        ListTile(
          title: const Text('Walnut Side Table'),
          trailing: Builder(
            builder: (BuildContext ctx) => TextButton(
              child: const Text('Remove'),
              onPressed: () => showDialog<void>(
                context: ctx,
                builder: (BuildContext d) => AlertDialog(
                  title: const Text("Couldn't remove the item"),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(d),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

void main() {
  // The pop's Future is held open by the app's dialog, and the dialog is only
  // built by a pump nobody issued while awaiting it — measured: the walk never
  // published, and no timeout fires on the test's fake clock.
  testWidgets(
    'system back on a screen that asks first does not hang the walk',
    (WidgetTester tester) async {
      final List<Map<String, Object?>> steps = await walk(
        tester,
        confirmOnLeave(),
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
          step('tap', 'Open editor', 'Editor'),
          step('system back', '', 'Discard changes?'),
          step('tap', 'Discard', 'Open editor'),
        ],
      );
      expect(
        steps.take(3).map((Map<String, Object?> s) => s['status']),
        <String>['OK', 'OK', 'OK'],
      );
      // The app took the pop and is asking the user: handled, not an exit.
      expect(steps[1]['popHandled'], isTrue);
    },
  );

  // An icon-only button with no tooltip has no label, so the entry wait never
  // finds "Cart". That is the defect this tool exists to report — refusing to
  // walk turned it into a launch failure and threw the screen's measurements
  // away.
  testWidgets(
    'an unlabelled first target is step 1\'s finding, not a launch failure',
    (WidgetTester tester) async {
      Map<String, Object?>? report;
      final List<Map<String, Object?>> steps = await walk(
        tester,
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('Shop'),
              actions: <Widget>[
                IconButton(
                  icon: const Icon(Icons.shopping_cart),
                  onPressed: () {},
                ),
              ],
            ),
            body: const Center(child: Text('Products')),
          ),
        ),
        <
          ({
            String action,
            String target,
            int? nth,
            String? text,
            String expected,
            bool absent,
          })
        >[step('tap', 'Cart', 'Your cart')],
        report: (Map<String, Object?> r) => report = r,
      );
      expect(report!['entryReached'], isFalse);
      expect(steps.first['status'], 'FAILED');
      expect('${steps.first['error']}', contains('no semantics node matches'));
      // The screen is measured: the label guideline is what names the defect.
      expect(steps.first['guidelines'], hasLength(4));
    },
  );

  // A dialog route blocks the semantics of everything under it, so the row
  // the failed removal left behind vanished from the tree — and `expect no`
  // read that as proof the removal worked.
  testWidgets('expect no does not pass because a dialog hides the item', (
    WidgetTester tester,
  ) async {
    final List<Map<String, Object?>> steps = await walk(
      tester,
      const MaterialApp(home: _FailedRemoval()),
      <
        ({
          String action,
          String target,
          int? nth,
          String? text,
          String expected,
          bool absent,
        })
      >[step('tap', 'Remove', 'Walnut Side Table', absent: true)],
    );
    expect(steps.first['status'], 'FAILED');
    expect('${steps.first['error']}', contains('still on screen'));
  });
}
