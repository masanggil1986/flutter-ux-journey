// The fixture's worked instance of references/network-stub.md.
//
// Only `_routes` below is app-specific; everything from the fallback consts
// down is the template, byte for byte — test/recipe_sync_test.dart asserts
// that, so the template in the docs cannot rot into something that does not
// compile.
//
// The endpoints are `*.example.invalid`, which by RFC 2606 can never resolve.
// Run this walk and no request can reach a real host even if the override
// were removed: the app would get a DNS failure, not somebody's server.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// path suffix -> (status, json body). First match wins, so order matters.
typedef StubRoute = ({String match, int status, Object body});

const List<StubRoute> _routes = <StubRoute>[
  // The session probe must answer 401 EXPLICITLY. Letting it fall through to
  // the permissive 200 + {} below tells the app it is already signed in, the
  // gate never renders, and every Setup step then fails looking for a field
  // that was never built — one wasted run, and the error blames the journey
  // rather than the route table.
  (
    match: '/session',
    status: 401,
    body: <String, Object?>{'error': 'no session'},
  ),
  // The gate itself. The token is a literal string, not a credential: nothing
  // here authenticates against anything.
  (
    match: '/auth/login',
    status: 200,
    body: <String, Object?>{
      'accessToken': 'stub-token-not-a-secret',
      'user': <String, Object?>{'email': 'ux-audit@example.invalid'},
    },
  ),
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
