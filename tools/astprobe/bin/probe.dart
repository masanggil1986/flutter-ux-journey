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
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

const _watchedWidgets = {
  'GestureDetector',
  'InkWell',
  'IconButton',
  'Icon',
  'Image',
  'TextField',
  'TextFormField',
};
// Ancestors that supply (or deliberately suppress) an accessible name. A bare
// `Semantics` is NOT one of them: container:, explicitChildNodes: and
// identifier: name nothing, and the runtime reports the control under them as
// unlabelled. It counts only with the fields [_Probe._suppliesName] checks.
const _labelWrappers = {
  'Semantics',
  'MergeSemantics',
  'ExcludeSemantics',
  'Tooltip',
};
// Arguments through which a control names itself, so an Icon in one of its
// other slots (`leading:`, `icon:`, `prefixIcon:`) is decoration — the label
// sits on the control's node, and the Icon adds no node of its own.
const _ownerLabels = {'label', 'labelText', 'hintText', 'title', 'text'};

/// Dotted callee source of a widget-shaped call: `IconButton`, `Image.network`,
/// `material.Icon`. Null for anything that is not a call. Type arguments are
/// dropped — `const MaterialPageRoute<void>(...)` is a MaterialPageRoute.
String? _calleeOf(AstNode? node) => switch (node) {
  InstanceCreationExpression(:final constructorName) => [
    constructorName.type.importPrefix?.name.lexeme,
    constructorName.type.name.lexeme,
    constructorName.name?.name,
  ].nonNulls.join('.'),
  MethodInvocation() =>
    '${node.target?.toSource() ?? ''}.${node.methodName.name}',
  _ => null,
};

ArgumentList? _argsOf(AstNode? node) => switch (node) {
  InstanceCreationExpression() => node.argumentList,
  MethodInvocation() => node.argumentList,
  _ => null,
};

Expression? _named(ArgumentList? args, String name) {
  for (final a
      in args?.arguments.whereType<NamedArgument>() ??
          const <NamedArgument>[]) {
    if (a.name.lexeme == name) {
      return a.argumentExpression;
    }
  }
  return null;
}

bool _isTrue(Expression? e) => e is BooleanLiteral && e.value;

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
///   `inline-push`    a Navigator push carrying a MaterialPageRoute, a
///                    CupertinoPageRoute or a PageRouteBuilder — the shape an
///                    app with no declarative router uses, and the one the
///                    public fixture exercises
///   `not-assessable` navigation that exists but cannot be read from source
///
/// Nothing here is inferred. A target that is not a string literal, a builder
/// that is not a closure returning one constructor call, an `onGenerateRoute`
/// that switches on a runtime string, a router this probe does not read
/// (GetX, auto_route, go_router_builder) — each of those is recorded as
/// `not-assessable` rather than guessed at, because a route graph that invents
/// one edge is worse than one that admits a hole.
List<Map<String, Object?>> scanRoutes(
  String source, {
  String path = '<memory>',
  Map<String, String> constants = const <String, String>{},
}) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final probe = _Routes(result.lineInfo, path, constants);
  result.unit.visitChildren(probe);
  return probe.routes;
}

/// Top-level and static `const`/`final` string literals this source declares,
/// keyed as `Owner.field` for a static of a class, enum, mixin or extension
/// and by its bare name for a top-level one.
///
/// This is pass one of two, and it exists because the shape SKILL.md calls the
/// usual GoRouter app — a file of route constants plus the GoRoute tree — is
/// unreadable without it. Measured on a real one: 44 of 44 route declarations
/// and 72 of 72 navigation targets were constant references, and every
/// constant behind them was a string literal in the same package.
///
/// Only literals are collected. A concatenation or an interpolation has a part
/// this cannot see, and a name declared twice with DIFFERENT values is dropped
/// rather than resolved to whichever came first — either would put a path in
/// the graph that the app does not answer to. Locals, instance fields and
/// anything reassignable are not constants another file can name: collecting
/// them resolved a helper's `String target` parameter to some other function's
/// local `target`.
Map<String, String> collectRouteConstants(String source) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final collector = _Constants();
  result.unit.visitChildren(collector);
  return {
    for (final e in collector.found.entries)
      if (!collector.ambiguous.contains(e.key)) e.key: e.value,
  };
}

class _Constants extends RecursiveAstVisitor<void> {
  final Map<String, String> found = {};
  final Set<String> ambiguous = {};

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) =>
      _collect(node.variables, null);

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    final owner = _typeName(_enclosingType(node));
    // An unnamed extension's statics cannot be named from anywhere else.
    if (node.isStatic && owner != null) {
      _collect(node.fields, owner);
    }
  }

  void _collect(VariableDeclarationList list, String? owner) {
    if (!list.isConst && !list.isFinal) {
      return;
    }
    for (final v in list.variables) {
      final init = v.initializer;
      if (init is! SimpleStringLiteral) {
        continue;
      }
      final key = owner == null ? v.name.lexeme : '$owner.${v.name.lexeme}';
      final existing = found[key];
      if (existing != null && existing != init.value) {
        ambiguous.add(key);
        continue;
      }
      found[key] = init.value;
    }
  }
}

/// The innermost class, enum, mixin, extension or extension type around
/// [node] — the declarations whose statics Dart lets a body name bare.
AstNode? _enclosingType(AstNode node) {
  for (AstNode? p = node.parent; p != null; p = p.parent) {
    if (p is ClassDeclaration ||
        p is EnumDeclaration ||
        p is MixinDeclaration ||
        p is ExtensionDeclaration ||
        p is ExtensionTypeDeclaration) {
      return p;
    }
  }
  return null;
}

String? _typeName(AstNode? type) => switch (type) {
  ClassDeclaration(:final namePart) => namePart.typeName.lexeme,
  EnumDeclaration(:final namePart) => namePart.typeName.lexeme,
  ExtensionTypeDeclaration(:final namePart) => namePart.typeName.lexeme,
  MixinDeclaration(:final name) => name.lexeme,
  ExtensionDeclaration(:final name) => name?.lexeme,
  _ => null,
};

/// Whether [scope] declares [name] as anything but a collected constant: a
/// parameter, a local, a field, a method.
bool _declares(AstNode scope, String name) {
  final finder = _Declares(name);
  scope.accept(finder);
  return finder.found;
}

class _Declares extends GeneralizingAstVisitor<void> {
  _Declares(this._name);

  final String _name;
  bool found = false;

  void _see(Token? name) => found = found || name?.lexeme == _name;

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _see(node.name);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitFormalParameter(FormalParameter node) {
    _see(node.name);
    super.visitFormalParameter(node);
  }

  @override
  void visitDeclaredIdentifier(DeclaredIdentifier node) {
    _see(node.name);
    super.visitDeclaredIdentifier(node);
  }

  @override
  void visitCatchClauseParameter(CatchClauseParameter node) {
    _see(node.name);
    super.visitCatchClauseParameter(node);
  }

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    _see(node.name);
    super.visitDeclaredVariablePattern(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _see(node.name);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _see(node.name);
    super.visitFunctionDeclaration(node);
  }
}

/// `return` statements of one function body, not of the closures inside it.
class _Returns extends RecursiveAstVisitor<void> {
  final List<ReturnStatement> found = [];

  @override
  void visitReturnStatement(ReturnStatement node) => found.add(node);

  @override
  void visitFunctionExpression(FunctionExpression node) {}
}

/// `push`, `pushReplacement`, `pushAndRemoveUntil` and friends — every method
/// the fixture and the gated fixture actually use. A matcher that knows only
/// `push` misses the fixture's dead end and the gate it replaces. `replace` is
/// here because Navigator's carries a page route (`newRoute:`); GoRouter's
/// `context.replace('/x')` still falls through to the string reading.
const _pushMethods = {
  'push',
  'pushReplacement',
  'pushAndRemoveUntil',
  'pushRoute',
  'replace',
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
  'replaceNamed',
  // Navigator's own named verbs. Leaving them out is a hole in the map with
  // nothing saying so — quieter than a wrong edge, and harder to notice.
  'popAndPushNamed',
  'pushNamedAndRemoveUntil',
  // Their state-restoring twins. The named ones read like the above; the
  // others take a static builder function, which is reported, not read.
  'restorablePush',
  'restorablePushNamed',
  'restorablePushReplacement',
  'restorablePushReplacementNamed',
  'restorablePushAndRemoveUntil',
  'restorablePushNamedAndRemoveUntil',
  'restorablePopAndPushNamed',
  'restorableReplace',
};

/// Routers this probe does not read. Their tables live in a GetPage list or
/// in generated code (`*.g.dart`, which is not scanned), so a GetX or
/// auto_route app would otherwise come out with every route block empty —
/// which reads as "no declarative router", a false statement about the app.
const _getxApps = {'GetMaterialApp', 'GetCupertinoApp'};
const _generatedRouters = {
  'AutoRouterConfig',
  // auto_route 5 and older
  'MaterialAutoRouter',
  'CupertinoAutoRouter',
  'AdaptiveAutoRouter',
  'CustomAutoRouter',
  // go_router_builder
  'TypedGoRoute',
  'TypedShellRoute',
  'TypedStatefulShellRoute',
};

class _Routes extends RecursiveAstVisitor<void> {
  _Routes(this._lineInfo, this._path, this._constants);

  final LineInfo _lineInfo;
  final String _path;
  final Map<String, String> _constants;
  final List<Map<String, Object?>> routes = [];

  /// The constant the last [_stringOf] resolved through, so an entry can carry
  /// where its value came from instead of asking a reader to trust it.
  String? _via;

  // Same trap as _Probe, and worth writing out twice: on an unresolved AST
  // `GoRoute(...)` is a MethodInvocation, and `const GoRoute(...)` is an
  // InstanceCreationExpression. Visit one and a whole GoRouter app reports zero
  // routes while looking healthy.
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

  @override
  void visitAnnotation(Annotation node) {
    final router = _match(node.name.name, _generatedRouters);
    if (router != null) {
      _add(node, 'not-assessable', {
        'reason':
            'a generated route table (@$router) is declared here and this '
            'probe does not read it; enumerate its screens by hand',
      });
    }
    super.visitAnnotation(node);
  }

  void _check(AstNode node, ArgumentList args) {
    final callee = _calleeOf(node)!;
    final name = callee.split('.').last;
    final getx = _match(callee, _getxApps);
    if (getx != null) {
      _add(node, 'not-assessable', {
        'reason':
            'a GetX app ($getx): its GetPage table and Get.to/Get.toNamed '
            'navigation are not read by this probe; enumerate its screens by '
            'hand',
      });
    } else if (name == 'GoRoute') {
      _goRoute(node, args);
    } else if (name == 'goBranch') {
      _add(node, 'not-assessable', {
        'reason':
            'goBranch switches a StatefulShellRoute branch by index; which '
            'branch it reaches cannot be read from source (the branch routes '
            'themselves are declared)',
      });
    } else if (_pushMethods.contains(name) && _inlinePush(node, args, name)) {
      // handled as a Navigator push
    } else if (_goMethods.contains(name) || _pushMethods.contains(name)) {
      // `push` belongs to BOTH APIs: `Navigator.push(c, MaterialPageRoute(…))`
      // and `context.push('/x')`. Which one it is follows from the argument,
      // not from the name — and matching the Navigator shape first and giving
      // up when no PageRoute turns up swallowed 67 calls on a real app, with
      // no edge and no line saying one was missed.
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
    final pathArg = _named(args, 'path');
    final nameArg = _named(args, 'name');
    final path = _stringOf(pathArg);
    // Captured here: reading `name` below runs _stringOf again and clears it.
    final pathVia = _via;
    final name = _stringOf(nameArg);
    final via = pathVia ?? _via;
    if (path == null && name == null) {
      if (pathArg == null && nameArg == null) {
        return; // a shell or a redirect: no destination was declared here
      }
      // A route constant is the shape SKILL.md itself calls the usual GoRouter
      // app, and it is not a string literal. Measured on a real one: 56
      // declarations, every `path:` a constant, 12 routes reported — 44
      // declared screens gone with nothing saying so.
      _add(node, 'not-assessable', {
        'reason':
            'a GoRoute whose path/name is not a string literal '
            '(${(pathArg ?? nameArg)!.toSource()}) — the route it declares '
            'cannot be read from source',
      });
      return;
    }
    // A child route's `path` is a SEGMENT: a GoRoute at `b` under `/a`
    // answers to `/a/b`, and printing `b` alone puts a path in the table
    // that nobody can type.
    final absolute = path == null ? null : _absolutePath(node, path);
    if (path != null && absolute == null) {
      _add(node, 'not-assessable', {
        'reason':
            'a GoRoute at `$path` under a parent route whose path cannot be '
            'read here (not a string literal, or declared outside this tree) '
            '— the path it answers to cannot be read from source',
      });
      return;
    }
    final pageBuilder = _named(args, 'pageBuilder');
    _add(node, 'go-route', {
      'path': absolute,
      'name': name,
      'via': via,
      // A pageBuilder returns a Page by type, so its outermost call is always
      // a transition wrapper (NoTransitionPage, CustomTransitionPage). The
      // screen is the Page's `child:`.
      'screen': pageBuilder == null
          ? _widgetName(_returned(_named(args, 'builder')))
          : _widgetName(_named(_argsOf(_returned(pageBuilder)), 'child')),
    });
  }

  /// True when this call was a Navigator push carrying a page route — the
  /// only reading under which the caller should stop looking.
  bool _inlinePush(AstNode node, ArgumentList args, String method) {
    for (final arg in args.arguments) {
      final route = arg.argumentExpression;
      final kind = _match(_calleeOf(route), _pageRoutes);
      if (kind == null) {
        continue;
      }
      // PageRouteBuilder has no `builder:`; its screen is in `pageBuilder:`.
      final routeArgs = _argsOf(route);
      final screen = _widgetName(
        _returned(
          _named(routeArgs, 'builder') ?? _named(routeArgs, 'pageBuilder'),
        ),
      );
      if (screen == null) {
        _add(node, 'not-assessable', {
          'reason':
              'a $method carries a $kind whose builder is not a closure '
              'returning one constructor call; the screen it reaches cannot '
              'be read from source',
        });
        return true;
      }
      _add(node, 'inline-push', {
        'from': _enclosing(node),
        'to': screen,
        'method': method,
      });
      return true;
    }
    return false;
  }

  void _goNav(AstNode node, ArgumentList args, String method) {
    // The route is the first POSITIONAL STRING, not the first argument: the
    // two shapes that share these names disagree about position.
    // `context.pushNamed('/x')` puts it first; `Navigator.pushNamed(context,
    // '/x')` puts it second. Reading position 0 blindly reports `context` as
    // an unreadable target — a wrong reason attached to a missed edge.
    final positional = args.arguments
        .where((a) => a is! NamedArgument)
        .toList();
    String? target;
    for (final a in positional) {
      target = _stringOf(a.argumentExpression);
      if (target != null) {
        break;
      }
    }
    if (target == null) {
      if (positional.isEmpty &&
          _named(args, 'newRoute') == null &&
          _named(args, 'newRouteBuilder') == null) {
        // `uri.replace(path: …)` shares a verb's name and is not navigation.
        // Navigator's `replace(oldRoute:, newRoute: route)` with the route
        // built elsewhere is, and falls through to be reported.
        return;
      }
      final shown = positional.isEmpty ? args.arguments : positional;
      _add(node, 'not-assessable', {
        'reason':
            'a $method call whose route is not a string literal '
            '(${shown.map((a) => a.toSource()).join(", ")}) — the route '
            'it reaches cannot be read from source',
      });
      return;
    }
    _add(node, 'go-nav', {
      'from': _enclosing(node),
      'target': target,
      'method': method,
      'via': _via,
    });
  }

  /// The one expression a builder closure returns, or null when the builder
  /// is anything else — a torn-off function, a variable — or can return more
  /// than one thing. Reading the first of two `return`s names one screen and
  /// drops the other.
  Expression? _returned(Expression? builder) {
    if (builder is! FunctionExpression) {
      return null;
    }
    final body = builder.body;
    if (body is ExpressionFunctionBody) {
      return body.expression;
    }
    final returns = _Returns();
    body.accept(returns);
    return returns.found.length == 1 ? returns.found.single.expression : null;
  }

  /// The widget [e] constructs, as its whole dotted name without type
  /// arguments: `DetailScreen`, `EditScreen.create`, `screens.DetailScreen`,
  /// `BlocProvider.value`. Unresolved, `Image.network(...)` and
  /// `screens.DetailScreen(...)` parse alike, so naming one segment is a guess
  /// that came out as `create`, `value` or `screens`; the whole name is what
  /// the code says. Null for a conditional, a chained call, or no call.
  String? _widgetName(Expression? e) => switch (e) {
    InstanceCreationExpression() => _calleeOf(e),
    MethodInvocation(target: null, :final methodName) => methodName.name,
    MethodInvocation(target: Identifier()) => _calleeOf(e),
    _ => null,
  };

  /// [path] with every enclosing GoRoute's path prepended. An absolute child
  /// path (one starting with `/`) is already whole and is left alone, which is
  /// what GoRouter itself does.
  ///
  /// Null when an enclosing GoRoute's path cannot be read, or when a relative
  /// path has no enclosing GoRoute here (its list is declared apart from its
  /// parent). Skipping the unreadable parent printed a well-formed path the
  /// app does not answer to.
  String? _absolutePath(AstNode node, String path) {
    if (path.startsWith('/')) {
      return path;
    }
    final parents = <String>[];
    for (AstNode? p = node.parent; p != null; p = p.parent) {
      final callee = _calleeOf(p);
      if (callee == null || callee.split('.').last != 'GoRoute') {
        continue;
      }
      final parent = _stringOf(_named(_argsOf(p), 'path'));
      if (parent == null) {
        return null;
      }
      parents.insert(0, parent);
    }
    if (parents.isEmpty) {
      return null;
    }
    final joined = <String>[...parents, path]
        .map((s) => s.replaceAll(RegExp(r'^/+|/+$'), ''))
        .where((s) => s.isNotEmpty)
        .join('/');
    return '/$joined';
  }

  /// The innermost class (or enum, mixin, extension) the node sits in, RAW.
  /// `_ListScreenState` stays `_ListScreenState`: stripping the underscore and
  /// the `State` suffix to make it read nicely is a guess about naming
  /// convention, and a graph that guesses its own node labels is not evidence.
  String? _enclosing(AstNode node) => _typeName(_enclosingType(node));

  /// The value of an UNINTERPOLATED string literal, or of a constant declared
  /// as one somewhere in the package. An interpolated literal has a runtime
  /// part, so it is not a target this can name.
  ///
  /// Sets [_via] when the value came from a constant and clears it otherwise,
  /// so a caller records provenance without a second lookup.
  String? _stringOf(Expression? e) {
    _via = null;
    if (e is SimpleStringLiteral) {
      return e.value;
    }
    final key = switch (e) {
      PrefixedIdentifier() => e.toSource(),
      SimpleIdentifier() => _bareKey(e),
      _ => null,
    };
    final value = _constants[key];
    if (value != null) {
      _via = key;
    }
    return value;
  }

  /// The constant a bare name refers to, in Dart's own lookup order: a
  /// parameter or local first, then the enclosing type's members (a class
  /// names its own statics bare), then the top level. Null when something
  /// nearer than a collected constant has the name.
  ///
  /// ponytail: coarse scopes — a same-named declaration anywhere in the
  /// enclosing member, or anywhere in the enclosing type, shadows. The worst
  /// case is a not-assessable line, never an edge to a constant the code does
  /// not use; real block scoping if those lines ever crowd out real ones.
  String? _bareKey(SimpleIdentifier e) {
    final name = e.name;
    AstNode? member = e.parent;
    while (member != null &&
        member is! ClassMember &&
        member is! CompilationUnitMember) {
      member = member.parent;
    }
    if (member != null && _declares(member, name)) {
      return null;
    }
    final type = _enclosingType(e);
    if (type != null) {
      final owned = '${_typeName(type)}.$name';
      if (_constants.containsKey(owned)) {
        return owned;
      }
      if (_declares(type, name)) {
        return null;
      }
    }
    return name;
  }

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
    // A call chained on another expression — `Image.asset(...).animate()` —
    // is an extension method, not a widget, and `IconButton.styleFrom` is a
    // ButtonStyle. Matching their dotted segments reported the labelled
    // widget underneath again, at its own position.
    if (node is MethodInvocation &&
        (node.target is! Identifier? || node.methodName.name == 'styleFrom')) {
      return;
    }
    final widget = _match(_calleeOf(node), _watchedWidgets);
    if (widget == null) return;
    // analyzer 14 renamed NamedExpression -> NamedArgument; `name` is a Token now.
    final named = {
      for (final a in args.arguments.whereType<NamedArgument>()) a.name.lexeme,
    };
    switch (widget) {
      case 'GestureDetector' || 'InkWell':
        if (named.contains('onTap') && !_ancestors(node).any(_suppliesName)) {
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
        if (widget == 'Icon' && _isDecorative(node)) break;
        final icon = _named(args, 'icon');
        if (!named.contains('tooltip') &&
            !named.contains('semanticLabel') &&
            _named(icon == null ? null : _argsOf(icon), 'semanticLabel') ==
                null) {
          _add(
            node,
            'icon-without-label',
            widget,
            'neither tooltip: nor semanticLabel: — the control has no name.',
            'medium',
          );
        }
      case 'Image':
        // Both are the SDK's own way to say "decorative": neither leaves an
        // image node in the tree at all. A labelled Semantics around the
        // Image does not count — measured, the Image's own unlabelled node
        // stays beside it.
        if (!named.contains('semanticLabel') &&
            !_isTrue(_named(args, 'excludeFromSemantics')) &&
            !_ancestors(
              node,
            ).any((a) => _match(_calleeOf(a), {'ExcludeSemantics'}) != null)) {
          _add(
            node,
            'image-without-label',
            widget,
            'no semanticLabel: — decorative images should say so, meaningful ones need a label.',
            'medium',
          );
        }
      case 'TextField' || 'TextFormField':
        final decoration = _named(args, 'decoration')?.toSource() ?? '';
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

  /// An Icon that is not the control needing the name. One control, one
  /// finding: reporting the Icon as well double-counts it, which is how a rule
  /// set turns into noise.
  bool _isDecorative(AstNode icon) {
    if (_ancestors(icon).any(
      (a) => _suppliesName(a) || _match(_calleeOf(a), {'IconButton'}) != null,
    )) {
      return true;
    }
    // The NEAREST tap owner only. A keyboard-dismiss GestureDetector around a
    // whole Scaffold does not own the FAB inside it, and the FAB's Icon is the
    // true positive there.
    for (final a in _ancestors(icon)) {
      final args = _argsOf(a);
      if (_named(args, 'onTap') != null || _named(args, 'onPressed') != null) {
        // The tap rule reports these owners (or a name wrapper silenced it).
        if (_match(_calleeOf(a), {'GestureDetector', 'InkWell'}) != null) {
          return true;
        }
        break;
      }
    }
    // The Icon is the direct value of a slot of a control that names itself.
    // `child:` is the control's content rather than a slot beside its name,
    // so only a tooltip covers it.
    final slot = icon.parent;
    final owner = slot?.parent?.parent;
    if (slot is! NamedArgument || owner == null) {
      return false;
    }
    final ownerArgs = _argsOf(owner);
    return _named(ownerArgs, 'tooltip') != null ||
        (slot.name.lexeme != 'child' &&
            _ownerLabels.any((l) => _named(ownerArgs, l) != null));
  }

  /// Calls enclosing [node], innermost first, up to the first `on*` callback:
  /// whatever is built inside `onPressed:` is shown elsewhere — a dialog, a
  /// pushed route — and the wrappers around the button do not reach it.
  Iterable<AstNode> _ancestors(AstNode node) sync* {
    for (AstNode? p = node.parent; p != null; p = p.parent) {
      final slot = p.parent;
      if (p is FunctionExpression &&
          slot is NamedArgument &&
          slot.name.lexeme.startsWith('on')) {
        return;
      }
      if (p is InstanceCreationExpression || p is MethodInvocation) yield p;
    }
  }

  /// A Semantics counts only when it carries what labeledTapTargetGuideline
  /// reads (label:, tooltip:) or drops the subtree altogether.
  bool _suppliesName(AstNode call) {
    final wrapper = _match(_calleeOf(call), _labelWrappers);
    if (wrapper != 'Semantics') {
      return wrapper != null;
    }
    final args = _argsOf(call);
    return _named(args, 'label') != null ||
        _named(args, 'tooltip') != null ||
        _isTrue(_named(args, 'excludeSemantics'));
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

  final sources = <String, String>{};
  for (final file in root.listSync(recursive: true).whereType<File>()) {
    final path = file.absolute.path;
    if (!path.endsWith('.dart') ||
        path.endsWith('.g.dart') ||
        path.endsWith('.freezed.dart') ||
        // macOS AppleDouble metadata (`._main.dart`) on a copied tree: named
        // like Dart, but binary.
        file.uri.pathSegments.last.startsWith('._')) {
      continue;
    }
    filesScanned++;
    final relative = path.startsWith(rootPath)
        ? path.substring(rootPath.length).replaceFirst(RegExp(r'^[/\\]'), '')
        : path;
    // Lenient, as the Dart toolchain is: one Latin-1 byte in a comment
    // compiles fine, and must not abort the whole scan.
    sources[relative] = utf8.decode(
      file.readAsBytesSync(),
      allowMalformed: true,
    );
  }

  // Pass one, over the whole package: a route path declared as
  // `Routes.login` is readable only once the file holding that constant has
  // been seen, and it is rarely the file holding the router. Measured on a real
  // app, skipping this left 170 unreadable entries against 17 readable ones.
  // A name two files disagree about is dropped by collectRouteConstants rather
  // than resolved to whichever was read first.
  final constants = <String, String>{};
  final conflicting = <String>{};
  for (final source in sources.values) {
    collectRouteConstants(source).forEach((key, value) {
      final existing = constants[key];
      if (existing != null && existing != value) {
        conflicting.add(key);
      }
      constants[key] = value;
    });
  }
  constants.removeWhere((key, _) => conflicting.contains(key));

  for (final entry in sources.entries) {
    findings.addAll(scan(entry.value, path: entry.key));
    routes.addAll(
      scanRoutes(entry.value, path: entry.key, constants: constants),
    );
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
        // Every string constant pass one could read, not just the route ones —
        // nothing here knows which is which until a route refers to it. It is
        // a diagnostic: a route table that reads as empty with a large number
        // here means the constants were found and the router was not, while
        // empty with zero here means the app declares its paths inline, which
        // is a different problem.
        'stringConstantsCollected': constants.length,
        'declared': ofKind('go-route'),
        'pushed': [...ofKind('inline-push'), ...ofKind('go-nav')],
        'notAssessable': ofKind('not-assessable'),
      },
    }),
  );
}
