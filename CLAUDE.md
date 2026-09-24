# flutter-ux-journey

실행 중인 Flutter 앱을 **사용자 저니 단위**로 걸어보고, 정적·런타임·시각 증거를 합쳐
휴리스틱 UX 감사 리포트를 만드는 Agent Skill.

**한 줄 정의: "화면"이 아니라 "저니"를 감사한다.**

---

## ⚠️ 이 저장소는 공개(public) 오픈소스다 — 최우선 규칙

이 규칙은 다른 모든 규칙보다 우선한다. 커밋 전에 매번 확인한다.

**절대 커밋에 들어가면 안 되는 것**

- 비공개 앱(dogfood 대상 포함)의 **이름, 번들 ID/패키지명, 저장소 경로**
- 그 앱의 **라우트명·화면명·위젯명·기능명**, UI 문구, 도메인 용어
- **스크린샷·화면 녹화** 일체 (실 앱 화면은 그 자체가 제품 유출이다)
- API 엔드포인트, 베이스 URL, 호스트명
- 계정, 비밀번호, 토큰, API 키, 인증서, `.env`, `serviceAccount*.json`, `*Credentials*.json`
- 실제 사용자 데이터 (이름, 이메일, 전화번호, 결제 정보)
- dogfood 실행이 만들어낸 `report.md` / `findings.json` / `screens/*.png` 원본

**대신 이렇게 한다**

- dogfood는 **로컬에서만** 돌린다. 산출물은 `.gitignore`로 차단돼 있다 — 차단 목록을 풀지 않는다.
- 공개 `example/`은 **`example/ux_demo_app/`**(백엔드 없는 `com.example.*` 스캐폴딩, 결함 6개를 의도적으로
  심은 앱) 하나만 쓴다. 이 앱의 스크린샷·골든 결과만 커밋한다. 사설 앱 산출물을 익명화해서 재사용하지
  않는다 — 익명화는 새는 구멍이 너무 많다(스크린샷 속 텍스트, 라우트 구조, 용어).
- 문서에서 dogfood 대상을 가리켜야 하면 `the private dogfood app` 처럼만 쓴다.
- 저니 예시는 가공의 앱(`com.example.*`)으로 쓴다.

**Day 1에서 실측으로 확인된 유출 벡터 (일반적인 것 외에 추가)**

- **`evals/`가 `examples/`보다 큰 유출 벡터다** — 케이스 파일에 프롬프트·픽스처·그레이더가 통째로 박힌다.
  커밋되는 케이스는 데모 앱 대상만(`evals/demo-app/`). 나머지는 gitignore.
- **`claude plugin eval`은 기본값이 claude.ai에 리포트를 게시한다.** dogfood eval을 돌리게 되면 반드시
  `--no-publish`. (아직 `evals/`도 실행 래퍼도 없다 — 만들 때 이 플래그를 래퍼 안에 박아 집행한다.
  산문 규칙으로 두지 않는다.)
- **정적 분석 출력이 그 자체로 유출이다** — file 경로와 suggestion 문자열이 기능명·화면명·UI 카피를
  그대로 실어 나른다. semantics 덤프의 모든 label은 제품 카피 원문이다.
- **`ext.flutter.inspector.getRootWidgetTree`는 `creationLocation{file,line,column}`으로 절대 소스 경로를
  박는다.**
- **산출물을 스킬 설치 디렉터리에 쓰지 않는다.** 공유 디렉터리이고, 거기 떨어진 스크린샷은
  `git add -A` 한 번 거리다. 산출물은 감사 대상 프로젝트 하위의 gitignore된 디렉터리에 쓴다.
- 리포트는 스크린샷을 **상대 경로**로 참조한다 → 이미지 없이 리포트만 공유해도 읽히고 아무것도 안 샌다.

**커밋 전 점검**

```bash
git diff --cached --name-only   # 파일 목록부터 눈으로 본다 — 바이너리·이미지가 섞였으면 멈춘다
git diff --cached | grep -inE 'token|secret|password|api[_-]?key|bearer|://' \
  | grep -viE 'github\.com|flutter\.dev|dart\.dev|api\.flutter\.dev|docs\.claude\.com|w3\.org'
```

두 번째 명령이 아무것도 출력하지 않아야 한다. 걸린 줄이 있으면 사람이 직접 판단한다.

스크린샷·바이너리가 스테이징에 섞여 있으면 멈추고 사람에게 묻는다.

---

## 현재 상태

**Day 1 배관 검증 완료 (2026-09-22).** 전체 기록: `docs/day1-plumbing.md`, 근거 원문: `docs/day1/*.md`.

**확정: v0.1은 서드파티 의존성 0개.** 초안이 전제한 두 의존성은 실행 검증 끝에 **둘 다 탈락**했다.

- `conalyz` — 실재·MIT·파싱 가능은 맞지만 (a) 출력의 70%가 실측 없는 문자열 nag, (b) 이 프로젝트의
  핵심인 탭 타깃 룰이 1083파일에서 0건, (c) **매 실행마다 기계 지문을 서드파티 서버로 POST하고
  옵트아웃해도 비콘을 한 번 쏜다.** → `package:analyzer` 직접 작성 60줄로 대체.
- `flutter_skill` — iOS 시뮬레이터에 실제로 붙긴 하지만 **존재하지 않는 위젯을 탭해도 `success:true`를
  반환한다.** 오라클 없는 워커는 가보지도 않은 화면의 UX 결함을 자신 있게 보고한다 — 무보고보다 나쁘다.
  → `integration_test` + `flutter_test`(둘 다 SDK 동봉)로 대체. `tester.tap`은 finder 불일치 시 throw하므로
  "디스패치"가 아니라 "결과"를 보고한다.

**핵심 구조 반전:** 앱을 *밖에서* VM Service로 조종하지 않는다. `journey.md`에서 생성한
`integration_test`를 `flutter drive`로 돌린다. 구조화된 semantics JSON과 프레임워크 내장 a11y
가이드라인 4종이 **테스트 프로세스 안에서만** 닿기 때문이다(외부 semantics 익스텐션은 prose 문자열
하나뿐이고, `ext.flutter.inspector.*` 32개에 semantics는 하나도 없다 — 전수 확인).

**공짜로 얻은 것:** `androidTapTargetGuideline` / `iOSTapTargetGuideline` / `labeledTapTargetGuideline` /
`textContrastGuideline` 4종이 실제 시뮬레이터에서 픽셀 Rect + 측정값 + 요구값을 붙여 반환하는 것을
실행 확인. v0.2 후보였으나 v0.1로 당겼다. **재구현 금지.**

**해피패스에선 안 보이는 함정 3개 (전부 실측, 지금 반영 안 하면 나중에 빈 리포트를 보고 헤맨다)**

1. semantics leaf rect는 **로컬 좌표**다. `MatrixUtils.transformRect`로 parent 체인을 누적하지 않으면
   중첩된 요소가 전부 `(0,0)`으로 보고되고 탭 타깃 휴리스틱 전체가 무의미해진다.
   globalRect는 물리 px이므로 `view.devicePixelRatio`로 나눠야 논리 px.
2. `tooltip:`은 label을 채우지 않고 **별도 필드**로 간다. label만 보는 매처는 툴팁 달린 아이콘 버튼을
   전부 놓친다. 매칭은 label ∪ tooltip ∪ value에 공백/개행 정규화 후 substring, 2개 이상 매치되면
   첫 번째를 고르지 말고 **ambiguity 에러**.
3. `InkWell`은 tap 액션은 있지만 `isButton` 플래그가 없다. 열거는 플래그가 아니라 **tap 액션 기준**.
   (실측 앱에서 탭 타깃 446개 중 key 보유는 2% — key 셀렉터는 이스케이프 해치로만 쓴다.)

정적 분석 함정: `parseString`은 타입 해석이 없어 `IconButton(...)`이 `MethodInvocation`으로 파싱된다.
`visitInstanceCreationExpression`만 방문하면 **1083파일에서 조용히 0건**이 나온다. 둘 다 방문할 것.

## 미검증으로 남은 것 (완료라고 말하지 않는다)

v0.1은 데모 픽스처(iOS 시뮬)와 **실제 운영 앱(Android 에뮬레이터)** 양쪽에서 실행 검증했다.
운영 앱 도그푸드에서 드러난 것과 남은 갭은 아래와 같다.

**도그푸드로 닫힌 갭**

- `textContrastGuideline`이 **Android Impeller에서 정상 동작**한다(실제 대비 2.02 산출 확인).
- 정적 룰 4개 전부 실제 코드베이스에서 발화했다 — 데모 픽스처가 못 건드리던 `image-without-label`(54건),
  `field-without-label`(8건) 포함.

**도그푸드가 새로 연 갭 — 둘 다 수정 완료, 단 재발 감시 필요**

- **`pumpAndSettle` 금지.** 기본 타임아웃이 10분이라 영구 애니메이션(스피너·셔머·네트워크 대기)이 있는
  앱에서 워크가 통째로 매달린다. 경계 있는 `_settle`로 교체했고 `settled`를 스텝 증거로 기록한다.
  (픽스처 앱 자체엔 영구 애니메이션이 없지만 `walker_test.dart`가 그 경로를 회귀 테스트한다.)
- **Android `takeScreenshot` 데드락.** 앱이 플랫폼 뷰(웹뷰·미디어·카메라)를 품으면
  `convertFlutterSurfaceToImage()` 후 캡처가 오류 없이 멈춘다. 가이드라인·semantics는 정상이므로 측정은
  살아있다. VISUAL은 호스트 `adb exec-out screencap` / `xcrun simctl io` 로 우회한다.

**닫힌 갭 (2026-09-23, 이후 커밋들)**

- **인증 관문 통과.** `references/network-stub.md`가 동작하는 `HttpOverrides` 템플릿을 싣는다.
  자격증명 0개로 관문을 넘어 20화면·4스텝을 측정했다(`843b1fc`, `0b80918`). 남은 것은 아래의
  "공개 재현"뿐 — 메커니즘 자체는 검증됐다.
- **영구 애니메이션.** 데모 픽스처가 "못 잡는다"던 결함은 이제 잡는다 —
  `walker_test.dart`가 `CircularProgressIndicator`로 "never quiets" 경로를 회귀 테스트한다.
- **디바이스·테마 다양성 (2026-09-23 실측).** 데모 픽스처를 네 조건으로 돌렸다.
  - iPhone SE 375x667 @2.0 / iPad Pro 13" **1032x1376 @2.0** — fold 수학 정상(`foldY` 1356,
    `padBottom` 20), 가이드라인 4종 전부 발화. 태블릿 폭은 이제 검증됨.
  - Android 에뮬 411.4x731.4 @2.625 — `foldY` 707.4, 대비 가이드라인 Impeller에서 동작,
    스텝마다 `screenshot: null`(설계대로).
  - **텍스트 스케일 `accessibility-XXXL`** — 측정은 정상이고 실제 열화를 잡는다(세 번째 상품 행이
    semantics 트리에서 사라지고 두 번째 행이 fold 아래로 내려간다). **그런데 `viewport` JSON이
    기본 런과 바이트 단위로 동일**했다 → 산출물이 조건을 구분하지 못했다.
  - **다크 모드** — iOS **시뮬레이터**(`simctl ui … appearance dark`) 런에서 `conditions.platformBrightness`가
    `"dark"`로 기록되는 것 확인. 실기기는 아니다 — 이 저장소에 실기기 런은 하나도 없다.
    픽스처가 `darkTheme`을 선언하지 않아 앱 렌더링은 그대로였다: 확인한 것은 **조건이 기록된다**는 것이지
    다크 팔레트의 대비가 옳게 측정된다는 것이 아니다.
  → 그래서 워커에 `conditions`(brightness·textScaleFactor·a11y 플래그·플랫폼)를 추가했고,
    리포트 scope 절은 이제 단언하지 않고 **인용한다**.

**새로 열린 갭 — 기록만, 코드 수정 안 함 (Strict YAGNI)**

- **태블릿 2-pane에서 덤프는 반쪽이다.** 형제 `Navigator` 둘(master-detail `Row`)이면 나중에 그려진
  pane의 `BlockSemantics`가 앞 pane의 semantics를 지운다. 워커 밖의 프레임워크 동작이라 안에서
  복구 불가 — 그래서 `panesPossiblyBlocked`로 **선언**하고, 덤프 기반 체크는 사라진 pane에 대해
  `not assessable`로 보고한다. 중첩(탭 셸)은 해당 없음이라 ancestry로 판정한다(테스트 3종).
  앱 쪽 해법은 pane마다 `Semantics(container: true)` — 실측으로 둘 다 복구된다.
- **`screenSig`는 플랫폼 간 이식 불가.** Material `BackButton`이 Android에선 label+tooltip,
  iOS에선 tooltip만 → 같은 화면이 `70ed0c2e` / `4ddc18db`. 런 내부 비교만 하므로 체크는 무영향이고,
  **골든 파일**은 어느 플랫폼 산출인지 반드시 밝혀야 한다.

**여전히 미검증**

- **iOS 실기기.** 시뮬레이터 전용이다. (구 메모가 "데모 앱은 시뮬레이터 슬라이스 때문에 못 돈다"고
  적었는데 그건 **비공개 앱** 사정이고 공개 데모 앱엔 해당 없다 — 데모 앱은 시뮬에서 잘 돈다.)
- **관문 통과의 공개 재현.** 메커니즘은 검증됐지만 공개 픽스처엔 HTTP 의존성이 없어
  `## Setup`·스텁·`networkCalls`가 공개적으로 행사되지 않는다. 픽스처에 가짜 관문을 달지 말지는
  **사람이 결정할 일** — 픽스처를 제품으로 키우는 쪽으로 넘어가는 선이다.
- **골든 자동 대조.** `expected-findings.json`은 회귀 오라클인데 `recipe_sync_test.dart`는 **모양만**
  검증한다. 런 출력과의 실제 diff는 아직 사람 손이다.
- **`flutter drive`의 exit code는 오라클이 아니다.** 모든 스텝이 실패해도 0으로 끝난다.
  판단은 반드시 `integration_response_data.json`의 `steps[].status`로.

## 확정된 제품 결정 (2026-09-22)

- **플랫폼 (2026-09-22 도그푸드로 갱신):** iOS 시뮬레이터와 **Android 에뮬레이터 양쪽에서 실행 검증됨.**
  가이드라인 4종과 semantics 덤프는 두 플랫폼 모두 정상이다(`textContrastGuideline`은 Impeller에서도 동작).
  **차이는 스크린샷뿐** — Android에서 앱이 플랫폼 뷰를 품으면 `takeScreenshot`이 데드락하므로 VISUAL은
  호스트 캡처(`adb exec-out screencap` / `xcrun simctl io`)로 잡는다. README는 이 상태 그대로 쓴다:
  "두 플랫폼에서 측정 검증, 스크린샷은 호스트 캡처". 실기기는 여전히 미검증.
- **포지셔닝: "추측하지 않고 측정하는 유일한 Flutter UX 감사."** 초안의 "아무도 저니 단위에 런타임
  증거를 안 붙인다"는 주장은 반증됐다(ux-audit-skill 레포 182개, 저니+라이브 브라우저+스크린샷을
  이미 MIT로 출시한 선행자 존재 — 단 전부 web). 방어 가능한 건 좁은 쪽이다: 실제 픽셀 Rect, 실제 대비
  비율, 실제 semantics 라벨을 돌아가는 앱에서 뽑는다. 경쟁자는 스크린샷 추측이거나 소스 grep이거나 web이다.
  README에서 선행 도구를 부정하지 말고 명시적으로 인정한다.
- **생성 파일: 감사 대상 앱에 쓰되, 기본은 gitignore 안내.** SKILL.md가 생성 경로를 대상 프로젝트의
  `.gitignore`에 추가하도록 안내한다. 재실행 가능·재현 가능하면서 대상 레포에 우리 파일이 커밋되지는
  않는다. 팀이 회귀 테스트로 쓰고 싶으면 명시적으로 승격시킨다.

## 설계 원칙

1. **증거 없는 발견은 쓰지 않는다.** 모든 finding에 증거 레이어(`STATIC`/`RUNTIME`/`VISUAL`/`JOURNEY`)와
   확신도를 붙인다. 못 본 것은 비워두지 말고 `not assessable`로 명시한다.
2. **심각도는 goal 기준.** 같은 결함이라도 저니의 goal을 막으면 4, 우회 가능하면 2.
3. **경쟁하지 않고 얹는다.** 평가 프레임워크·심각도 척도는 선행 연구를 차용하고 출처를 명시한다.
   재발명하지 않는다.
4. **자격증명을 절대 요구하지 않는다.** 사용자에게 아이디·비밀번호·PIN·토큰을 묻지 않는다 —
   저니 파일로도, 환경변수로도, 프롬프트로도. 감사 도구가 비밀번호를 묻는 건 피싱과 같은 모양이고,
   채택을 막고, 실계정을 리포트 파일 한 번의 실수 거리에 둔다. 그리고 **불필요하다** — 워크는 앱
   프로세스 *안에서* 돌기 때문에 앱이 무엇을 보는지 통제할 수 있다.
   기본값은 **네트워크 차단 + 임의 데이터**로 실패 경로를 감사하는 것이고(설정 0, 모든 앱에 적용,
   요청이 기기를 떠나지 않는다), 게이트를 넘어야 하면 `app.main()` 전에 `HttpOverrides.global`로
   HTTP를 스텁한다(앱 소스 수정 0줄). 스텁이 틀리면 스텝이 실패하고 그렇다고 말한다 — 오라클은 그대로다.
   **빨간 스텝을 초록으로 만들려고 실계정을 끌어오지 않는다.**
5. **에이전트 중립.** SKILL.md 표준 포맷. 특정 MCP 서버가 사용자 머신에 있다고 전제하지 않는다 —
   전제해야 한다면 스킬이 그 의존성을 명시적으로 선언해야 한다.
6. **Strict YAGNI.** 지금 쓰지 않는 코드·인터페이스·"미래 대비" 설계는 만들지 않는다.
   화면 자동 탐색, 코드 자동 수정, 성능 프로파일링, 디자인 취향 평가는 **비범위**다.

## 비범위 (명시적으로 안 함)

- 화면 자동 탐색(크롤링) — 저니는 사람이 선언한다
- 코드 자동 수정
- 성능 프로파일링, 시각 디자인 취향 평가("예쁜가")
- 웹/데스크톱 타겟 (v0.1은 모바일 에뮬레이터/시뮬레이터만)

---

## 코드 스타일

- 주석은 *why*를 설명한다. *what*은 코드로 표현한다.
- 디버그용 `print()` / `console.log()` 남기지 않는다.
- 사용자 대면 문서(README, SKILL.md)는 **영어**. 저장소 내부 메모는 한국어 가능.
  → 공개 프로젝트이므로 SKILL.md와 README는 영어가 기본이다.

## 검증

- 스크립트에 로직(분기·파싱·병합·채점)이 있으면 실행 가능한 체크를 하나 남긴다.
  단순 패스스루는 테스트 대상이 아니다.
- 워커·픽스처를 건드렸으면 `cd example/ux_demo_app && flutter test` (48종), 정적 룰을 건드렸으면
  `cd tools/astprobe && dart test` (7종). 둘 다 통과해야 한다.
- `references/walking.md`와 워커 구현은 `recipe_sync_test.dart`로 서로 고정돼 있다 — 레시피에 워커를
  다시 베껴 넣으면 실패한다. 포인터를 고치지, 사본을 만들지 않는다.
- 저니 포맷(`# Goal` / `## Setup` / `## Steps` / `## Priorities`)을 바꿨으면 `example/journey.md`와
  README·SKILL.md의 예시 셋이 같이 움직여야 한다.
