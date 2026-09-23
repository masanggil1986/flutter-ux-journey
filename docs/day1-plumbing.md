# Day 1 — 배관 검증 결과 (결정 기록)

> 계획서 §9 Day 1. 8개 가정을 각각 **실행으로** 검증했다(설치·빌드·시뮬레이터 실행 포함).
> 근거 원문: `docs/day1/*.md`. 사설 앱 관련 조사는 공개 불가라 `local/day1/`(gitignored)에만 둔다.

## 결론

v0.1은 서드파티 의존성 0개다. conalyz와 flutter_skill 둘 다 버리고, 저니 워커를 앱 "밖에서 VM Service로 조종"하는 게 아니라 journey.md에서 생성한 integration_test를 flutter drive로 돌리는 구조로 뒤집는다 — 구조화된 semantics JSON과 프레임워크 내장 a11y 가이드라인 4종은 테스트 프로세스 '안'에서만 닿기 때문이고, 그 둘은 이미 실제 iOS 시뮬레이터에서 실행 검증됐다. 공개 레포는 결함을 심은 데모 앱 하나로 예제·픽스처를 겸한다.

## 가정 검증표

| 가정 | 판정 | 대체/조치 |
|---|---|---|
| conalyz가 실재하고 파싱 가능하며 노이즈가 쓸 만한 수준이다 | ❌ 깨짐 | `package:analyzer` 60줄 직접 작성(astprobe/bin/probe.dart, 실제 앱에 3초 실행 성공). 룰 4개만: 라벨 없는 GestureDetector/InkWell+onTap, tooltip/semanticLabel 없는 IconButton/Icon, semanticLabel 없는 Image, 라벨 없는 TextField. 필수 함정: parseString은 타입 해석이 없어 `IconButton(...)`이 MethodInvocation으로 파싱됨 — visitInstanceCreationExpression만 방문하면 1083파일에서 0건이 조용히 나온다. 둘 다 방문해야 함 |
| flutter_skill은 기계 호출 가능한 런타임 드라이버다 | ❌ 깨짐 | `package:integration_test` + `package:flutter_test`(둘 다 SDK 동봉). tester.tap(finder)은 finder가 안 맞으면 throw하므로 '디스패치'가 아니라 '결과'를 보고한다 — 가짜 성공 문제가 설계상 사라진다 |
| 구조화된 semantics 트리를 앱 '밖에서' 런타임에 얻을 수 있다 | ❌ 깨짐 | 테스트 프로세스 '안'에서 30줄로 덤프. nrprobe/integration_test/probe_test.dart가 실제로 출력한 형태: tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode! 에서 node.getSemanticsData() → {attributedLabel.string, attributedValue.string, tooltip, identifier, role.name, flagsCollection.toStrings(), hasAction(SemanticsAction.tap), rect, transform}, MatrixUtils.transformRect로 parent 체인 누적해 globalRect. globalRect는 물리 픽셀이므로 view.devicePixelRatio로 나눠야 논리 px |
| Flutter 캔버스에 라벨로 탭이 먹는다 | ✅ 유지 | 매칭은 label ∪ tooltip ∪ value에 대해 공백/개행 정규화 후 substring, 2개 이상 매치되면 첫 번째를 고르지 말고 ambiguity 에러. 열거는 isButton 플래그가 아니라 tap 액션 기준. key 셀렉터는 이스케이프 해치로만(실제 앱 446개 탭타깃 중 key 보유 2%) |
| Flutter 내장 a11y 가이드라인을 integration_test에서 쓸 수 있다 | ✅ 유지 | 없음 — 그대로 v0.1에 편입. `await guideline.evaluate(tester)` → Evaluation{passed, reason}를 assert가 아니라 수집. 절대 재구현하지 말 것(픽셀 Rect + 측정값 + 요구값 + 인용 URL이 한 덩어리로 나온다) |
| EliaAlberti/ux-audit-skill은 MIT이고 차용 가능하다 | ✅ 유지 | 차용은 Named Checks 16개 ID(TOUCH-TARGET, DEAD-END, CONTRAST-FAIL, FAKE-AFFORDANCE, ERROR-VAGUE 등)와 리포트 골격만. annotate.py는 차용 안 함(아래 Pillow 항목). 차용 시 NOTICE에 MIT 고지 동봉 의무 |
| 공식 dart-lang/ai의 저니+접근성 도구가 이 자리를 이미 차지하고 있다 | ❌ 깨짐 | 자리는 비어있다. 단 '아무도 저니 단위 UX 평가에 런타임 증거를 붙이지 않는다'는 시장 주장 자체는 REFUTED — ux-audit-skill 검색 182개 레포, dmsakamoto가 '페이지가 아니라 저니 + 라이브 브라우저 + 계수된 마찰 + 스크린샷'을 이미 MIT로 출시. 다만 전부 web. flutter ux audit 검색은 3개뿐이고 그 중 유일한 경쟁자(kakzaki)의 런타임 레이어는 실행 코드가 아니라 '가서 확인해라'는 산문이다 |
| Python 스크립트 페이로드가 스킬로 성립한다 | ❌ 깨짐 | SKILL.md + references/ 3장, 실행 코드는 Dart만. journey.yaml → journey.md(목표 한 줄 + 번호 매긴 스텝, 파서·스키마·검증기 전부 불필요). 기계 소비가 나중에 필요해지면 YAML이 아니라 JSON |
| 도그푸드 저니를 걸을 수 있다 | ❌ 깨짐 | v0.1 도그푸드는 로그인 이후 단일 탭 안의 3스텝 `list → detail → back`. back 스텝이 들어가야 실제 저니 결함(스크롤 위치 소실, 복귀 시 refetch, 상태 리셋)이 잡힌다. journey 스펙에 측정에서 제외되는 `setup:` 블록이 필수. UNVERIFIED — 아무도 이 앱을 빌드하거나 실행하지 않았다(dogfood.md U2/U3). 'walkable'은 '코드 레벨 차단 요인 없음'이지 '걸어봤다'가 아니다 |
| ext.flutter.accessibilityEvaluations로 탭타깃/대비/라벨 검사를 공짜로 받는다 | ❌ 깨짐 | package:flutter_test의 AccessibilityGuideline 4종(위 항목). 동일한 측정을 stable에서 의존성 0으로 제공한다. beta 승격 시 재검토 |

<details><summary>각 판정의 근거(펼치기)</summary>


**conalyz가 실재하고 파싱 가능하며 노이즈가 쓸 만한 수준이다** — broken

실재·MIT·파싱 가능은 맞음(v1.1.0, JSON 8키 스키마 확보). 그러나 conalyz.md Fact 5: 실제 5개 Flutter 앱 1083파일/2634건 측정 결과 상위 2개 룰(Theme Color Recommendation 41.9%, Text Scaling Issue 28.1%)이 전체의 70%이고 둘 다 실제 측정 없는 문자열 nag. 50개 룰 중 34개는 0건. Fact 6: 이 프로젝트에 가장 중요한 Small Tap Target 룰이 `code.contains('padding:')`면 통과시키는 정규식이라 1083파일에서 0건. Fact 3: 매 실행마다 sha256(hostname+OS) 기계 지문 + 룰별 결함 프로파일을 conalyz.codeanalyer.workers.dev로 POST하고, 옵트아웃해도 'opted_out' 비콘을 한 번 쏜다


**flutter_skill은 기계 호출 가능한 런타임 드라이버다** — broken

사실 자체는 HOLDS — flutter_skill.md F12에서 iOS 시뮬레이터 위 Flutter 앱에 실제로 붙어 element별 bounds{x,y,width,height}를 JSON으로 반환(20x20 버튼이 정확히 20x20으로 나옴). 의존 대상으로서는 BROKEN: F19 — 존재하지 않는 위젯에 tap해도 `{"success":true}` + exit 0. F15 — 텍스트로 tap하면 성공이라 보고하고 아무것도 안 함(픽셀로 확인). F13 — Semantics(label:)이 출력에 아예 안 나타남(위젯 리스트지 semantics 트리가 아님). F17 — screenshot 서브커맨드는 web 전용. F18 — 동작하는 경로에 타이밍 없음. F4 — 대상 앱 main()에 FlutterSkillBinding.ensureInitialized() 추가 필요


**구조화된 semantics 트리를 앱 '밖에서' 런타임에 얻을 수 있다** — broken

native-runtime.md F1: semantics 관련 서비스 익스텐션은 rendering/binding.dart:191,199 두 개뿐이고 payload는 `data` 문자열 하나(toStringDeep prose). F2: ext.flutter.inspector.* 32개 전수 열거 — semantics는 단 하나도 없음. F5: 유일한 외부 geometry는 getLayoutExplorerNode이고 RenderBox.size는 주지만 글로벌 좌표는 없음(parentData offset만). device-control.md F17: prose 덤프는 label/rect/actions/flags를 다 주지만 leaf rect가 로컬이고 `with transform`이라 순진한 파서는 (0,0)을 읽는다


**Flutter 캔버스에 라벨로 탭이 먹는다** — holds

native-runtime.md F9/F6: 실제 iPhone SE 시뮬레이터에서 `find.bySemanticsLabel('tiny labeled button').evaluate().length == 1`. finders.dart:592/623/396에 bySemanticsLabel/bySemanticsIdentifier/byTooltip 존재. 단 dogfood.md F5가 실측한 3개 함정: (1) tooltip:은 label을 채우지 않고 별도 tooltip 필드로 감 — label만 보는 매처는 툴팁 달린 아이콘 버튼을 전부 놓친다, (2) 형제 Text들이 \n으로 합쳐져 하나의 label이 됨 — 정확일치 매칭은 이 앱의 모든 카드에서 실패, (3) InkWell은 tap 액션은 있지만 isButton 플래그가 없음 — isButton으로 필터하면 이 앱 탭타깃의 대부분이 사라진다


**Flutter 내장 a11y 가이드라인을 integration_test에서 쓸 수 있다** — holds

이번 조사에서 가장 값싼 승리. native-runtime.md F6이 실제 iPhone SE(3rd gen) iOS 18.6 시뮬레이터에서 `flutter test integration_test/probe_test.dart -d <udid>` exit 0으로 4종 전부 실행: iOS/androidTapTargetGuideline이 'SemanticsNode#4(Rect.fromLTRB(175.5,233.5,199.5,257.5), actions:[tap], flags:[isButton], label:"tiny labeled button"): expected tap target size of at least Size(44.0,44.0), but found Size(24.0,24.0)'를 반환. labeledTapTargetGuideline·textContrastGuideline(실제 픽셀 읽어 3.68 비율 산출)도 발화. accessibility.dart:785/800/818/825에 const로 선언되어 있고 stable 3.47.2


**EliaAlberti/ux-audit-skill은 MIT이고 차용 가능하다** — holds

prior-art.md F9: LICENSE 전문 확인, MIT, Copyright (c) 2026 Elia Alberti. F10: 레포 전체가 SKILL.md 17KB 한 장 + Python 2개(6.6KB). 두 가지 정정 — 심각도 척도는 문자 그대로 'Nielsen 0-4'가 아니라 `4 Critical/3 Major/2 Minor/1 Cosmetic/✓ Positive`이고, '16 프레임워크'는 A-L 12개 섹션 중 E가 행동법칙 5개로 전개될 때만 16


**공식 dart-lang/ai의 저니+접근성 도구가 이 자리를 이미 차지하고 있다** — broken

prior-art.md F3: dart_mcp_server-1.1.2의 flutter_driver_user_journey_test는 서버의 유일한 '프롬프트'이고 내용은 영문 25줄 — '저니를 드라이브해서 flutter driver 테스트를 디스크에 써라'. 평가·휴리스틱·심각도·스크린샷·측정 전부 0. 산출물이 리포트가 아니라 회귀 테스트다. F4: accessibilityEvaluations는 dart-lang/ai에 아예 없음(dart_mcp_server, dart_mcp 양쪽 grep 0건) — _PRIOR.md의 귀속이 틀렸다. 그건 프레임워크 VM 익스텐션이고 F17/F19에서 stable에서 죽어있음이 실행으로 증명됨


**Python 스크립트 페이로드가 스킬로 성립한다** — broken

packaging.md F11 실측: 이 머신의 python3는 Xcode 셰이프 3.9.6이고 `import jinja2` → ModuleNotFoundError, `import yaml` → ModuleNotFoundError. 스킬 저자 본인 머신에서 이미 실패한다. F10: Claude API 런타임은 네트워크 없음·런타임 패키지 설치 없음 — 의존성 설치 스토리가 스펙에 존재하지 않고 SKILL.md 문장 한 줄이 전부. F14: 이 머신의 스킬 디렉터리 1069개 중 실행 코드를 번들하는 건 107개(10%). F13: 공식 dart-flutter 플러그인은 스킬 25개에 실행 스크립트 0개. F12: Dart도 Python도 stdlib에 YAML 파서가 없다 — journey.yaml은 어느 언어로 가든 의존성을 강제한다


**도그푸드 저니를 걸을 수 있다** — broken

dogfood.md F2: 계획서의 5스텝 예약 저니는 라우트 레벨로는 2개뿐이고(소스 주석에 '합본 단일 페이지 → 확인, 완료는 다이얼로그'라고 명시) 나머지 스텝은 showDialog 7개 + showModalBottomSheet 1개 — 라우트 변화로 스텝을 자르면 사용자가 6스텝으로 겪는 저니를 2스텝으로 기록한다. F3: API base URL이 하드코딩된 운영 상수이고 소스 주석이 dart-define을 일부러 안 쓴다고 밝힘. lib 전체에서 String.fromEnvironment/dotenv/MOCK/useMock grep 0건. 저니 시작 전에 로그인 → 프로필 선택 → PIN/비번 확인의 네트워크 게이트 4개가 선다. F4: 탭 타깃 446개 중 key 보유 2%, 명시적 Semantics 1.1%


**ext.flutter.accessibilityEvaluations로 탭타깃/대비/라벨 검사를 공짜로 받는다** — broken

두 보고서가 독립적으로 실행해 동일 결론. prior-art.md F17/F19, device-control.md F12, a11y_run2/4.log: 익스텐션은 등록되어 있고 콜백도 도는데 _accessibility_evaluations.dart:71에서 'Unsupported operation: Accessibility evaluations APIs are not enabled'를 던진다. 탈출로 2개 모두 막힘 — `--dart-define=FLUTTER_ENABLED_FEATURE_FLAGS=...`는 'cannot be set using --dart-define'로 거부, `flutter config --enable-accessibility-evaluations`는 설정은 받지만 `(Unavailable)`로 남고 재빌드해도 동일하게 throw. 게다가 API 전체가 @internal이고 '패치 버전에서도 breaking change를 하겠다'고 명시


</details>

## 확정 아키텍처

```
서드파티 의존성 0개. 대상 앱 소스 수정 0줄(추가 파일 2개 + dev_dependency 1개는 있음).

  journey.md ──▶ [0 preflight] ──▶ [1 static] ──▶ [2 walk] ──▶ [3 visual] ──▶ [4 merge] ──▶ 산출물

[0] PREFLIGHT (신규, dogfood.md가 강제함)
  journey.md의 goal/setup/steps를 모델이 체크리스트로 복창하고 시뮬레이터를 건드리기 전에 멈춘다.
  setup: 블록(로그인·PIN 등)은 측정·채점에서 제외. 계획서의 5단계는 전부 "앱이 이미 1스텝에 있다"를
  가정했는데 실제 앱은 그 앞에 네트워크 게이트가 4개다.

[1] STATIC — Dart, `package:analyzer` 단독, 약 60줄 (astprobe/bin/probe.dart로 실행 검증)
  parseString(unresolved AST) → visitInstanceCreationExpression + visitMethodInvocation 둘 다.
  룰 4개만: (a) onTap 있는 GestureDetector/InkWell에 semantics 없음 (b) tooltip/semanticLabel 없는
  IconButton/Icon (c) semanticLabel 없는 Image (d) 라벨 없는 TextField.
  대비·텍스트 스케일링은 정적으로 결정 불가라 제외(conalyz가 70% 노이즈로 증명). 탭 타깃 크기도 제외 —
  정적으로 알 수 없고 [2]가 실측한다. 출력에 confidence 필드(이름 매칭이라 동명 비위젯 오탐 가능).

[2] JOURNEY WALK — 앱 '안'에서 도는 생성된 integration_test. 여기가 계획 대비 가장 큰 반전.
  스킬이 journey.md에서 두 파일을 대상 앱에 생성한다:
    integration_test/ux_journey_test.dart
    test_driver/integration_test.dart   (15줄, integrationDriver(onScreenshot:) — 실행 검증됨)
  실행: flutter drive --driver=test_driver/integration_test.dart
                      --target=integration_test/ux_journey_test.dart -d <device-id>

  스텝마다, 전부 SDK API로 (native-runtime.md F6/F7/F10/F12에서 iPhone SE 시뮬레이터 실행 검증):
    final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
    final handle = tester.ensureSemantics();                 // 절대 이미 켜져 있다고 가정하지 말 것
    final sw = Stopwatch()..start();
    await tester.tap(finder); await tester.pumpAndSettle();  // finder 불일치면 throw = 진짜 오라클
    sw.stop();                                               // 측정 546ms, 증거로만 기록
    // 구조화 semantics 덤프 (약 30줄)
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!
      → node.getSemanticsData() → SemanticsData
         .attributedLabel.string .attributedValue.string .tooltip .identifier
         .role.name .flagsCollection.toStrings() .hasAction(SemanticsAction.tap)
         .rect .transform
      → MatrixUtils.transformRect(t, r)를 parent 체인 따라 누적 = globalRect(물리 px)
      → view.devicePixelRatio로 나눠 논리 px
    // 가이드라인 4종, assert가 아니라 수집
    for (final g in [androidTapTargetGuideline, iOSTapTargetGuideline,
                     textContrastGuideline, labeledTapTargetGuideline])
      final Evaluation e = await g.evaluate(tester);         // {passed, reason}
    // 스크린샷
    await binding.convertFlutterSurfaceToImage();            // Android 전용, iOS는 no-op
    await binding.takeScreenshot('step_$i');                 // 실측 45135바이트 PNG
    binding.reportData = {...};                              // → build/integration_response_data.json

  호스트 회수: onScreenshot 콜백이 screenshots/*.png를 디스크에 쓰고, reportData는
  $FLUTTER_TEST_OUTPUTS_DIR/integration_response_data.json(기본 build/)에 떨어진다.
  필수: writeResponseData 전에 reportData['screenshots']를 잘라낼 것 — 45KB PNG가 561KB JSON이 된다(실측).
  주의: 평범한 `flutter test`는 그 JSON을 안 쓴다. flutter drive여야 한다.

  ※ 계획의 별도 "RenderBox 측정 스텝"은 삭제. tester.getRect(finder) 한 줄이고, 가이드라인이 이미
    측정값과 요구값을 같이 준다.

[3] VISUAL — 모델이 PNG를 본다. 스크립트 없음.
    (공식 문서 패턴: 스크립트는 이미지를 만들고 판단은 모델이 한다.)

[4] MERGE + RESCORE — 모델이 references/heuristics.md를 따라 수행. 스크립트 없음.
    저니의 goal 대비 Nielsen 심각도 재채점은 정의상 "휴리스틱이 방향을 정하는" 열린 문제다.
    스크립트가 할 수 있는 건 키로 dedup하고 심각도로 정렬하는 것뿐이고, 그건 heuristics.md 열 줄이다.

산출물: report.md + findings.json + screens/ — 감사 대상 프로젝트 하위의 gitignore된 디렉터리에.
        스킬 설치 디렉터리에는 절대 쓰지 않는다(공유 디렉터리이고 업데이트 때 덮어써진다).

배포: 레포 자체가 플러그인. .claude-plugin/plugin.json + marketplace.json(source "./") + skills/.
      pkgtest에서 `claude plugin validate`로 실증됨 — 파일 3개면 설치 가능해진다.

── 증거가 결정하지 못한 갈림길, 명시 ──
device-control.md는 완전히 다른 런타임 레이어를 증명했다: 의존성 0의 Dart 스크립트가 VM Service로
`SemanticsBinding.instance.ensureSemantics()`를 원격 호출하고(F16, 대상 앱 수정 불필요),
`GestureBinding.instance.handlePointerEvent(PointerDownEvent(...))`로 스톡 앱에 탭을 5/5 성공시켰다(F10).
장점은 결정적이다 — 앱을 고치지도 리빌드하지도 않고, 개발자가 이미 수동 로그인해 둔 세션에 그대로 붙는다.
도그푸드 앱의 네트워크 게이트 4개를 통째로 우회한다.
그럼에도 v0.1은 integration_test를 택한다. 이유 세 가지, 전부 측정된 것:
  (1) 대비 검사가 불가능하다. 외부에서는 노드별 픽셀을 못 읽고, 내장 가이드라인은 캘리브레이션까지 끝나 있다.
  (2) semantics가 prose다. 파서가 필요하고 leaf rect가 `with transform`이라 순진한 파서는 (0,0)을 읽는다.
      게다가 그 파서는 9노드짜리 카운터 앱에서만 검증됐다.
  (3) 탭 주입이 타임스탬프/포인터 id를 손수 맞추지 않으면 3번에 1번 조용히 사라진다(F11 실측).
VM Service 경로는 v0.2의 "dev_dependency를 추가할 수 없는 앱" 탈출구로 둔다. 삭제가 아니라 보류다.
```

## 스코프 변경


### 잘라냄

- **conalyz 의존 (파이프라인 1단계)** — 기계 지문을 서드파티 서버로 전송(옵트아웃해도 비콘 1회), 출력의 70%가 측정 없는 노이즈, 이 프로젝트의 핵심 룰인 탭타깃은 1083파일에서 0건. 대체물이 이미 작성·실행된 60줄이다
- **flutter_skill 의존 (파이프라인 2단계)** — 존재하지 않는 위젯 탭에도 success:true를 반환한다. 오라클이 없는 워커는 가보지도 않은 화면에 대해 자신 있게 UX 결함을 보고한다 — 아무것도 보고하지 않는 것보다 나쁘다
- **ext.flutter.accessibilityEvaluations** — stable에서 하드 오프이고 탈출로 둘 다 실행으로 막힘 확인. @internal이며 패치 버전에서도 breaking change를 예고한다
- **별도 RenderBox 측정 스텝** — tester.getRect(finder) 한 줄이고, 가이드라인이 위반마다 측정값과 요구값을 이미 붙여 준다
- **journey.yaml + JSON Schema + validate_journey.py** — Dart도 Python도 stdlib에 YAML 파서가 없고 이 머신엔 PyYAML도 없다. 유일한 소비자가 모델이므로 journey.md면 파서·스키마·검증기가 전부 사라진다
- **Jinja2 리포트 템플릿** — 스킬 저자 본인 머신에서 import가 실패한다. 리포트 골격은 references/report-format.md의 마크다운 펜스 한 덩이면 된다
- **run_static.py / run_journey.py / merge_findings.py** — 앞 둘은 bash 한 줄의 래퍼, 마지막은 모델의 판단을 JSON으로 세탁하는 것이다. goal 대비 심각도 재채점은 스크립트가 결정할 수 없다
- **'저니 단위 UX 평가에 런타임 증거를 붙이는 건 아무도 안 한다'는 시장 주장** — 반증됨. 남는 방어 가능한 주장은 좁은 쪽이다 — 추측하지 않고 측정하는 유일한 Flutter UX 감사(실제 픽셀 Rect, 실제 대비 비율, 실제 semantics 라벨을 돌아가는 앱에서 뽑는다). 경쟁자는 전부 스크린샷 추측이거나 소스 grep이거나 web 전용이다

### 다시 씀

- **스텝 타이밍을 채점 대상 결함으로 쓰기** — Stopwatch 자체는 공짜라 증거로는 기록한다(546ms 실측). 하지만 이건 호스트 왕복 시간이지 사용자 체감 지연이 아니다 — 결함으로 채점하면 거짓말이 된다. watchPerformance는 호출당 4~6초를 강제로 잡아먹으므로 기본값 금지

### v0.1로 당김

- **Flutter 내장 a11y 가이드라인 4종** — v0.2 후보였는데 사실상 공짜다. 실제 시뮬레이터에서 노드별 Rect + 측정값 + 인용 URL까지 붙어 나오는 게 이미 실행 검증됐다. 재구현 금지
- **저니 스펙의 setup: 블록 (인증·전제조건 단계)** — 도그푸드 앱은 1스텝 전에 네트워크 게이트가 4개다. setup이 없으면 실행이 setup에서 죽었는데 짧은 저니를 걸은 것처럼 조용히 보고된다
- **셀렉터 매처: label ∪ tooltip ∪ value, 정규화 substring, 모호하면 에러** — 실측 — tooltip:은 label에 절대 안 들어가고, 형제 Text는 \n으로 합쳐진다. 가장 자연스러운 첫 구현(label 정확일치)은 이 앱의 모든 카드와 모든 툴팁 아이콘 버튼에서 실패한다. 지금 고치면 공짜, 나중에 빈 리포트 보고 알아내면 지옥
- **semantics rect의 transform 누적 (캘리브레이션 노브)** — leaf rect는 로컬이다. 누적을 안 하면 중첩된 모든 요소가 (0,0)으로 보고되고 탭타깃 휴리스틱 전체가 쓰레기가 된다. 해피패스에서는 멀쩡해 보이는 종류의 버그다
- **결함을 심은 데모 앱** — 부차적 산출물이 아니라 v0.1의 1순위 산출물이다. 공개 레포의 유일한 실행 가능 예제이면서 동시에 유일한 결정론적 회귀 픽스처다. 하나로 두 가지를 낸다

### v0.2로 미룸

- **annotate.py (Pillow)** — Pillow가 보장되지 않는다. 박스는 리포트를 읽는 사람을 위한 것이지 분석을 위한 게 아니다. 필요해지면 img 위에 absolute div를 얹는 HTML이 의존성 0이고 줌도 된다
- **VM Service 외부 드라이버 (원격 ensureSemantics + handlePointerEvent 주입)** — 실물로 증명됐고 앱 수정이 전혀 필요 없다는 진짜 장점이 있다. 하지만 v0.1에 넣으면 prose 파서 + 탭 캘리브레이션 + 대비 검사 자체 구현이 딸려 온다. integration_test는 그 셋을 전부 공짜로 준다

### 유지

- **.claude-plugin/plugin.json + marketplace.json** — 파일 2개로 설치 가능해진다. claude plugin validate로 실증 완료. CI 게이트는 validate --strict --json

## 공개 예제 계획

공개 레포에 도그푸드 앱의 산출물은 어떤 형태로도 들어가지 않는다. 대신 `example/ux_demo_app/`를 만들고, 이걸 예제와 픽스처로 겸용한다.

무엇을 커밋하는가
  example/ux_demo_app/          `flutter create` 스캐폴딩, package id com.example.ux_demo, 약 200줄.
                                백엔드 없음 → 인증 게이트 없음 → 개발 루프가 초 단위.
  example/journey.md            goal 한 줄 + 3스텝(list → detail → back) + 스텝별 기대 결과.
  example/expected-findings.json  위 앱에 대해 실행한 골든 결과. 이 앱에서 나온 것만 커밋한다.
  example/screens/*.png         위 앱의 스크린샷만.

데모 앱에 심을 결함 — 교과서용이 아니라 dogfood.md가 실제 앱에서 측정한 모양 그대로
  · 24x24 GestureDetector 탭 타깃          → iOS/androidTapTargetGuideline이 잡아야 함 (sev 3)
  · tooltip도 semanticLabel도 없는 IconButton → labeledTapTargetGuideline + 정적 룰 (b) (sev 3)
  · 형제 Text 3개가 \n으로 합쳐지는 카드      → 셀렉터 모호성 처리의 회귀 테스트
  · 흰 배경 위 #DDDDDD 텍스트               → textContrastGuideline (sev 2~3)
  · 돌아갈 어포던스가 없는 막다른 화면        → DEAD-END, 저니 단위에서만 보이는 결함 (sev 4)
  · 확인 없는 파괴적 액션                    → 크로스 스텝 패스가 잡아야 함 (sev 4)
  단정하게 key와 semantics를 붙인 데모 앱은 도구가 잘 도는 것처럼 보이게 하면서 모든 실사용자가
  첫날 맞을 실패 모드를 정확히 가린다. 야생에서 측정된 결함을 심는다.

왜 이게 데모가 아니라 픽스처인가
  지금 이 프로젝트에는 "휴리스틱 엔진이 퇴행했는가"에 답할 방법이 없다. 살아있는 사설 앱에 대한 결과는
  네트워크·데이터·시각에 따라 비결정적이라 CI에서 단정할 수 없다. 심은 결함은 정답이 알려진 테스트를
  모든 휴리스틱에 하나씩 준다 — 이 6개를 이 심각도로 찾아내는가.

무엇을 절대 커밋하지 않는가 (측정된 유출 경로)
  · 스크린샷 — UI 카피, 실데이터, 제품 정체성이 파일 하나에 다 들어있다
  · semantics 덤프 — 모든 label이 제품 카피 원문
  · 정적 패스 출력 — conalyz의 실제 JSON에서 file 경로와 suggestion 문자열이 기능명·화면명·UI 카피를
    그대로 실어 날랐다. 우리 출력도 같은 모양이다
  · ext.flutter.inspector.getRootWidgetTree — creationLocation{file,line,column}으로 절대 소스 경로가 박힌다
  · 도그푸드 journey.md — 라우트명과 goal 텍스트 자체가 제품 정보
  · evals/ — examples/보다 evals/가 더 큰 유출 벡터다. 케이스에 프롬프트·픽스처·그레이더가 박힌다.
    커밋되는 모든 케이스는 데모 앱만 대상으로 한다

집행 (사람의 기억에 맡기지 않는다)
  · 레포 루트 .gitignore에 report.md, findings.json, screens/, ux-audit-out/, *.journey.local.md
  · SKILL.md는 산출물을 감사 대상 프로젝트나 temp 디렉터리에 쓰라고 지시한다. 스킬 디렉터리 금지 —
    공유 디렉터리이고 거기 떨어진 스크린샷은 `git add -A` 한 번 거리다
  · `claude plugin eval`은 기본값이 claude.ai에 리포트를 게시한다. 도그푸드 eval은 반드시 --no-publish.
    CONTRIBUTING.md가 아니라 make/npm 타깃 안에 넣는다
  · 리포트 포맷은 스크린샷을 상대 경로로 참조한다 → 이미지 디렉터리 없이 리포트만 공유해도 읽히고
    아무것도 새지 않는다
  · 사설 앱은 gitignore된 로컬 설정 뒤에 둔 로컬 전용 스모크 타깃으로만 유지 —
    "899파일 앱에서 살아남는가"라는 진짜 신호는 얻고 레포는 그걸 보지 않는다

이미 안전한 출발점: scratchpad의 nrprobe(스텝 타이밍·semantics 덤프·가이드라인 4종·flutter drive
스크린샷을 이미 실증), a11yprobe(대비/탭타깃/라벨 결함 심어둠), semdemo(스톡 카운터 앱). 전부 순수
스캐폴딩이라 새는 게 없고, 데모 앱은 사실상 이 셋의 병합이다.

## 다음 3개 작업

1. 레포를 설치 가능한 플러그인으로 스캐폴딩하고 결함 심은 데모 앱을 만든다. .claude-plugin/{plugin.json,marketplace.json}(source "./") + skills/flutter-ux-journey/SKILL.md(프런트매터는 name/description/license/compatibility 4개만 — triggers·homepage·version 같은 비스펙 키 금지) + example/ux_demo_app/. 데모 앱은 nrprobe/a11yprobe의 위젯을 합쳐 6개 결함을 심는다. 성공 확인: `claude plugin validate --strict <repo>`가 "Validation passed"를 출력하고, `flutter run -d <sim-udid>` 로 데모 앱이 뜨며 24x24 탭타깃과 라벨 없는 IconButton이 화면에 보인다.

2. nrprobe/integration_test/probe_test.dart를 데모 앱의 integration_test/ux_journey_test.dart + test_driver/integration_test.dart로 이식해 3스텝 저니를 걷게 한다. 스텝마다: tester.tap → pumpAndSettle → 다음 화면의 finder를 assert(오라클) → Stopwatch ms → transform 누적한 semantics JSON → 가이드라인 4종 evaluate 수집 → takeScreenshot. 드라이버의 responseDataCallback에서 reportData['screenshots']를 잘라낸다. 성공 확인: `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/ux_journey_test.dart -d <sim-udid>`가 exit 0, screenshots/에 PNG 3장, build/integration_response_data.json이 (a) 24x24 노드를 Rect와 함께 지목하는 실패 Evaluation을 최소 1건 포함하고 (b) 크기가 100KB 미만이다(스크린샷 제거가 먹었다는 증거). 일부러 스텝 2의 finder를 틀리게 바꿔 한 번 더 돌려서 통과가 아니라 실패가 나오는지도 본다 — 오라클이 실제로 오라클인지 확인.

3. 같은 생성기를 사설 앱에 겨눠 v0.1 최대 미검증 가정을 끝낸다. dev_dependencies에 integration_test 추가, 테스트에서 앱의 실제 main()을 pump, --dart-define으로 주입한 자격증명으로 로그인+PIN을 setup: 블록에서 통과, 그 뒤 list→detail→back. 성공 확인: 리스트 화면에 도달해 reportData에 스텝 3개 이상이 기록된다. 부팅하지 못하면 그것이 곧 갈림길의 답이고 VM Service 접속 경로가 v0.2에서 v0.1로 올라온다 — 어느 쪽이든 오늘 확정된다. 반드시: 실행 후 `git status`가 clean이어야 하고(사설 앱 산출물이 레포에 한 조각도 없어야 함), 사설 앱 쪽 변경은 커밋하지 않는다.

## 사용자 결정 대기

1. Android 패리티를 v0.1에 넣을까요, 아니면 iOS 시뮬레이터 전용으로 내보내고 그렇다고 명시할까요? 실행 검증된 건 전부 iOS 시뮬레이터입니다. Android는 takeScreenshot 전에 convertFlutterSurfaceToImage()가 필수이고(안 부르면 StateError), Impeller-on-Android에서 textContrastGuideline의 OffsetLayer.toImage()가 도는지는 미검증입니다. 하루치 작업으로 보이지만 하루입니다.

2. 포지셔닝: '아무도 안 한다'는 주장이 반증됐습니다(ux-audit-skill 레포 182개, dmsakamoto가 저니+런타임을 이미 MIT로 출시 — 단 web 전용). 좁은 주장('추측하지 않고 측정하는 유일한 Flutter UX 감사')으로 갈아타면 방어 가능하지만 시장은 훨씬 작아 보입니다. 그대로 갑니까, 아니면 범위를 다시 잡습니까?

3. 생성된 integration_test 파일을 감사 대상 앱에 남길까요, 임시 디렉터리에 쓰고 지울까요? 남기면 팀이 다시 돌릴 수 있는 회귀 산출물이 되지만 대상 레포에 우리 파일이 커밋됩니다. 지우면 발자국이 0이지만 매번 재생성이고 결과가 재현 불가능해집니다. 증거가 결정해 주지 않는 제품 취향 문제입니다.
