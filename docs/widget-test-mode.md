# widget-test 모드 — 시뮬레이터 없이 측정하기 (설계)

> 2026-09-28. 이 문서는 구현 **전**의 설계다. 구현이 끝나면 확정 사항은 `CLAUDE.md`로 올라가고
> 이 문서는 근거 기록으로 남는다.

## 결론

저니 워크를 `flutter drive` + `integration_test` 대신 **plain `flutter test`**로 돌린다.
디바이스가 필요 없어지는데 **측정은 하나도 잃지 않는다** — 실측으로 확인했다.

`flutter drive` 경로는 지운다가 아니라 **남긴다**. 플러그인·플랫폼 뷰가 무거운 앱의 폴백이고,
이미 검증된 자산이다. 워커는 한 파일로 두 모드를 다 섬긴다.

## 왜 — probe 실측 (2026-09-28)

데모 픽스처를 `flutter test`로 걷고, 커밋된 시뮬레이터 실측(`example/walk.json`,
iPhone SE 375x667@2.0, iOS 18.6)과 diff했다.

### 동일한 것

| | 시뮬레이터 | widget test |
|---|---|---|
| 스텝 상태 | OK / FAILED / FAILED / OK | 동일 |
| `screenSig` | a9582ba2 / 4ddc18db / 3afe0168 / 3afe0168 | **바이트 동일** |
| 가이드라인 판정 | 16개 (4스텝 x 4종) | **16/16 동일** |
| 탭 타깃 실측 | Dismiss 24x24, Sort 48x48, Back 48x48 | 동일 |
| semantics 노드 수 | 23 / 10 / 7 / 7 | 동일 |
| 노드 필드(`onScreen`·`aboveFold`·`fullyVisible`·`coversSurface`·`tappable`·`flags`·`role`) | | **불일치 0건** |
| `viewport` | foldY 667.0, contentTop 20.0, dpr 2.0 | 동일 |
| `taps` / `entrySettled` / `appErrors` | 2 / true / [] | 동일 |

스크린샷도 나온다 — `OffsetLayer.toImage()`로 **750x1334 PNG 4장**, 디바이스 0.

### 다른 것 — 폰트

| | 최대 drift | 평균 | 중앙값 |
|---|---|---|---|
| 기본 `flutter test` (Ahem) | **153.6px** | 60.6px | 39.0px |
| 실폰트 로드 후 | **18.9px** | 3.5px | **0.0px** |

Ahem은 글리프 하나가 em 정사각형이라 "Saved items"가 112.3px → 242.0px(11자 x 22px).
텍스트 두 덩이가 한 줄씩 더 접히면서 상품 리스트 전체가 39px 내려간다.
실폰트를 로드하면 18개 라벨 노드 중 13개가 drift 0.0px이고, 남는 건 텍스트 런 폭 차이
(Roboto ≠ SF)뿐이며 아무것도 밀지 않는다.

### 다른 것 — 대비 수치

`sim 1.03` vs `headless 1.36`. 같은 노드, 같은 폰트 크기, **Ahem과 Roboto가 똑같이 1.36**이므로
폰트 효과가 아니라 래스터라이저 차이다. 여기선 판정 불변(둘 다 4.5 미달)이지만 4.5 경계값은
뒤집힐 수 있다.

### 근거가 되는 SDK 사실 (전부 소스 확인)

| 사실 | 위치 |
|---|---|
| 가이드라인 4종은 plain widget test에서 돈다 | Flutter 자체 테스트 10개 파일이 `meetsGuideline` 사용, 그중 `integration_test` import 0개 |
| 대비 가이드라인은 `renderViews` + `layer.toImage()`만 쓴다 | `flutter_test/src/accessibility.dart:317-326` |
| 골든과 같은 헤드리스 캡처 경로 | `flutter_test/src/_matchers_io.dart:26-35` |
| `flutter test`는 모든 HTTP를 400으로 **기본 차단** | `flutter_test/src/_binding_io.dart:26-27, 75-79` |
| 전 채널 catch-all 훅이 존재 | `flutter_test/src/test_default_binary_messenger.dart:137` `allMessagesHandler` |
| 기본 폰트는 Ahem | `flutter_test/src/binding.dart:2665` |

## 설계

### 1. 워커 API — 바인딩 의존을 콜백 2개로

워커 1155줄 중 `integration_test`에 닿는 곳은 4군데뿐이다(`ensureInitialized`,
`convertFlutterSurfaceToImage`, `takeScreenshot`, `reportData`). 그 4개를 주입으로 바꾼다.

```dart
Future<void> walkJourney(
  WidgetTester tester, {                      // binding 파라미터 삭제
  required void Function() launch,
  required List<Step> journey,
  List<Step> setup = const <Step>[],
  List<String> networkCalls = const <String>[],
  Future<void> Function(String name)? shot,   // null = VISUAL not assessable
  required Future<void> Function(Map<String, Object?> report) publish,
})
```

- `_inTestScreenshots = Platform.isIOS` 상수는 **삭제**한다. `shot == null`이 그 자리를 정확히
  대신한다 — Android 데드락 회피가 워커 안의 플랫폼 분기에서 엔트리의 선택으로 내려간다.
- `convertFlutterSurfaceToImage()`는 파라미터로 빼지 않는다. drive 엔트리의 `shot` 클로저가
  **첫 호출에 한 번** 실행한다. "첫 프레임 뒤, 첫 캡처 전"이라는 제약을 그대로 만족하면서
  공개 API가 늘지 않는다.

### 2. 두 엔트리

> **구현 중 정정 (2026-09-28).** 아래 "위치는 바꾸지 않는다"는 **틀렸다.** `flutter test`는
> `integration_test/`를 디렉터리 *이름*만 보고 디바이스 러너로 보낸다
> (`flutter_tools/commands/test.dart`의 `_kIntegrationTestDirectory`) — 플래그는 없고,
> `flutter test integration_test/ux_journey_test.dart`는 "No devices are connected"로 죽는다.
> 워커는 **`ux_audit/ux_journey_test.dart`**로 갔다. 그 디렉터리는 `test/`도 아니므로 감사 대상
> 앱의 맨 `flutter test`가 워커를 쓸어가지도 않는다(둘 다 실측 확인). 아래 표의 실행 명령과
> 파일 경로는 그 기준으로 읽는다.

생성 파일 위치는 ~~**바꾸지 않는다**~~. `flutter test`는 경로를 받으므로
`integration_test/ux_journey_test.dart`에 그대로 두고 `flutter test integration_test/...`로 돈다.
`test/`로 옮기면 남의 앱 `flutter test`가 우리 파일을 같이 돌려 그쪽 CI를 깬다.

| | widget-test 모드 (기본) | drive 모드 (폴백) |
|---|---|---|
| 실행 | `flutter test integration_test/ux_journey_test.dart` | `flutter drive --driver=... --target=...` |
| 바인딩 | `TestWidgetsFlutterBinding` | `IntegrationTestWidgetsFlutterBinding` |
| `shot` | `writePng(tester, 'ux-audit-out/screens/$name.png')` | iOS: `takeScreenshot` / Android: `null` |
| `publish` | `File('ux-audit-out/walk.json').writeAsStringSync(...)` | `(binding.reportData ??= {}).addAll(r)` |
| 앱에 생기는 파일 | **1개** — 워커 자신 | 3개 — 워커 + `ux_journey_drive.dart` + `test_driver/ux_journey_driver.dart` |
| 네트워크 | **기본 차단**(SDK가 400 반환), airplane-mode 불필요 | airplane-mode 토글 필요 |

두 바인딩을 한 파일에 둘 수는 없다 — 바인딩은 다른 무엇보다 먼저 정해져야 하고,
`IntegrationTestWidgetsFlutterBinding`은 live 바인딩이라 프레임 정책이 다르다. 그래서 drive
모드만 엔트리 파일을 하나 더 얻는다. 기본 모드는 **앱이 파일 하나만 얻는다**(스텁이 있으면 둘) —
지금의 2개(스텁 포함 3개)보다 줄어든다.

SKILL.md의 gitignore 안내에 `integration_test/ux_journey_drive.dart` 한 줄이 추가돼야 한다.

### 3. `## Device` — 저니가 조건을 선언한다

drive 모드에선 디바이스가 viewport를 공급했다. widget-test 모드엔 그 주체가 없고, 아무도
선언하지 않으면 `isTestDefault` 800x600@3.0이 되어 fold 컬럼이 전부 빈칸이 된다.

```markdown
## Device
iphone-se
# textScale: 2.0
# brightness: dark
```

파싱은 코드가 아니라 **에이전트**가 한다(`## Steps`와 동일). 워커에는 상수로 생성된다.

**출시 프리셋은 `iphone-se` 하나다.** `example/walk.json`에서 전 필드가 그대로 재현되는 유일한
프로파일이기 때문이다: `physicalSize 750x1334`, `dpr 2.0`, `padding.top 40`(= contentTop 20.0),
`padding.bottom 0`.

`pixel-6`(411.4x731.4@2.625, foldY 707.4 → padBottom 24.0)과 `ipad-13`(1032x1376@2.0, foldY 1356
→ padBottom 20.0)은 `CLAUDE.md`에 수치가 있지만 **`contentTop`이 기록돼 있지 않다.** 상태바
높이를 추정해 채우는 것은 이 저장소가 금지하는 종류의 일이므로, 두 프리셋은 각 1회 캘리브레이션
런으로 `contentTop`을 실측한 뒤에 출시한다(아래 "조사 항목" 2).

그때까지 `## Device`는 **명시 수치**도 받는다:

```markdown
## Device
375x667 @2.0 contentTop 20 padBottom 0
```

`## Device` 절이 없으면 `iphone-se`로 돌리되
`conditions.deviceProfile: "iphone-se (default, not declared)"`로 기록하고 리포트의 scope 절이
그것을 인용한다 — `## Priorities`의 `not declared`와 같은 처리다.

### 4. 폰트

**엔트리가** `walkJourney`를 부르기 전에 `Future<String> loadFonts(WidgetTester)`를 먼저 부른다
(drive 모드는 실기기/에뮬의 실폰트를 쓰므로 부르지 않는다):

1. `rootBundle`의 `FontManifest.json`에 선언된 앱 폰트를 전부 로드 → `'app'` (drift 0)
2. 하나도 없거나 로드가 실패하면 SDK Roboto를 `Roboto` / `CupertinoSystemDisplay` /
   `CupertinoSystemText` 세 패밀리에 등록 → `'sdk-fallback'`
3. 어느 쪽이든 `MaterialIcons-Regular.otf`를 로드한다

패밀리 이름을 런타임에 알아낼 수 없다 — 폰트는 첫 프레임 **전**에 올라가야 하는데 테마는 앱을
띄워야 읽힌다. 그래서 고정 3개로 Material/Cupertino 기본을 덮는다. 실측 근거:
`Theme.of(c).textTheme.titleLarge?.fontFamily == 'CupertinoSystemDisplay'` (iOS 타겟),
그리고 **`FontLoader`는 null family를 바꾸지 못한다** — 로드 후에도 기본 텍스트는 242.0px로
그대로였고, 이름을 지정한 스타일만 119.7px로 떨어졌다. 옛 이름(`.SF UI Text`)에 등록하면 조용히
아무 일도 일어나지 않는다.

반환값은 `conditions.fontSource`에 기록한다. `'sdk-fallback'`이면 리포트가 배치·fold 수치에
"실제 폰트가 아닌 대체 폰트로 측정됨" 캐비앗을 붙인다.

### 5. 대비 — 새 메커니즘을 만들지 않는다

`walking.md`에 이미 "`MinimumTextContrastGuideline`의 **node**를 신호로, **ratio**를 참고로
취급하라"는 캐비앗이 있다. 거기에 headless 한 문장을 덧붙이고 `conditions.renderer`
(`'flutter_tester (software)'` / `'device'`)를 기록하는 것으로 끝낸다.

### 6. `conditions`에 추가되는 필드

| 필드 | 값 | 왜 |
|---|---|---|
| `mode` | `'widget-test'` / `'drive'` | 산출물이 어느 경로에서 나왔는지 |
| `deviceProfile` | `'iphone-se'` 또는 `'... (default, not declared)'` | 선언되지 않은 기본값을 리포트가 인용할 수 있게 |
| `fontSource` | `'app'` / `'sdk-fallback'` | 배치·fold 수치의 신뢰도 |
| `renderer` | `'flutter_tester (software)'` / `'device'` | 대비 수치의 신뢰도 |
| `targetPlatform` | `'iOS'` / `'android'` | 아래 참고 |

`conditions.platform`은 widget-test 모드에서 `Platform.operatingSystem`이 호스트를 보므로
`'macos'`가 된다. 이건 **버그가 아니라 사실**이다 — 그 런은 정말로 호스트에서 돌았다.
프레임워크에 알린 타겟(`debugDefaultTargetPlatformOverride`)은 그것과 다른 값이므로 섞지 않고
`targetPlatform`에 따로 기록한다. 이 구분은 실재한다: 같은 화면이 Android에서 `70ed0c2e`,
iOS에서 `4ddc18db`로 해시된다(Material `BackButton`의 label/tooltip 차이, 기존 실측).

## 변경 파일

| 파일 | 변경 |
|---|---|
| `example/ux_demo_app/integration_test/ux_journey_test.dart` | `walkJourney` 시그니처, `_inTestScreenshots` 제거, `loadFonts`, `applyDevice`, `conditions` 5필드 |
| `example/ux_demo_app/integration_test/ux_journey_drive.dart` (신규) | drive 엔트리 (`main` + 콜백 2개) |
| `example/ux_demo_app/integration_test/gated_journey_test.dart` | 새 시그니처에 맞춤 |
| `example/journey.md`, `example/journey-gated.md` | `## Device` 절 추가 |
| `skills/.../SKILL.md` | frontmatter(시뮬레이터 필수→선택), `[2] WALK` 두 경로, 출력 위치, credentials 절의 airplane-mode |
| `skills/.../references/walking.md` | 실행 절을 모드별로, `isTestDefault` 문단을 `## Device`로, 대비 캐비앗 한 줄 |
| `skills/.../references/report-format.md` | scope 절이 `mode`/`deviceProfile`/`fontSource`/`renderer`를 인용 |
| `README.md`, `CLAUDE.md` | "booted simulator required" 제거, 갭 목록 갱신 |

## 테스트

| 대상 | 무엇 |
|---|---|
| `recipe_sync_test.dart` | `reportData ??=` assertion을 **drive 엔트리 파일로 이동** (그 위험은 그 경로에만 남는다). `## Device` ↔ 워커 상수 pin 추가 |
| `walker_test.dart` | `shot: null` → 모든 스텝 `screenshot: null` 회귀. `loadFonts`가 `'app'`/`'sdk-fallback'`을 올바로 반환. `applyDevice`가 viewport를 프리셋대로 만든다 |
| 신규 `widget_walk_test.dart` | widget-test 엔트리가 완주하고 `walk.json`을 쓴다. **그리고 `example/walk.json`과 스텝 상태·`screenSig`·가이드라인 판정이 일치한다** |

마지막 항목이 이 작업의 큰 부산물이다: 런이 디바이스를 안 쓰므로 CI에서 돌고,
handoff의 1순위였던 **골든 자동 대조**(`expected-findings.json` 실제 diff)가 비로소 가능해진다.

## 조사 항목 — 추측으로 고치지 않는다

> **구현 중 정정 (2026-09-28).** 항목 1의 전제는 **재현되지 않았다.** 한 파일에서 `walkJourney`를
> 여덟 번(연속 두 워크, 던지는 `shot`, 던지는 `publish`, 워크 중 발생한 `FlutterError` 포함)
> 돌렸고 워커를 한 줄도 바꾸지 않은 채 전부 통과했다. probe가 본 teardown assert의 진짜 원인은
> **`addTearDown(() => debugDefaultTargetPlatformOverride = null)`**이었다 — 바인딩의
> `_verifyInvariants`는 테스트 **본문 끝**에서 돌고 teardown은 그 뒤에 돈다. 인라인으로 되돌리면
> 사라진다. 그래서 복원 코드는 넣지 않았다(실패하는 테스트가 없으므로). 세 테스트는 회귀 핀으로
> 남았다.

**1. `FlutterError.onError` 미복원 (`ux_journey_test.dart:126`)**

probe에서 `flutter test` teardown이 `binding.dart:1912`의
`'_pendingExceptionDetails != null'` assert로 실패했다. 한 파일에 테스트를 2개 두면 두 번째가
자기 실패를 첫 번째의 죽은 리스트로 삼켜 **매달린다**(실측 6분+ 0% CPU).

그런데 순진하게 복원하면 **이미 측정된 버그가 되살아난다** — 워커가 이걸 가로채는 이유가
"워크보다 오래 사는 백그라운드 요청의 늦은 예외가 리포트를 통째로 버린다(실측: 9스텝 저니가
날아감)"이기 때문이다.

그래서: 재현 → 어떤 uncaught error가 오는지 확인 → 그 다음에 고친다.
**폴백**: 워크는 완주하고 `walk.json`은 정상으로 쓴다(probe 확인). 조사가 비싸면 v1은
"widget-test 런은 teardown 실패를 보고한다; 판단은 `steps[].status`로, exit code로 하지 않는다"로
문서화한다 — 이 저장소가 `flutter drive`에 대해 이미 갖고 있는 규칙과 같은 문장이다.

**2. `pixel-6` / `ipad-13` 프리셋 캘리브레이션**

각 1회 런으로 `contentTop`을 실측한다. 나오면 프리셋으로 승격, 그 전까지는 명시 수치로만 쓴다.

## 범위 밖

- **라우트 그래프 정적 룰.** 좋은 아이디어지만 이 작업과 독립이다. 섞으면 둘 다 반만 된다.
- 화면 자동 탐색, 코드 자동 수정, 성능 프로파일링 — 기존 비범위 그대로.

## 미검증으로 남는 것 (완료라고 말하지 않는다)

- **플러그인이 있는 실제 앱.** `allMessagesHandler` catch-all은 SDK 소스로만 확인했고 실행하지
  않았다. 플러그인이 `MissingPluginException`을 던지는 앱에서 widget-test 모드가 어디까지 가는지
  모른다. **drive 모드를 남기는 주된 이유가 이것이다.**
- **플랫폼 뷰**(웹뷰·지도·카메라)는 widget-test에서 렌더되지 않는다 → 빈 영역. `not assessable`로
  보고한다. (현재 Android는 이것 때문에 스크린샷이 데드락하므로 실질적으로는 개선이다.)
- **Android 테마에서의 widget-test 런.** probe는 iOS 타겟 한 조건만 걸었다.
- **iOS 실기기.** 이 저장소에 실기기 런은 여전히 하나도 없다.
