// loadFonts against a mocked FontManifest, in a file of its own.
//
// FontLoader registers into the engine's font collection for the whole test
// PROCESS, and every walk in walker_test.dart registers the SDK fallback. A
// regression that skips that registration is invisible there; here, in a
// fresh process, the first test is the first to register anything.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ux_demo_app/main.dart';

import '../ux_audit/ux_journey_test.dart'
    show applyDevice, kIphoneSe, loadFonts;

/// Serve a FontManifest.json of [families], and real font bytes for every
/// asset key so FontLoader.load() actually succeeds.
void _mockManifest(WidgetTester tester, List<String> families) {
  final Uint8List ttf = File(
    '${Platform.environment['FLUTTER_ROOT']}'
    '/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
  ).readAsBytesSync();
  rootBundle.clear(); // loadStructuredData caches
  tester.binding.defaultBinaryMessenger.setMockMessageHandler(
    'flutter/assets',
    (ByteData? message) async {
      final String key = utf8.decode(message!.buffer.asUint8List());
      if (key == 'FontManifest.json') {
        return ByteData.sublistView(
          Uint8List.fromList(
            utf8.encode(
              jsonEncode(<Map<String, Object?>>[
                for (final String f in families)
                  <String, Object?>{
                    'family': f,
                    'fonts': <Map<String, Object?>>[
                      <String, Object?>{'asset': 'fonts/$f.ttf'},
                    ],
                  },
              ]),
            ),
          ),
        );
      }
      return ByteData.sublistView(ttf);
    },
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
    rootBundle.clear();
  });
}

void main() {
  // FIRST in the file on purpose — see the header.
  testWidgets('an app font that is not the theme font leaves no Ahem text', (
    WidgetTester tester,
  ) async {
    // One bare family — an icon font, a brand face used on one title — made
    // loadFonts return 'app' early and skip registering the SDK stand-in, so
    // every Text asking for the platform default rendered as em squares.
    // Measured end to end: the title at 242.0 instead of 112.3.
    debugDefaultTargetPlatformOverride = kIphoneSe.targetPlatform;
    applyDevice(tester, kIphoneSe);
    addTearDown(tester.view.reset);
    _mockManifest(tester, <String>['MaterialIcons', 'AppIcons']);

    expect(await loadFonts(tester), 'app');
    await tester.pumpWidget(const UxDemoApp());
    final double title = tester.getSize(find.text('Saved items')).width;
    // A body-style line too: the iOS theme asks CupertinoSystemText for it,
    // a different family from the title's CupertinoSystemDisplay.
    final double body = tester.getSize(find.text('189,000 KRW')).width;
    debugDefaultTargetPlatformOverride = null;
    expect(title, lessThan(150.0), reason: 'Ahem puts it at 242.0');
    expect(body, lessThan(120.0), reason: 'Ahem puts it at 156.75');
  });

  testWidgets('a font from a package answers to its package name', (
    WidgetTester tester,
  ) async {
    // A design-system package's font reaches the manifest as
    // `packages/<pkg>/<Family>`, and that full name is what
    // TextStyle(fontFamily:, package:) asks for. Registered under the bare
    // family, it was never found and the text fell back to Ahem.
    _mockManifest(tester, <String>['packages/brand_ui/Brand']);
    await loadFonts(tester);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Text(
            'Brand text',
            style: TextStyle(
              fontFamily: 'Brand',
              package: 'brand_ui',
              fontSize: 20,
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.text('Brand text')).width,
      lessThan(150.0),
      reason: 'Ahem puts 10 glyphs at 20px at 200.0',
    );
  });
}
