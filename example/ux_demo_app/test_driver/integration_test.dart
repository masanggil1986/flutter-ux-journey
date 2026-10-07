import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  // ONE output root, the one SKILL.md declares. `screenshots/` — the default
  // this file used to write — is a conventionally TRACKED directory in a
  // Flutter app, so a walk against somebody's repo dropped their product
  // screenshots where `git add -A` would take them.
  final Directory screens = Directory('ux-audit-out/screens');
  // Emptied first: a PNG left by an earlier run would pass as this run's, and
  // a missing setup_N.png is how a reader knows the setup passed.
  if (screens.existsSync()) {
    screens.deleteSync(recursive: true);
  }
  await integrationDriver(
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? args]) async {
          final File f = File('${screens.path}/$name.png');
          f.parent.createSync(recursive: true);
          f.writeAsBytesSync(bytes);
          return true;
        },
    // The PNGs already went to disk above. takeScreenshot ALSO stuffs each one
    // into reportData['screenshots'] as a JSON int array, which inflated a
    // 45 KB PNG into 561 KB of JSON in the Day 1 run.
    responseDataCallback: (Map<String, dynamic>? data) async {
      data?.remove('screenshots');
      await writeResponseData(data);
    },
  );
}
