// STATIC evidence pass — step [1] of the flutter-ux-journey pipeline.
//
// Four rules, on purpose. The tool this replaces shipped 50 rules: 34 of them
// never fired at all, two string-matching rules produced 70% of all output, and
// its tap-target rule matched nothing across 1083 files. Rules only earn a place
// here if they can be decided from source alone.
//
// Deliberately NOT implemented, and not by omission:
//   - contrast and text scaling. Undecidable statically: the colour actually
//     painted depends on ThemeData, inherited widgets and the platform, and the
//     effective text size depends on the device's accessibility settings. This
//     is exactly where the prior tool generated its noise. Step [2] reads the
//     real pixels with textContrastGuideline instead.
//   - tap target SIZE. Unknowable statically — the size comes from layout, not
//     from the constructor call. Step [2] measures it for real on a simulator.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

const _watchedWidgets = {
  'GestureDetector',
  'InkWell',
  'IconButton',
  'Icon',
  'Image',
  'TextField',
};
// Ancestors that already supply (or deliberately suppress) an accessible name.
const _labelWrappers = {
  'Semantics',
  'MergeSemantics',
  'ExcludeSemantics',
  'Tooltip',
};
const _iconOwners = {'IconButton', ..._labelWrappers};

/// Dotted callee source of a widget-shaped call: `IconButton`, `Image.network`,
/// `material.Icon`. Null for anything that is not a call.
String? _calleeOf(AstNode node) => switch (node) {
  InstanceCreationExpression() => node.constructorName.type.toSource(),
  MethodInvocation() =>
    '${node.target?.toSource() ?? ''}.${node.methodName.name}',
  _ => null,
};

/// Unresolved, `new Image.network(...)` parses with the WHOLE `Image.network`
/// as the type — the parser cannot tell a named constructor from a library
/// prefix — so every dotted segment is a candidate widget name.
String? _match(String? callee, Set<String> names) {
  for (final part in callee?.split('.') ?? const <String>[]) {
    if (names.contains(part)) return part;
  }
  return null;
}

/// Findings for one Dart source. [path] is only a label in the output.
List<Map<String, Object?>> scan(String source, {String path = '<memory>'}) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final probe = _Probe(result.lineInfo, path);
  result.unit.visitChildren(probe);
  return probe.findings;
}

/// Route entries for one Dart source. [path] is only a label in the output.
///
/// Three kinds, and the third is the point:
///   `go-route`       a declared GoRoute — path, name, the screen its builder
///                    makes
///   `inline-push`    a Navigator push carrying a MaterialPageRoute or a
///                    CupertinoPageRoute — the shape an app with no declarative
///                    router uses, and the one the public fixture exercises
///   `not-assessable` navigation that exists but cannot be read from source
///
/// Nothing here is inferred. A target that is not a string literal, a builder
/// that is not a closure over a constructor, an `onGenerateRoute` that
/// switches on a runtime string — each of those is recorded as
/// `not-assessable` rather than guessed at, because a route graph that invents
/// one edge is worse than one that admits a hole.
List<Map<String, Object?>> scanRoutes(
  String source, {
  String path = '<memory>',
}) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final probe = _Routes(result.lineInfo, path);
  result.unit.visitChildren(probe);
  return probe.routes;
}

/// `push`, `pushReplacement`, `pushAndRemoveUntil` and friends — every method
/// the fixture and the gated fixture actually use. A matcher that knows only
/// `push` misses the fixture's dead end and the gate it replaces.
const _pushMethods = {
  'push',
  'pushReplacement',
  'pushAndRemoveUntil',
  'pushRoute',
};
const _pageRoutes = {
  'MaterialPageRoute',
  'CupertinoPageRoute',
  'PageRouteBuilder',
};

/// GoRouter's navigation verbs, as called on a BuildContext or a router.
const _goMethods = {
  'go',
  'goNamed',
  'pushNamed',
  'pushReplacementNamed',
  'replace',
  'replaceNamed',
  // Navigator's own named verbs. Leaving them out is a hole in the map with
  // nothing saying so — quieter than a wrong edge, and harder to notice.
  'popAndPushNamed',
  'pushNamedAndRemoveUntil',
};

class _Routes extends RecursiveAstVisitor<void> {
  _Routes(this._lineInfo, this._path);

  final LineInfo _lineInfo;
  final String _path;
  final List<Map<String, Object?>> routes = [];

  // Same trap as _Probe, and worth writing out twice: on an unresolved AST
  // `GoRoute(...)` is a MethodInvocation, and `const GoRoute(...)` is an
  // InstanceCreationExpression. Visit one and a whole GoRouter app reports zero
  // routes while looking healthy.
  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _check(node, node.argumentList, node.constructorName.type.toSource());
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _check(node, node.argumentList, node.methodName.name);
    super.visitMethodInvocation(node);
  }

  void _check(AstNode node, ArgumentList args, String callee) {
    final name = callee.split('.').last;
    if (name == 'GoRoute') {
      _goRoute(node, args);
    } else if (_pushMethods.contains(name)) {
      _inlinePush(node, args, name);
    } else if (_goMethods.contains(name)) {
      _goNav(node, args, name);
    } else if (name == 'MaterialApp' || name == 'CupertinoApp') {
      if (_named(args, 'onGenerateRoute') != null) {
        _add(node, 'not-assessable', {
          'reason':
              'onGenerateRoute resolves its routes from a runtime string; '
              'the table it switches on cannot be read from source',
        });
      }
      // A named-route table IS the app's feature surface. Reading it is out of
      // scope here, but saying nothing makes `declared: []` read as "this app
      // has no routes" — the worst thing this block could claim.
      if (_named(args, 'routes') != null) {
        _add(node, 'not-assessable', {
          'reason':
              'a named-route table (MaterialApp `routes:`) is declared here '
              'and this probe does not read it; enumerate it by hand',
        });
      }
    }
  }

  void _goRoute(AstNode node, ArgumentList args) {
    final path = _stringOf(_named(args, 'path'));
    final name = _stringOf(_named(args, 'name'));
    if (path == null && name == null) {
      return; // not a GoRoute we can say anything about
    }
    _add(node, 'go-route', {
      // A child route's `path` is a SEGMENT: a GoRoute at `b` under `/a`
      // answers to `/a/b`, and printing `b` alone puts a path in the table
      // that nobody can type.
      'path': path == null ? null : _absolutePath(node, path),
      'name': name,
      'screen': _builtWidget(
        _named(args, 'builder') ?? _named(args, 'pageBuilder'),
      ),
    });
  }

  void _inlinePush(AstNode node, ArgumentList args, String method) {
    for (final arg in args.arguments) {
      final route = arg.argumentExpression;
      final callee = _calleeOf(route);
      if (_match(callee, _pageRoutes) == null) {
        continue;
      }
      final builder = _named(
        route is InstanceCreationExpression
            ? route.argumentList
            : (route as MethodInvocation).argumentList,
        'builder',
      );
      final screen = _builtWidget(builder);
      if (screen == null) {
        _add(node, 'not-assessable', {
          'reason':
              "a $method carries a ${_match(callee, _pageRoutes)} whose builder "
              'is not a closure over a constructor; the screen it reaches '
              'cannot be read from source',
        });
        return;
      }
      _add(node, 'inline-push', {
        'from': _enclosing(node),
        'to': screen,
        'method': method,
      });
      return;
    }
  }

  void _goNav(AstNode node, ArgumentList args, String method) {
    // The route is the first POSITIONAL STRING, not the first argument: the
    // two shapes that share these names disagree about position.
    // `context.pushNamed('/x')` puts it first; `Navigator.pushNamed(context,
    // '/x')` puts it second. Reading position 0 blindly reports `context` as
    // an unreadable target — a wrong reason attached to a missed edge.
    String? target;
    final positional = args.arguments
        .where((a) => a is! NamedArgument)
        .toList();
    if (positional.isEmpty) {
      return;
    }
    for (final a in positional) {
      target = _stringOf(a.argumentExpression);
      if (target != null) {
        break;
      }
    }
    if (target == null) {
      _add(node, 'not-assessable', {
        'reason':
            'a $method call whose route is not a string literal '
            '(${positional.map((a) => a.toSource()).join(", ")}) — the route '
            'it reaches cannot be read from source',
      });
      return;
    }
    _add(node, 'go-nav', {
      'from': _enclosing(node),
      'target': target,
      'method': method,
    });
  }

  /// The widget a `builder:` closure constructs, or null when the builder is
  /// anything else — a torn-off function, a variable, a conditional.
  String? _builtWidget(Expression? builder) {
    if (builder is! FunctionExpression) {
      return null;
    }
    final body = builder.body;
    Expression? returned;
    if (body is ExpressionFunctionBody) {
      returned = body.expression;
    } else if (body is BlockFunctionBody) {
      for (final s in body.block.statements) {
        if (s is ReturnStatement) {
          returned = s.expression;
          break;
        }
      }
    }
    // Read the two node shapes separately rather than through _calleeOf. The
    // two disagree about which dotted segment is the widget: `DetailScreen(p)`
    // parses as a MethodInvocation with no target, so its callee is
    // `.DetailScreen` and the NAME is last; while `new Image.network(...)`
    // parses with the whole `Image.network` as the type, where the widget is
    // FIRST. One split cannot serve both, and guessing picks the empty string.
    return switch (returned) {
      InstanceCreationExpression(:final constructorName) =>
        constructorName.type.toSource().split('.').first,
      MethodInvocation(:final methodName) => methodName.name,
      _ => null,
    };
  }

  /// [path] with every enclosing GoRoute's path prepended. An absolute child
  /// path (one starting with `/`) is already whole and is left alone, which is
  /// what GoRouter itself does.
  String _absolutePath(AstNode node, String path) {
    if (path.startsWith('/')) {
      return path;
    }
    final parents = <String>[];
    for (AstNode? p = node.parent; p != null; p = p.parent) {
      final callee = _calleeOf(p);
      if (callee == null || callee.split('.').last != 'GoRoute') {
        continue;
      }
      final args = switch (p) {
        InstanceCreationExpression() => p.argumentList,
        MethodInvocation() => p.argumentList,
        _ => null,
      };
      final parent = args == null ? null : _stringOf(_named(args, 'path'));
      if (parent != null) {
        parents.insert(0, parent);
      }
    }
    if (parents.isEmpty) {
      return path;
    }
    final joined = <String>[...parents, path]
        .map((s) => s.replaceAll(RegExp(r'^/+|/+$'), ''))
        .where((s) => s.isNotEmpty)
        .join('/');
    return '/$joined';
  }

  /// The innermost class the node sits in, RAW. `_ListScreenState` stays
  /// `_ListScreenState`: stripping the underscore and the `State` suffix to
  /// make it read nicely is a guess about naming convention, and a graph that
  /// guesses its own node labels is not evidence.
  String? _enclosing(AstNode node) {
    for (AstNode? p = node.parent; p != null; p = p.parent) {
      if (p is ClassDeclaration) {
        return p.namePart.typeName.lexeme;
      }
    }
    return null;
  }

  Expression? _named(ArgumentList args, String name) {
    for (final a in args.arguments.whereType<NamedArgument>()) {
      if (a.name.lexeme == name) {
        return a.argumentExpression;
      }
    }
    return null;
  }

  /// The value of an UNINTERPOLATED string literal. An interpolated one has a
  /// runtime part, so it is not a target this can name.
  String? _stringOf(Expression? e) => e is SimpleStringLiteral ? e.value : null;

  void _add(AstNode node, String kind, Map<String, Object?> fields) {
    final loc = _lineInfo.getLocation(node.offset);
    routes.add({
      'kind': kind,
      ...fields,
      'file': _path,
      'line': loc.lineNumber,
      'layer': 'STATIC',
    });
  }
}

class _Probe extends RecursiveAstVisitor<void> {
  _Probe(this._lineInfo, this._path);

  final LineInfo _lineInfo;
  final String _path;
  final List<Map<String, Object?>> findings = [];

  // parseString produces an UNRESOLVED AST, so `IconButton(...)` parses as a
  // MethodInvocation and NOT as an InstanceCreationExpression — the parser has
  // no way to know IconButton is a type. Visiting only instance creations
  // returns zero findings across a whole app while looking perfectly healthy
  // (measured: 0 findings / 1083 files). Both visitors must funnel into _check,
  // and test/probe_test.dart fails if either branch is removed.
  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _check(node, node.argumentList);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _check(node, node.argumentList);
    super.visitMethodInvocation(node);
  }

  void _check(AstNode node, ArgumentList args) {
    final widget = _match(_calleeOf(node), _watchedWidgets);
    if (widget == null) return;
    // analyzer 14 renamed NamedExpression -> NamedArgument; `name` is a Token now.
    final named = {
      for (final a in args.arguments.whereType<NamedArgument>()) a.name.lexeme,
    };
    switch (widget) {
      case 'GestureDetector' || 'InkWell':
        if (named.contains('onTap') &&
            !_hasAncestorCall(node, _labelWrappers)) {
          _add(
            node,
            'tap-without-label',
            widget,
            'onTap with no enclosing Semantics — a screen reader announces nothing tappable here.',
            // An ancestor widget built in another file can still supply the label.
            'low',
          );
        }
      case 'IconButton' || 'Icon':
        // An Icon inside an IconButton is decorative: the button is the control
        // that needs the name, and it is judged on its own. Reporting both
        // double-counts one control, which is how a rule set turns into noise.
        if (widget == 'Icon' && _hasAncestorCall(node, _iconOwners)) break;
        if (!named.contains('tooltip') && !named.contains('semanticLabel')) {
          _add(
            node,
            'icon-without-label',
            widget,
            'neither tooltip: nor semanticLabel: — the control has no name.',
            'medium',
          );
        }
      case 'Image':
        if (!named.contains('semanticLabel')) {
          _add(
            node,
            'image-without-label',
            widget,
            'no semanticLabel: — decorative images should say so, meaningful ones need a label.',
            'medium',
          );
        }
      case 'TextField':
        final decoration = args.arguments
            .whereType<NamedArgument>()
            .where((a) => a.name.lexeme == 'decoration')
            .map((a) => a.argumentExpression.toSource())
            .join();
        if (!decoration.contains('labelText') &&
            !decoration.contains('label:')) {
          _add(
            node,
            'field-without-label',
            widget,
            'no labelText:/label: in its InputDecoration — hint text alone disappears on focus.',
            // The decoration may be a shared constant defined elsewhere.
            'low',
          );
        }
    }
  }

  bool _hasAncestorCall(AstNode node, Set<String> names) {
    for (AstNode? p = node.parent; p != null; p = p.parent) {
      if (_match(_calleeOf(p), names) != null) return true;
    }
    return false;
  }

  void _add(
    AstNode node,
    String rule,
    String widget,
    String message,
    String confidence,
  ) {
    final loc = _lineInfo.getLocation(node.offset);
    findings.add({
      'rule': rule,
      'widget': widget,
      'file': _path,
      'line': loc.lineNumber,
      'column': loc.columnNumber,
      'layer': 'STATIC',
      // Matching is by constructor NAME on an unresolved AST, so a same-named
      // non-widget (your own class called Image, say) can false-positive.
      'confidence': confidence,
      'message': message,
    });
  }
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run bin/probe.dart <lib-dir>');
    exit(64);
  }
  final root = Directory(args.single);
  if (!root.existsSync()) {
    stderr.writeln('no such directory: ${args.single}');
    exit(66);
  }

  final rootPath = root.absolute.path;
  final findings = <Map<String, Object?>>[];
  final routes = <Map<String, Object?>>[];
  var filesScanned = 0;
  for (final file in root.listSync(recursive: true).whereType<File>()) {
    final path = file.absolute.path;
    if (!path.endsWith('.dart') ||
        path.endsWith('.g.dart') ||
        path.endsWith('.freezed.dart')) {
      continue;
    }
    filesScanned++;
    final relative = path.startsWith(rootPath)
        ? path.substring(rootPath.length).replaceFirst(RegExp(r'^[/\\]'), '')
        : path;
    final source = file.readAsStringSync();
    findings.addAll(scan(source, path: relative));
    routes.addAll(scanRoutes(source, path: relative));
  }

  // Bucketed here rather than in scanRoutes, so the per-file function stays a
  // flat list that a test can read without unwrapping three keys.
  List<Map<String, Object?>> ofKind(String kind) =>
      routes.where((r) => r['kind'] == kind).toList();

  // filesScanned is reported so "0 findings" can be told apart from "0 files
  // parsed" — the shape the MethodInvocation bug above takes in the wild. The
  // same reading applies to routes: an app whose whole router is behind an
  // onGenerateRoute has 0 declared routes and that is a FACT about the app, not
  // a failed scan, which is why notAssessable is a list and not a flag.
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'filesScanned': filesScanned,
      'findings': findings,
      'routes': {
        'declared': ofKind('go-route'),
        'pushed': [...ofKind('inline-push'), ...ofKind('go-nav')],
        'notAssessable': ofKind('not-assessable'),
      },
    }),
  );
}
