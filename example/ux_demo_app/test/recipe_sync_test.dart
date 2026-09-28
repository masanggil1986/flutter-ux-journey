// walking.md IS the recipe the skill generates code from, and this file is the
// worked instance of it. If the two drift, the skill writes code that was never
// run into somebody else's app — which is the whole failure mode this project
// exists to avoid. So they are pinned to each other.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/gated_journey_test.dart'
    as gated
    show journey, setup;
// Both journey files export `journey`, so both imports are prefixed.
import '../ux_audit/ux_journey_test.dart'
    as walker
    show Step, journey, kIphoneSe;

const String _recipe = '../../skills/flutter-ux-journey/references/walking.md';
const String _walker = 'ux_audit/ux_journey_test.dart';
const String _driveEntry = 'integration_test/ux_journey_drive.dart';
const String _golden = '../expected-findings.json';
const String _journey = '../journey.md';
const String _gatedJourney = '../journey-gated.md';
const String _stubTemplate =
    '../../skills/flutter-ux-journey/references/network-stub.md';
const String _stub = 'integration_test/gate_stub.dart';

/// The numbered lines under `## <heading>`, in document order. Stops at the
/// next `##` so that `## Priorities`, which is also a numbered list, cannot be
/// mistaken for steps.
List<String> _numbered(String md, String heading) {
  final List<String> out = <String>[];
  bool inside = false;
  for (final String line in md.split('\n')) {
    if (line.startsWith('## ')) {
      inside = line.startsWith('## $heading');
      continue;
    }
    if (inside && RegExp(r'^\d+\.\s').hasMatch(line)) {
      out.add(line.trim());
    }
  }
  return out;
}

/// Pins one `##` section of a journey file to the const list the walker will
/// actually execute. Everything a step line quotes — the target, the text to
/// type, the expectation — must be a field of the matching entry and nothing
/// else, so the published example cannot walk something the document does not
/// describe.
void _pin(String label, List<String> lines, List<walker.Step> steps) {
  expect(
    lines.length,
    steps.length,
    reason:
        '$label: the document declares ${lines.length} steps, '
        'the walker ${steps.length}',
  );
  for (int i = 0; i < lines.length; i++) {
    final walker.Step step = steps[i];
    expect(
      lines[i],
      startsWith('${i + 1}. ${step.action} '),
      reason:
          '$label step ${i + 1}: the document does not say '
          '"${step.action}"',
    );
    expect(
      RegExp('"([^"]*)"')
          .allMatches(lines[i])
          .map((RegExpMatch m) => m.group(1)!),
      unorderedEquals(<String>[
        step.target,
        step.expected,
        if (step.text != null) step.text!,
      ]),
      reason:
          '$label step ${i + 1}: the quoted strings in the document are '
          'not the target, text and expectation the walker uses',
    );
  }
}

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
    expect(
      md,
      isNot(contains('typedef Step =')),
      reason: 'walking.md re-embedded the walker; point at it instead',
    );
    expect(
      File(_walker).existsSync(),
      isTrue,
      reason: '$_walker is what walking.md points at',
    );
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
      expect(
        f['layers'],
        isA<List<Object?>>().having((List<Object?> l) => l, where, isNotEmpty),
      );
      expect(f['confidence'], isNotNull, reason: '$where has no confidence');
      expect(
        (f['evidence']! as String).trim(),
        isNotEmpty,
        reason: '$where has no evidence',
      );
      expect(
        (f['rationale']! as String),
        contains(RegExp('goal|journey|path|reach', caseSensitive: false)),
        reason:
            '$where: the rationale must name the goal, not just the measurement',
      );
      expect(f['severity'], isIn(<int>[1, 2, 3, 4]));
    }

    // Not Assessable is split by what the reader can do about it — two keys,
    // never one list. The split is the point; a flat list puts "you never told
    // us" and "we could not get there" in the same bucket.
    final Map<String, Object?> na = g['notAssessable']! as Map<String, Object?>;
    expect(na.keys.toSet(), <String>{'notDeclared', 'notReached'});
    expect(
      na['notReached'],
      isNotEmpty,
      reason: 'Not Assessable is never empty — at minimum it states the platform limit',
    );

    // Reach is counted on the declared path and must say so, because "N taps"
    // reads as a minimum and a minimum would need a crawl.
    final Map<String, Object?> reach = g['reach']! as Map<String, Object?>;
    expect(reach['basis'], contains('declared'));
  });

  test('the walker keeps the habit that fails silently', () {
    // Both assertions are on the raw string rather than a matcher over the
    // source, so a failure prints the reason and not fifty kilobytes of walker.
    final String src = File(_walker).readAsStringSync();
    expect(
      src.contains('pumpAndSettle('),
      isFalse,
      reason:
          'pumpAndSettle only gives up after a 10-minute default timeout, so an '
          'app that animates continuously — a spinner, a shimmer, a network '
          'wait — never goes quiet and the walk hangs producing nothing. The '
          'bounded settle() exists for exactly that.',
    );
    // The walk itself must not know about integration_test any more: that is
    // the whole reason it can run under `flutter test`, and an import creeping
    // back is the one change that would silently undo it.
    expect(
      src.contains('package:integration_test/'),
      isFalse,
      reason:
          'the walk is binding-agnostic; only a drive entry may import '
          'integration_test',
    );
  });

  test('the drive entry keeps the habit that fails silently', () {
    // The hazard is real but it is now the DRIVE path's alone: takeScreenshot
    // appends each PNG into reportData['screenshots'] and that list is how the
    // driver gets the bytes, so assigning a fresh map deletes every screenshot
    // and the run still passes.
    final String src = File(_driveEntry).readAsStringSync();
    expect(src.contains('reportData ??='), isTrue);
    expect(
      src.contains('.addAll('),
      isTrue,
      reason: 'publish must merge into reportData, never replace it',
    );
  });

  test('example/journey.md walks what the walker walks', () {
    final File file = File(_journey);
    if (!file.existsSync()) {
      markTestSkipped('$_journey not present — running outside the repo');
      return;
    }
    _pin(
      'journey.md ## Steps',
      _numbered(file.readAsStringSync(), 'Steps'),
      walker.journey,
    );
  });

  test('example/journey-gated.md walks what the gated walker walks', () {
    final File file = File(_gatedJourney);
    if (!file.existsSync()) {
      markTestSkipped('$_gatedJourney not present — running outside the repo');
      return;
    }
    final String md = file.readAsStringSync();
    // The heading is `## Setup (excluded from measurement and scoring)`, so
    // the match is on the prefix.
    _pin('journey-gated.md ## Setup', _numbered(md, 'Setup'), gated.setup);
    _pin('journey-gated.md ## Steps', _numbered(md, 'Steps'), gated.journey);
  });

  test('both journey files declare the device the walker applies', () {
    for (final String path in <String>[_journey, _gatedJourney]) {
      final File file = File(path);
      if (!file.existsSync()) {
        markTestSkipped('$path not present — running outside the repo');
        continue;
      }
      final String md = file.readAsStringSync();
      expect(
        md,
        contains('## Device'),
        reason:
            '$path has no `## Device`: under `flutter test` nothing else '
            'supplies the viewport and every fold column comes out blank',
      );
      // The section must name a preset the walker can actually resolve, or the
      // document describes a run that cannot happen.
      expect(
        md.contains('`${walker.kIphoneSe.name}`'),
        isTrue,
        reason: '$path names a preset that is not `${walker.kIphoneSe.name}`',
      );
    }
  });

  test('the walker admits whether the journey declared a device', () {
    // `deviceDeclared` is a claim about the JOURNEY FILE frozen into generated
    // Dart, and it is the only thing separating "the screen the author chose"
    // from "the screen nobody chose" in the report's scope clause. Nothing but
    // this checks that the two agree.
    final File journey = File(_journey);
    if (!journey.existsSync()) {
      markTestSkipped('$_journey not present — running outside the repo');
      return;
    }
    final bool declaredInDoc = journey.readAsStringSync().contains('## Device');
    final String src = File(_walker).readAsStringSync();
    final RegExpMatch? m = RegExp(r'const bool deviceDeclared = (true|false);')
        .firstMatch(src);
    expect(m, isNotNull, reason: '$_walker lost `deviceDeclared`');
    expect(
      m!.group(1) == 'true',
      declaredInDoc,
      reason: declaredInDoc
          ? '$_journey declares `## Device` but the walker says it did not, so '
                'the report would label a chosen screen as a fallback'
          : '$_journey declares no `## Device` but the walker says it did, so '
                'the report would assert a fold line nobody asked for',
    );
  });

  test('network-stub.md carries a template that is known to compile', () {
    final File doc = File(_stubTemplate);
    if (!doc.existsSync()) {
      markTestSkipped('$_stubTemplate not present — running outside the repo');
      return;
    }
    final List<String> lines = doc.readAsStringSync().split('\n');
    final int open = lines.indexOf('```dart');
    expect(open, isNonNegative, reason: '$_stubTemplate lost its dart fence');
    final int close = lines.indexWhere(
      (String l) => l.trimRight() == '```',
      open + 1,
    );
    expect(close, isNonNegative, reason: '$_stubTemplate fence is unclosed');

    // Above this line the template is app-specific (`_routes`); from it down
    // it is generic, and gate_stub.dart is that part verbatim.
    const String marker = '/// Anything not in [_routes] gets this.';
    final List<String> generic = lines.sublist(open + 1, close);
    final int from = generic.indexWhere((String l) => l.startsWith(marker));
    expect(from, isNonNegative, reason: '$_stubTemplate lost "$marker"');
    generic.removeRange(0, from);
    // The fence ends on a blank line before the closing ```; the file does not.
    while (generic.isNotEmpty && generic.last.trim().isEmpty) {
      generic.removeLast();
    }

    final List<String> stub = File(_stub).readAsStringSync().split('\n');
    final int at = stub.indexWhere((String l) => l.startsWith(marker));
    expect(at, isNonNegative, reason: '$_stub lost "$marker"');
    for (int i = 0; i < generic.length; i++) {
      expect(
        at + i < stub.length ? stub[at + i] : '<end of file>',
        generic[i],
        reason:
            '$_stub:${at + i + 1} drifted from '
            '$_stubTemplate:${open + from + i + 2}. The template is code living '
            'in a document, and the only thing that can prove it compiles is a '
            'copy of it that does.',
      );
    }
  });
}
