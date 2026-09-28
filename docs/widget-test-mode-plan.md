# widget-test 모드 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 저니 워크를 디바이스 없이 `flutter test`로 돌릴 수 있게 하고, `flutter drive` 경로는 폴백으로 남긴다.

**Architecture:** 워커(`walkJourney`)가 `integration_test`에 닿는 4지점을 콜백 2개(`shot`, `publish`)와 컨텍스트 맵 1개(`runContext`)로 바꾼다. 워커 파일 하나가 두 엔트리를 섬긴다 — widget-test 엔트리는 워커 파일 자신의 `main()`이고, drive 엔트리는 별도 파일이다. 디바이스가 공급하던 viewport는 저니의 `## Device` 절이, 디바이스가 공급하던 실폰트는 `loadFonts`가 대신한다.

**Tech Stack:** Dart 3.13+ / Flutter 3.47+. `package:flutter_test`, `package:integration_test` (둘 다 SDK 동봉). 서드파티 의존성 0개.

**Spec:** `docs/widget-test-mode.md`

> **실행 후 메모 (2026-09-28).** 이 계획은 완료됐고, 실행 중 내린 판정 다섯 건이 계획을 고쳤다 —
> 워커 위치(`integration_test/` → `ux_audit/`), Task 2의 전제 반증, 폰트 테스트가 재는 표면,
> `FontLoader`의 프로세스 전역성, 디바이스 이름 해석. 어긋나는 부분은 커밋 메시지와
> `docs/widget-test-mode.md`의 정정 블록이 기준이다.

## Global Constraints

- **서드파티 의존성 0개.** SDK 동봉 패키지 외 어떤 것도 `pubspec.yaml`에 추가하지 않는다.
- **이 저장소는 공개 오픈소스다.** 커밋 전 매번: `git diff --cached --name-only`로 파일 목록을 눈으로 보고(바이너리·이미지가 섞였으면 멈춘다), 그다음 `git diff --cached | grep -inE 'token|secret|password|api[_-]?key|bearer|://' | grep -viE 'github\.com|flutter\.dev|dart\.dev|api\.flutter\.dev|docs\.claude\.com|w3\.org'`가 **아무것도 출력하지 않아야** 한다.
- **`*.png` 등 이미지는 커밋하지 않는다.** 이 작업이 만드는 스크린샷은 전부 `ux-audit-out/`(gitignored) 또는 스크래치패드로 간다.
- **사용자 대면 문서(`README.md`, `SKILL.md`, `references/*.md`)는 영어.** 저장소 내부 메모(`docs/*.md`, `CLAUDE.md`)는 한국어 가능.
- **주석은 *why*를 설명한다.** *what*은 코드로 표현한다. 디버그용 `print()`를 남기지 않는다.
- **코드 변경 후 매번:** `cd example/ux_demo_app && dart format . && flutter analyze --no-pub` 그리고 `flutter test`. 정적 룰을 건드렸으면 `cd tools/astprobe && dart test`.
- **커밋 메시지 끝에** `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`
- **기준선:** 작업 시작 시점 `flutter test`는 **72 passed, 1 skipped**다. 어떤 태스크도 이 숫자를 줄이지 않는다.

## Review Focus

스펙이 함의하지만 어느 태스크의 테스트도 건드리지 않는 입력들. 각 줄은 그 코드를 소유한 태스크에 테스트로 들어간다.

1. **`## Device`에 모르는 프리셋 이름** — 조용히 기본값으로 떨어지면 사용자가 요청한 적 없는 화면 크기로 측정한 리포트를 받는다. 알 수 없는 이름은 **던져야** 한다. → Task 3
2. **`FontManifest.json`이 없거나 깨졌다** — `rootBundle.loadStructuredData`가 던지면 워크 전체가 죽는다. 폰트를 못 얻는 것은 fold를 못 믿는 것이지 감사를 못 하는 것이 아니다. → Task 4
3. **`shot` 콜백이 던진다**(디스크 참, 경로 권한) — 스크린샷 한 장이 이미 측정된 스텝 전부를 버리면 안 된다. 그 스텝의 `screenshot`만 null이 되고 워크는 계속된다. → Task 1
4. **`publish`가 던진다** — 모든 측정이 끝난 뒤에 산출물만 날아간다. `publish` 실패는 조용할 수 없다. → Task 1
5. **`## Device` 절이 없는 저니** — 기본값으로 돌되 그 사실이 `conditions`에 남지 않으면, 리포트가 사용자가 선언하지 않은 화면 크기의 fold를 단언한다. → Task 3

---

## File Structure

| 파일 | 책임 |
|---|---|
| `example/ux_demo_app/integration_test/ux_journey_test.dart` | 워커 엔진 + 측정 헬퍼 + **widget-test 엔트리 `main()`**. 감사 대상 앱이 얻는 유일한 파일. |
| `example/ux_demo_app/integration_test/ux_journey_drive.dart` (신규) | drive 엔트리. `IntegrationTestWidgetsFlutterBinding`을 아는 유일한 파일. |
| `example/ux_demo_app/integration_test/gated_journey_test.dart` | 게이트 저니. 새 시그니처에 맞춤. |
| `example/ux_demo_app/test/walker_test.dart` | 헬퍼 단위 테스트. 태스크마다 그룹 추가. |
| `example/ux_demo_app/test/widget_walk_test.dart` (신규) | 전체 워크를 widget test로 돌리고 `example/walk.json`과 대조. |
| `example/ux_demo_app/test/recipe_sync_test.dart` | 레시피↔워커 고정. `reportData ??=` 단언을 drive 엔트리로 옮긴다. |

---

## Task 1: 워커에서 바인딩 분리

**Files:**
- Modify: `example/ux_demo_app/integration_test/ux_journey_test.dart` (14, 69-90, 109-116, 140-147, 160-168, 200-212, 250-262, 292-302)
- Create: `example/ux_demo_app/integration_test/ux_journey_drive.dart`
- Modify: `example/ux_demo_app/integration_test/gated_journey_test.dart` (85-105)
- Modify: `example/ux_demo_app/test/recipe_sync_test.dart` (`_walker` 상수 부근, "the walker keeps the two habits that fail silently")
- Test: `example/ux_demo_app/test/walker_test.dart`

**Interfaces:**
- Consumes: 없음 (첫 태스크)
- Produces:
  - `Future<void> walkJourney(WidgetTester tester, {required void Function() launch, required List<Step> journey, List<Step> setup, List<String> networkCalls, Future<void> Function(String name)? shot, required Future<void> Function(Map<String, Object?> report) publish, Map<String, Object?> runContext})`
  - `const String kWalkerDriveEntry = 'integration_test/ux_journey_drive.dart'` 는 만들지 않는다 — 경로는 `recipe_sync_test.dart`의 상수로만 존재한다.

- [ ] **Step 1: `shot`이 던져도 워크가 계속되는 테스트를 쓴다 (Review Focus 3)**

`walker_test.dart` 맨 끝에 추가:

```dart
  group('walkJourney — the two injection points', () {
    testWidgets('a shot that throws costs that step its image, not the walk', (
      WidgetTester tester,
    ) async {
      Map<String, Object?>? report;
      await walkJourney(
        tester,
        launch: () => runApp(const UxDemoApp()),
        journey: journey,
        shot: (String name) async => throw const FileSystemException('disk full'),
        publish: (Map<String, Object?> r) async => report = r,
      );
      final List<Object?> steps = report!['steps']! as List<Object?>;
      expect(steps, hasLength(journey.length + 1));
      for (final Object? raw in steps) {
        expect((raw! as Map<String, Object?>)['screenshot'], isNull);
      }
      // The measurement is what must survive: a missing PNG is a missing
      // evidence LAYER, not a missing audit.
      expect(
        (steps.first as Map<String, Object?>)['guidelines'],
        hasLength(4),
      );
    });

    testWidgets('no shot at all means every step reports screenshot: null', (
      WidgetTester tester,
    ) async {
      Map<String, Object?>? report;
      await walkJourney(
        tester,
        launch: () => runApp(const UxDemoApp()),
        journey: journey,
        publish: (Map<String, Object?> r) async => report = r,
      );
      for (final Object? raw in report!['steps']! as List<Object?>) {
        expect((raw! as Map<String, Object?>)['screenshot'], isNull);
      }
    });

    testWidgets('shot is called once per step, named for that step', (
      WidgetTester tester,
    ) async {
      final List<String> names = <String>[];
      Map<String, Object?>? report;
      await walkJourney(
        tester,
        launch: () => runApp(const UxDemoApp()),
        journey: journey,
        shot: (String name) async => names.add(name),
        publish: (Map<String, Object?> r) async => report = r,
      );
      expect(names, <String>['step_1', 'step_2', 'step_3', 'step_4']);
      expect(
        ((report!['steps']! as List<Object?>).first
            as Map<String, Object?>)['screenshot'],
        'step_1.png',
      );
    });

    testWidgets('a publish that throws is never swallowed', (
      WidgetTester tester,
    ) async {
      // Review Focus 4: every measurement is already made by the time publish
      // runs, so a swallowed failure here is a green run with no artifact —
      // the one outcome a reader cannot detect.
      await expectLater(
        walkJourney(
          tester,
          launch: () => runApp(const UxDemoApp()),
          journey: journey,
          publish: (Map<String, Object?> r) async =>
              throw const FileSystemException('read-only output dir'),
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    testWidgets('runContext lands in conditions beside the measured ones', (
      WidgetTester tester,
    ) async {
      Map<String, Object?>? report;
      await walkJourney(
        tester,
        launch: () => runApp(const UxDemoApp()),
        journey: journey,
        publish: (Map<String, Object?> r) async => report = r,
        runContext: const <String, Object?>{'mode': 'widget-test'},
      );
      final Map<String, Object?> c =
          report!['conditions']! as Map<String, Object?>;
      expect(c['mode'], 'widget-test');
      expect(c['textScaleFactor'], isNotNull); // the measured ones survive
    });
  });
```

`walker_test.dart`의 import `show` 목록에 `journey`, `walkJourney`를 추가한다. (뒤 태스크들이
같은 목록에 `applyDevice`, `deviceProfileByName`, `deviceProfileLabel`, `kIphoneSe`, `loadFonts`를
더한다 — 각 태스크의 첫 스텝에서.)

- [ ] **Step 2: 실패를 확인한다**

```bash
cd example/ux_demo_app && flutter test test/walker_test.dart --plain-name 'the two injection points'
```
Expected: FAIL — `walkJourney`가 `show` 목록에 없고, 시그니처에 `shot`/`publish`/`runContext`가 없다.

- [ ] **Step 3: 워커 시그니처를 바꾼다**

`ux_journey_test.dart`:

```dart
// 삭제: import 'package:integration_test/integration_test.dart';
// 삭제: final bool _inTestScreenshots = Platform.isIOS;
```

```dart
Future<void> walkJourney(
  WidgetTester tester, {
  required void Function() launch,
  required List<Step> journey,
  List<Step> setup = const <Step>[],
  List<String> networkCalls = const <String>[],
  // null means the VISUAL layer is not assessable on this run — the report
  // must say so rather than leave the section empty. On Android under
  // `flutter drive` this is null because convertFlutterSurfaceToImage() +
  // takeScreenshot() deadlocks on any app hosting a platform view.
  Future<void> Function(String name)? shot,
  // Where the report goes. The drive entry mutates binding.reportData; the
  // widget-test entry writes a file. The walk knows neither.
  required Future<void> Function(Map<String, Object?> report) publish,
  // What the ENTRY knows and the walk cannot measure: which mode, which
  // renderer, which declared device, which fonts.
  Map<String, Object?> runContext = const <String, Object?>{},
}) async {
```

`_inTestScreenshots`를 쓰던 자리를 전부 `shot != null`로 바꾸고, 캡처 자체는 아래 헬퍼를 거친다:

```dart
/// Take one screenshot, or report that it could not be taken.
///
/// A capture that throws — a full disk, an unwritable path, a device-side
/// deadlock that surfaces as an error — costs that step its IMAGE. It must not
/// cost the step its measurements: by the time this runs, the semantics dump
/// and all four guideline evaluations are already in hand.
Future<String?> _capture(
  Future<void> Function(String)? shot,
  String name,
) async {
  if (shot == null) {
    return null;
  }
  try {
    await shot(name);
    return '$name.png';
  } catch (_) {
    return null;
  }
}
```

호출부 4곳:

```dart
// setup 실패 시 (기존 `final bool shot = out.status != 'OK' && _inTestScreenshots;`)
final String? shotName =
    out.status != 'OK' ? await _capture(shot, 'setup_$i') : null;
// (every other entry in this map is unchanged)
'screenshot': shotName,
```

```dart
// 저니 스텝 (기존 `if (_inTestScreenshots) { await binding.takeScreenshot('step_$i'); }`)
final String? shotName = await _capture(shot, 'step_$i');
// (every other entry in this map is unchanged)
'screenshot': shotName,
```

```dart
// outcome 스텝
final String? outcomeShot =
    await _capture(shot, 'step_${steps.length + 1}');
// (every other entry in this map is unchanged)
'screenshot': outcomeShot,
```

`launch()` 직후의 `if (_inTestScreenshots) { await binding.convertFlutterSurfaceToImage(); }` 블록은 **삭제한다** — drive 엔트리의 `shot` 클로저가 첫 호출에 한 번 실행한다.

보고 마무리(기존 `binding.reportData ??=` 블록)를 교체:

```dart
  handle.dispose();
  final Map<String, Object?> report = <String, Object?>{
    'steps': steps,
    'setupSteps': setupSteps,
    'setupFailed': setupFailed,
    'entrySettled': entrySettled,
    'appErrors': appErrors,
    'networkCalls': networkCalls,
    'taps': taps,
    // runContext LAST: an entry may correct something the walk could only
    // guess (platform, above), and a silent disagreement between the two is
    // worse than either value.
    'conditions': <String, Object?>{...conditionsOf(tester), ...runContext},
  };
  // Never swallowed. Every measurement is already made by this point, so a
  // publish that fails silently means a green run with no artifact — the one
  // outcome a reader cannot detect.
  await publish(report);
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

```bash
cd example/ux_demo_app && flutter test test/walker_test.dart --plain-name 'the two injection points'
```
Expected: 5 PASS

- [ ] **Step 5: drive 엔트리 파일을 만든다**

`example/ux_demo_app/integration_test/ux_journey_drive.dart`:

```dart
// The `flutter drive` entry. It exists as a separate file because the binding
// has to be chosen before anything else runs, and
// IntegrationTestWidgetsFlutterBinding is a LIVE binding — under `flutter test`
// it would change the frame policy out from under the walk. The default mode
// is the widget-test one in ux_journey_test.dart; this is the fallback for an
// app whose plugins or platform views need a real device under them.
//
// Run:
//   flutter drive --driver=test_driver/integration_test.dart \
//                 --target=integration_test/ux_journey_drive.dart -d <device-id>

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:ux_demo_app/main.dart' as app;

import 'ux_journey_test.dart' show journey, setup, walkJourney;

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Android deadlocks in convertFlutterSurfaceToImage() + takeScreenshot()
  // whenever the app hosts a platform view (webview, media, camera) — no
  // error, no timeout. Measured twice on a production app. Guidelines and the
  // semantics dump are unaffected, so the walk still measures; the VISUAL
  // layer comes from a host capture (`adb exec-out screencap`) instead.
  bool surfaceReady = false;
  Future<void> shot(String name) async {
    // Lazily, on the first capture: the conversion needs a frame to already
    // exist, and every caller of this is after one.
    if (!surfaceReady) {
      await binding.convertFlutterSurfaceToImage();
      surfaceReady = true;
    }
    await binding.takeScreenshot(name);
  }

  testWidgets('ux journey', (WidgetTester tester) async {
    await walkJourney(
      tester,
      launch: app.main,
      setup: setup,
      journey: journey,
      shot: Platform.isIOS ? shot : null,
      // MUTATE, never replace: takeScreenshot appends each PNG into
      // reportData['screenshots'], and that list is how the driver's
      // onScreenshot gets the bytes. Assigning a fresh map here silently
      // deletes every screenshot and the run still passes.
      publish: (Map<String, Object?> report) async =>
          (binding.reportData ??= <String, dynamic>{}).addAll(report),
      runContext: <String, Object?>{
        'mode': 'drive',
        'renderer': 'device',
        'targetPlatform': Platform.operatingSystem,
      },
    );
  });
}
```

`ux_journey_test.dart`에서 `void main() { ... }`는 이 태스크에서 **지운다** — Task 5가 widget-test 엔트리로 다시 만든다. 그 사이 워커 파일은 라이브러리다.

- [ ] **Step 6: 게이트 저니를 새 시그니처에 맞춘다**

`gated_journey_test.dart`의 `main()`을 교체(위 drive 엔트리와 같은 모양, `launch: app.main`이 `main_gated.dart`를 가리키고 `networkCalls: stubCalls`가 붙는다):

```dart
void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  bool surfaceReady = false;
  Future<void> shot(String name) async {
    if (!surfaceReady) {
      await binding.convertFlutterSurfaceToImage();
      surfaceReady = true;
    }
    await binding.takeScreenshot(name);
  }

  testWidgets('gated ux journey', (WidgetTester tester) async {
    // BEFORE app.main(), which walkJourney calls. The app fires its session
    // probe on the first frame, so an override installed afterwards is already
    // too late — that is the reason walkJourney takes `launch` as a callback
    // instead of launching the app itself.
    HttpOverrides.global = StubHttpOverrides();

    await walkJourney(
      tester,
      launch: app.main,
      setup: setup,
      journey: journey,
      // Wire the stub's own call list into the report. It is not automatic:
      // the walker's `networkCalls` defaults to empty, and an empty field
      // costs the report the one layer that shows which calls the journey
      // depended on.
      networkCalls: stubCalls,
      shot: Platform.isIOS ? shot : null,
      publish: (Map<String, Object?> report) async =>
          (binding.reportData ??= <String, dynamic>{}).addAll(report),
      runContext: <String, Object?>{
        'mode': 'drive',
        'renderer': 'device',
        'targetPlatform': Platform.operatingSystem,
      },
    );
  });
}
```

- [ ] **Step 7: `recipe_sync_test.dart`의 `reportData` 단언을 옮긴다**

상수를 추가하고:

```dart
const String _driveEntry = 'integration_test/ux_journey_drive.dart';
```

`'the walker keeps the two habits that fail silently'` 테스트를 교체:

```dart
  test('the walker keeps the habit that fails silently', () {
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
          'the walk is binding-agnostic; only the drive entry may import '
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
```

- [ ] **Step 8: 전체 스위트를 돌린다**

```bash
cd example/ux_demo_app && dart format . && flutter analyze --no-pub && flutter test
```
Expected: 앞의 5개가 더해져 **77 passed, 1 skipped**. 실패 0.

- [ ] **Step 9: 커밋**

```bash
cd "$(git rev-parse --show-toplevel)"
git add example/ux_demo_app/integration_test/ example/ux_demo_app/test/walker_test.dart example/ux_demo_app/test/recipe_sync_test.dart
git diff --cached --name-only
git diff --cached | grep -inE 'token|secret|password|api[_-]?key|bearer|://' | grep -viE 'github\.com|flutter\.dev|dart\.dev|api\.flutter\.dev|docs\.claude\.com|w3\.org'
git commit -m "$(cat <<'EOF'
Let the walk run without knowing what is under it

The walk touched integration_test in four places: the binding, the surface
conversion, takeScreenshot and reportData. All four were about the device, not
about the journey, so they become two callbacks and a context map. The drive
entry keeps them; the walk no longer imports integration_test at all, which
recipe_sync_test now pins.

A capture that throws costs its step the image and nothing else — every
measurement is already in hand by then. A publish that throws is never
swallowed: it is the only failure a reader of a green run could not detect.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: 두 번째 워크가 매달리는 것을 고친다

probe에서 측정된 것: `flutter test`에서 한 파일에 `walkJourney`를 부르는 테스트를 둘 두면 두 번째가 **매달린다**(6분+ 0% CPU). 하나만 둬도 teardown이 `binding.dart:1912`의 `'_pendingExceptionDetails != null'` assert로 실패한다. 원인은 워커가 `FlutterError.onError`를 교체하고 복원하지 않는 것(`ux_journey_test.dart:126`).

**순진하게 복원하면 이미 측정된 버그가 되살아난다**: 워커가 이걸 가로채는 이유는 워크보다 오래 사는 백그라운드 요청의 늦은 예외가 리포트를 통째로 버리기 때문이다(실측: 9스텝 저니가 날아감).

**Files:**
- Modify: `example/ux_demo_app/integration_test/ux_journey_test.dart` (125-129, 그리고 `handle.dispose()` 부근)
- Test: `example/ux_demo_app/test/walker_test.dart`

**Interfaces:**
- Consumes: Task 1의 `walkJourney(... publish:)`
- Produces: 시그니처 변화 없음. `report['appErrors']`의 의미가 "워크 중 앱이 낸 에러"로 유지된다.

- [ ] **Step 1: 매달림을 재현하는 테스트를 쓴다**

Task 1이 추가한 그룹 안에:

```dart
    testWidgets('a second walk in the same file runs (walk 1 of 2)', (
      WidgetTester tester,
    ) async {
      Map<String, Object?>? report;
      await walkJourney(
        tester,
        launch: () => runApp(const UxDemoApp()),
        journey: journey,
        publish: (Map<String, Object?> r) async => report = r,
      );
      expect(report!['steps'], isNotNull);
    });

    testWidgets('a second walk in the same file runs (walk 2 of 2)', (
      WidgetTester tester,
    ) async {
      Map<String, Object?>? report;
      await walkJourney(
        tester,
        launch: () => runApp(const UxDemoApp()),
        journey: journey,
        publish: (Map<String, Object?> r) async => report = r,
      );
      // If FlutterError.onError is still the first walk's, this test's own
      // failures land in a dead list and the run hangs instead of reporting.
      expect(report!['steps'], isNotNull);
    });

    testWidgets('an app error during the walk is evidence, not a failure', (
      WidgetTester tester,
    ) async {
      Map<String, Object?>? report;
      await walkJourney(
        tester,
        launch: () {
          runApp(const UxDemoApp());
          // What a production app does: a background request that fails while
          // the walk is in flight. Without the walker's interception this
          // fails the test and DISCARDS the whole report — measured, a voucher
          // fetch completing after the walk threw away a nine-step journey.
          FlutterError.reportError(
            FlutterErrorDetails(exception: StateError('late voucher fetch')),
          );
        },
        journey: journey,
        publish: (Map<String, Object?> r) async => report = r,
      );
      expect(
        report!['appErrors'],
        contains(contains('late voucher fetch')),
      );
    });
```

- [ ] **Step 2: 실행해서 어떻게 실패하는지 **관찰**한다**

```bash
cd example/ux_demo_app && timeout 180 flutter test test/walker_test.dart --plain-name 'the two injection points' --reporter expanded 2>&1 | tail -40
```

`timeout`은 macOS에 없다. 대신 `flutter test --timeout 90s`를 쓴다:

```bash
cd example/ux_demo_app && flutter test test/walker_test.dart --plain-name 'the two injection points' --timeout 90s --reporter expanded 2>&1 | tail -40
```

Expected: `walk 2 of 2`가 타임아웃하거나, teardown이 `'_pendingExceptionDetails != null'` assert로 실패한다. **출력의 스택 전체를 기록한다** — 다음 스텝의 판단 근거다.

- [ ] **Step 3: 어떤 에러가 바인딩에 도달하는지 확인한다**

`walkJourney`의 핸들러에 일시적으로 출처를 남기고 한 번만 돌린다(커밋하지 않는다):

```dart
  FlutterError.onError = (FlutterErrorDetails details) {
    appErrors.add(details.exceptionAsString());
    stderr.writeln('WALKER-CAUGHT: ${details.exceptionAsString()}');
  };
```

그리고 `flutter_test/src/binding.dart:1900-1930`을 읽어 `handleUncaughtError`가 어떤 경로로 불리는지 확인한다. 두 가지 중 하나다:

- **(a) zone 레벨 uncaught async error** — `FlutterError.onError`를 거치지 않고 바로 `handleUncaughtError`로 간다. 이 경우 `FlutterError.onError` 복원은 해결책이 아니고, 복원 여부와 무관하게 터진다.
- **(b) 워커가 가로챈 뒤 바인딩이 자기 `_pendingExceptionDetails`를 기대한다** — 이 경우 복원이 해결책이고, 늦은 예외는 아래 (2)로 막는다.

- [ ] **Step 4: 관찰에 따라 고친다**

**(a)라면** — 복원해도 안 고쳐지므로, 워커는 그대로 두고 **엔트리가** 자신의 `testWidgets` 안에서만 가로채도록 범위를 좁힌다:

```dart
// walkJourney 안, 지금 자리
final FlutterExceptionHandler? previousOnError = FlutterError.onError;
FlutterError.onError = (FlutterErrorDetails details) {
  appErrors.add(details.exceptionAsString());
};
```

그리고 `await publish(report);` **바로 앞**에서:

```dart
  // Restored before publish, not in a teardown: the walk is over, every
  // measurement is made, and from here on an error is the test framework's to
  // report. Leaving it replaced makes the NEXT test in the same file swallow
  // its own failures into a dead list and hang — measured.
  FlutterError.onError = previousOnError;
```

**(b)라면** — 같은 코드가 해결책이다. 어느 쪽이든 위 두 조각을 넣고 Step 5로 간다.

- [ ] **Step 5: 세 테스트가 다 통과하는지 확인한다**

```bash
cd example/ux_demo_app && flutter test test/walker_test.dart --plain-name 'the two injection points' --timeout 90s
```
Expected: 8 PASS (Task 1의 5 + 이 태스크의 3), 매달림 없음.

**여기서 `walk 2 of 2`가 여전히 매달리면** — 폴백으로 넘어간다: 두 테스트를 하나로 합치지 **말고**, 이 태스크의 결과를 "widget-test 런은 파일당 워크 1개로 제한된다"로 기록하고 Task 5의 엔트리가 그 제약을 지키도록 한다. `walking.md`에 한 줄을 남긴다:

> A widget-test walk is one `testWidgets` per file. A second walk in the same file hangs — `FlutterError.onError` is replaced for the whole file and the second test's own failures land in the first's dead list. Judge a run by `steps[].status`, never by the exit code.

이 폴백을 택하면 `walk 1 of 2`/`walk 2 of 2` 테스트를 지우고 `an app error during the walk` 하나만 남긴다.

- [ ] **Step 6: 전체 스위트 + 커밋**

```bash
cd example/ux_demo_app && dart format . && flutter analyze --no-pub && flutter test
```
Expected: **80 passed, 1 skipped** (폴백을 택했으면 78 passed).

```bash
cd "$(git rev-parse --show-toplevel)"
git add example/ux_demo_app/integration_test/ux_journey_test.dart example/ux_demo_app/test/walker_test.dart
git diff --cached --name-only
git diff --cached | grep -inE 'token|secret|password|api[_-]?key|bearer|://' | grep -viE 'github\.com|flutter\.dev|dart\.dev|api\.flutter\.dev|docs\.claude\.com|w3\.org'
git commit -m "$(cat <<'EOF'
Give the error handler back before the next walk needs it

The walk replaces FlutterError.onError so that a background request outliving
a step is collected as evidence instead of discarding the report — measured, a
voucher fetch completing after the walk threw away a nine-step journey. Under
`flutter drive` nothing noticed that it never gave the handler back, because
there is one test per file. Under `flutter test` a second walk swallows its own
failures into the first walk's dead list and hangs.

Restored just before publish: by then every measurement is made, and an error
after that point is the framework's to report.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `## Device`와 `applyDevice`

**Files:**
- Modify: `example/ux_demo_app/integration_test/ux_journey_test.dart` (`viewportOf` 위에 추가)
- Modify: `example/journey.md`, `example/journey-gated.md`
- Modify: `example/ux_demo_app/test/recipe_sync_test.dart`
- Test: `example/ux_demo_app/test/walker_test.dart`

**Interfaces:**
- Consumes: Task 1의 `runContext`
- Produces:
  - `typedef DeviceProfile = ({String name, Size physicalSize, double devicePixelRatio, double padTop, double padBottom, TargetPlatform targetPlatform})`
  - `const DeviceProfile kIphoneSe`
  - `DeviceProfile deviceProfileByName(String name)` — 모르는 이름이면 `ArgumentError`를 던진다
  - `void applyDevice(WidgetTester tester, DeviceProfile d)`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
  group('applyDevice — the viewport the device used to supply', () {
    testWidgets('iphone-se reproduces the committed simulator viewport', (
      WidgetTester tester,
    ) async {
      applyDevice(tester, kIphoneSe);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const UxDemoApp());
      final Map<String, Object?> v = viewportOf(tester);
      // These are example/walk.json's own numbers, measured on an iPhone SE
      // (3rd gen) simulator. A preset that does not reproduce them is not a
      // preset, it is a guess.
      expect(v['width'], 375.0);
      expect(v['height'], 667.0);
      expect(v['devicePixelRatio'], 2.0);
      expect(v['contentTop'], 20.0);
      expect(v['padBottom'], 0.0);
      expect(v['foldY'], 667.0);
      expect(v['isTestDefault'], isFalse);
    });

    test('an undeclared device is labelled as one', () {
      // Review Focus 5: running on a default is fine; running on a default that
      // the artifact does not admit to is not. The report's scope clause quotes
      // this string, so the difference has to survive into it.
      expect(deviceProfileLabel(kIphoneSe, declared: true), 'iphone-se');
      expect(
        deviceProfileLabel(kIphoneSe, declared: false),
        'iphone-se (default, not declared)',
      );
    });

    test('an unknown preset name throws instead of quietly substituting one', () {
      // Review Focus 1: falling back would hand the reader a report measured at
      // a screen size they never asked for, with nothing in the artifact
      // saying so.
      expect(
        () => deviceProfileByName('pixel-6'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => deviceProfileByName('iphone-se'),
        returnsNormally,
      );
    });
  });
```

`walker_test.dart`의 `show` 목록에 `applyDevice`, `deviceProfileByName`, `deviceProfileLabel`,
`kIphoneSe`를 추가한다.

- [ ] **Step 2: 실패를 확인한다**

```bash
cd example/ux_demo_app && flutter test test/walker_test.dart --plain-name 'applyDevice'
```
Expected: FAIL — `applyDevice`, `kIphoneSe`, `deviceProfileByName`, `deviceProfileLabel` 미정의.

- [ ] **Step 3: 구현한다**

`ux_journey_test.dart`, `viewportOf` 바로 위:

```dart
/// The screen the walk is measured on.
///
/// Under `flutter drive` the device supplies all of this. Under `flutter test`
/// nothing does — the view is Flutter's hardcoded 800x600 @ 3.0, which is no
/// device — so the journey has to declare it, in `## Device`.
typedef DeviceProfile = ({
  String name,
  Size physicalSize, // physical px, as a real view reports it
  double devicePixelRatio,
  double padTop, // physical px; contentTop = padTop / dpr
  double padBottom,
  TargetPlatform targetPlatform,
});

/// iPhone SE (3rd gen). The ONLY preset that ships, because it is the only one
/// whose every field is reproduced by a committed artifact —
/// `example/walk.json`, measured on that simulator: 375x667 logical, dpr 2.0,
/// contentTop 20.0, padBottom 0.0 (the SE has a home button, so its bottom
/// padding really is zero).
///
/// `pixel-6` and `ipad-13` are NOT here. CLAUDE.md records their size, dpr and
/// foldY, but not their `contentTop`, and inventing a status-bar height is
/// exactly the kind of unmeasured number this tool exists to refuse. They ship
/// after one calibration run each. Until then a journey names explicit numbers.
const DeviceProfile kIphoneSe = (
  name: 'iphone-se',
  physicalSize: Size(750, 1334),
  devicePixelRatio: 2.0,
  padTop: 40.0,
  padBottom: 0.0,
  targetPlatform: TargetPlatform.iOS,
);

/// Resolve a `## Device` preset name.
///
/// Throws on an unknown name rather than substituting a default: a report
/// measured at a screen size nobody asked for, with nothing in the artifact
/// saying so, is worse than no report.
DeviceProfile deviceProfileByName(String name) {
  const Map<String, DeviceProfile> presets = <String, DeviceProfile>{
    'iphone-se': kIphoneSe,
  };
  final DeviceProfile? found = presets[name];
  if (found == null) {
    throw ArgumentError.value(
      name,
      'name',
      'unknown device preset — known: ${presets.keys.join(", ")}. '
          'Declare explicit numbers in `## Device` instead, e.g. '
          '"375x667 @2.0 contentTop 20 padBottom 0".',
    );
  }
  return found;
}

/// How `conditions.deviceProfile` names the screen this run used.
///
/// A run on the fallback is not a problem; a run on the fallback that the
/// artifact does not admit to is, because the report's scope clause would then
/// assert a fold line for a screen nobody chose.
String deviceProfileLabel(DeviceProfile d, {required bool declared}) =>
    declared ? d.name : '${d.name} (default, not declared)';

/// Make the test view look like [d]. The caller owns `tester.view.reset()`.
void applyDevice(WidgetTester tester, DeviceProfile d) {
  tester.view.physicalSize = d.physicalSize;
  tester.view.devicePixelRatio = d.devicePixelRatio;
  final FakeViewPadding pad = FakeViewPadding(
    top: d.padTop,
    bottom: d.padBottom,
  );
  tester.view.padding = pad;
  tester.view.viewPadding = pad;
}
```

- [ ] **Step 4: 통과 확인**

```bash
cd example/ux_demo_app && flutter test test/walker_test.dart --plain-name 'applyDevice'
```
Expected: 3 PASS

- [ ] **Step 5: 저니 파일에 `## Device` 절을 넣는다**

`example/journey.md`의 `## Steps` **앞**에:

```markdown
## Device

`iphone-se` — 375x667 @2.0, the iPhone SE (3rd gen) simulator `example/walk.json`
was measured on.

Under `flutter drive` the device supplies this and the section is ignored. Under
`flutter test` nothing does, so leaving it out makes the walk fall back to
`iphone-se` and record `deviceProfile: "iphone-se (default, not declared)"` — the
report's scope clause quotes that rather than asserting a screen nobody chose.

Only `iphone-se` ships as a preset. For anything else, name the numbers:
`375x667 @2.0 contentTop 20 padBottom 0`.
```

`example/journey-gated.md`의 `## Steps` 앞에도 같은 절을 넣되 본문은 한 줄로:

```markdown
## Device

`iphone-se` — the same screen `journey.md` walks, so the two runs are comparable.
```

- [ ] **Step 6: `recipe_sync_test.dart`에 `## Device` 고정을 추가한다**

```dart
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
```

`recipe_sync_test.dart` 상단의 walker import `show` 목록에 `kIphoneSe`를 추가한다.

- [ ] **Step 7: 전체 스위트 + 커밋**

```bash
cd example/ux_demo_app && dart format . && flutter analyze --no-pub && flutter test
```
Expected: **83 passed, 1 skipped**

```bash
cd "$(git rev-parse --show-toplevel)"
git add example/ux_demo_app/integration_test/ux_journey_test.dart example/ux_demo_app/test/ example/journey.md example/journey-gated.md
git diff --cached --name-only
git diff --cached | grep -inE 'token|secret|password|api[_-]?key|bearer|://' | grep -viE 'github\.com|flutter\.dev|dart\.dev|api\.flutter\.dev|docs\.claude\.com|w3\.org'
git commit -m "$(cat <<'EOF'
Make the journey say which screen it was walked on

Under `flutter drive` the device answered this and nobody had to ask. Under
`flutter test` the view is Flutter's hardcoded 800x600 at dpr 3.0, which is no
device, and the walk would blank every fold column rather than quote a fold for
a phone that does not exist.

One preset ships. iphone-se is the only profile whose every field a committed
artifact reproduces — example/walk.json's 375x667, dpr 2.0, contentTop 20.0,
padBottom 0.0. pixel-6 and ipad-13 have a recorded size and foldY but no
recorded contentTop, and a status-bar height nobody measured is the kind of
number this tool refuses elsewhere. An unknown preset name throws.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `loadFonts`

측정된 것: 기본 `flutter test` 폰트(Ahem)는 글리프가 em 정사각형이라 "Saved items"를 112.3px 대신 242.0px로 만들고, 텍스트 두 덩이가 한 줄씩 더 접혀 상품 리스트 전체가 39px 내려간다 — 시뮬레이터 대비 최대 drift 153.6px. 실폰트를 로드하면 최대 18.9px, 중앙값 0.0px.

그리고 **`FontLoader`는 null family를 바꾸지 못한다**: 로드 후에도 기본 텍스트는 242.0px였고, 이름을 지정한 스타일만 119.7px로 떨어졌다. 테마가 실제로 부르는 이름은 iOS 타겟에서 `CupertinoSystemDisplay`다.

**Files:**
- Modify: `example/ux_demo_app/integration_test/ux_journey_test.dart` (`applyDevice` 아래)
- Test: `example/ux_demo_app/test/walker_test.dart`

**Interfaces:**
- Consumes: Task 3의 `applyDevice`, `kIphoneSe`
- Produces: `Future<String> loadFonts(WidgetTester tester)` → `'app'` | `'sdk-fallback'` | `'none'`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

```dart
  group('loadFonts — the metrics the device used to supply', () {
    testWidgets('the fixture declares no font, so the SDK one stands in', (
      WidgetTester tester,
    ) async {
      expect(await loadFonts(tester), 'sdk-fallback');
    });

    testWidgets('a loaded font gives text its real width back', (
      WidgetTester tester,
    ) async {
      // Ahem draws every glyph as an em square, so an 11-character title at
      // 22px measures 242.0. The simulator measured the same title at 112.3.
      Future<double> widthOfTitle() async {
        await tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: Text('Saved items', style: TextStyle(fontSize: 22)),
            ),
          ),
        );
        return tester.getSize(find.text('Saved items')).width;
      }

      expect(await widthOfTitle(), 242.0);
      await loadFonts(tester);
      final double after = await widthOfTitle();
      expect(
        after,
        lessThan(150.0),
        reason:
            'still an em-square width — the font was registered under a family '
            'the theme does not ask for, which fails silently',
      );
    });

    testWidgets('a broken FontManifest costs the fold, never the walk', (
      WidgetTester tester,
    ) async {
      // Review Focus 2: rootBundle.loadStructuredData throws on unparseable
      // JSON. A run that cannot measure text metrics still measures tap
      // targets, contrast, labels and every step outcome.
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        (ByteData? message) async =>
            ByteData.sublistView(Uint8List.fromList('{ not json'.codeUnits)),
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
          'flutter/assets',
          null,
        ),
      );
      expect(await loadFonts(tester), anyOf('sdk-fallback', 'none'));
    });
  });
```

`walker_test.dart` 상단에 `import 'dart:typed_data';`를, `show` 목록에 `loadFonts`를 추가한다.

- [ ] **Step 2: 실패를 확인한다**

```bash
cd example/ux_demo_app && flutter test test/walker_test.dart --plain-name 'loadFonts'
```
Expected: FAIL — `loadFonts` 미정의.

- [ ] **Step 3: 구현한다**

`ux_journey_test.dart`에 import를 추가:

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
```

`applyDevice` 아래:

```dart
/// Give the run real text metrics, and say where they came from.
///
/// `flutter test` renders every glyph as an em square (the "Ahem" test font),
/// which is not a cosmetic problem: measured against the simulator baseline,
/// the fixture's title went 112.3px -> 242.0px, two text blocks wrapped to an
/// extra line each, and the whole product list moved down 39px. Max drift
/// 153.6px. With a real font loaded: max 18.9px, median 0.0px.
///
/// Returns what the report must disclose:
/// - `'app'`         the app's own fonts, from its asset bundle. Exact.
/// - `'sdk-fallback'` the SDK's Roboto standing in for the platform default.
///                    Close, not exact — the placement caveat applies.
/// - `'none'`        neither was available; fold and placement are NOT
///                    assessable and the report says so.
///
/// Call this BEFORE `walkJourney`: the first frame already lays text out.
Future<String> loadFonts(WidgetTester tester) async {
  int appFamilies = 0;
  await tester.runAsync(() async {
    try {
      final Object? manifest = await rootBundle.loadStructuredData<Object?>(
        'FontManifest.json',
        (String s) async => jsonDecode(s),
      );
      for (final Map<String, Object?> font
          in (manifest! as List<Object?>).cast<Map<String, Object?>>()) {
        // A packaged font is declared as `packages/<pkg>/<family>`, but that is
        // not the name a TextStyle asks for.
        final String family = (font['family']! as String).split('/').last;
        final FontLoader loader = FontLoader(family);
        for (final Map<String, Object?> asset
            in (font['fonts']! as List<Object?>).cast<Map<String, Object?>>()) {
          loader.addFont(rootBundle.load(asset['asset']! as String));
        }
        await loader.load();
        // MaterialIcons rides in on `uses-material-design: true` and is not
        // the app declaring a typeface — without this, every Material app
        // would report 'app' and skip the fallback its TEXT still needs.
        if (family != 'MaterialIcons') {
          appFamilies++;
        }
      }
    } catch (_) {
      // No manifest, or an unreadable one. Not being able to measure text
      // metrics is a missing evidence layer, not a reason to abandon the walk.
    }
  });
  if (appFamilies > 0) {
    return 'app';
  }

  // A null fontFamily resolves to the test font no matter what is loaded —
  // measured: after loading, the default width was still 242.0 and only a
  // NAMED style dropped to 119.7. So register over the families the themes
  // actually name. Modern Flutter asks for CupertinoSystemDisplay/Text on iOS
  // and Roboto on Android; the old `.SF UI *` names are silently never used.
  final String? root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    return 'none';
  }
  final File regular = File(
    '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
  );
  if (!regular.existsSync()) {
    return 'none';
  }
  final Uint8List bytes = regular.readAsBytesSync();
  await tester.runAsync(() async {
    for (final String family in <String>[
      'Roboto',
      'CupertinoSystemDisplay',
      'CupertinoSystemText',
    ]) {
      final FontLoader loader = FontLoader(family)
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });
  return 'sdk-fallback';
}
```

- [ ] **Step 4: 통과 확인**

```bash
cd example/ux_demo_app && flutter test test/walker_test.dart --plain-name 'loadFonts'
```
Expected: 3 PASS

- [ ] **Step 5: 전체 스위트 + 커밋**

```bash
cd example/ux_demo_app && dart format . && flutter analyze --no-pub && flutter test
```
Expected: **86 passed, 1 skipped**

```bash
cd "$(git rev-parse --show-toplevel)"
git add example/ux_demo_app/integration_test/ux_journey_test.dart example/ux_demo_app/test/walker_test.dart
git diff --cached --name-only
git diff --cached | grep -inE 'token|secret|password|api[_-]?key|bearer|://' | grep -viE 'github\.com|flutter\.dev|dart\.dev|api\.flutter\.dev|docs\.claude\.com|w3\.org'
git commit -m "$(cat <<'EOF'
Give the headless run real text metrics, and name which ones it got

`flutter test` draws every glyph as an em square. That moved the fixture's
title from 112.3px to 242.0px, wrapped two text blocks to an extra line each,
and pushed the whole product list down 39px — 153.6px of drift against the
simulator baseline. A real font brings that to a median of 0.0px.

Loading one is not enough on its own: a null fontFamily keeps resolving to the
test font whatever is registered, so this registers over the families the
themes actually name. The old `.SF UI Text` spelling is never asked for and
fails silently, which is how the first attempt at this measured identical to
no attempt at all.

The return value is disclosure, not a status code: 'app' is exact,
'sdk-fallback' earns the placement caveat, 'none' makes fold not assessable.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: widget-test 엔트리와 시뮬레이터 베이스라인 자동 대조

**Files:**
- Modify: `example/ux_demo_app/integration_test/ux_journey_test.dart` (`main()` 복원)
- Create: `example/ux_demo_app/test/widget_walk_test.dart`
- Test: 위 신규 파일 자신

**Interfaces:**
- Consumes: `walkJourney`(T1), `applyDevice`/`kIphoneSe`/`deviceProfileByName`(T3), `loadFonts`(T4)
- Produces: `Future<void> writePng(WidgetTester tester, String path)`

- [ ] **Step 1: 베이스라인 대조 테스트를 쓴다**

`example/ux_demo_app/test/widget_walk_test.dart`:

```dart
// The walk, run with no device, checked against the run that had one.
//
// example/walk.json was measured on an iPhone SE (3rd gen) simulator. This
// reproduces its conditions under `flutter test` and asserts the things that
// must not move: what each step did, which screen it was on, and what the four
// guidelines decided. Rects are deliberately NOT compared — the fallback font
// is Roboto where the simulator had SF, and the contrast RATIO is not compared
// either, because the headless rasterizer reports 1.36 where the device
// reported 1.03 on the same node. Both are disclosed in `conditions`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ux_demo_app/main.dart' as app;

import '../integration_test/ux_journey_test.dart'
    show applyDevice, journey, kIphoneSe, loadFonts, walkJourney;

const String _baseline = '../walk.json';

void main() {
  testWidgets('the headless walk decides what the simulator walk decided', (
    WidgetTester tester,
  ) async {
    final File file = File(_baseline);
    if (!file.existsSync()) {
      markTestSkipped('$_baseline not present — running outside the repo');
      return;
    }
    final Map<String, Object?> sim =
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

    debugDefaultTargetPlatformOverride = kIphoneSe.targetPlatform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    applyDevice(tester, kIphoneSe);
    addTearDown(tester.view.reset);
    final String fontSource = await loadFonts(tester);

    Map<String, Object?>? here;
    await walkJourney(
      tester,
      launch: app.main,
      journey: journey,
      publish: (Map<String, Object?> r) async => here = r,
      runContext: <String, Object?>{
        'mode': 'widget-test',
        'fontSource': fontSource,
      },
    );

    final List<Object?> a = sim['steps']! as List<Object?>;
    final List<Object?> b = here!['steps']! as List<Object?>;
    expect(b, hasLength(a.length));

    for (int i = 0; i < a.length; i++) {
      final Map<String, Object?> x = a[i]! as Map<String, Object?>;
      final Map<String, Object?> y = b[i]! as Map<String, Object?>;
      final String at = 'step ${i + 1} (${x['action']} ${x['target']})';

      // The oracle. If this moves, the headless walk is auditing a different
      // app than the simulator walk did.
      expect(y['status'], x['status'], reason: '$at: status');
      // Screen identity is built from labels, not geometry, so it survives the
      // font substitution — and if it did not, every state-loss and dead-tap
      // check would be reading a different screen.
      expect(y['screenSig'], x['screenSig'], reason: '$at: screenSig');

      final List<Object?> gx = x['guidelines']! as List<Object?>;
      final List<Object?> gy = y['guidelines']! as List<Object?>;
      for (int g = 0; g < gx.length; g++) {
        final Map<String, Object?> gxm = gx[g]! as Map<String, Object?>;
        final Map<String, Object?> gym = gy[g]! as Map<String, Object?>;
        expect(gym['guideline'], gxm['guideline'], reason: '$at: guideline $g');
        expect(
          gym['passed'],
          gxm['passed'],
          reason: '$at: ${gxm['guideline']} changed its verdict',
        );
      }

      final List<Object?> nx =
          (x['semantics']! as Map<String, Object?>)['nodes']! as List<Object?>;
      final List<Object?> ny =
          (y['semantics']! as Map<String, Object?>)['nodes']! as List<Object?>;
      expect(ny, hasLength(nx.length), reason: '$at: semantics node count');
    }

    expect(here!['taps'], sim['taps']);
    expect(here!['entrySettled'], sim['entrySettled']);

    final Map<String, Object?> vx =
        (a.first! as Map<String, Object?>)['semantics']! as Map<String, Object?>;
    final Map<String, Object?> vy =
        (b.first! as Map<String, Object?>)['semantics']! as Map<String, Object?>;
    expect(vy['viewport'], vx['viewport']);

    // The run must disclose that it was not the simulator's.
    final Map<String, Object?> c = here!['conditions']! as Map<String, Object?>;
    expect(c['mode'], 'widget-test');
    expect(c['fontSource'], isNotNull);
  });
}
```

- [ ] **Step 2: 실패를 확인한다**

```bash
cd example/ux_demo_app && flutter test test/widget_walk_test.dart --timeout 90s
```
Expected: FAIL — `walker_test.dart`가 아직 `writePng`를 안 쓰므로 여기는 통과할 수도 있다. 통과하면 그대로 Step 3으로 간다(이 테스트는 대조가 목적이지 TDD 구동이 아니다). 실패하면 실패 메시지가 정확히 어떤 필드가 어긋났는지 말해준다 — 그걸 고친다.

- [ ] **Step 3: `writePng`와 widget-test 엔트리를 만든다**

`ux_journey_test.dart`에 import 추가:

```dart
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
```

`loadFonts` 아래:

```dart
/// One screenshot, with no device under it.
///
/// This is the path golden files take (`OffsetLayer.toImage`), so it needs no
/// platform surface — which is also why it cannot deadlock the way
/// `convertFlutterSurfaceToImage()` + `takeScreenshot()` does on Android when
/// the app hosts a platform view. Platform views themselves do not render
/// here; that area comes out blank and the report says `not assessable`.
///
/// `runAsync` is required: `toImage` is real async work and the test binding's
/// fake clock would never complete it.
Future<void> writePng(WidgetTester tester, String path) async {
  final RenderView rv = tester.binding.renderViews.first;
  final OffsetLayer layer = rv.debugLayer! as OffsetLayer;
  ByteData? data;
  await tester.runAsync(() async {
    final ui.Image img = await layer.toImage(rv.paintBounds);
    data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
  });
  if (data == null) {
    return;
  }
  final File f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(data!.buffer.asUint8List());
}
```

그리고 파일의 `setup` const 아래에 `## Device`에서 생성되는 상수와 엔트리:

```dart
/// `## Device` — the screen this journey declares. Generated from the journey
/// file; `example/journey.md` names `iphone-se`.
const DeviceProfile device = kIphoneSe;

/// True when the journey file had no `## Device` and this is the fallback. The
/// report's scope clause quotes it, so a reader can tell a chosen screen from
/// an assumed one.
const bool deviceDeclared = true;

/// One output root, the one SKILL.md declares. Never `screenshots/`, which is a
/// conventionally TRACKED directory in a Flutter app and not ours to claim.
const String outDir = 'ux-audit-out';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ux journey', (WidgetTester tester) async {
    // This fixture has no backend, so no network stub is installed and
    // `networkCalls` stays empty. `flutter test` already refuses every request
    // with a 400 (flutter_test installs its own HttpOverrides), so the default
    // posture — network cut, arbitrary data — costs nothing here. A real app
    // that has to walk past a gate installs a stub; see
    // references/network-stub.md and integration_test/gated_journey_test.dart.
    debugDefaultTargetPlatformOverride = device.targetPlatform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    applyDevice(tester, device);
    addTearDown(tester.view.reset);
    final String fontSource = await loadFonts(tester);

    await walkJourney(
      tester,
      launch: app.main,
      setup: setup,
      journey: journey,
      shot: (String name) => writePng(tester, '$outDir/screens/$name.png'),
      publish: (Map<String, Object?> report) async =>
          File('$outDir/walk.json')
            ..parent.createSync(recursive: true)
            ..writeAsStringSync(jsonEncode(report)),
      runContext: <String, Object?>{
        'mode': 'widget-test',
        // The contrast guideline reads back rasterized pixels, and this
        // rasterizer is not the device's: measured, the same node came out at
        // 1.36 here and 1.03 on the simulator. Same verdict there; a value near
        // 4.5 could go either way, which is why walking.md already says to
        // treat the guideline's NODE as the signal and its ratio as advisory.
        'renderer': 'flutter_tester (software)',
        // NOT conditions.platform, which correctly reads the host (`macos`):
        // this is what the framework was told to be, and the two differ.
        'targetPlatform': device.targetPlatform.name,
        'deviceProfile': deviceProfileLabel(device, declared: deviceDeclared),
        'fontSource': fontSource,
      },
    );
  });
}
```

- [ ] **Step 4: 대조 테스트를 돌린다**

```bash
cd example/ux_demo_app && flutter test test/widget_walk_test.dart --timeout 90s
```
Expected: PASS. 실패하면 메시지가 어긋난 스텝·필드를 정확히 말한다.

- [ ] **Step 5: 엔트리를 실제로 돌려 산출물을 확인한다**

```bash
cd example/ux_demo_app && flutter test integration_test/ux_journey_test.dart --timeout 90s
ls -la ux-audit-out/ ux-audit-out/screens/
python3 -c "
import json; w=json.load(open('ux-audit-out/walk.json'))
print('steps', [s['status'] for s in w['steps']])
print('conditions', json.dumps(w['conditions'], indent=1))
"
```
Expected: `ux-audit-out/walk.json` + `screens/step_1..4.png`(각 750x1334), 스텝 상태 `OK/FAILED/FAILED/OK`, `conditions.mode == 'widget-test'`.

**`ux-audit-out/`는 gitignored다 — 커밋하지 않는다.** 확인 후 `rm -rf ux-audit-out`.

- [ ] **Step 6: 전체 스위트 + 커밋**

```bash
cd example/ux_demo_app && rm -rf ux-audit-out && dart format . && flutter analyze --no-pub && flutter test
```
Expected: **87 passed, 1 skipped**

```bash
cd "$(git rev-parse --show-toplevel)"
git status --porcelain   # ux-audit-out/ 가 보이면 멈춘다
git add example/ux_demo_app/integration_test/ux_journey_test.dart example/ux_demo_app/test/widget_walk_test.dart
git diff --cached --name-only
git diff --cached | grep -inE 'token|secret|password|api[_-]?key|bearer|://' | grep -viE 'github\.com|flutter\.dev|dart\.dev|api\.flutter\.dev|docs\.claude\.com|w3\.org'
git commit -m "$(cat <<'EOF'
Check the walk with no device against the walk that had one

example/walk.json has been a committed artifact with nothing reading it: the
golden diff needed a device, so it skipped. The headless walk can run anywhere,
so now it runs in the suite and is checked against that baseline — every step
status, every screen signature, all sixteen guideline verdicts, the node counts
and the viewport.

What is deliberately not compared: rects, because the fallback font is Roboto
where the simulator had SF, and the contrast ratio, because this rasterizer
reported 1.36 where the device reported 1.03 on the same node. Both conditions
are recorded in the artifact instead of being quietly averaged away.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: 문서

**Files:**
- Modify: `skills/flutter-ux-journey/SKILL.md` (frontmatter, `## Output location`, `## [2] WALK`, `### 1. Offline + arbitrary data`)
- Modify: `skills/flutter-ux-journey/references/walking.md` (제목 아래 전제, `## Prerequisites`, `## Running it and collecting the artifacts`, fold 문단, 대비 캐비앗)
- Modify: `skills/flutter-ux-journey/references/report-format.md` (scope 절)
- Modify: `README.md`, `CLAUDE.md`
- Test: `example/ux_demo_app/test/recipe_sync_test.dart` (이미 walking.md↔워커를 고정하고 있다)

**Interfaces:**
- Consumes: 앞의 다섯 태스크 전부
- Produces: 없음 (문서)

- [ ] **Step 1: `SKILL.md` frontmatter의 `compatibility`를 고친다**

기존의 "Also a booted iOS simulator or Android emulator with the app buildable on it." 이하를 교체:

```
No device is required for the default mode: the walk runs under `flutter test`, which measures
every tap-target rect, contrast ratio and semantics label the device run measures — verified
against a committed simulator baseline — and captures its own screenshots. Two caveats it
records in the artifact: text metrics come from the app's own fonts when it declares any and
from the SDK's Roboto otherwise, and the headless rasterizer's contrast ratios differ from a
device's by a small margin, so treat a value near the threshold as advisory. An app whose
plugins or platform views need a real device under them falls back to `flutter drive` on a
booted iOS simulator or Android emulator; there, screenshots are iOS-only. Real devices are
untested.
```

- [ ] **Step 2: `SKILL.md`의 `## Output location`을 고친다**

gitignore 블록을 교체:

```
ux-audit-out/
integration_test/ux_journey_test.dart
integration_test/ux_journey_drive.dart
integration_test/net_stub.dart
test_driver/integration_test.dart
```

그리고 그 아래 산문의 "Those four are everything a run writes into the app."를:

```
The default mode writes ONE of those into the app — `ux_journey_test.dart` — plus `net_stub.dart`
when the journey has a gate to walk past. The other two exist only when the run falls back to
`flutter drive`. `net_stub.dart` matters most of the five: it is the only generated file that
holds the app's real endpoints and real response bodies.
```

- [ ] **Step 3: `SKILL.md`의 `## [2] WALK`를 두 경로로 고친다**

"Summary of what happens:" 단락 이후의 실행 블록을 교체:

```
Default — no device:

```bash
flutter test integration_test/ux_journey_test.dart
```

The walk writes `ux-audit-out/walk.json` and `ux-audit-out/screens/step_*.png` itself; there is
nothing to copy afterwards. The journey's `## Device` section supplies the screen, because
nothing else does — leave it out and the walk falls back to `iphone-se` and records that it was
not declared.

Fallback — the app needs a real device under it (plugins that throw `MissingPluginException`,
platform views that must actually render):

```bash
flutter drive --driver=test_driver/integration_test.dart \
              --target=integration_test/ux_journey_drive.dart -d <device-id>
```

then copy `build/integration_response_data.json` into the output dir as `walk.json`. The PNGs are
already there: the driver writes them straight to `ux-audit-out/screens/`.

**Neither mode's exit code is the oracle.** Judge the run by `walk.json`'s `steps[].status`.
```

- [ ] **Step 4: `SKILL.md`의 airplane-mode 안내에 단서를 단다**

`### 1. Offline + arbitrary data` 의 bash 블록 바로 위에 추가:

```
In the default mode this needs no command at all: `flutter test` installs its own
`HttpOverrides` and answers every request with an empty 400, so nothing leaves the host and
there is no device setting to put back. The commands below are for the `flutter drive` fallback.
```

- [ ] **Step 5: `walking.md`를 고친다**

(a) 파일 두 번째 줄의 전제를 교체:

```
Every API call below was executed — the measurements against an iOS simulator (iPhone SE 3rd gen,
iOS 18.6, Flutter 3.47.2 stable), and the headless path under `flutter test` on the same fixture,
checked against that simulator run. Signatures are verbatim from the SDK. Do not substitute
remembered ones.
```

(b) `## Prerequisites in the audited app`의 yaml에 단서를 단다:

```
`integration_test` is only needed for the `flutter drive` fallback. The default mode needs
`flutter_test` alone.
```

(c) fold 문단(`**The fold.**`)의 "And in a plain `flutter test` the view is Flutter's hardcoded
`Size(800, 600)` ..." 문장 뒤에 추가:

```
That is why the default mode does not leave the view alone: `applyDevice` sets it from the
journey's `## Device` section, and `iphone-se` is defined to reproduce `example/walk.json`'s own
numbers exactly — 375.0 x 667.0 @ 2.0, contentTop 20.0, padBottom 0.0, foldY 667.0. An unknown
preset name throws rather than substituting a default, because a report measured at a screen
nobody asked for says nothing about where that screen's fold is.
```

(d) 파일 끝의 대비 캐비앗을 확장:

```
One caveat for step 4: `MinimumTextContrastGuideline` partitions foreground/background naively and
picked a nearby button's colour in the verification run while still flagging the correct node.
Treat its **node** as the signal and its **ratio** as advisory. That holds twice over in the
default mode: the guideline reads back rasterized pixels, and the headless rasterizer is not the
device's — measured on the same node, 1.36 under `flutter test` against 1.03 on the simulator.
Same verdict both times, but a ratio near 4.5 could land either side. `conditions.renderer` says
which one produced the number.
```

(e) `## Running it and collecting the artifacts`를 두 모드로 다시 쓴다 — Step 3의 SKILL.md 본문과 같은 내용에, 산출물 경로 설명을 모드별로 붙인다. 기존의 "Plain `flutter test integration_test/...` does **not** write the JSON — only stdout. It must be `flutter drive`." 문장은 **삭제한다** — 그 문장은 워커가 `binding.reportData`에만 쓰던 시절의 사실이고, 이제 widget-test 엔트리가 파일을 직접 쓴다.

(f) 스크린샷 데드락 절의 제목 아래에 한 줄 추가:

```
This is the drive path's problem alone. The default mode captures through
`OffsetLayer.toImage()` — the path golden files take — which needs no platform surface and cannot
deadlock. What it cannot do is render a platform view at all: that area comes out blank, and the
report says `not assessable` for it rather than describing an empty rectangle.
```

- [ ] **Step 6: `report-format.md`의 scope 절을 고친다**

scope 절이 인용해야 하는 필드 목록에 추가:

```
- `conditions.mode` — `widget-test` (no device) or `drive` (on a device)
- `conditions.deviceProfile` — the screen the journey declared, or `<name> (default, not declared)`
- `conditions.fontSource` — `app` (exact), `sdk-fallback` (placement numbers are close, not exact),
  or `none` (fold and placement are **not assessable**)
- `conditions.renderer` — which rasterizer produced the contrast ratios
```

- [ ] **Step 7: `README.md`에서 시뮬레이터 요구를 걷어낸다**

포지셔닝 문장("measures instead of guessing")은 **그대로 둔다** — 이 변경은 그 주장을 강화하지
약화하지 않는다. 고쳐야 할 자리는 `grep -n -i "simulator|emulator|flutter drive|booted" README.md`가
전부 찾아준다. 그중 **문장의 뜻이 바뀌는 여섯 곳**은 아래대로 고친다.

**(a) L19 배너 첫 줄** — 현재 `> **Platform, stated up front: simulators and emulators only, and
screenshots differ per platform.**` 를 교체:

```markdown
> **Platform, stated up front: no device needed by default; a simulator or emulator is the fallback.**
> The default walk runs under `flutter test` and was checked against the simulator run committed in
> `example/walk.json` — same step outcomes, same screen signatures, same sixteen guideline verdicts.
> Two things it cannot borrow from a device, and records instead of hiding: text metrics come from
> the app's own fonts when it declares any and from the SDK's Roboto otherwise, and contrast ratios
> come from a software rasterizer that differs from a device's by a small margin.
```

L20-21의 "The pipeline was built and run end to end on ..." 문장은 **그대로 둔다** — 그 실행들은
정말 일어났고, 이제 그 위에 헤드리스 경로가 얹힌 것이다. 다만 문장 끝에 한 절을 덧붙인다:
`, and the headless path was checked against the first of those runs.`

**(b) L33** — `> **Real devices are not verified and are not claimed.**` 는 **그대로 둔다.**

**(c) L70-75 Requirements** — `- **Xcode** for iOS simulators, or the **Android SDK** for
emulators.` 로 시작하는 두 항목과 그 bash 블록을 다음으로 교체:

```markdown
- Nothing else for the default mode. The walk runs under `flutter test`.
- **Only for the `flutter drive` fallback** (an app whose plugins or platform views need a real
  device under them): **Xcode** for iOS simulators or the **Android SDK** for emulators, a **booted**
  one, and its device id:

  ```bash
  open -a Simulator && flutter devices                           # iOS
  flutter emulators --launch <emulator-id> && flutter devices    # Android
  ```
```

**(d) L96-108 Quickstart** — `open -a Simulator && flutter devices` 와 그 뒤 `flutter drive` 블록을
교체:

```bash
flutter test integration_test/ux_journey_test.dart
```

바로 뒤 문단의 비용 수치(`about **70 s** the first time`)는 시뮬레이터 런의 것이므로, 헤드리스
런의 실측으로 바꾼다 — Task 5 Step 5에서 잰 시간을 여기에 적는다. 재지 않았으면 `time` 을 붙여
한 번 재고 그 숫자를 쓴다. **기억이나 추정으로 쓰지 않는다.**

L108의 `And \`flutter drive\` **exits 0 either way** — the exit code is not the oracle.` 는
`Neither mode's exit code is the oracle.` 로 고친다.

**(e) L195-197 파이프라인 표** — `0. preflight     confirm the parsed goal + steps before touching a
simulator` → `... before running anything`, 그리고 `2. walk          a generated integration_test,
run with \`flutter drive\`` → `2. walk          a generated test, run with \`flutter test\`
(\`flutter drive\` as fallback)`.

**(f) L268-273 한계 절** — `- **Real devices.** Simulators and emulators only in v0.1 ...` 항목의
"an app whose native SDKs drop the simulator slice cannot be built for the iOS simulator at all"
이하는 **fallback 경로에만** 해당하므로 그렇게 한정한다. L272의 `- **Anything on screen, if you are
not on macOS.**` 항목은 기본 모드에선 해당 없으므로 첫 문장을 교체:

```markdown
- **Anything on screen, if you are not on macOS — only in the `flutter drive` fallback.** iOS
  simulators need macOS, so there the Android emulator is the only target and the walk records
  `screenshot: null` on every step. The default mode captures its own screenshots on any host.
```

**(g) L387 트러블슈팅 표** — `build/integration_response_data.json` 을 `walk.json` 으로 고치고,
행 제목을 `The run exited 0 but steps failed` 로 일반화한다.

- [ ] **Step 8: `CLAUDE.md`를 갱신한다**

- `## 현재 상태`: 기본 실행 경로가 `flutter test`임을 한 문단으로.
- `## 닫힌 갭`에 추가: 시뮬레이터 의존, Android 스크린샷 데드락(기본 모드에선 해당 없음), 골든 자동 대조(`widget_walk_test.dart`).
- `## 여전히 미검증`에 추가: 플러그인 있는 실제 앱에서의 widget-test 모드, 플랫폼 뷰, Android 타겟 widget-test 런, `pixel-6`/`ipad-13` 프리셋 캘리브레이션.
- `## 검증` 절 L220의 `(48종)` 을 `flutter test` 가 실제로 출력하는 숫자로 고친다. 그 줄은 현재:

  ```
  - 워커·픽스처를 건드렸으면 `cd example/ux_demo_app && flutter test` (48종), 정적 룰을 건드렸으면
  ```

  실행해서 나온 수를 쓴다 — 계획이 예상한 87이 아니라 **그때 실제로 출력된 수**를 쓴다.

- [ ] **Step 9: 문서가 가리키는 것이 실재하는지 확인한다**

```bash
cd "$(git rev-parse --show-toplevel)"
grep -rn "ux_journey_drive.dart\|integration_test/ux_journey_test.dart" skills/ README.md | head -20
ls example/ux_demo_app/integration_test/
cd example/ux_demo_app && flutter test
```
Expected: 문서가 언급하는 모든 경로가 존재하고, **87 passed, 1 skipped**.

- [ ] **Step 10: 커밋**

```bash
cd "$(git rev-parse --show-toplevel)"
git add skills/ README.md CLAUDE.md
git diff --cached --name-only
git diff --cached | grep -inE 'token|secret|password|api[_-]?key|bearer|://' | grep -viE 'github\.com|flutter\.dev|dart\.dev|api\.flutter\.dev|docs\.claude\.com|w3\.org'
git commit -m "$(cat <<'EOF'
Stop telling people they need a device

The frontmatter asked for a booted simulator or emulator, which was the single
largest thing between this skill and someone trying it. The default is now
`flutter test`, and the document says what that costs: text metrics from the
SDK's font when the app declares none, and a contrast ratio from a rasterizer
that is not the device's. Both are recorded per run, so the report quotes them
rather than asserting a scope.

walking.md loses the line saying plain `flutter test` cannot write the JSON.
That was true while the walk only ever filled binding.reportData; the
widget-test entry writes the file itself.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## 완료 기준

1. `cd example/ux_demo_app && flutter test` → **87 passed, 1 skipped** (남는 skip은 `golden_diff_test.dart`의 drive 전용 절반)
2. `cd example/ux_demo_app && flutter test integration_test/ux_journey_test.dart` → 디바이스 없이 `ux-audit-out/walk.json` + PNG 4장
3. `cd tools/astprobe && dart test` → 7 passed (건드리지 않았으므로 불변)
4. `dart format` 차이 없음, `flutter analyze --no-pub` 경고 0
5. `git status --porcelain`에 `ux-audit-out/`·`*.png`가 없다

## 이 계획이 하지 않는 것

- **라우트 그래프 정적 룰.** 독립 작업이다.
- **`pixel-6` / `ipad-13` 프리셋.** 각 1회 캘리브레이션 런으로 `contentTop`을 실측한 뒤 별도로 승격한다.
- **플러그인 있는 앱의 검증.** `allMessagesHandler` catch-all은 SDK 소스로만 확인했다. 이것이 `flutter drive` 경로를 남기는 주된 이유다.
