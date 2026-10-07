// main() as an audit runs it. Its merge, filter and relative-path logic is
// what keeps absolute source paths out of static.json, and none of it is
// reachable through scan()/scanRoutes().

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('the CLI reads a lib/ tree the way an audit quotes it', () async {
    final Directory lib = Directory.systemTemp.createTempSync('astprobe_cli');
    addTearDown(() => lib.deleteSync(recursive: true));
    void write(String path, List<int> bytes) => (File(
      '${lib.path}/$path',
    )..createSync(recursive: true)).writeAsBytesSync(bytes);

    // A Latin-1 byte in a comment: the Dart toolchain accepts this file, so
    // the probe must not exit on it.
    write('a.dart', <int>[
      ...utf8.encode("// caf"),
      0xE9,
      ...utf8.encode(
        "\nconst shared = '/one';\nclass A { void f() => context.go(shared); }\n",
      ),
    ]);
    write(
      'sub/b.dart',
      utf8.encode('''
const shared = '/two';
Widget w = Image.asset('x.png');
'''),
    );
    write('sub/c.g.dart', utf8.encode("Widget g = Image.asset('gen.png');"));
    // macOS AppleDouble metadata next to a real file: not Dart, not UTF-8.
    write('._a.dart', <int>[0x00, 0x05, 0x16, 0x07, 0xFF, 0xFE]);

    final ProcessResult run = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart', lib.path],
    );
    expect(run.exitCode, 0, reason: '${run.stderr}');
    final Map<String, Object?> out =
        jsonDecode(run.stdout as String) as Map<String, Object?>;

    expect(out['filesScanned'], 2);
    final List<Object?> findings = out['findings']! as List<Object?>;
    // Relative to the scanned root, never absolute: the path is the leak.
    expect(findings.map((Object? f) => (f! as Map<String, Object?>)['file']), [
      'sub/b.dart',
    ]);
    final Map<String, Object?> routes = out['routes']! as Map<String, Object?>;
    // Two files disagree about `shared`, so it resolves to neither.
    expect(routes['stringConstantsCollected'], 0);
    expect(routes['pushed'], isEmpty);
    expect(routes['notAssessable'], hasLength(1));
  });
}
