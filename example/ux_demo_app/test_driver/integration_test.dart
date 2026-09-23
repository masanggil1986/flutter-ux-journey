import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final File f = File('screenshots/$name.png');
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
