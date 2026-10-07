// The gate mechanism, held down without a device.
//
// `flutter drive` proves the gate on a simulator, but it runs by hand, takes a
// minute of Xcode build, and never runs in CI — so every case below is a thing
// that would otherwise be checked only when someone remembered to check it.
// Several are the answers a wrong stub gives, because the whole no-credentials
// design rests on a wrong stub making a step go red and say why. The rest hold
// down the network boundary itself: what the stub answers, and what the drive
// entry refuses.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// No material import: its `Step` collides with the walker's. widgets has no
// `Step`, and the image test needs one widget of its own.
import 'package:flutter/widgets.dart' show Image, SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:ux_demo_app/main.dart' show Product, products;
import 'package:ux_demo_app/main_gated.dart' show GatedDemoApp;
import 'package:ux_demo_app/main_gated.dart' as gated_app show main;

import '../integration_test/gate_stub.dart';
import '../integration_test/gated_journey_test.dart' show journey, setup;
import '../integration_test/ux_journey_drive.dart' show NetworkCut;
import '../ux_audit/ux_journey_test.dart'
    show Step, StepOutcome, performStep, settle, walkJourney;

const String _driveEntry = 'integration_test/ux_journey_drive.dart';

void main() {
  // DEFECT 6 mutates this top-level list, and test 2 walks past the gate onto
  // the screen that owns it. Same copy/restore as fixture_test and walker_test.
  late List<Product> original;
  setUp(() {
    original = List<Product>.of(products);
    // Top-level and mutable: one leaked entry from the previous test would make
    // the next one's call-order assertion read a call it never made.
    stubCalls.clear();
  });
  tearDown(() {
    products
      ..clear()
      ..addAll(original);
    HttpOverrides.global = null;
  });

  testWidgets('the stub answers the probe, and 401 renders the gate', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = await _pumpGate(tester, StubHttpOverrides());
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Saved items'), findsNothing);
    // The probe fires on the first frame, so this is also the evidence that an
    // override installed after app.main() would be too late.
    expect(stubCalls, <String>['/session']);
    handle.dispose();
  });

  testWidgets('the three setup steps open the gate', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = await _pumpGate(tester, StubHttpOverrides());
    final List<StepOutcome> out = await _runSetup(tester);

    expect(out.map((StepOutcome o) => o.status), <String>[
      'OK',
      'OK',
      'OK',
    ], reason: 'errors: ${out.map((StepOutcome o) => o.error).toList()}');
    expect(find.text('Saved items'), findsOneWidget);
    expect(stubCalls, <String>['/session', '/auth/login']);
    handle.dispose();
  });

  testWidgets('the permissive fallback does not read as a live session', (
    WidgetTester tester,
  ) async {
    // What a route table missing '/session' does: the call falls through to the
    // template's deliberately permissive 200 + {}. `hasSession` asks for a user
    // object rather than for a 2xx precisely so this cannot skip the gate.
    final SemanticsHandle handle = await _pumpGate(
      tester,
      _MisfilledOverrides((Uri _) => _fallback),
    );
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Saved items'), findsNothing);
    handle.dispose();
  });

  testWidgets('a wrong route table fails the setup out loud', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = await _pumpGate(
      tester,
      _MisfilledOverrides(_signInRefused),
    );
    final List<StepOutcome> out = await _runSetup(tester);

    // The two type steps still pass: the fields are there, the gate rendered.
    // It is the step that needs the server that goes red.
    expect(out.map((StepOutcome o) => o.status), <String>[
      'OK',
      'OK',
      'FAILED',
    ]);
    // Names what it could not find, so the reader fixes the route table rather
    // than suspecting the journey.
    expect(out.last.error, contains('Saved items'));
    expect(out.last.error, contains('no semantics node matches'));
    // The gesture went out — this is a server answer the app handled, not a
    // selector miss.
    expect(out.last.dispatched, isTrue);
    expect(find.text('Saved items'), findsNothing);
    expect(
      find.textContaining('could not sign you in'),
      findsOneWidget,
      reason: 'the user has to see it too, not only the artifact',
    );
    handle.dispose();
  });

  testWidgets('with no override the app never reaches the list', (
    WidgetTester tester,
  ) async {
    // flutter_test installs an HttpOverrides of its own that answers 400.
    // Dropping it is what puts the app on the default audit path: no stub, and
    // a host that RFC 2606 guarantees is nobody's — so whether the socket dies
    // at DNS or at the sandbox, it cannot have been a real server.
    HttpOverrides.global = null;
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(const GatedDemoApp());
    // A real socket completes on the real event loop, which `pump` does not
    // turn. If it never completes, this environment cannot run the case, and a
    // skip is the honest outcome — a passing assertion here would be a fiction.
    if (!await _pumpRealAsync(
      tester,
      () => find.text('Welcome back').evaluate().isNotEmpty,
    )) {
      markTestSkipped('the session probe never completed off the fake clock');
      handle.dispose();
      return;
    }
    expect(find.text('Saved items'), findsNothing);

    final List<StepOutcome> out = await _runSetup(tester);
    expect(out.last.status, 'FAILED');
    await _pumpRealAsync(
      tester,
      () => find.textContaining('could not sign you in').evaluate().isNotEmpty,
    );
    expect(find.textContaining('could not sign you in'), findsOneWidget);
    expect(find.text('Saved items'), findsNothing);
    handle.dispose();
  });

  testWidgets('a walk through the gate sets up, then walks the journey', (
    WidgetTester tester,
  ) async {
    // The ## Setup path at walkJourney level, which is where setupFailed and
    // the setup screenshots are decided. performStep alone (above) never
    // reaches that code.
    final ({Map<String, Object?> report, List<String> shots}) r = await _walk(
      tester,
      StubHttpOverrides(),
    );
    final List<Object?> setupSteps = r.report['setupSteps']! as List<Object?>;
    expect(r.report['setupFailed'], isFalse);
    expect(_field(setupSteps, 'status'), <String>['OK', 'OK', 'OK']);
    // Every journey step plus the outcome screen.
    expect((r.report['steps']! as List<Object?>).length, journey.length + 1);
    expect(r.report['networkCalls'], <String>['/session', '/auth/login']);
    expect(r.shots.where((String s) => s.startsWith('setup_')), isEmpty);
  });

  testWidgets('a walk the gate stops reports the gate, and no journey', (
    WidgetTester tester,
  ) async {
    final ({Map<String, Object?> report, List<String> shots}) r = await _walk(
      tester,
      _MisfilledOverrides(_signInRefused),
    );
    final List<Object?> setupSteps = r.report['setupSteps']! as List<Object?>;
    // Reporting the steps that did run as a journey would describe a short,
    // healthy app. A setup failure is a setup failure.
    expect(r.report['setupFailed'], isTrue);
    expect(r.report['steps'], isEmpty);
    expect(r.report['taps'], 0);
    expect(_field(setupSteps, 'status'), <String>['OK', 'OK', 'FAILED']);
    // One screenshot, of the step the gate stopped: it is the whole evidence.
    expect(_field(setupSteps, 'screenshot'), <String?>[
      null,
      null,
      'setup_3.png',
    ]);
    expect(r.shots, <String>['setup_3']);
  });

  testWidgets('a network image is answered by the stub, not by a TypeError', (
    WidgetTester tester,
  ) async {
    // NetworkImage asks for getUrl, not openUrl. A stub that only answers
    // openUrl hands it null, and the walk then records a TypeError the app
    // does not have — and paints it on screen, where it reads as a finding.
    //
    // NetworkImage builds ONE HttpClient per process, on its first load, from
    // whatever override is current then. Keep this the only image in the file,
    // or the client this test sees is some earlier test's.
    HttpOverrides.global = StubHttpOverrides();
    Object? error;
    await tester.pumpWidget(
      Image.network(
        'https://api.example.invalid/p/walnut.png',
        errorBuilder: (_, Object e, _) {
          error = e;
          return const SizedBox();
        },
      ),
    );
    // The decode runs on the engine, off the fake clock.
    await _pumpRealAsync(tester, () => error != null);
    expect(stubCalls, <String>['/p/walnut.png']);
    // The stub's {} is not an image, so it still fails — as a decode, which
    // network-stub.md documents as a walk artifact.
    expect(error, isNotNull);
    expect('$error', isNot(contains('is not a subtype')));
  });

  test('every HttpClient request method reaches the stub, once', () async {
    final HttpClient client = StubHttpOverrides().createHttpClient(null);
    final Uri url = Uri.parse('https://api.example.invalid/m');
    const String host = 'api.example.invalid';
    final List<Future<HttpClientRequest>> opened = <Future<HttpClientRequest>>[
      client.getUrl(url),
      client.postUrl(url),
      client.putUrl(url),
      client.deleteUrl(url),
      client.patchUrl(url),
      client.headUrl(url),
      client.get(host, 443, '/m?q=1'),
      client.post(host, 443, '/m'),
      client.put(host, 443, '/m'),
      client.delete(host, 443, '/m'),
      client.patch(host, 443, '/m'),
      client.head(host, 443, '/m'),
      client.open('GET', host, 443, '/m?q=1'),
    ];
    final List<String> methods = <String>[];
    final List<String> queries = <String>[];
    for (final Future<HttpClientRequest> f in opened) {
      final HttpClientRequest req = await f;
      methods.add(req.method);
      queries.add(req.uri.query);
      // A cookie jar adds to this list, so it must exist and be mutable.
      req.cookies.add(Cookie('session', 'stub'));
      await req.flush();
      final HttpClientResponse res = await req.close();
      // Awaiting `done` after `close` is one request, not two.
      await req.done;
      expect(res.cookies, isEmpty);
      await res.drain<void>();
    }
    const List<String> verbs = <String>[
      'GET',
      'POST',
      'PUT',
      'DELETE',
      'PATCH',
      'HEAD',
    ];
    expect(methods, <String>[...verbs, ...verbs, 'GET']);
    // A query stays a query, as in dart:io: folded into the path, it would
    // change what the routes match on.
    expect(queries[6], 'q=1');
    expect(queries[12], 'q=1');
    expect(stubCalls, List<String>.filled(opened.length, '/m'));
  });

  test(
    'the drive entry cuts the network: refused, recorded, never sent',
    () async {
      // A listener the cut must never reach. Loopback, so a broken cut sends
      // nothing beyond this machine either.
      final ServerSocket server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      int connections = 0;
      server.listen((Socket s) {
        connections++;
        s.destroy();
      });
      final List<String> calls = <String>[];
      final HttpClient client = NetworkCut(calls).createHttpClient(null);
      try {
        final Uri url = Uri(
          scheme: 'http',
          host: server.address.address,
          port: server.port,
          path: '/auth/login',
        );
        await expectLater(
          client.postUrl(url).then((HttpClientRequest r) => r.close()),
          throwsA(isA<SocketException>()),
        );
        expect(calls, <String>['/auth/login']);
        expect(connections, 0);
      } finally {
        client.close(force: true);
        await server.close();
      }
    },
  );

  test('the drive entry installs the cut before launch, and reports it', () {
    // The drive entry runs only on a device, so nothing else would notice
    // either line going missing — and without them an iOS-simulator run
    // reaches whatever backend the app names while the report says nothing.
    final String src = File(_driveEntry).readAsStringSync();
    const String cut = 'HttpOverrides.global = NetworkCut(calls);';
    final int cutAt = src.indexOf(cut);
    final int walkAt = src.indexOf('await walkJourney(');
    expect(cutAt, isNonNegative, reason: '$_driveEntry lost `$cut`');
    expect(walkAt, isNonNegative, reason: '$_driveEntry lost its walk');
    expect(
      cutAt < walkAt,
      isTrue,
      reason:
          'the cut must be in before the app launches, or its first frame '
          'has already sent what the cut exists to stop',
    );
    expect(
      src.contains('networkCalls: calls,'),
      isTrue,
      reason: 'the refused paths are the evidence; unwired, the field is []',
    );
  });
}

/// What a route table that refuses the sign-in does: the probe still answers
/// 401, so the gate renders, and the step that needs the server goes red.
({int status, Object body}) _signInRefused(Uri url) =>
    url.path.contains('/auth/login')
    ? (status: 500, body: <String, Object?>{})
    : (status: 401, body: <String, Object?>{'error': 'no session'});

/// One field of each recorded step, in order.
List<Object?> _field(List<Object?> steps, String key) =>
    steps.map((Object? s) => (s! as Map<String, Object?>)[key]).toList();

/// The shipped gated setup and journey through the real walkJourney, as the
/// gated drive entry runs them, minus the device. [shots] is every name the
/// walk asked to capture; nothing is written.
Future<({Map<String, Object?> report, List<String> shots})> _walk(
  WidgetTester tester,
  HttpOverrides overrides,
) async {
  HttpOverrides.global = overrides;
  final List<String> shots = <String>[];
  late Map<String, Object?> report;
  await walkJourney(
    tester,
    launch: gated_app.main,
    setup: setup,
    journey: journey,
    networkCalls: stubCalls,
    shot: (String name) async => shots.add(name),
    publish: (Map<String, Object?> r) async => report = r,
  );
  return (report: report, shots: shots);
}

/// Install [overrides], pump the gated app, and wait for the session probe to
/// answer. The caller disposes the returned handle: `addTearDown` is too late,
/// flutter_test checks for a live handle before tear-downs run.
///
/// The override goes in before `pumpWidget` because `GateClient` builds its
/// `HttpClient` in a field initialiser, so `HttpOverrides.current` is read while
/// the first frame is being built.
Future<SemanticsHandle> _pumpGate(
  WidgetTester tester,
  HttpOverrides overrides,
) async {
  HttpOverrides.global = overrides;
  final SemanticsHandle handle = tester.ensureSemantics();
  await tester.pumpWidget(const GatedDemoApp());
  // Not `pumpAndSettle`: while the probe is in flight the app renders a
  // `CircularProgressIndicator`, and an animation that never stops is exactly
  // the case the walker's bounded settle exists for.
  await settle(
    tester,
    until: () => find.text('Welcome back').evaluate().isNotEmpty,
  );
  return handle;
}

/// The same three steps `example/journey-gated.md` declares, through the same
/// `performStep` the drive uses. Importing them rather than restating them is
/// what makes this a test of the shipped setup phase.
Future<List<StepOutcome>> _runSetup(WidgetTester tester) async {
  final List<StepOutcome> out = <StepOutcome>[];
  for (final Step step in setup) {
    out.add(await performStep(tester, step));
  }
  return out;
}

/// Pump until [done], yielding to the REAL event loop between frames.
///
/// Only needed for the no-override case: `tester.pump` advances a fake clock, so
/// a genuine socket failure is never delivered inside it. Returns whether [done]
/// came true within the bound.
Future<bool> _pumpRealAsync(WidgetTester tester, bool Function() done) async {
  for (int i = 0; i < 25 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    // With a duration, not bare: `HttpClient` was built inside the fake-async
    // zone, so its own timers only fire when the fake clock is advanced, and a
    // zero-length pump leaves the connect attempt parked forever.
    await tester.pump(const Duration(milliseconds: 200));
  }
  return done();
}

/// gate_stub.dart's fallback, restated because `_fallbackStatus` and
/// `_fallbackBody` are private there and that file is the docs template byte for
/// byte — it must not grow a test hook.
const ({int status, Object body}) _fallback = (
  status: 200,
  body: <String, Object?>{},
);

/// Stands in for a mis-filled `_routes` table in gate_stub.dart. That table is a
/// private const, so the only way to audit what a wrong one does is to answer
/// with a different one from here.
class _MisfilledOverrides extends HttpOverrides {
  _MisfilledOverrides(this._answer);

  final ({int status, Object body}) Function(Uri url) _answer;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client(_answer);
}

class _Client implements HttpClient {
  _Client(this._answer);

  final ({int status, Object body}) Function(Uri url) _answer;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _Request(_answer, url);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this._answer, this._url);

  final ({int status, Object body}) Function(Uri url) _answer;
  final Uri _url;

  // Concrete because `GateClient` sets `headers.contentType` on the POST.
  // Forwarded to noSuchMethod it answers null, the assignment throws inside
  // `_json`'s catch-all, and the sign-in fails with no trace of why — measured:
  // a table answering 200 + an accessToken still left the gate up, so the
  // 500-answering test above would have passed without ever sending a request.
  @override
  final HttpHeaders headers = _Headers();

  @override
  Future<HttpClientResponse> close() async {
    final ({int status, Object body}) r = _answer(_url);
    return _Response(r.status, utf8.encode(jsonEncode(r.body)));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode, this._body);

  @override
  final int statusCode;
  final List<int> _body;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(_body).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Headers implements HttpHeaders {
  @override
  ContentType? contentType;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
