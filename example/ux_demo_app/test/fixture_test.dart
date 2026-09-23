// The fixture's own oracle. This app is a regression fixture, so its value is
// entirely in tripping exactly the six seeded defects and nothing else — if
// someone "fixes" the app, these fail and say so.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ux_demo_app/main.dart';

Future<Evaluation> _evaluate(WidgetTester tester, AccessibilityGuideline g) async {
  final SemanticsHandle handle = tester.ensureSemantics();
  final Evaluation e = await g.evaluate(tester);
  handle.dispose();
  return e;
}

void main() {
  late List<Product> original;
  setUp(() => original = List<Product>.of(products));
  tearDown(() => products
    ..clear()
    ..addAll(original));

  testWidgets('DEFECT 1: the promo dismiss target is 24x24', (WidgetTester tester) async {
    await tester.pumpWidget(const UxDemoApp());
    final Evaluation e = await _evaluate(tester, iOSTapTargetGuideline);
    expect(e.passed, isFalse);
    expect(e.reason, contains('Size(24.0, 24.0)'));
    expect(e.reason, contains('Dismiss promotion'));
  });

  testWidgets('DEFECT 2: exactly one tappable node has no label', (WidgetTester tester) async {
    await tester.pumpWidget(const UxDemoApp());
    final Evaluation e = await _evaluate(tester, labeledTapTargetGuideline);
    expect(e.passed, isFalse);
    // Exactly one: the unlabelled search IconButton. More than one means a
    // widget meant to be a control or a single-defect target also lost its
    // label — including the 24x24 target, which must fail on size alone.
    expect('expected tappable node to have semantic label'.allMatches(e.reason!).length, 1);
  });

  testWidgets('DEFECT 3: a card is one label joined by newlines', (WidgetTester tester) async {
    await tester.pumpWidget(const UxDemoApp());
    final SemanticsHandle handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Walnut Side Table\n189,000 KRW\nOnly 2 left'), findsOneWidget);
    // Two cards share "Side Table": a substring selector must report ambiguity
    // instead of silently taking the first hit.
    expect(find.bySemanticsLabel(RegExp('Side Table')), findsNWidgets(2));
    handle.dispose();
  });

  testWidgets('DEFECT 4: #DDDDDD on white fails contrast', (WidgetTester tester) async {
    await tester.pumpWidget(const UxDemoApp());
    final Evaluation e = await _evaluate(tester, textContrastGuideline);
    expect(e.passed, isFalse);
    expect(e.reason, contains('Free returns within 14 days'));
  });

  testWidgets('DEFECT 5 + 6: remove destroys with no confirmation and dead-ends',
      (WidgetTester tester) async {
    await tester.pumpWidget(const UxDemoApp());
    await tester.tap(find.text('Walnut Side Table'));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget, reason: 'detail screen is not the dead end');

    await tester.tap(find.text('Remove from list'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing, reason: 'DEFECT 6: no confirmation');
    expect(products.length, 2, reason: 'DEFECT 6: destroyed on the first tap');
    expect(find.byType(RemovedScreen), findsOneWidget);
    expect(find.byType(BackButton), findsNothing, reason: 'DEFECT 5: dead end');
    expect(ModalRoute.of(tester.element(find.byType(RemovedScreen)))!.canPop, isFalse);
  });

  testWidgets('CONTROL: the cart button passes every per-widget check',
      (WidgetTester tester) async {
    await tester.pumpWidget(const UxDemoApp());
    expect(tester.getSize(find.byType(FilledButton)).height, greaterThanOrEqualTo(48));
    final SemanticsHandle handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('View cart (3 items)'), findsOneWidget);
    handle.dispose();
  });
}
