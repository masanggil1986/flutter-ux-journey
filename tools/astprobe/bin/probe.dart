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
const _labelWrappers = {'Semantics', 'MergeSemantics', 'ExcludeSemantics', 'Tooltip'};
const _iconOwners = {'IconButton', ..._labelWrappers};

/// Dotted callee source of a widget-shaped call: `IconButton`, `Image.network`,
/// `material.Icon`. Null for anything that is not a call.
String? _calleeOf(AstNode node) => switch (node) {
  InstanceCreationExpression() => node.constructorName.type.toSource(),
  MethodInvocation() => '${node.target?.toSource() ?? ''}.${node.methodName.name}',
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
        if (named.contains('onTap') && !_hasAncestorCall(node, _labelWrappers)) {
          _add(node, 'tap-without-label', widget,
              'onTap with no enclosing Semantics — a screen reader announces nothing tappable here.',
              // An ancestor widget built in another file can still supply the label.
              'low');
        }
      case 'IconButton' || 'Icon':
        // An Icon inside an IconButton is decorative: the button is the control
        // that needs the name, and it is judged on its own. Reporting both
        // double-counts one control, which is how a rule set turns into noise.
        if (widget == 'Icon' && _hasAncestorCall(node, _iconOwners)) break;
        if (!named.contains('tooltip') && !named.contains('semanticLabel')) {
          _add(node, 'icon-without-label', widget,
              'neither tooltip: nor semanticLabel: — the control has no name.', 'medium');
        }
      case 'Image':
        if (!named.contains('semanticLabel')) {
          _add(node, 'image-without-label', widget,
              'no semanticLabel: — decorative images should say so, meaningful ones need a label.',
              'medium');
        }
      case 'TextField':
        final decoration = args.arguments
            .whereType<NamedArgument>()
            .where((a) => a.name.lexeme == 'decoration')
            .map((a) => a.argumentExpression.toSource())
            .join();
        if (!decoration.contains('labelText') && !decoration.contains('label:')) {
          _add(node, 'field-without-label', widget,
              'no labelText:/label: in its InputDecoration — hint text alone disappears on focus.',
              // The decoration may be a shared constant defined elsewhere.
              'low');
        }
    }
  }

  bool _hasAncestorCall(AstNode node, Set<String> names) {
    for (AstNode? p = node.parent; p != null; p = p.parent) {
      if (_match(_calleeOf(p), names) != null) return true;
    }
    return false;
  }

  void _add(AstNode node, String rule, String widget, String message, String confidence) {
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
    findings.addAll(scan(file.readAsStringSync(), path: relative));
  }

  // filesScanned is reported so "0 findings" can be told apart from "0 files
  // parsed" — the shape the MethodInvocation bug above takes in the wild.
  stdout.writeln(const JsonEncoder.withIndent('  ')
      .convert({'filesScanned': filesScanned, 'findings': findings}));
}
