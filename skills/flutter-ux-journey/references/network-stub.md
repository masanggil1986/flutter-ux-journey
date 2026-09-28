# Network stub — getting past a gate without credentials

Copy `net_stub.dart` below into the audited app's `ux_audit/` — beside the walker, and inside the
path SKILL.md tells them to gitignore, because this is the one generated file that holds their real
endpoints and real response bodies. Fill in `_routes`, and set
`HttpOverrides.global = StubHttpOverrides();` **before `app.main()`** in the walker.

The mechanism is generic; only `_routes` is app-specific. `HttpOverrides` intercepts `dart:io`
`HttpClient`, which Dio, `package:http` and most clients sit on — so **the app is not modified** and
**no request leaves the device**.

**Before `app.main()`** is load-bearing, not tidiness. An app that probes a session on its first
frame has already made that call by the time a later override lands. This is precisely why
`walkJourney` takes `launch` as a callback instead of launching the app itself: handing it
`app.main` is the only way a caller gets in front of the first frame.

## The worked instance

`example/ux_demo_app/integration_test/gate_stub.dart` IS this template with `_routes` filled in and
nothing else touched — from the line `/// Anything not in [_routes] gets this.` to the end, the two
are byte-identical, and `test/recipe_sync_test.dart` holds them that way. So the template compiles,
and it has been run: against the fixture's gated entrypoint on an iPhone SE (3rd gen) simulator it
reports `networkCalls: ["/session", "/auth/login"]`, all three `## Setup` steps OK, and the same
three screen signatures as the ungated run of the same three journey steps.

Read the three files together before writing a stub for a real app:

- `example/journey-gated.md` — the journey, and the `## Setup` block this stub exists to serve.
- `example/ux_demo_app/integration_test/gate_stub.dart` — the filled-in `_routes`, two entries.
- `example/ux_demo_app/lib/main_gated.dart` — the gate being got past: a session probe on the first
  frame, a sign-in form, and a `dart:io` `HttpClient` on purpose, because that is the layer
  `HttpOverrides` intercepts.

## How to fill in `_routes` — iterate, do not read everything first

1. Stub the sign-in endpoint only. Run the walk.
2. The walk reports `networkCalls` (every path the app requested, in order) — **wire it**: the
   template's list is called `stubCalls`, and the walker's `networkCalls` starts empty, so assign
   one to the other or the field ships empty and the report quietly loses a layer. Then the step that
   failed. That tells you exactly what to add next.
3. Repeat. Three or four rounds is typical.

Measured on a production app: sign-in -> profile list -> profile detail -> home -> notifications,
found in four rounds without reading the API surface up front.

## Three mistakes that cost a run each

- **A session probe must be answered EXPLICITLY.** Falling through to the permissive `200 + {}`
  fallback tells the app it is already signed in, so the gate never renders and every `## Setup`
  step then fails looking for a field nobody built. Measured on the fixture's own first gated run:
  one wasted build, and the error blamed the journey rather than the route table. The fixture
  answers `/session` with 401.
- **content-type must be in the header MAP**, not only in the typed `contentType` field. Dio calls
  `headers.value('content-type')` to decide whether to JSON-decode. Without it the body arrives as a
  `String`, the app's `res.data!` cast throws, and the failure surfaces as the app's generic
  "something went wrong" — indistinguishable from a real server error.
- **A list endpoint must return a list.** The permissive `{}` fallback produces
  `type 'Null' is not a subtype of type ...` deep inside a model.

## The stub is not what keeps a password out of the artifact

A `type` step's text is recorded from the JOURNEY FILE, never read back from the screen, so
`obscureText` on the field does nothing for it. Measured on the fixture's first gated run:
`not-a-real-password` landed verbatim in `example/walk-gated.json`. The walker now asks the resolved
`EditableText` whether it hides its own value, and records `<redacted N chars: ...>` when it does.

That is a backstop, not the rule. The rule is that a journey types arbitrary data and the walk never
receives a real credential — see "Credentials: never ask for them" in SKILL.md. The redaction exists
because "the rule says so" is not a guarantee, and this is the one file in an audit that a reader
should never have to be careful with.

## Verifying interception actually happened

Run the walk with the device offline. If a response arrives at all, the stub is intercepting — a
real request could not have succeeded. This doubles as the guarantee that the audit never touches
production.

```bash
adb shell cmd connectivity airplane-mode enable
# ... run the walk ...
adb shell cmd connectivity airplane-mode disable   # ALWAYS — whether the walk passed or not
adb shell cmd connectivity airplane-mode           # prints `disabled`; confirm it before moving on
```

Restore it even when the walk failed, hung or was killed. Airplane mode survives the run, so an
emulator left offline breaks the next thing anyone does on that device for a reason that has nothing
to do with them.

```dart
// TEMPLATE — copy into the audited app's ux_audit/ and fill in _routes.
//
// A network stub for the walk's Setup phase.
//
// This file is the APP-SPECIFIC part of an audit: response shapes come from
// the app's own service and model classes, so the skill generates it per app
// by reading them. The mechanism below is generic; only `_routes` is not.
//
// Why it exists: the walker must get past a sign-in gate without a real
// account. `HttpOverrides.global` intercepts `dart:io` HttpClient, which is
// what Dio, package:http and most clients sit on — so the app is not modified
// and no request ever leaves the device.
//
// If a shape here is wrong, the journey step that depends on it FAILS and says
// so. That is the point: the oracle still holds. Never reach for a real
// account to turn a red step green.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// path suffix -> (status, json body). First match wins, so order matters.
typedef StubRoute = ({String match, int status, Object body});

const List<StubRoute> _routes = <StubRoute>[
  // APP-SPECIFIC. Read the app's own service + model classes and fill these in.
  // Start with the sign-in endpoint only, run the walk, and let the failures
  // tell you what else to add — that loop is faster than reading everything.
  //
  // (match: '/auth/sign-in', status: 200, body: <String, Object?>{'accessToken': 'stub', ...}),
  //
  // A LIST endpoint must return a LIST. The permissive {} fallback produces a
  // 'Null is not a subtype' deep inside a model — measured on a real app.
];

/// Anything not in [_routes] gets this. 200 + an empty object is deliberately
/// permissive: an unmatched call should not crash the app before the walk can
/// report where it actually got stuck.
const int _fallbackStatus = 200;
const Object _fallbackBody = <String, Object?>{};

class StubHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _StubClient();
}

/// Every request the app makes, in order. The walk reports this so an audit
/// can see which calls a journey actually depends on — and so the next
/// iteration of this stub knows what still needs a real shape.
final List<String> stubCalls = <String>[];

({int status, Object body}) _resolve(Uri url) {
  stubCalls.add(url.path);
  for (final StubRoute r in _routes) {
    if (url.path.contains(r.match)) {
      return (status: r.status, body: r.body);
    }
  }
  return (status: _fallbackStatus, body: _fallbackBody);
}

class _StubClient implements HttpClient {
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  Duration? connectionTimeout;
  @override
  bool autoUncompress = true;
  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _StubRequest(method, url);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubRequest implements HttpClientRequest {
  _StubRequest(this.method, this.uri);

  @override
  final String method;
  @override
  final Uri uri;
  @override
  final HttpHeaders headers = _StubHeaders();
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  int contentLength = -1;
  @override
  bool persistentConnection = true;
  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<HttpClientResponse> close() async {
    final ({int status, Object body}) r = _resolve(uri);
    return _StubResponse(r.status, utf8.encode(jsonEncode(r.body)));
  }

  @override
  Future<HttpClientResponse> get done => close();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubResponse extends Stream<List<int>> implements HttpClientResponse {
  _StubResponse(this.statusCode, this._body);

  @override
  final int statusCode;
  final List<int> _body;

  @override
  int get contentLength => _body.length;
  @override
  String get reasonPhrase => 'OK';
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => false;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  List<RedirectInfo> get redirects => const <RedirectInfo>[];
  @override
  HttpHeaders get headers => _StubHeaders()..contentType = ContentType.json;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_body).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubHeaders implements HttpHeaders {
  // content-type lives in the map too, not only in the typed field: Dio reads
  // it with headers.value('content-type') to decide whether to JSON-decode.
  // With it only in the field, the body arrives as a String, the app's
  // `res.data!` cast blows up, and the failure surfaces as a generic
  // "something went wrong" — indistinguishable from a real server error.
  final Map<String, List<String>> _store = <String, List<String>>{
    'content-type': <String>['application/json; charset=utf-8'],
  };

  @override
  ContentType? contentType = ContentType.json;
  @override
  int contentLength = -1;
  @override
  bool chunkedTransferEncoding = false;
  @override
  bool persistentConnection = true;

  @override
  List<String>? operator [](String name) => _store[name.toLowerCase()];

  @override
  String? value(String name) => _store[name.toLowerCase()]?.first;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _store[name.toLowerCase()] = <String>['$value'];

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      _store.putIfAbsent(name.toLowerCase(), () => <String>[]).add('$value');

  @override
  void removeAll(String name) => _store.remove(name.toLowerCase());

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      _store.forEach(action);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

```
