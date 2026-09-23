// walking.md IS the recipe the skill generates code from, and this file is the
// worked instance of it. If the two drift, the skill writes code that was never
// run into somebody else's app — which is the whole failure mode this project
// exists to avoid. So they are pinned to each other.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _recipe = '../../skills/flutter-ux-journey/references/walking.md';
const String _walker = 'integration_test/ux_journey_test.dart';
const String _golden = '../expected-findings.json';

void main() {
  test('walking.md points at a walker that exists', () {
    final File recipe = File(_recipe);
    if (!recipe.existsSync()) {
      // The demo app also ships standalone; outside the repo there is nothing
      // to check and that is not a failure.
      markTestSkipped('$_recipe not present — running outside the repo');
      return;
    }
    // walking.md deliberately does NOT copy the walker into a code block: a
    // second copy in prose drifts from the one that was executed, and every
    // trap in that file was found by executing it. It points instead — so the
    // only thing that can rot is the path.
    final String md = recipe.readAsStringSync();
    expect(md, contains('ux_journey_test.dart'));
    // File 1 (the driver) IS embedded — it is 20 lines and never changes.
    // File 2 is the one that must not be copied.
    expect(md, isNot(contains('typedef Step =')),
        reason: 'walking.md re-embedded the walker; point at it instead');
    expect(File(_walker).existsSync(), isTrue, reason: '$_walker is what walking.md points at');
  });

  test('the golden obeys report-format.md', () {
    final File file = File(_golden);
    if (!file.existsSync()) {
      markTestSkipped('$_golden not present — running outside the repo');
      return;
    }
    final Map<String, Object?> g =
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

    // Every finding carries an evidence layer and a confidence, or it does not
    // ship. This is principle (a) with a test behind it rather than a rule in
    // a document nobody re-reads.
    final List<Object?> findings = g['findings']! as List<Object?>;
    expect(findings, isNotEmpty);
    for (final Object? raw in findings) {
      final Map<String, Object?> f = raw! as Map<String, Object?>;
      final String where = '${f['check']} #${f['id']}';
      expect(f['layers'], isA<List<Object?>>().having((List<Object?> l) => l, where, isNotEmpty));
      expect(f['confidence'], isNotNull, reason: '$where has no confidence');
      expect((f['evidence']! as String).trim(), isNotEmpty, reason: '$where has no evidence');
      expect((f['rationale']! as String), contains(RegExp('goal|journey|path|reach', caseSensitive: false)),
          reason: '$where: the rationale must name the goal, not just the measurement');
      expect(f['severity'], isIn(<int>[1, 2, 3, 4]));
    }

    // Not Assessable is split by what the reader can do about it — two keys,
    // never one list. The split is the point; a flat list puts "you never told
    // us" and "we could not get there" in the same bucket.
    final Map<String, Object?> na = g['notAssessable']! as Map<String, Object?>;
    expect(na.keys.toSet(), <String>{'notDeclared', 'notReached'});
    expect(na['notReached'], isNotEmpty,
        reason: 'Not Assessable is never empty — at minimum it states the platform limit');

    // Reach is counted on the declared path and must say so, because "N taps"
    // reads as a minimum and a minimum would need a crawl.
    final Map<String, Object?> reach = g['reach']! as Map<String, Object?>;
    expect(reach['basis'], contains('declared'));
  });
}
