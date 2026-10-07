import 'package:test/test.dart';

import '../bin/probe.dart';

Set<String> rulesIn(String source) =>
    scan(source).map((f) => f['rule'] as String).toSet();

List<String> widgetsIn(String source) =>
    scan(source).map((f) => f['widget'] as String).toList();

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
    expect(
      rules,
      containsAll([
        'icon-without-label',
        'image-without-label',
        'field-without-label',
        'tap-without-label',
      ]),
    );
  });

  // `const`/`new` force an InstanceCreationExpression instead. Delete
  // visitInstanceCreationExpression and this one fails.
  test('fires on const/new calls (InstanceCreationExpression branch)', () {
    expect(rulesIn("Widget w = const Icon(Icons.add);"), {
      'icon-without-label',
    });
    expect(rulesIn("Widget w = new Image.network('u');"), {
      'image-without-label',
    });
  });

  test('labelled widgets are clean', () {
    expect(
      rulesIn('''
      Widget build(BuildContext context) => Column(children: [
        IconButton(tooltip: 'Add', icon: Icon(Icons.add, semanticLabel: 'add'), onPressed: doIt),
        Image.asset('a.png', semanticLabel: 'A cat'),
        TextField(decoration: InputDecoration(labelText: 'Email')),
        TextField(decoration: InputDecoration(label: Text('Name'))),
        Icon(Icons.warning, semanticLabel: 'Warning'),
        Semantics(button: true, label: 'Continue',
          child: GestureDetector(onTap: doIt, child: Text('Continue'))),
      ]);
    '''),
      isEmpty,
    );
  });

  test('an InkWell with onTap is held to the tap rule', () {
    expect(widgetsIn("Widget w = InkWell(onTap: doIt, child: Text('x'));"), [
      'InkWell',
    ]);
  });

  test('InkWell without onTap is not a finding', () {
    expect(rulesIn("Widget w = InkWell(child: Text('x'));"), isEmpty);
  });

  // One control, one finding. An IconButton and the Icon it wraps are the same
  // control; reporting both is how a rule set turns into noise.
  test('an Icon inside a labelled owner is not reported twice', () {
    expect(
      scan("Widget w = IconButton(icon: Icon(Icons.add), onPressed: f);"),
      hasLength(1),
    );
    expect(
      rulesIn("Widget w = Tooltip(message: 'Add', child: Icon(Icons.add));"),
      isEmpty,
    );
  });

  test(
    'findings carry a location, the STATIC layer and an honest confidence',
    () {
      final finding = scan(
        "Widget w = Image.asset('a.png');",
        path: 'lib/a.dart',
      ).single;
      expect(finding['file'], 'lib/a.dart');
      expect(finding['line'], 1);
      expect(finding['layer'], 'STATIC');
      expect(finding['confidence'], anyOf('low', 'medium'));
    },
  );

  test('unparseable source yields nothing rather than throwing', () {
    expect(scan('this is not dart {{{'), isEmpty);
  });

  // Each case below was checked against the runtime labeledTapTargetGuideline
  // and a semantics dump on the same source. The static rule is a candidate
  // list, but a candidate the runtime always refutes is noise with a line
  // number on it — the failure mode the tool this replaced died of.
  group('agrees with the runtime', () {
    // A Material control that names itself — through label:, title:, text:,
    // tooltip: or a field's labelText:/hintText: — owns its icon. The Icon
    // adds no node of its own; reporting it says "the control has no name"
    // about a control that has one. Measured: the stock `flutter create`
    // template's only finding was its tooltipped FAB.
    test('an Icon in a slot of a control that names itself is decorative', () {
      expect(
        scan('''
        Widget build(BuildContext context) => Column(children: [
          FloatingActionButton(tooltip: 'Increment', onPressed: f, child: Icon(Icons.add)),
          FloatingActionButton.extended(onPressed: f, icon: Icon(Icons.add), label: Text('New')),
          ListTile(leading: Icon(Icons.person), title: Text('Profile'), onTap: f),
          NavigationBar(destinations: [
            NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.search_outlined),
                selectedIcon: Icon(Icons.search), label: 'Search'),
          ]),
          BottomNavigationBar(items: [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          ]),
          TabBar(tabs: [Tab(icon: Icon(Icons.cloud), text: 'Cloud')]),
          ElevatedButton.icon(onPressed: f, icon: Icon(Icons.send), label: Text('Send')),
          TextField(decoration: InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email))),
          IconButton(icon: Icon(Icons.add, semanticLabel: 'Add item'), onPressed: f),
        ]);
      '''),
        isEmpty,
      );
      // A hint-only field is labelled by its hint at runtime; its icon is not
      // a second unnamed control. (The field itself is still a finding.)
      expect(
        rulesIn('''
        Widget w = TextField(decoration: InputDecoration(
            hintText: 'Search', prefixIcon: Icon(Icons.search)));
      '''),
        {'field-without-label'},
      );
    });

    test('an icon that is the whole of an unnamed control still fires', () {
      expect(
        widgetsIn(
          'Widget w = FloatingActionButton(onPressed: f, child: Icon(Icons.add));',
        ),
        ['Icon'],
      );
      // `child:` is the control's content, not a slot beside its name: a FAB
      // whose only child is an Icon and that has no tooltip is unnamed.
      expect(
        widgetsIn('''
        Widget w = ListTile(title: Text('Profile'),
            trailing: IconButton(icon: Icon(Icons.edit), onPressed: f));
      '''),
        ['IconButton'],
      );
    });

    test('an icon inside a reported tap target is not counted again', () {
      // One control, one finding: the tap rule already reports the owner.
      expect(
        widgetsIn('Widget w = InkWell(onTap: f, child: Icon(Icons.close));'),
        ['InkWell'],
      );
      expect(
        widgetsIn('''
        Widget w = GestureDetector(onTap: f,
            child: Padding(padding: p, child: Icon(Icons.close)));
      '''),
        ['GestureDetector'],
      );
      // But only the NEAREST tap owner counts. A keyboard-dismiss detector
      // around a whole Scaffold does not own the FAB inside it, and the FAB's
      // Icon is the only true positive on the screen.
      expect(
        widgetsIn('''
        Widget w = GestureDetector(onTap: dismissKeyboard,
            child: Scaffold(floatingActionButton:
                FloatingActionButton(onPressed: f, child: Icon(Icons.add))));
      '''),
        ['GestureDetector', 'Icon'],
      );
    });

    test('a Semantics that names nothing does not silence the tap rule', () {
      for (final String wrapper in <String>[
        'Semantics(container: true, child: ',
        'Semantics(explicitChildNodes: true, child: ',
        "Semantics(identifier: 'close_button', child: ",
      ]) {
        expect(
          widgetsIn(
            'Widget w = ${wrapper}GestureDetector(onTap: f, child: Text("")));',
          ),
          ['GestureDetector'],
          reason: wrapper,
        );
      }
      expect(
        rulesIn('''
        Widget w = Column(children: [
          Semantics(label: 'Close', button: true,
              child: InkWell(onTap: f, child: Icon(Icons.close))),
          Semantics(excludeSemantics: true,
              child: InkWell(onTap: f, child: Icon(Icons.close))),
          // MergeSemantics folds the sibling Text into the tap node.
          MergeSemantics(child: Row(children: [Text('Remember me'),
              GestureDetector(onTap: f, child: Icon(Icons.check_box))])),
        ]);
      '''),
        isEmpty,
      );
    });

    test('a label does not reach into a callback that builds elsewhere', () {
      // The dialog is built when the button is pressed, in a route of its
      // own; the Semantics around the button is nowhere near it.
      expect(
        widgetsIn('''
        Widget w = Semantics(label: 'Open', child: ElevatedButton(
          onPressed: () => showDialog(context: c,
              builder: (_) => GestureDetector(onTap: f, child: Text(''))),
          child: Text('Open'),
        ));
      '''),
        ['GestureDetector'],
      );
    });

    test('an image marked decorative is not asked to say so again', () {
      expect(
        rulesIn('''
        Widget w = Column(children: [
          Image.asset('bg.png', excludeFromSemantics: true),
          ExcludeSemantics(child: Image.asset('bg.png')),
        ]);
      '''),
        isEmpty,
      );
      // A labelled Semantics(image: true) around an Image leaves the image's
      // own unlabelled node in the tree too — measured — so it still fires.
      expect(
        widgetsIn('''
        Widget w = Semantics(label: 'Company logo', image: true,
            child: Image.memory(png));
      '''),
        ['Image'],
      );
    });

    test('a call chained on a widget is not another widget', () {
      // flutter_animate's canonical API, and the documented way to style an
      // M3 icon button. Matching every dotted segment of the chain read both as
      // fresh unlabelled widgets at the labelled one's position.
      expect(
        scan('''
        Widget w = Column(children: [
          Image.asset('a.png', semanticLabel: 'Logo').animate().fadeIn(),
          IconButton(tooltip: 'Add', style: IconButton.styleFrom(),
              icon: Icon(Icons.add), onPressed: f),
        ]);
      '''),
        isEmpty,
      );
      expect(
        widgetsIn("Widget w = Image.network(u).animate().fadeIn().slideY();"),
        ['Image'],
      );
    });

    test('a TextFormField is held to the TextField rule', () {
      // It forwards its decoration to an inner TextField: the defect is the
      // same, and it is the commonest form field there is.
      expect(
        widgetsIn('''
        Widget w = Column(children: [
          TextFormField(decoration: InputDecoration(hintText: 'Email')),
          TextFormField(),
          TextFormField(decoration: InputDecoration(labelText: 'Email')),
        ]);
      '''),
        ['TextFormField', 'TextFormField'],
      );
    });
  });
}
