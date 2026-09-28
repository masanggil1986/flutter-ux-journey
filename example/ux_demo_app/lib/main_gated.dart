// The same fixture, behind a sign-in gate. A second entrypoint, not a second
// app: past the gate this hands over to `ListScreen` from main.dart, so the six
// seeded defects and the golden that pins them are untouched.
//
// It exists because `## Setup`, `HttpOverrides` and `networkCalls` were
// documented but never publicly exercised — the ungated fixture has no HTTP
// layer at all, so the one mechanism that gets an audit past a real app's front
// door was only ever verified in private. This file is the public reproduction.
//
// Two ways to run it, and both are the point:
//
//   flutter run -t lib/main_gated.dart          # no stub: the call fails, and
//                                               # the screen shows what a user
//                                               # sees when it does. That is
//                                               # the default audit mode —
//                                               # offline, arbitrary data,
//                                               # the failure path nobody tests.
//   flutter drive --target=integration_test/gated_journey_test.dart
//                                               # with the stub installed, the
//                                               # gate opens and the journey
//                                               # past it gets measured.
//
// Several classes in one file, matching main.dart: the fixture is meant to read
// as one artifact per app, and the audit's own generated walker has the same
// one-file constraint.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'main.dart' show ListScreen;

void main() => runApp(const GatedDemoApp());

/// The host is `*.example.invalid`, which RFC 2606 guarantees can never
/// resolve. With no stub installed the app gets a DNS failure, never somebody
/// else's server — an audit tool must not be able to reach production by
/// accident.
const String _baseUrl = 'https://api.example.invalid';

class GatedDemoApp extends StatelessWidget {
  const GatedDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'UX Demo (gated)',
    theme: ThemeData(scaffoldBackgroundColor: Colors.white),
    home: const SignInScreen(),
  );
}

/// The gate. Deliberately *clean* — labelled fields, 48 lpx targets, readable
/// contrast — because its job is to exercise the Setup phase, not to add a
/// seventh seeded defect to a fixture whose six are pinned by a golden.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final GateClient _gate = GateClient();
  bool _checking = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The session probe fires on the first frame. It is why the walker has to
    // install HttpOverrides BEFORE app.main() rather than after: by the time
    // the first step runs, this request has already gone out.
    _probe();
  }

  Future<void> _probe() async {
    final bool signedIn = await _gate.hasSession();
    if (!mounted) {
      return;
    }
    if (signedIn) {
      _enter();
      return;
    }
    setState(() => _checking = false);
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final bool ok = await _gate.signIn(_email.text, _password.text);
    if (!mounted) {
      return;
    }
    if (ok) {
      _enter();
      return;
    }
    setState(() {
      _busy = false;
      // Names the cause and the recovery, so ERROR-VAGUE does not fire here.
      // The interesting audit question is upstream of the wording: whether the
      // user can tell a wrong password from a dead network at all.
      _error = 'We could not sign you in. Check the address, then try again.';
    });
  }

  void _enter() => Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(builder: (_) => const ListScreen()),
  );

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            // A label, so the walk's dump can tell "still probing" from "blank
            // screen" without a screenshot.
            semanticsLabel: 'Checking your session',
          ),
        ),
      );
    }
    return Scaffold(
      // NOT 'Sign in'. The first run of this fixture titled it that, and the
      // walk refused the whole setup phase: `ambiguous: 2 nodes match "Sign in"
      // — 1=Sign in @343x48, 2=Sign in @62x28`. The title and the button were
      // the same string, the selector would have had to guess which one a
      // journey meant, and it declined to. Left as a comment rather than
      // deleted, because a real app hits this constantly and the fix is a
      // journey's `nth:` — not a cleverer matcher.
      appBar: AppBar(title: const Text('Welcome back')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email address',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              // This is what made the walker redact: `obscureText` keeps the
              // value out of the SEMANTICS tree, but the walk records a `type`
              // step's text from the journey file, so the first gated run wrote
              // `not-a-real-password` into example/walk-gated.json anyway. The
              // walker now asks this widget and redacts — see `_recordedText`.
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _busy ? null : _signIn,
                child: Text(_busy ? 'Signing in…' : 'Sign in'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `dart:io` `HttpClient` on purpose: that is the layer `HttpOverrides`
/// intercepts, and it is what Dio and `package:http` sit on — so a stub written
/// for this fixture is written for a real app too. No package added.
class GateClient {
  final HttpClient _client = HttpClient();

  /// True only when the response actually carries a user. A stub's permissive
  /// `200 + {}` fallback must NOT read as a live session, or the gate is
  /// skipped and every Setup step fails looking for a field nobody built.
  Future<bool> hasSession() async {
    final Map<String, Object?>? body = await _json('GET', '/session');
    return body?['user'] is Map;
  }

  Future<bool> signIn(String email, String password) async {
    final Map<String, Object?>? body = await _json(
      'POST',
      '/auth/login',
      payload: <String, Object?>{'email': email, 'password': password},
    );
    return body?['accessToken'] is String;
  }

  /// Returns null on any failure — a non-2xx status, unparseable JSON, or no
  /// network at all. The caller turns that into something the user can read,
  /// which is the whole path an offline audit is there to measure.
  Future<Map<String, Object?>?> _json(
    String method,
    String path, {
    Map<String, Object?>? payload,
  }) async {
    try {
      final HttpClientRequest req = await _client.openUrl(
        method,
        Uri.parse('$_baseUrl$path'),
      );
      if (payload != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(payload));
      }
      final HttpClientResponse res = await req.close();
      final String raw = await res.transform(utf8.decoder).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return null;
      }
      final Object? decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } on Object {
      // Every failure mode collapses to the same user-visible outcome, so the
      // audit sees one error state rather than a stack trace.
      return null;
    }
  }
}
