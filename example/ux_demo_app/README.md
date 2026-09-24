# ux_demo_app

The public fixture for [flutter-ux-journey](../../README.md). No backend, no login, no real data —
a `com.example.*` scaffold that exists to be audited.

**Do not fix the defects below.** They are seeded on purpose, and they are what
[`../expected-findings.json`](../expected-findings.json) is pinned against. "Fixing" one silently
invalidates the golden and the worked report; `test/fixture_test.dart` fails loudly when you do.

## The six seeded defects

| # | Defect | Where | What it exercises |
|---|---|---|---|
| 1 | The promo dismiss `×` is 24×24 lpx | `lib/main.dart:134` | `iOSTapTargetGuideline` / `androidTapTargetGuideline` |
| 2 | The search `IconButton` has neither `tooltip:` nor `semanticLabel:` | `lib/main.dart:73` | `labeledTapTargetGuideline`, and the static probe |
| 3 | A product card is one merged semantics node with a tap action and no `isButton` | `lib/main.dart:155` | tap targets enumerated by *action*, not by flag |
| 4 | `#DDDDDD` body text on a white scaffold | `lib/main.dart:89` | `textContrastGuideline` |
| 5 | The screen after a removal has no way back and nothing on the stack | `lib/main.dart:235` (`RemovedScreen`) | `DEAD-END`, measured as `canPop == false` |
| 6 | Removal destroys the product on the first tap, with no confirmation | `lib/main.dart:213` (`DetailScreen`) | `TRUST-GAP` — only visible at journey level |

Two traps are seeded alongside them, for the walker rather than for the report: the `Sort` button is
labelled by `tooltip:` only (a matcher reading `label` alone never finds it), and two products share
the substring "Side Table" (a selector must report ambiguity, not take the first hit).

## Run it

```bash
flutter test                                   # 48 tests: the walker's helpers, the fixture's oracle
flutter drive --driver=test_driver/integration_test.dart \
              --target=integration_test/ux_journey_test.dart -d <device-id>
```

The journey being walked is [`../journey.md`](../journey.md); the report it produces is
[`../report.md`](../report.md), with its screenshots in [`../screens/`](../screens).

Steps 2 and 3 are **expected to fail** — that is the fixture working. `flutter drive` exits 0 either
way, so read `steps[].status` in `build/integration_response_data.json`, never `$?`.

Verified on an iPhone SE (3rd gen) simulator and an Android emulator (API 36). On Android the walk
records `screenshot: null` on every step by design; capture from the host with
`adb exec-out screencap -p` instead.
