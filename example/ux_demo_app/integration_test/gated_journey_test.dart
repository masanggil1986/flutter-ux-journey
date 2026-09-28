// The worked instance of example/journey-gated.md — a journey that starts
// behind a sign-in gate.
//
// Note what is NOT here: the measurement. Every rect, guideline evaluation and
// semantics dump comes from `walkJourney` in ux_journey_test.dart, so this file
// is only the three things that are genuinely per-journey — the stub, the setup
// steps, the journey steps. This file is 105 lines to the first walker's 1155,
// and 67 of them are the two step lists — a second journey costs its own steps,
// not a second copy of a walker.
//
// The file the skill generates into an app it is auditing is still ONE file:
// there, the consts and the engine live together. Two journeys in one repo is
// the case where sharing is possible, and this is what it looks like.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ux_demo_app/main_gated.dart' as app;

import 'gate_stub.dart';
import 'ux_journey_test.dart' show Step, walkJourney;

/// `## Setup` — getting to the journey's starting line. Excluded from
/// measurement and from scoring: the goal is not "sign in", it is what the user
/// came to do once they are in.
///
/// The values are arbitrary and the address is `*.example.invalid`. The walk
/// never receives a real credential, and with the stub installed no request
/// leaves the device.
const List<Step> setup = <Step>[
  (
    action: 'type',
    target: 'Email address',
    nth: null,
    text: 'ux-audit@example.invalid',
    expected: 'Password',
  ),
  (
    action: 'type',
    target: 'Password',
    nth: null,
    text: 'not-a-real-password',
    expected: 'Sign in',
  ),
  (
    action: 'tap',
    target: 'Sign in',
    nth: null,
    text: null,
    expected: 'Saved items',
  ),
];

/// The same three steps example/journey.md walks. Identical on purpose: the
/// only difference between the two runs is the gate, so a number that moves
/// between them moved because of the gate.
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

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('gated ux journey', (WidgetTester tester) async {
    // BEFORE app.main(), which walkJourney calls. The app fires its session
    // probe on the first frame, so an override installed afterwards is already
    // too late — that is the reason walkJourney takes `launch` as a callback
    // instead of launching the app itself.
    HttpOverrides.global = StubHttpOverrides();

    // Wire the stub's own call list into the report. It is not automatic: the
    // walker's `networkCalls` defaults to empty, and an empty field costs the
    // report the one layer that shows which calls the journey depended on.
    await walkJourney(
      tester,
      binding,
      launch: app.main,
      setup: setup,
      journey: journey,
      networkCalls: stubCalls,
    );
  });
}
