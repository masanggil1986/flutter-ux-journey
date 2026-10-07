# Network stub — getting past a gate without credentials

Copy `net_stub.dart` below into the audited app's `ux_audit/` — beside the walker, and inside the
path SKILL.md tells them to gitignore, because this is the one generated file that holds their real
endpoints and real response bodies. Fill in `_routes`, and set
`HttpOverrides.global = StubHttpOverrides();` **before `app.main()`** in the entry that actually
runs:

- `flutter test` (the default): the walker's `main()`.
- `flutter drive` (the fallback): the drive entry, `integration_test/ux_journey_drive.dart`. The
  walker's `main()` never runs there. Make **both** edits: replace its
  `HttpOverrides.global = NetworkCut(calls);` line with the stub, **and** change
  `networkCalls: calls` to `networkCalls: stubCalls`. With only the first edit the gate opens but
  `networkCalls` ships `[]`. `integration_test/gated_journey_test.dart` is the worked example.

The mechanism is generic; only `_routes` is app-specific. The app is not modified.

**What it covers is narrower than "the network".** `HttpOverrides` replaces the `dart:io`
`HttpClient` that is built in the walk's isolate after the override went in. Dio, `package:http`'s
`IOClient` and `NetworkImage` all sit on that client, so their requests are stubbed. That is the
whole boundary. Anything else is neither stubbed nor cut, and it can reach the app's real backend:
WebSockets under `flutter test`, raw sockets, other isolates, native HTTP clients and native SDKs.
See [What the stub cannot see](#what-the-stub-cannot-see) before you tell anyone a run is offline.

**Before `app.main()`** is load-bearing, not tidiness. An app that probes a session on its first
frame has already made that call by the time a later override lands. This is precisely why
`walkJourney` takes `launch` as a callback instead of launching the app itself: handing it
`app.main` is the only way a caller gets in front of the first frame.

## Routing: a path substring, nothing else

A route matches when its `match` string appears anywhere in the request PATH. The first match wins,
so order matters: `'/session'` also matches `'/session/refresh'`, so put the longer path first.
The method, the query and the body are ignored. A single-endpoint GraphQL or JSON-RPC app therefore
gets one answer for every operation, and this template cannot stub it per operation.

## The worked instance

`example/ux_demo_app/integration_test/gate_stub.dart` IS this template with `_routes` filled in and
nothing else touched — from the line `/// Anything not in [_routes] gets this.` to the end, the two
are byte-identical, and `test/recipe_sync_test.dart` holds them that way. So the template compiles,
and it has been run: against the fixture's gated entrypoint on an iPhone SE (3rd gen) simulator it
reports `networkCalls: ["/session", "/auth/login"]`, all three `## Setup` steps OK, and the same
three screen signatures as the ungated run of the same three journey steps.

`test/gated_gate_test.dart` walks the same gate headless, through the real `walkJourney`, twice:
once through the stub ("a walk through the gate sets up, then walks the journey") and once with a
route table that refuses the sign-in ("a walk the gate stops reports the gate, and no journey":
`setupFailed: true`, no journey steps, and `setup_3.png` as the only screenshot).

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

## Network images are a walk artifact — do not score them

The stub answers an image URL with JSON, so the image fails to decode:
`Exception: Invalid image data`. With no stub, `flutter test` answers 400 and the image fails with
`HTTP request failed, statusCode: 400, <url>`. Both measured. In a debug build Flutter paints that
text in its red image-error box, so it shows up in the screenshot and in the semantics dump, and in
`appErrors` unless the app passes an `errorBuilder`. A real user never sees either string, so it is
not a "leaking internals" finding. Under the stub, the image's path does show up in `networkCalls`.

## What the stub cannot see

Everything below bypasses `HttpOverrides`: the stub does not answer it, flutter_test's 400 does not
refuse it, and the drive entry's `NetworkCut` does not cut it. It can reach the real backend from
the host (under `flutter test`) or from the simulator, which shares the host's network.

Measured, each reaching a listener on the host while `networkCalls` stayed `[]`:

- **WebSocket under `flutter test`.** `dart:io` shares one `HttpClient` across every WebSocket, and
  the test bootstrap builds it before any override exists. Under `flutter drive` that client is
  built later, through the override, and `NetworkCut` refused it on the simulator.
- **Raw `Socket`** — gRPC, MQTT and similar protocols. `SecureSocket` has no override hook either.
- **Other isolates** — `Isolate.run`, `compute`. `HttpOverrides` is per isolate.
- **`cupertino_http`** — an FFI client. Its README selects it with
  `Platform.isIOS || Platform.isMacOS`, which is true under `flutter test` on a Mac, so it sends from
  the host.

Outside by construction, not measured: `cronet_http`, `native_dio_adapter`, and native plugin SDKs
(Firebase Auth and the like) and webviews. On a device or simulator they use the platform's own
network stack. Under `flutter test` they usually have no native side and fail with a
`MissingPluginException` instead of sending anything.

Two more ways round it: an `HttpClient` the app built before the override went in, and, under
drive only, a client the app gives its own `connectionFactory`, which replaces the one
`NetworkCut` sets.

**Before you promise anyone an offline or stubbed run**, search `pubspec.yaml` and `lib/` for
`web_socket_channel`, `WebSocket.connect`, `grpc`, `mqtt`, `socket_io`, `Socket.connect`,
`SecureSocket`, `Isolate.run`, `compute(`, `cupertino_http`, `cronet_http`,
`native_dio_adapter`, `firebase_` and `webview`. If any of them is on the journey's path, say so
before the walk: that traffic is not cut and may reach the real backend. The only posture that cuts
it is a `flutter drive` run on an Android emulator in airplane mode (below).

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

`networkCalls` is the evidence in every mode, provided it is wired. The stub records what it
answered. The drive entry's `NetworkCut` records what it refused. flutter_test's own 400 records
nothing. If a stub was installed in a `main()` that never ran, for example the walker's under
`flutter drive`, `networkCalls` still lists the expected paths, because `NetworkCut` refused them.
The tell is a red setup step, not an empty list.

On an **Android emulator under `flutter drive`**, go further and run the walk offline. If a response
arrives at all, the stub is intercepting, because a real request could not have succeeded. This is
also the only posture that cuts the traffic `HttpOverrides` cannot see. The iOS simulator shares the
host's network and has no equivalent.

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
// account. `HttpOverrides.global` replaces the `dart:io` HttpClient built in
// this isolate, which is what Dio, package:http and NetworkImage sit on — so
// the app is not modified. WebSockets, raw sockets, other isolates and native
// clients go round it: see "What the stub cannot see" in network-stub.md.
//
// If a shape here is wrong, the journey step that depends on it FAILS and says
// so. That is the point: the oracle still holds. Never reach for a real
// account to turn a red step green.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// path substring -> (status, json body). First match wins, so order matters:
/// '/session' also matches '/session/refresh', so put the longer path first.
/// Only the path is matched — method, query and body are not.
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

  // Every other way to open a request lands on openUrl. Left to noSuchMethod
  // they answer null, and the caller reports a TypeError the app does not
  // have — NetworkImage asks for getUrl, so every image past the gate did.
  // resolve(), not `path:`, so a query stays a query, as in dart:io.
  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => openUrl(
    method,
    Uri(scheme: 'http', host: host, port: port).resolve(path),
  );
  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      open('GET', host, port, path);
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      open('POST', host, port, path);
  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      open('PUT', host, port, path);
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      open('DELETE', host, port, path);
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      open('PATCH', host, port, path);
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      open('HEAD', host, port, path);
  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);
  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);

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
  // Mutable: a cookie jar adds to it before sending.
  @override
  final List<Cookie> cookies = <Cookie>[];

  @override
  void add(List<int> data) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<void> flush() async {}

  // One answer per request, however often it is asked for: a client that
  // awaits both close() and done would otherwise be recorded twice.
  @override
  late final Future<HttpClientResponse> done = _answer();

  @override
  Future<HttpClientResponse> close() => done;

  Future<HttpClientResponse> _answer() async {
    final ({int status, Object body}) r = _resolve(uri);
    return _StubResponse(r.status, utf8.encode(jsonEncode(r.body)));
  }

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
  List<Cookie> get cookies => const <Cookie>[];
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
