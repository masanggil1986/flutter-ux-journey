// The worked instance of example/journey-gated.md — a journey that starts
// behind a sign-in gate.
//
// Note what is NOT here: the measurement. Every rect, guideline evaluation and
// semantics dump comes from `walkJourney` in ux_journey_test.dart, so this file
// is only the three things that are genuinely per-journey — the stub, the setup
// steps, the journey steps. Most of this file is the two step lists — a second
// journey costs its own steps, not a second copy of a walker.
//
// The file the skill generates into an app it is auditing is still ONE file:
// there, the consts and the engine live together. Two journeys in one repo is
// the case where sharing is possible, and this is what it looks like.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ux_demo_app/main_gated.dart' as app;

import 'gate_stub.dart';
import '../ux_audit/ux_journey_test.dart' show Step, walkJourney;

/// `## Setup` — getting to the journey's starting line. Excluded from
/// measurement and from scoring: the goal is not "sign in", it is what the user
/// came to do once they are in.
///
/// The values are arbitrary and the address is `*.example.invalid`. The walk
/// never receives a real credential, and with the stub installed the sign-in
/// is answered in-process — this app speaks only through a `dart:io`
/// HttpClient, which is what the stub replaces.
const List<Step> setup = <Step>[
  (
    action: 'type',
    target: 'Email address',
    nth: null,
    text: 'ux-audit@example.invalid',
    absent: false,
    expected: 'Password',
  ),
  (
    action: 'type',
    target: 'Password',
    nth: null,
    text: 'not-a-real-password',
    absent: false,
    expected: 'Sign in',
  ),
  (
    action: 'tap',
    target: 'Sign in',
    nth: null,
    text: null,
    absent: false,
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
    absent: false,
    expected: '189,000 KRW',
  ),
  (
    action: 'tap',
    target: 'Remove from list',
    nth: null,
    text: null,
    absent: false,
    expected: 'Cancel',
  ),
  (
    action: 'tap',
    target: 'Back',
    nth: null,
    text: null,
    absent: false,
    expected: 'Saved items',
  ),
];

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  bool surfaceReady = false;
  Future<void> shot(String name) async {
    if (!surfaceReady) {
      await binding.convertFlutterSurfaceToImage();
      surfaceReady = true;
    }
    await binding.takeScreenshot(name);
  }

  testWidgets('gated ux journey', (WidgetTester tester) async {
    // BEFORE app.main(), which walkJourney calls. The app fires its session
    // probe on the first frame, so an override installed afterwards is already
    // too late — that is the reason walkJourney takes `launch` as a callback
    // instead of launching the app itself.
    HttpOverrides.global = StubHttpOverrides();

    await walkJourney(
      tester,
      launch: app.main,
      setup: setup,
      journey: journey,
      // Wire the stub's own call list into the report. It is not automatic:
      // the walker's `networkCalls` defaults to empty, and an empty field
      // costs the report the one layer that shows which calls the journey
      // depended on.
      networkCalls: stubCalls,
      // Android deadlocks on convertFlutterSurfaceToImage() when the app hosts
      // a platform view; the host captures the visual layer there instead.
      shot: Platform.isIOS ? shot : null,
      // MUTATE, never replace: reportData['screenshots'] is how the driver
      // gets the PNG bytes, and a fresh map deletes every one of them while
      // the run still passes.
      publish: (Map<String, Object?> report) async =>
          (binding.reportData ??= <String, dynamic>{}).addAll(report),
      runContext: <String, Object?>{
        'mode': 'drive',
        'renderer': 'device',
        // defaultTargetPlatform, not Platform.operatingSystem: the widget-test
        // entry records what the FRAMEWORK was told to be ('iOS'), and two
        // spellings of one field across the two modes is a field a reader
        // cannot compare.
        'targetPlatform': defaultTargetPlatform.name,
        // The report format requires these in the scope clause. On a device
        // they are not measured, they are supplied — but the clause quotes
        // what it finds, so a missing key leaves the author to invent one.
        'deviceProfile': 'device-supplied',
        'fontSource': 'device',
      },
    );
  });
}
