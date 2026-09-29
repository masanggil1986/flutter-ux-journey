// Route inventory — what the app says its feature surface is.
//
// Kept in its own file because it answers a different question from
// probe_test.dart: that one asks "is this control labelled", this one asks
// "which screens exist and what reaches them". Both parse the same unresolved
// AST and share the same trap, which is why the MethodInvocation regression is
// written out again here rather than assumed.

import 'dart:io';

import 'package:test/test.dart';

import '../bin/probe.dart';

List<Map<String, Object?>> ofKind(
  String source,
  String kind, {
  Map<String, String> constants = const <String, String>{},
}) => scanRoutes(
  source,
  constants: constants,
).where((Map<String, Object?> r) => r['kind'] == kind).toList();

void main() {
  group('inline Navigator pushes', () {
    test('a pushed MaterialPageRoute names the screen it builds', () {
      final edges = ofKind('''
        class _ListScreenState extends State<ListScreen> {
          Widget build(BuildContext context) => InkWell(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => DetailScreen(p))),
          );
        }
      ''', 'inline-push');
      expect(edges, hasLength(1));
      expect(edges.single['to'], 'DetailScreen');
      // The enclosing declaration, raw. Stripping `_`/`State` to make it pretty
      // would be a guess about naming convention, and this tool does not guess.
      expect(edges.single['from'], '_ListScreenState');
      expect(edges.single['method'], 'push');
    });

    test('every push method the fixture actually uses is counted', () {
      // pushAndRemoveUntil is how the fixture reaches its dead end and
      // pushReplacement is how the gated fixture leaves its gate. A matcher
      // that knows only `push` misses both.
      for (final String method in <String>[
        'push',
        'pushReplacement',
        'pushAndRemoveUntil',
      ]) {
        final edges = ofKind('''
          class HomePage extends StatelessWidget {
            void go() => Navigator.of(context).$method(
              MaterialPageRoute<void>(builder: (_) => const RemovedScreen()),
              (Route<void> route) => false,
            );
          }
        ''', 'inline-push');
        expect(edges, hasLength(1), reason: '$method produced no edge');
        expect(edges.single['to'], 'RemovedScreen');
      }
    });

    test('a builder with a block body still names its screen', () {
      final edges = ofKind('''
        class HomePage extends StatelessWidget {
          void go() => Navigator.push(context, CupertinoPageRoute<void>(
            builder: (BuildContext c) { return SettingsScreen(); },
          ));
        }
      ''', 'inline-push');
      expect(edges.single['to'], 'SettingsScreen');
    });

    test('an unreadable builder is declared, not guessed', () {
      final routes = scanRoutes('''
        class HomePage extends StatelessWidget {
          void go() => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: screenFactory),
          );
        }
      ''');
      expect(
        routes.where((Map<String, Object?> r) => r['kind'] == 'inline-push'),
        isEmpty,
      );
      expect(
        routes.where((Map<String, Object?> r) => r['kind'] == 'not-assessable'),
        hasLength(1),
      );
    });
  });

  group('GoRouter', () {
    // THE REGRESSION THAT MATTERS, again. Flutter code is written without
    // `const`, so `GoRoute(...)` parses as a MethodInvocation on the unresolved
    // AST. Visit only instance creations and a GoRouter app reports zero routes
    // while looking perfectly healthy — measured once already, at 1083 files.
    test('a GoRoute declares its path, name and screen (MethodInvocation)', () {
      final declared = ofKind('''
        final router = GoRouter(routes: [
          GoRoute(path: '/detail', name: 'detail',
                  builder: (c, s) => DetailScreen()),
        ]);
      ''', 'go-route');
      expect(declared, hasLength(1));
      expect(declared.single['path'], '/detail');
      expect(declared.single['name'], 'detail');
      expect(declared.single['screen'], 'DetailScreen');
    });

    test('a const GoRoute declares the same (InstanceCreationExpression)', () {
      final declared = ofKind(
        "final r = const GoRoute(path: '/a', builder: b);",
        'go-route',
      );
      expect(declared.single['path'], '/a');
    });

    test('a literal navigation target is an edge', () {
      final edges = ofKind('''
        class HomePage extends StatelessWidget {
          void open() => context.go('/detail');
          void named() => context.pushNamed('settings');
        }
      ''', 'go-nav');
      expect(
        edges.map((Map<String, Object?> e) => e['target']),
        containsAll(<String>['/detail', 'settings']),
      );
      expect(edges.first['from'], 'HomePage');
    });

    test('a non-literal navigation target is declared, never guessed', () {
      // Interpolation and constants are where a route graph starts inventing
      // edges. The honest answer is that these cannot be read from source.
      final routes = scanRoutes(r'''
        class HomePage extends StatelessWidget {
          void open(String id) => context.go('/detail/$id');
          void other() => context.go(Routes.settings);
        }
      ''');
      expect(
        routes.where((Map<String, Object?> r) => r['kind'] == 'go-nav'),
        isEmpty,
      );
      expect(
        routes.where((Map<String, Object?> r) => r['kind'] == 'not-assessable'),
        hasLength(2),
      );
    });
  });

  // Found by trying to break it, which is the only way these surface: each one
  // prints something that is not true rather than failing.
  group('adversarial — output that would lie', () {
    test(
      'a named-route table is declared unread, not reported as no routes',
      () {
        // MaterialApp(routes: {...}) is a whole feature surface. Saying nothing
        // about it makes `declared: []` read as "this app has no routes", which
        // is the worst thing this block could claim.
        final routes = scanRoutes('''
        Widget b(c) => MaterialApp(routes: {
          '/': (c) => Home(),
          '/settings': (c) => Settings(),
        });
      ''');
        final na = routes
            .where((Map<String, Object?> r) => r['kind'] == 'not-assessable')
            .toList();
        expect(na, hasLength(1));
        expect(na.single['reason'], contains('routes:'));
      },
    );

    test('Navigator.pushNamed is read at its own signature', () {
      // Navigator.pushNamed(context, '/x') puts the route SECOND. Reading it
      // like GoRouter's context.pushNamed('/x') reports the route as
      // unreadable and names `context` as the target — a wrong reason attached
      // to a missed edge.
      final edges = ofKind(
        "class A { void f() => Navigator.pushNamed(context, '/settings'); }",
        'go-nav',
      );
      expect(edges, hasLength(1));
      expect(edges.single['target'], '/settings');
    });

    test('a nested GoRoute reports the path a user would actually type', () {
      // A child route's `path` is a SEGMENT. Printing it alone puts `b` in a
      // route table where the app answers to `/a/b`.
      final declared = ofKind('''
        final r = GoRouter(routes: [
          GoRoute(path: '/a', builder: (c, s) => A(), routes: [
            GoRoute(path: 'b', builder: (c, s) => B()),
          ]),
        ]);
      ''', 'go-route');
      expect(
        declared.map((Map<String, Object?> r) => r['path']),
        containsAll(<String>['/a', '/a/b']),
      );
    });

    test('the named-navigation verbs that are not just pushNamed', () {
      // Missing one of these is a hole in the map with nothing saying so —
      // quieter than a wrong edge, and harder to notice.
      for (final String method in <String>[
        'pushNamed',
        'popAndPushNamed',
        'pushNamedAndRemoveUntil',
      ]) {
        expect(
          ofKind(
            "class A { void f() => Navigator.$method(context, '/x'); }",
            'go-nav',
          ),
          hasLength(1),
          reason: '$method produced no edge',
        );
      }
    });

    test(
      'a GoRoute whose path is a constant is declared unread, not dropped',
      () {
        // Measured on a real app: 56 GoRoute declarations, every single `path:`
        // a constant reference, and the probe reported 12 routes. Forty-four
        // declared screens vanished with nothing saying so — the same silence
        // the named-route table used to produce, in the shape SKILL.md itself
        // describes as the usual GoRouter app.
        final routes = scanRoutes('''
        final r = GoRouter(routes: [
          GoRoute(path: Routes.home, builder: (c, s) => HomeScreen()),
        ]);
      ''');
        expect(
          routes.where((Map<String, Object?> r) => r['kind'] == 'go-route'),
          isEmpty,
        );
        final na = routes
            .where((Map<String, Object?> r) => r['kind'] == 'not-assessable')
            .toList();
        expect(na, hasLength(1));
        expect(na.single['reason'], contains('GoRoute'));
      },
    );

    test('context.push is GoRouter navigation, not a Navigator push', () {
      // `push` belongs to both APIs. Matching the Navigator shape first and
      // returning when no PageRoute turns up swallowed 67 calls on a real app
      // — no edge, and no line saying one was missed.
      final edges = ofKind(
        "class A { void f() => context.push('/detail'); }",
        'go-nav',
      );
      expect(edges, hasLength(1));
      expect(edges.single['target'], '/detail');
    });

    test('a context.push with an unreadable target still says so', () {
      final routes = scanRoutes(
        'class A { void f() => context.push(Routes.detail); }',
      );
      expect(
        routes.where((Map<String, Object?> r) => r['kind'] == 'go-nav'),
        isEmpty,
      );
      expect(
        routes.where((Map<String, Object?> r) => r['kind'] == 'not-assessable'),
        hasLength(1),
      );
    });

    test('an unrelated call is not navigation at all', () {
      // Nothing here shares a name with a navigation verb. (`items.push(x)`
      // would, but Dart's List has no `push` — it is `add` — so the only
      // things called `push` in a Flutter app are Navigator's and GoRouter's,
      // which is why an unreadable `push` is reported rather than dropped.)
      expect(scanRoutes('void f() { items.add(x); }'), isEmpty);
      expect(
        scanRoutes('void f() => showDialog(context: c, builder: (_) => D());'),
        isEmpty,
      );
    });

    test('an unreadable push is reported, never silently dropped', () {
      final routes = scanRoutes('class A { void f() => context.push(dest); }');
      expect(
        routes.where((Map<String, Object?> r) => r['kind'] == 'go-nav'),
        isEmpty,
      );
      expect(
        routes.where((Map<String, Object?> r) => r['kind'] == 'not-assessable'),
        hasLength(1),
      );
    });
  });

  group('what cannot be read from source', () {
    test('onGenerateRoute is recorded, not silently absent', () {
      final routes = scanRoutes('''
        Widget build(c) => MaterialApp(
          onGenerateRoute: (RouteSettings s) =>
              MaterialPageRoute(builder: (_) => X()),
        );
      ''');
      final na = routes
          .where((Map<String, Object?> r) => r['kind'] == 'not-assessable')
          .toList();
      expect(na, isNotEmpty);
      expect(
        na.map((Map<String, Object?> r) => r['reason']).join(),
        contains('onGenerateRoute'),
      );
    });

    test('a file with no navigation yields nothing rather than throwing', () {
      expect(scanRoutes("Widget w = Text('hi');"), isEmpty);
      expect(scanRoutes('this is not dart {{{'), isEmpty);
    });

    test('every route entry carries a location', () {
      final Map<String, Object?> r = scanRoutes(
        "class A { void f() => context.go('/x'); }",
        path: 'lib/a.dart',
      ).single;
      expect(r['file'], 'lib/a.dart');
      expect(r['line'], 1);
    });
  });

  // Measured on a real GoRouter app: 44 of 44 route declarations and 72 of 72
  // navigation targets are constant references, and every one of those
  // constants is a string literal in the same package. Without resolving them
  // the probe produced 170 "cannot read this" lines against 17 it could — a
  // wall of honest noise, which is the shape the tool this replaced died of.
  group('route constants', () {
    test('a class constant is collected under Owner.field', () {
      final consts = collectRouteConstants('''
        class Routes {
          static const login = '/login';
          static const String home = '/';
        }
      ''');
      expect(consts['Routes.login'], '/login');
      expect(consts['Routes.home'], '/');
    });

    test('a top-level constant is collected under its bare name', () {
      expect(
        collectRouteConstants(
          "const String settings = '/settings';",
        )['settings'],
        '/settings',
      );
    });

    test('a computed constant is not collected', () {
      final consts = collectRouteConstants(r'''
        class Routes {
          static const detail = '$base/detail';
          static const other = base + '/x';
        }
      ''');
      expect(consts, isEmpty);
    });

    test('a name declared twice with different values is dropped', () {
      // Picking one silently would put a path in the graph that half the app
      // does not use.
      final consts = collectRouteConstants('''
        const a = '/one';
        const a = '/two';
        const b = '/same';
        const b = '/same';
      ''');
      expect(consts.containsKey('a'), isFalse);
      expect(consts['b'], '/same');
    });

    test('a GoRoute path given as a constant resolves, and says how', () {
      final declared = ofKind(
        "final r = GoRoute(path: Routes.login, builder: (c, s) => L());",
        'go-route',
        constants: const <String, String>{'Routes.login': '/login'},
      );
      expect(declared, hasLength(1));
      expect(declared.single['path'], '/login');
      // Provenance, so a reader can check the resolution rather than trust it.
      expect(declared.single['via'], 'Routes.login');
    });

    test('a navigation target given as a constant resolves', () {
      final edges = ofKind(
        "class A { void f() => context.push(Routes.detail); }",
        'go-nav',
        constants: const <String, String>{'Routes.detail': '/detail'},
      );
      expect(edges.single['target'], '/detail');
      expect(edges.single['via'], 'Routes.detail');
    });

    test('a constant nobody declared is still not assessable', () {
      final routes = scanRoutes(
        "class A { void f() => context.go(Unknown.thing); }",
        constants: const <String, String>{'Routes.detail': '/detail'},
      );
      expect(
        routes.where((Map<String, Object?> r) => r['kind'] == 'go-nav'),
        isEmpty,
      );
      expect(
        routes.where((Map<String, Object?> r) => r['kind'] == 'not-assessable'),
        hasLength(1),
      );
    });
  });

  // The bar this repo sets: a rule earns its place by firing on real code. The
  // tool this replaced shipped a tap-target rule that matched nothing across
  // 1083 files. If the demo app's screens stop coming out of this, the
  // extractor is decoration.
  test('the demo app yields the screens its journey walks', () {
    final Directory lib = Directory('../../example/ux_demo_app/lib');
    if (!lib.existsSync()) {
      markTestSkipped('${lib.path} not present — running outside the repo');
      return;
    }
    final Set<String> targets = <String>{};
    for (final File f in lib.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) {
        continue;
      }
      for (final Map<String, Object?> r in scanRoutes(
        f.readAsStringSync(),
        path: f.path,
      )) {
        if (r['kind'] == 'inline-push') {
          targets.add(r['to']! as String);
        }
      }
    }
    expect(
      targets,
      containsAll(<String>['DetailScreen', 'RemovedScreen', 'ListScreen']),
    );
  });
}
