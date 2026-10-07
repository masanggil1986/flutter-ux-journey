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

    test('a PageRouteBuilder names the screen its pageBuilder makes', () {
      // PageRouteBuilder has no `builder:`. Reading only that one reported
      // every custom-transition push as "not a closure over a constructor",
      // which is false about the code.
      final edges = ofKind('''
        class HomePage extends StatelessWidget {
          void a() => Navigator.of(context).push(PageRouteBuilder(
            pageBuilder: (c, a1, a2) => const DetailScreen(),
            transitionsBuilder: fade,
          ));
          void b() => Navigator.push(context, new PageRouteBuilder<void>(
            pageBuilder: (c, a1, a2) => SettingsScreen(),
          ));
        }
      ''', 'inline-push');
      expect(edges.map((Map<String, Object?> e) => e['to']), <String>[
        'DetailScreen',
        'SettingsScreen',
      ]);
    });

    test('a screen reached through a dotted name is named in full', () {
      // One guessed segment gave `create`, `forUser`, `value`, `screens` —
      // not widgets at all. The dotted source is what the code says.
      final edges = ofKind('''
        class HomePage extends StatelessWidget {
          void a() => push(MaterialPageRoute(builder: (_) => EditScreen.create()));
          void b() => push(MaterialPageRoute(builder: (_) => const EditScreen.create()));
          void c() => push(MaterialPageRoute(builder: (_) => const screens.DetailScreen()));
          void d() => push(MaterialPageRoute(builder: (_) => screens.ProfileScreen.forUser(u)));
          void e() => push(MaterialPageRoute(builder: (_) =>
              BlocProvider.value(value: bloc, child: OrdersScreen())));
          void f() => push(MaterialPageRoute(builder: (_) => DetailScreen<Item>(p)));
        }
      ''', 'inline-push');
      expect(edges.map((Map<String, Object?> e) => e['to']), <String>[
        'EditScreen.create',
        'EditScreen.create',
        'screens.DetailScreen',
        'screens.ProfileScreen.forUser',
        'BlocProvider.value',
        'DetailScreen',
      ]);
    });

    test('a builder that returns one of two screens is not half-read', () {
      // Reading the first `return` named AccountScreen and dropped the login
      // screen the same push can reach.
      final routes = scanRoutes('''
        class HomePage extends StatelessWidget {
          void a() => push(MaterialPageRoute(builder: (_) {
            if (!loggedIn) {
              return LoginScreen();
            }
            return AccountScreen();
          }));
          void b() => push(MaterialPageRoute(
              builder: (_) => loggedIn ? AccountScreen() : LoginScreen()));
          void c() => push(MaterialPageRoute(builder: (_) {
            final Widget Function() make = () { return Spare(); };
            return AccountScreen();
          }));
        }
      ''');
      expect(routes.map((Map<String, Object?> r) => r['kind']), <String>[
        'not-assessable',
        'not-assessable',
        'inline-push',
      ]);
      // A closure's own return is not the builder's.
      expect(routes.last['to'], 'AccountScreen');
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

    test('a pageBuilder route names the screen, not the transition', () {
      // A pageBuilder returns a Page by type, so its outermost call is always
      // a transition wrapper. The screen is the Page's `child:`.
      final declared = ofKind('''
        final r = GoRouter(routes: [
          GoRoute(path: '/home', pageBuilder: (c, s) =>
              NoTransitionPage(child: HomeScreen())),
          GoRoute(path: '/fade', pageBuilder: (c, s) =>
              const CustomTransitionPage<void>(child: FadeScreen(), transitionsBuilder: t)),
          GoRoute(path: '/login', pageBuilder: (c, s) {
            return const MaterialPage<void>(child: LoginPage());
          }),
          GoRoute(path: '/made', pageBuilder: (c, s) => makePage(c, s)),
        ]);
      ''', 'go-route');
      expect(declared.map((Map<String, Object?> r) => r['screen']), <String?>[
        'HomeScreen',
        'FadeScreen',
        'LoginPage',
        null,
      ]);
    });

    test('a literal navigation target is an edge', () {
      final edges = ofKind('''
        class HomePage extends StatelessWidget {
          void open() => context.go('/detail');
          void named() => context.pushNamed('settings');
          void byName() => context.goNamed('cart');
          void swap() => context.replace('/swapped');
        }
      ''', 'go-nav');
      expect(edges.map((Map<String, Object?> e) => e['target']), <String>[
        '/detail',
        'settings',
        'cart',
        '/swapped',
      ]);
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

    test('a child of a parent whose path cannot be read is not given one', () {
      // Skipping the unreadable parent printed `/reviews` — a well-formed path
      // the app does not answer to, in the table as an ordinary row.
      final routes = scanRoutes(r'''
        final r = GoRouter(routes: [
          GoRoute(path: '/', builder: (c, s) => Home(), routes: [
            GoRoute(path: AppRoute.shop.path, builder: (c, s) => Shop(), routes: [
              GoRoute(path: 'reviews', builder: (c, s) => ReviewsScreen()),
            ]),
          ]),
          GoRoute(path: '/shop', builder: (c, s) => Shop(), routes: [
            GoRoute(path: '$category', builder: (c, s) => C(), routes: [
              GoRoute(path: 'item', builder: (c, s) => Item()),
            ]),
          ]),
        ]);
        // A child list declared apart from its parent: no parent in sight.
        final settingsRoutes = [
          GoRoute(path: 'notifications', builder: (c, s) => N()),
        ];
      ''');
      expect(
        routes
            .where((Map<String, Object?> r) => r['kind'] == 'go-route')
            .map((Map<String, Object?> r) => r['path']),
        <String>['/', '/shop'],
      );
      final List<String> reasons = routes
          .where((Map<String, Object?> r) => r['kind'] == 'not-assessable')
          .map((Map<String, Object?> r) => r['reason']! as String)
          .toList();
      expect(reasons, hasLength(5));
      for (final String segment in <String>[
        'reviews',
        'item',
        'notifications',
      ]) {
        expect(
          reasons.where((String r) => r.contains('`$segment`')),
          hasLength(1),
        );
      }
    });

    test('a readable parent still prefixes its child', () {
      final declared = ofKind(
        '''
        final r = GoRouter(routes: [
          GoRoute(path: Routes.shop, builder: (c, s) => Shop(), routes: [
            GoRoute(path: 'reviews', builder: (c, s) => ReviewsScreen()),
          ]),
          ShellRoute(builder: (c, s, child) => Shell(child: child), routes: [
            GoRoute(path: '/a', builder: (c, s) => A(), routes: [
              GoRoute(path: 'b', builder: (c, s) => B()),
            ]),
          ]),
        ]);
      ''',
        'go-route',
        constants: const <String, String>{'Routes.shop': '/shop'},
      );
      expect(declared.map((Map<String, Object?> r) => r['path']), <String>[
        '/shop',
        '/shop/reviews',
        '/a',
        '/a/b',
      ]);
    });

    test('a router this probe does not read is named, not silent', () {
      // Empty `declared` plus empty `notAssessable` reads as "this app has no
      // declarative router". For a GetX or auto_route app that is false, and
      // the coverage line built on it is the most misleading thing the
      // report can say.
      for (final String source in <String>[
        "Widget b(c) => GetMaterialApp(getPages: [GetPage(name: '/', page: () => Home())]);",
        'Widget b(c) => GetMaterialApp.router(routeInformationParser: p);',
        'Widget b(c) => GetCupertinoApp(home: Home());',
        '@AutoRouterConfig()\nclass AppRouter extends RootStackRouter {}',
        // auto_route 5 and older
        '@MaterialAutoRouter(routes: <AutoRoute>[])\nclass AppRouterBase {}',
        "@TypedGoRoute<HomeRoute>(path: '/', routes: [TypedGoRoute<CartRoute>(path: 'cart')])\n"
            'class HomeRoute extends GoRouteData {}',
        '@TypedShellRoute<S>(routes: [])\nclass S extends ShellRouteData {}',
        '@TypedStatefulShellRoute<S>(branches: [])\nclass S {}',
      ]) {
        final routes = scanRoutes(source);
        expect(routes, hasLength(1), reason: source);
        expect(routes.single['kind'], 'not-assessable', reason: source);
        expect(routes.single['reason'], contains('not read'), reason: source);
      }
      // GetX for state alone routes nothing.
      expect(scanRoutes('final c = Get.put(CartController());'), isEmpty);
    });

    test('the navigation verbs that never name a route still say so', () {
      List<String> kinds(String body) => scanRoutes(
        'class A { void f() => $body; }',
      ).map((Map<String, Object?> r) => r['kind']! as String).toList();

      // goBranch takes an index; the branches themselves are declared.
      final branch = scanRoutes(
        'class A { void f() => shell.goBranch(i, initialLocation: true); }',
      );
      expect(branch.single['kind'], 'not-assessable');
      expect(branch.single['reason'], contains('goBranch'));
      expect(
        ofKind(
          "class A { void f() => Navigator.restorablePushNamed(context, '/settings'); }",
          'go-nav',
        ).single['target'],
        '/settings',
      );
      expect(
        kinds("Navigator.of(context).restorablePushReplacementNamed('/home')"),
        <String>['go-nav'],
      );
      expect(kinds('Navigator.restorablePush(context, _builder)'), <String>[
        'not-assessable',
      ]);
      // Navigator's replace carries its route as `newRoute:`.
      final replaced = ofKind('''
        class A {
          void f() => Navigator.of(context).replace(oldRoute: old,
              newRoute: MaterialPageRoute(builder: (_) => NewScreen()));
          void g() => Navigator.replace(context, oldRoute: old,
              newRoute: MaterialPageRoute(builder: (_) => NewScreen()));
        }
      ''', 'inline-push');
      expect(replaced.map((Map<String, Object?> e) => e['method']), <String>[
        'replace',
        'replace',
      ]);
      // No positional route at all used to return with nothing said.
      expect(
        kinds('Navigator.of(context).replace(oldRoute: o, newRoute: r)'),
        <String>['not-assessable'],
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
      // Dart's own Uri.replace shares a navigation verb's name; it takes
      // only named arguments and none of them is a route.
      expect(
        scanRoutes('Uri f(Uri u) => u.replace(queryParameters: q);'),
        isEmpty,
      );
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

    test('only a name another file can reach is a constant', () {
      // Locals and instance fields were collected and resolved package-wide
      // by bare name: a helper's `String target` parameter became an edge to
      // whatever some other function's local `target` held.
      expect(
        collectRouteConstants('''
          const top = '/top';
          final topFinal = '/top-final';
          var topVar = '/var';
          String topMutable = '/mutable';
          class Routes {
            static const home = '/';
            static final settings = '/settings';
            final instance = '/instance';
            static var mutable = '/m';
            void f() { const local = '/local-in-class'; }
          }
          enum Tab { a; static const path = '/tabs'; }
          mixin M { static const route = '/mixin'; }
          extension E on String { static const location = '/ext'; }
          extension on int { static const hidden = '/unnamed'; }
          extension type ET(String s) { static const where = '/et'; }
          void g() { const lastTab = '/home'; final initialRoute = '/onboarding'; }
        '''),
        <String, String>{
          'top': '/top',
          'topFinal': '/top-final',
          'Routes.home': '/',
          'Routes.settings': '/settings',
          'Tab.path': '/tabs',
          'M.route': '/mixin',
          'E.location': '/ext',
          'ET.where': '/et',
        },
      );
    });

    test('a parameter or local is not the constant it shares a name with', () {
      const Map<String, String> consts = <String, String>{
        'target': '/faq',
        'location': '/debug/log',
        'path': '/onboarding/seed',
        'Prefs.home': '/home',
      };
      final routes = scanRoutes('''
        class _MenuState { void open(String target) => context.go(target); }
        class OrderTile {
          void open(BuildContext context, String location) => context.go(location);
        }
        class Checkout {
          void next() { final String path = computeNext(); context.push(path); }
        }
        class Prefs {
          static const home = '/home';
          void f(String home) => context.go(home);
        }
        class Tile {
          final String target;
          void f() => context.go(target);
        }
      ''', constants: consts);
      expect(
        routes.where((Map<String, Object?> r) => r['kind'] == 'go-nav'),
        isEmpty,
      );
      expect(routes, hasLength(5));
      // Unshadowed, the same bare name still resolves.
      final edge = ofKind(
        'class B { void f() => context.go(target); }',
        'go-nav',
        constants: consts,
      ).single;
      expect(edge['target'], '/faq');
      expect(edge['via'], 'target');
    });

    test("a class's own constants resolve unqualified inside it", () {
      // Dart lets a class use its statics bare, and a router declared beside
      // its constants does. Looking up only the bare name lost every route.
      final source = '''
        class AppRouter {
          static const home = '/';
          static const settings = '/settings';
          static final router = GoRouter(routes: [
            GoRoute(path: home, builder: (c, s) => HomeScreen()),
            GoRoute(path: settings, builder: (c, s) => SettingsScreen()),
          ]);
        }
      ''';
      final declared = ofKind(
        source,
        'go-route',
        constants: collectRouteConstants(source),
      );
      expect(declared.map((Map<String, Object?> r) => r['path']), <String>[
        '/',
        '/settings',
      ]);
      expect(declared.map((Map<String, Object?> r) => r['via']), <String>[
        'AppRouter.home',
        'AppRouter.settings',
      ]);
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
