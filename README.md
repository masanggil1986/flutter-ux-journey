# flutter-ux-journey

A Claude Agent Skill that audits a **running** Flutter app one *user journey* at a time, and scores
what it finds against that journey's goal (Nielsen 0–4 severity).

**The pitch: the only Flutter UX audit that measures instead of guessing.** Every finding carries
evidence pulled out of a live app — real pixel `Rect`s, real contrast ratios, real semantics labels —
not a model's estimate of what a screenshot probably looks like.

> **Platform, stated up front: simulators and emulators only, and screenshots differ per platform.**
> The pipeline was built and run end to end on an iOS simulator (iPhone SE, iOS 18.6) and on an
> Android emulator (API 36, arm64), both on Flutter 3.47.2 stable. Measurement — the four guidelines
> and the semantics dump — works on both; `textContrastGuideline` does run under Impeller.
> **Screenshots are the exception.** On Android, `takeScreenshot` deadlocks, with no error and no
> timeout, whenever the app embeds platform views (a webview, a media surface, a camera preview) —
> measured against a production app. The walk still measures; the visual layer is captured from the
> host instead (`adb exec-out screencap` / `xcrun simctl io`), or reported as not assessable.
> **Real devices are not verified and are not claimed.**

## Install

```
/plugin marketplace add masanggil1986/flutter-ux-journey
/plugin install flutter-ux-journey@flutter-ux-journey
```

Requirements: the Flutter SDK (Dart comes with it) and a booted iOS simulator. **No third-party
packages, in any language.** Everything the skill uses — `package:analyzer`, `package:integration_test`,
`package:flutter_test` — ships inside the Flutter SDK you already have.

## 60 seconds to a report

1. Write a `journey.md` next to your app. A goal line and numbered steps, each with what should happen:

   ```markdown
   # Journey: first purchase
   Goal: a first-time user completes checkout in under 60 seconds without leaving the app.

   1. Tap "Shop" — the product list appears.
   2. Tap the first product — a price and an "Add to cart" button are visible.
   3. Tap "Add to cart" — the cart badge reads 1.
   4. Tap "Checkout" — the payment form appears.
   5. Tap "Pay" — a confirmation screen names the order.
   ```

2. Boot a simulator, then ask Claude: **"audit journey.md against this app"**.
3. Read `report.md`. Each finding names its evidence layer (`STATIC` / `RUNTIME` / `VISUAL` /
   `JOURNEY`), its measured numbers, and a severity scored against *your* goal — the same defect is a
   4 when it blocks the goal and a 2 when there is a way around it.

The skill writes a generated `integration_test/ux_journey_test.dart` (plus a driver file) into the
app being audited, and tells you to add those paths to that app's `.gitignore`. Reruns are
reproducible; nothing of ours gets committed to your repo unless you decide to promote it.

## How it works

```
journey.md
  └─ 0. preflight   confirm the parsed goal + steps before touching a simulator
     1. static      package:analyzer over the source — missing labels, unlabeled tap handlers
     2. walk        a generated integration_test, run with `flutter drive`
     3. visual      the model reads the screenshots the walk captured
     4. merge       findings deduped, scored 0–4 against the goal, written up
```

Steps 3 and 4 are the model following written heuristics, not scripts. Scoring a tap target as fatal
*here* and tolerable *there* depends on the journey's goal; that is judgement, and a script doing it
would only be judgement in a costume.

The walk runs **inside** the app's own test process rather than steering it from outside. That is not
a style choice: structured semantics (label / value / tooltip / role / flags / actions / rect) and
Flutter's four built-in accessibility guidelines are reachable only from in-process. Over the VM
service you get a prose dump and none of the geometry. Details and receipts in
[`docs/day1/native-runtime.md`](docs/day1/native-runtime.md).

## What it actually measures

Flutter ships four accessibility guidelines in `package:flutter_test`; all four were run on a real
simulator and return a node, a pixel `Rect`, the measured value and the required value:

| guideline | what it returns |
|---|---|
| `iOSTapTargetGuideline` / `androidTapTargetGuideline` | `expected tap target size of at least Size(44.0, 44.0), but found Size(24.0, 24.0)` + the node's `Rect` |
| `labeledTapTargetGuideline` | every tappable node with no semantic label |
| `textContrastGuideline` | `Expected contrast ratio of at least 4.5 but found 3.68 for a font size of 14.0` — computed from real rendered pixels |

Plus, per step: the full semantics tree as JSON, a PNG screenshot, and wall-clock timing.

## What this cannot see

Honesty is most of the product here. A finding without evidence does not get written, and what could
not be assessed is listed as `not assessable` instead of quietly omitted.

- **Screens you did not declare.** There is no crawler. The journey is written by a human, on purpose.
- **Real devices.** Simulators and emulators only in v0.1 (see the banner). Real-device-only
  behaviour — permission dialogs, push, deep links, biometrics — is out of reach. Note also that an
  app whose native SDKs drop the simulator slice cannot be built for the iOS simulator at all; on
  such apps, use the Android emulator or a real device.
- **Anything with no semantics node.** Tappables are enumerated by *tap action*, not by widget type,
  so custom-painted decoration that exposes nothing to the semantics tree is invisible to the walk.
- **Whether a screen reader actually sounds right.** Labels and roles are measured; VoiceOver's real
  announcement order and phrasing are not.
- **Contrast, precisely.** `textContrastGuideline` partitions rendered pixels into light and dark
  naively; in our own probe it picked up an adjacent button's colour. The ratios are measured, not
  authoritative — treat a borderline result as a prompt to look, not as a verdict.
- **Performance.** Per-step wall clock only. Frame timing costs 4–6 seconds per measured action, so it
  is not on by default, and profiling is explicitly out of scope.
- **Taste.** "Is this pretty" is not a heuristic. Neither is automatic code fixing — the report tells
  you; it does not edit your app.

## Prior art

This project is **not** the first journey-level UX auditor, and any README claiming otherwise is one
GitHub search away from being disproved. Journey-level auditing with a live browser and a screenshot
trail already ships under MIT today:

- [dmsakamoto/ux-audit-skill](https://github.com/dmsakamoto/ux-audit-skill) (MIT) — "journeys, never
  pages", driven in a live browser, friction counted per step. The same thesis, one platform over.
- [denysosadchyi/ux-auditor](https://github.com/denysosadchyi/ux-auditor) — Playwright capture with
  DOM-accurate annotation. DOM-accurate is exactly the idea, for the web.
- [EliaAlberti/ux-audit-skill](https://github.com/EliaAlberti/ux-audit-skill) (MIT) — heuristic audits
  from screenshots, with the Named Check IDs and report skeleton this project borrows. See
  [CREDITS.md](CREDITS.md).
- [AjnasNB/mobile-app-ux-auditor-skill](https://github.com/AjnasNB/mobile-app-ux-auditor-skill) (MIT)
  and its Flutter-first fork
  [kakzaki/mobile-app-ux-auditor-flutter](https://github.com/kakzaki/mobile-app-ux-auditor-flutter) —
  the closest Flutter neighbour. It ships a static Python scanner and then *instructs* the model to go
  verify at runtime by hand.

What is left after subtracting all of that is narrow, and it is the only thing this project claims:
**Flutter-native runtime evidence — real geometry and framework accessibility evaluations captured
mechanically from a live app — attached to journey-level findings.** The web tools cannot reach a
Flutter canvas; the Flutter tool measures nothing at runtime. Survey and counts:
[`docs/day1/prior-art.md`](docs/day1/prior-art.md).

## Relationship to conalyz and flutter_skill

Both were planned dependencies. Both were installed, run, and dropped on measured evidence — this
project does not depend on either.

- **[conalyz](https://pub.dev/packages/conalyz)** — a real MIT static analyzer, but its tap-target
  rules returned 0 hits across 1,083 files of a real app, and it POSTs a machine fingerprint to a
  third-party server on every run (one beacon still goes out after opting out). Replaced by ~60 lines
  of `package:analyzer`. → [`docs/day1/conalyz.md`](docs/day1/conalyz.md)
- **flutter_skill** — it does connect to an iOS simulator, but it returns `success: true` for taps on
  widgets that do not exist. With no oracle, a walker confidently reports UX defects on screens it
  never reached, which is worse than reporting nothing. Replaced by `integration_test` +
  `flutter_test`, where `tester.tap` throws on a finder miss and therefore reports an outcome rather
  than a dispatch. → [`docs/day1/flutter_skill.md`](docs/day1/flutter_skill.md)

Neither judgement is about the quality of those projects in general; both are about whether they could
carry this project's specific load.

## Licence

MIT — see [LICENSE](LICENSE). Third-party attribution in [CREDITS.md](CREDITS.md).
