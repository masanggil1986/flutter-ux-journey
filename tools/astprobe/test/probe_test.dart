import 'package:test/test.dart';

import '../bin/probe.dart';

Set<String> rulesIn(String source) =>
    scan(source).map((f) => f['rule'] as String).toSet();

void main() {
  // THE REGRESSION THAT MATTERS. Written the way Flutter code is actually
  // written — no `const`, no `new` — these parse as MethodInvocation on the
  // unresolved AST. Delete visitMethodInvocation and this test goes green-less
  // while a real app would silently report zero findings.
  test('fires on plain constructor calls (MethodInvocation branch)', () {
    final rules = rulesIn('''
      Widget build(BuildContext context) => Column(children: [
        IconButton(icon: Icon(Icons.add), onPressed: doIt),
        Image.asset('a.png'),
        TextField(decoration: InputDecoration(hintText: 'Email')),
        GestureDetector(onTap: doIt, child: Text('Continue')),
      ]);
    ''');
    expect(rules, containsAll([
      'icon-without-label',
      'image-without-label',
      'field-without-label',
      'tap-without-label',
    ]));
  });

  // `const`/`new` force an InstanceCreationExpression instead. Delete
  // visitInstanceCreationExpression and this one fails.
  test('fires on const/new calls (InstanceCreationExpression branch)', () {
    expect(rulesIn("Widget w = const Icon(Icons.add);"), {'icon-without-label'});
    expect(rulesIn("Widget w = new Image.network('u');"), {'image-without-label'});
  });

  test('labelled widgets are clean', () {
    expect(rulesIn('''
      Widget build(BuildContext context) => Column(children: [
        IconButton(tooltip: 'Add', icon: Icon(Icons.add, semanticLabel: 'add'), onPressed: doIt),
        Image.asset('a.png', semanticLabel: 'A cat'),
        TextField(decoration: InputDecoration(labelText: 'Email')),
        Semantics(button: true, label: 'Continue',
          child: GestureDetector(onTap: doIt, child: Text('Continue'))),
      ]);
    '''), isEmpty);
  });

  test('InkWell without onTap is not a finding', () {
    expect(rulesIn("Widget w = InkWell(child: Text('x'));"), isEmpty);
  });

  // One control, one finding. An IconButton and the Icon it wraps are the same
  // control; reporting both is how a rule set turns into noise.
  test('an Icon inside a labelled owner is not reported twice', () {
    expect(scan("Widget w = IconButton(icon: Icon(Icons.add), onPressed: f);"), hasLength(1));
    expect(rulesIn("Widget w = Tooltip(message: 'Add', child: Icon(Icons.add));"), isEmpty);
  });

  test('findings carry a location, the STATIC layer and an honest confidence', () {
    final finding = scan("Widget w = Image.asset('a.png');", path: 'lib/a.dart').single;
    expect(finding['file'], 'lib/a.dart');
    expect(finding['line'], 1);
    expect(finding['layer'], 'STATIC');
    expect(finding['confidence'], anyOf('low', 'medium'));
  });

  test('unparseable source yields nothing rather than throwing', () {
    expect(scan('this is not dart {{{'), isEmpty);
  });
}
