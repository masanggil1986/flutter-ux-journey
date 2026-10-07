// The `flutter drive` entry. It exists as a separate file because the binding
// has to be chosen before anything else runs, and
// IntegrationTestWidgetsFlutterBinding is a LIVE binding — under `flutter test`
// it would change the frame policy out from under the walk. The default mode is
// the widget-test one in ux_journey_test.dart; this is the fallback for an app
// whose plugins or platform views need a real device under them.
//
// Run:
//   flutter drive --driver=test_driver/integration_test.dart \
//                 --target=integration_test/ux_journey_drive.dart -d <device-id>

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:ux_demo_app/main.dart' as app;

import '../ux_audit/ux_journey_test.dart' show journey, setup, walkJourney;

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Android deadlocks in convertFlutterSurfaceToImage() + takeScreenshot()
  // whenever the app hosts a platform view (webview, media, camera) — no error,
  // no timeout. Measured twice on a production app. Guidelines and the
  // semantics dump are unaffected, so the walk still measures; the VISUAL layer
  // comes from a host capture (`adb exec-out screencap`) instead.
  bool surfaceReady = false;
  Future<void> shot(String name) async {
    // Lazily, on the first capture: the conversion needs a frame to already
    // exist, and every caller of this is after one.
    if (!surfaceReady) {
      await binding.convertFlutterSurfaceToImage();
      surfaceReady = true;
    }
    await binding.takeScreenshot(name);
  }

  testWidgets('ux journey', (WidgetTester tester) async {
    // BEFORE app.main(), which walkJourney calls: an app that probes on its
    // first frame has sent that request by the time a later override lands.
    // A journey that has to get past a gate swaps this line for
    // `HttpOverrides.global = StubHttpOverrides();` AND passes
    // `networkCalls: stubCalls` below — gated_journey_test.dart does both.
    final List<String> calls = <String>[];
    HttpOverrides.global = NetworkCut(calls);

    await walkJourney(
      tester,
      launch: app.main,
      setup: setup,
      journey: journey,
      // The paths the cut refused. Without this the field ships [] and reads
      // as "the journey made no requests".
      networkCalls: calls,
      shot: Platform.isIOS ? shot : null,
      // MUTATE, never replace: takeScreenshot appends each PNG into
      // reportData['screenshots'], and that list is how the driver's
      // onScreenshot gets the bytes. Assigning a fresh map here silently
      // deletes every screenshot and the run still passes.
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

/// The drive path's network posture: every `dart:io` HttpClient request is
/// refused at connect, as under airplane mode, and its path recorded.
///
/// `flutter test` gets this for free — flutter_test answers every request with
/// a 400 — but the drive binding installs nothing, so without this a run on
/// the iOS simulator (which shares the host's network) sends the journey's
/// sign-in to whatever backend the app names. It is the REAL HttpClient with
/// one hook: connectionFactory is consulted before any DNS lookup or socket,
/// so nothing is sent.
///
/// Its ceiling: only HttpClient, only in this isolate, only one built after
/// this is installed, and only while the app does not set its own
/// connectionFactory. network-stub.md lists what that leaves out.
class NetworkCut extends HttpOverrides {
  NetworkCut(this.calls);

  final List<String> calls;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionFactory =
            (Uri url, String? proxyHost, int? proxyPort) async {
              calls.add(url.path);
              throw const SocketException('ux audit: network cut');
            };
}
