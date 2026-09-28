// The gate mechanism, held down without a device.
//
// `flutter drive` proves the gate on a simulator, but it runs by hand, takes a
// minute of Xcode build, and never runs in CI — so every case below is a thing
// that would otherwise be checked only when someone remembered to check it.
// Only one of the five is the happy path. The rest are the answers a wrong stub
// gives, because the whole no-credentials design rests on a wrong stub making a
// step go red and say why.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// No material import: its `Step` collides with the walker's, and nothing here
// needs a widget — the app under test brings its own.
import 'package:flutter_test/flutter_test.dart';
import 'package:ux_demo_app/main.dart' show Product, products;
import 'package:ux_demo_app/main_gated.dart' show GatedDemoApp;

import '../integration_test/gate_stub.dart';
import '../integration_test/gated_journey_test.dart' show setup;
import '../integration_test/ux_journey_test.dart'
    show Step, StepOutcome, performStep, settle;

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
      _MisfilledOverrides(
        (Uri url) => url.path.contains('/auth/login')
            ? (status: 500, body: <String, Object?>{})
            : (status: 401, body: <String, Object?>{'error': 'no session'}),
      ),
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
