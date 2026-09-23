# prior-art

## VERDICT: partial
The market claim as worded is **REFUTED**. The narrower Flutter-specific claim is **CONFIRMED**.
The licensing question is **CONFIRMED clear** (everything to be borrowed is MIT).
And the plan's runtime layer should be rebuilt on something the plan never mentioned.

Four headline results:
1. **"Nobody attaches runtime evidence to journey-level UX evaluation" is FALSE.**
   182 GitHub repos match `ux-audit-skill`. `dmsakamoto/ux-audit-skill` ships the exact pitch
   ("journeys, never pages", live-browser walk, counted friction, screenshot trail) — MIT, today.
   `denysosadchyi/ux-auditor` does Playwright capture + DOM-accurate annotation. (F2, F11, F12)
2. **But the FLUTTER seat is nearly empty: 3 repos for `flutter ux audit`, vs 182 generic.**
   The one real Flutter competitor (`AjnasNB` + `kakzaki` fork) ships a *static* Python scanner
   and only *prose instructions* to go verify at runtime. Nothing in the field mechanically
   captures Flutter runtime evidence and attaches it to a finding. (F13, F16)
3. **`dart-lang/ai`'s `flutter_driver_user_journey_test` is a PROMPT STRING, ~25 lines of English.**
   Zero evaluation, zero heuristics, zero scoring; it writes a regression test. Not a competitor,
   not a foundation. Its sibling *tools* (`flutter_driver_command`, `widget_inspector`) might be. (F3, F5)
4. **THE ACTIONABLE FIND — and it is not where _PRIOR.md said.** `accessibilityEvaluations` is
   nowhere in `dart-lang/ai` (F4). It is a Flutter framework VM-service extension — and I proved by
   running it that it is **DEAD ON STABLE** (F17, F19). The thing that *does* work on stable today,
   with zero dependencies, is `package:flutter_test`'s `AccessibilityGuideline.evaluate()`, which
   returns exact pixel Rects, measured values and citation URLs. **Ran it. Output in F21.**

---

## Facts

### F1 — EliaAlberti/ux-audit-skill is real; MIT
`curl -s https://api.github.com/repos/EliaAlberti/ux-audit-skill`
```
"full_name": "EliaAlberti/ux-audit-skill"
"html_url": "https://github.com/EliaAlberti/ux-audit-skill"
"description": "Heuristic UX audits from screenshots for Claude Code & Codex with severity-rated
                findings, heuristic citations, annotated screenshots, structured reports."
license spdx_id: MIT     stars: 18
```
(LICENSE text + structure verification in progress — see Unknowns)

### F2 — THE SEAT IS NOT EMPTY. 182 repos.
`curl -s "https://api.github.com/search/repositories?q=ux-audit-skill"` -> `"total_count": 182`
| repo | license | stars | description |
|---|---|---|---|
| EliaAlberti/ux-audit-skill | MIT | 18 | heuristic UX audits from screenshots |
| **dmsakamoto/ux-audit-skill** | **MIT** | 5 | **"task-based UX audits from the user's seat — journeys not pages, counts not vibes"** |
| paulunemoon/ux-audit-skill | MIT | 5 | audits UX across 16 dimensions |
| denysosadchyi/ux-auditor | none | 25 | "Playwright-driven capture, DOM-accurate annotation" (runtime evidence, web) |
| dungnotnull/mobile-app-uxui-audit-agent-skill | none | 5 | mobile UX/UI auditor: Nielsen + HIG + Material |
| phazurlabs/sumi | Apache-2.0 | 47 | 43 UX skills for Claude Code |
| mastepanoski/claude-skills | MIT | 54 | Nielsen heuristics |
| appariciojunior/website-audit-skill | none | 44 | content + UX structure audit |
| uxuiprinciples/agent-skills | none | 16 | evaluate interfaces, detect UX smells |
| EnchStyle/ui-ux-audit-skill | MIT | 4 | 15 categories, severity rubric |
| notacp/ux-laws-audit-skill | MIT | 3 | 10 UX laws |
| jalaalrd/full-stack-audit | none | 39 | 90-point audit |
| devanshuDesai/agent-skills | MIT | 11 | UI/UX design audits |

The defensible remaining claim is NOT "journey-level UX audit" — that exists. It is narrower:
**Flutter-native runtime evidence (real RenderBox geometry + framework a11y evaluations from a
live app) attached to journey-level findings.** Everything above is web/screenshot-based.

### F3 — `flutter_driver_user_journey_test` is a PROMPT, not a tool. Verbatim source.
Installed locally: `~/.pub-cache/hosted/pub.dev/dart_mcp_server-1.1.2/`
`lib/src/utils/names.dart:73-82` — it is the server's ONLY prompt:
```dart
/// The names of all the prompts provided by the server.
enum PromptNames {
  flutterDriverUserJourneyTest('flutter_driver_user_journey_test');
```
`lib/src/mixins/prompts.dart:43-49` description verbatim:
```
Prompts the LLM to attempt to accomplish a user journey in the running app using
flutter driver. If successful, it will then translate the steps it followed into
a flutter driver test and write that to disk.
```
Its full content (prompts.dart:61-88) instructs: navigate home -> ask user for journey ->
drive it with flutter driver -> write an `integration_test/` flutter_driver test ->
`flutter drive --driver <test-path>`.

**It contains ZERO evaluation.** No heuristic, no severity, no screenshot, no measurement,
no accessibility. Its output is a regression test, not a report.
**Verdict: does NOT make flutter-ux-journey redundant. Different product entirely.**

### F4 — `accessibilityEvaluations` is NOT in dart-lang/ai. _PRIOR.md attributed it wrong.
```
$ grep -rn -i "accessib" ~/.pub-cache/hosted/pub.dev/dart_mcp_server-1.1.2/
(no output)
$ grep -rn -i "accessib" ~/.pub-cache/hosted/pub.dev/dart_mcp-0.5.2/
(no output)
```
Zero hits in either the MCP server or the MCP protocol package.

### F5 — The real dart_mcp_server tool surface (names.dart:40-64), verbatim enum:
```
analyzeFiles('analyze_files'), createProject('create_project'), dartFix('dart_fix'),
dartFormat('dart_format'), dtd('dtd'), flutterDriverCommand('flutter_driver_command'),
getActiveLocation('get_active_location'), getAppLogs('get_app_logs'),
getRuntimeErrors('get_runtime_errors'), hotReload('hot_reload'), hotRestart('hot_restart'),
launchApp('launch_app'), listDevices('list_devices'), listRunningApps('list_running_apps'),
lsp('lsp'), pub('pub'), pubDevSearch('pub_dev_search'), readPackageUris('read_package_uris'),
ripGrepPackages('rip_grep_packages'), roots('roots'), runTests('run_tests'),
stopApp('stop_app'), vmService('vm_service'), widgetInspector('widget_inspector')
```
`flutter_driver_command`, `widget_inspector` and `vm_service` are the interesting three —
this IS a plausible foundation for the journey-walk layer (and it is already installed in this
user's Claude Code as `mcp__plugin_dart-flutter_dart-mcp-server__*`).

### F6 — `ext.flutter.accessibilityEvaluations` is in the installed stable SDK (⚠️ SUPERSEDED by F17/F19: registered but non-functional on stable)
Path: `/opt/homebrew/share/flutter/packages/flutter/lib/src/widgets/binding.dart:756-793`
Registered inside `WidgetsBinding.initServiceExtensions()` under **`if (!kReleaseMode)`**
(binding.dart:684) — i.e. **present in every debug and profile build. No feature flag in the
framework guards it.**

Declared at `packages/flutter/lib/src/widgets/service_extensions.dart:117-124`:
```dart
  /// Name of service extension that, when called, will perform accessibility
  /// evaluations on the widget tree and return the results.
  accessibilityEvaluations,
```

### F7 — Exact API of `ext.flutter.accessibilityEvaluations` (verbatim from binding.dart)
Params are all STRINGS (VM service extension convention). `type` is required.
```dart
case 'MinimumTextContrastEvaluation':
  if (parameters case {
    'minNormalTextContrastRatio': final String minNormalTextContrastRatio,
    'minLargeTextContrastRatio':  final String minLargeTextContrastRatio,
  }) { ... MinimumTextContrastEvaluation(...).evaluate(this) ... }
  throw Exception('Invalid arguments');
case 'MinimumTapTargetEvaluation':
  if (parameters case {'targetSize': final String targetSize}) {
    ... MinimumTapTargetEvaluation(size: Size.square(double.parse(targetSize))).evaluate(this) ...
  }
  throw Exception('Invalid arguments');
case 'LabeledTapTargetEvaluation':
  ... const LabeledTapTargetEvaluation().evaluate(this) ...
default:
  throw Exception('unknown type: $type');
```
Return shape (`_formatEvaluationResult`, binding.dart:815-824), verbatim:
```dart
Map<String, List<Map<String, String>>> _formatEvaluationResult(List<Violation> violations) {
  return <String, List<Map<String, String>>>{
    'result': violations.map((Violation violation) {
      return <String, String>{
        'nodeId': violation.node.id.toString(),
        'message': violation.reason,
      };
    }).toList(),
  };
}
```
So: `{"result":[{"nodeId":"<semantics node id>","message":"<reason>"}, ...]}` — structured JSON,
keyed to **semantics node ids**, not prose. This is exactly the structured a11y evidence
_PRIOR.md said Flutter did not provide (it only checked `debugDumpSemanticsTree`, which is prose).

### F8 — The flutter_tools feature flag is Unavailable on stable (⚠️ my inference that it does not gate F6 was WRONG — see F17)
`/opt/homebrew/share/flutter/packages/flutter_tools/lib/src/features.dart:265-273`:
```dart
const accessibilityEvaluationsFeature = Feature(
  name: 'support for accessibility evaluations',
  configSetting: 'enable-accessibility-evaluations',
  environmentOverride: 'FLUTTER_ACCESSIBILITY_EVALUATIONS',
  runtimeId: 'accessibility_evaluations',
  master: FeatureChannelSetting(available: true),
);
```
master-only. Confirmed on this machine (stable 3.47.2):
```
$ flutter config --list
  enable-accessibility-evaluations: (Not set) (Unavailable)
```
**But the flag lives in flutter_tools, and the service-extension registration in the framework
has no flag at all (F6).** Prediction: the extension is callable over the VM service on stable
right now. STILL TO BE PROVEN BY RUNNING IT — see Unknowns.

### F9 — EliaAlberti LICENSE verbatim (MIT, 2026 Elia Alberti). Borrowing is legally clear.
`curl -sL https://raw.githubusercontent.com/EliaAlberti/ux-audit-skill/main/LICENSE`
```
MIT License

Copyright (c) 2026 Elia Alberti

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, ...
```
**No license anywhere in this prior art forbids the assumed borrowing.** MIT only requires the
copyright notice + permission notice be retained in copies/substantial portions. Concretely:
if flutter-ux-journey copies `scripts/annotate.py` or large verbatim chunks of the framework
tables, it must ship Elia's MIT notice (e.g. a `NOTICE`/`THIRD_PARTY.md` or a header comment).
Heuristic *concepts* (Nielsen, WCAG, Fitts) are not copyrightable — only his expression is.

### F10 — Real structure of EliaAlberti/ux-audit-skill (full tree, `git/trees/main?recursive=1`)
```
.gitignore 207        CONTRIBUTING.md 2037    LICENSE 1069      README.md 11798
SKILL.md 17248
examples/README.md 1417   examples/annotations.json 945   examples/report.md 10583
examples/make-example-mockup.py 4403
examples/assets/{signup,signup-annotated,verify-email,verify-email-annotated}.png
scripts/annotate.py 2214
```
**It is ONE file of substance.** No `references/` dir, no progressive disclosure, no multi-file
skill. All 16 frameworks, the severity scale, the Named Checks table and the report template live
inline in a single 17KB `SKILL.md`. Two Python files total, 6.6KB combined.

**Plan corrections about it:**
- "16 frameworks" is CORRECT but only under one counting: the Framework Reference has 12 lettered
  sections A-L, and section E ("Behavioural Laws") expands to 5 (Hick, Fitts, Miller, Jakob,
  Peak-End). 11 + 5 = 16. Sections are: A Nielsen(10) · B Shneiderman(8) · C Gerhardt-Powals(10) ·
  D Bastien & Scapin · E 5 behavioural laws · F Fogg B=MAP · G Cialdini · H Gestalt · I Norman ·
  J Tognazzini · K WCAG 2.1 (static subset) · L Content Design (10, "canonical set for this skill").
- Severity scale is Nielsen 0-4 as assumed, BUT 0 is repurposed: the table is
  `4 Critical / 3 Major / 2 Minor / 1 Cosmetic / ✓ Positive` — there is no "0 = not a problem" row;
  0 is used only as the *positive* colour in annotate.py. Copying it as "Nielsen 0-4" is imprecise.
- "Named Checks" is real and is the most reusable single artifact: 16 stable IDs
  `CTA-AMBIGUITY, DEAD-END, FAKE-AFFORDANCE, CONTRAST-FAIL, TOUCH-TARGET, JARGON-LEAK,
   PROGRESS-BLIND, ERROR-VAGUE, FORM-FRICTION, OVERLOAD, PATTERN-DRIFT, TRUST-GAP, DARK-PATTERN,
   STATE-GAP, HIERARCHY-FLAT, RECALL-TAX`.
- `scripts/annotate.py` is **74 lines**. It reads an `annotations.json` of fractional boxes
  `{"id","sev","x","y","w","h"}` (0-1 of W/H) and draws a coloured rect + a numbered label chip.
  `COLORS = {4:"#D32F2F", 3:"#F57C00", 2:"#F9A825", 1:"#1976D2", 0:"#2E7D32"}`.
  It is Pillow-only, no other deps. **Worth borrowing wholesale** — but note flutter-ux-journey
  can do better than fractional LLM-guessed boxes: it will have real RenderBox rects, so it should
  feed pixel rects, not guesses. That is a genuine differentiator, and it means the script needs a
  ~5-line change (accept px when values > 1), not a rewrite.
- **Its own stated non-goal is our whole thesis.** SKILL.md, verbatim:
  `"Not assessable from static screens" (list in report, never guess): focus visibility, keyboard
   navigation, screen-reader semantics/alt text, reflow/zoom, motion, timing`
  and the frontmatter: `"Do not use for ... code-level accessibility scans of a live DOM."`
  Elia's skill explicitly punts on exactly the layer runtime evidence supplies.

### F11 — ⚠️ dmsakamoto/ux-audit-skill IS the direct competitor for the journey-level claim.
`https://github.com/dmsakamoto/ux-audit-skill` — MIT, 5 stars, 3 files (LICENSE, README 2624B,
SKILL.md 4211B). README verbatim:
```
- **Journeys, never pages.** The unit of audit is one real user task ("set a stop-loss for the
  first time"), executed start to finish in a live browser.
- **Naive execution.** Before every click: *how would I know to click this without having read
  the code?* Every moment that requires insider knowledge is logged as a finding.
- **Numbers, not adjectives.** Clicks, scrolls, back-tracks, dead ends, depth — counted per step,
  with a screenshot trail.
```
SKILL.md verbatim: `The unit of audit is a **journey** (one task), never a page. Page-level polish
falls out of journey findings; it never leads.` It measures click cost, findability, state
visibility, copy honesty, recovery, depth. It drives a **live** app (Claude in Chrome) and captures
a screenshot trail — i.e. **runtime evidence attached to journey-level findings already exists.**

**This refutes the plan's market claim as literally worded.** What it does NOT do:
- web only (requires the Claude in Chrome extension); no Flutter, no mobile, no simulator
- no static pass, no measured geometry, no a11y tree, no framework citations, no Nielsen 0-4
  severity, no annotated images — its findings are ranked `task-blocking / friction / polish`
- 4.2KB of prose, zero scripts

### F12 — ⚠️ denysosadchyi/ux-auditor also attaches runtime evidence (web).
25 stars. Description: `"Repeatable UX-audit toolkit: bilingual playbook, Claude Code skills,
Playwright-driven capture, DOM-accurate annotation."` **DOM-accurate annotation** is the same idea
as RenderBox-accurate annotation, one platform over. Not yet read in detail (see Unknowns).

### F13 — ⚠️ AjnasNB/mobile-app-ux-auditor-skill + its Flutter-first fork is the closest competitor.
`https://github.com/AjnasNB/mobile-app-ux-auditor-skill` — MIT, 2 stars, created 2026-06-27,
last push 2026-07-20. Fork: `kakzaki/mobile-app-ux-auditor-flutter` ("Flutter-first").
Fork tree (`git/trees/main?recursive=1`):
```
SKILL.md 5043                       references/mobile-ux-audit-reference.md 19266
scripts/mobile_ux_static_scan.py 14614   bin/install.js 22547
.claude-plugin/plugin.json          .codex-plugin/plugin.json   agents/openai.yaml
```
Fork README verbatim: `"scanner Flutter-first otomatis (pola native Compose/Views/SwiftUI
di-skip di proyek Flutter), cek tooltip: multi-baris, flag --stack auto|flutter|all.
Terbukti di app Flutter nyata: P1 64 -> 4 tanpa kehilangan temuan valid."`
(= real-world Flutter proof, P1 count 64 -> 4 after tuning.)

SKILL.md step 2 verbatim: `python scripts/mobile_ux_static_scan.py <project-root>` — Flutter-first,
`IconButton` findings only when no `tooltip:` in the constructor block.
SKILL.md step 8 verbatim: `"Verify with the best available evidence: emulator/simulator
walkthrough, screenshots, accessibility scanner, VoiceOver/TalkBack, widget/UI tests, route tests,
or static inspection. State any verification that could not be run."`
Non-negotiable verbatim: `"Do not audit from static screenshots alone when code or an app build
is available."`

**This is the single biggest threat to the plan's positioning.** It already claims: Flutter-first,
static scan + flow map + emulator verification + P0-P3 severity, packaged as a Claude/Codex plugin.
**But the runtime layer is PROSE, not a pipeline.** Its only executable is a *static* Python
scanner. Nothing in the repo captures a screenshot, drives the app, reads a semantics tree, or
measures a RenderBox. Step 8 instructs the LLM to go do that by hand and then confess what it
could not run. **That gap — "told to verify at runtime" vs "runtime evidence is captured
mechanically and attached to the finding" — is the only defensible wedge left.**

### F14 — dungnotnull/mobile-app-uxui-audit-agent-skill: Nielsen 0-4 for mobile already exists.
README verbatim: `Nielsen's 10 Usability Heuristics (1994) with severity rating` /
`Apple Human Interface Guidelines (iOS 18+)` / `Material Design 3 (Android 15+)` /
`Fitts's Law and Hick's Law` / `WCAG 2.1 Mobile` / `ISO 9241-110`, with a table row
`Nielsen's 10 Heuristics | All screens/flows | Severity 0-4 scale`. MIT badge. 5 stars.
So "Nielsen 0-4 severity applied to mobile UX" is NOT novel either.

### F15 — "claude-flutter-ui-skills" EXISTS as named, but is a GENERATOR, not an auditor.
`curl -s "https://api.github.com/search/repositories?q=claude-flutter-ui-skills"` -> total 17.
Top hit: `Naimehossein77/claude-flutter-ui-skills`, 2 stars,
`"Pixel-perfect Flutter UI, smooth animations, GoRouter navigation, and enforced state management
rules."` Nothing to borrow for an audit skill; no overlap, no threat.
(`conalyz` was already verified real + MIT by the prior run — see conalyz.md. No change.)

### F16 — The FLUTTER-specific UX-audit seat is nearly empty. Only 3 repos.
`curl -s "https://api.github.com/search/repositories?q=flutter+ux+audit"` -> `"total_count": 3`
```
kakzaki/mobile-app-ux-auditor-flutter | 0 stars
mz185/pixel-discipline                | 2 stars | "audits and fixes mobile UI/UX using five focused design rules"
pagersloan-afk/cryptoclone_fixed      | 0 stars | (an app, not a tool)
```
Contrast with 182 for `ux-audit-skill`. **The generic UX-audit seat is packed; the Flutter one
is nearly bare, and nobody in it captures runtime evidence mechanically.**

### F17 — ⛔ RAN IT. On stable 3.47.2 the extension is REGISTERED but the evaluations THROW.
Built a probe app with deliberate violations (12x12 tap target, unlabeled 60x60 GestureDetector,
#EEEEEE-on-white text): `<scratch>/a11yprobe/lib/main.dart`
`flutter run -d macos` -> VM service at `http://127.0.0.1:64255/pnMpBpSaTjQ=/`

```
$ curl -s -G "${BASE}ext.flutter.accessibilityEvaluations" \
    --data-urlencode "isolateId=$ISO" \
    --data-urlencode "type=MinimumTapTargetEvaluation" --data-urlencode "targetSize=48.0"
{"jsonrpc":"2.0","error":{"code":-32000,"message":"Server error","data":{"details":
 "{\"exception\":\"Unsupported operation: Accessibility evaluations APIs are not enabled.
   Accessibility evaluations APIs are currently experimental. Do not use accessibility
   evaluations APIs in production applications or plugins published to pub.dev.
   To try experimental accessibility evaluations APIs:
   1. Switch to Flutter's main release channel.
   2. Turn on the accessibility evaluations feature flag. (See flutter config --help)\",
   \"stack\":\"#0 AccessibilityEvaluation.evaluate
     (package:flutter/src/widgets/_accessibility_evaluations.dart:71:7) ...\"}"}},"id":""}
```
Same for `LabeledTapTargetEvaluation` and `MinimumTextContrastEvaluation`.
Control (proves the extension IS registered and the callback DOES run on stable):
```
$ curl -s -G "${BASE}ext.flutter.accessibilityEvaluations" --data-urlencode "isolateId=$ISO"
{"jsonrpc":"2.0","error":{...,"details":"{\"exception\":\"Exception: type parameter is required\",
  \"stack\":\"#0 WidgetsBinding.initServiceExtensions.<anonymous closure>
    (package:flutter/src/widgets/binding.dart:762:13) ...\"}"}}
```
**This corrects F6/F8.** Registration is unguarded (F6 stands), but `AccessibilityEvaluation.evaluate`
has its own gate — `packages/flutter/lib/src/widgets/_accessibility_evaluations.dart:70-73`:
```dart
FutureOr<EvaluationResult> evaluate(WidgetsBinding binding) {
  if (!isAccessibilityEvaluationsEnabled) {
    throw UnsupportedError(_kAccessibilityEvaluationsDisabledErrorMessage);
  }
  return _evaluate(binding);
}
```

### F18 — The gate is a `--dart-define` read from `String.fromEnvironment` (⚠️ but flutter_tools blocks setting it — F19)
`packages/flutter/lib/src/foundation/_features.dart`, verbatim:
```dart
@internal
bool isAccessibilityEvaluationsEnabled = debugEnabledFeatureFlags.contains(
  'accessibility_evaluations',
);

/// The feature flags this app was built with.
@internal
final Set<String> debugEnabledFeatureFlags = <String>{
  ...const String.fromEnvironment('FLUTTER_ENABLED_FEATURE_FLAGS').split(','),
};
```
So the flag is read from a compile-time environment constant, i.e.
`--dart-define=FLUTTER_ENABLED_FEATURE_FLAGS=accessibility_evaluations`.
The flutter_tools feature flag (F8) exists only to *inject* that define. Being unavailable on
stable blocks `flutter config`, not the define. TESTING NOW — result in F19.

Also note the whole API is marked `@internal` with:
```
/// Do not use in production.
/// Flutter will make breaking changes to this API, even in patch versions.
```
Tracking issue: https://github.com/flutter/flutter/issues/32057
**Maturity verdict: EXPERIMENTAL. Breaking changes promised even in patch versions.** A public
skill must not hard-depend on it; it can use it opportunistically and degrade cleanly.

### F20 — Maestro is a real competitor for the journey-walk layer (not for the audit layer).
Web search, maestro.dev / github.com/mobile-dev-inc/Maestro: Maestro drives apps through the
**accessibility layer**, works on Flutter without a per-platform framework, and **ships an MCP
server inside the Maestro CLI** that Claude Code can use to "inspect the screen, tap, scroll,
assert". Also `callstack/agent-device` — "Mobile app automation and verification for AI coding
agents. CLI, MCP server, and typed Node.js API for iOS, Android, ... macOS".
**Implication for the plan:** the journey-WALKING layer is a solved, commoditized problem with at
least three credible providers (Maestro MCP, callstack/agent-device, dart_mcp_server's
flutter_driver_command) plus flutter_skill. Building or depending on a bespoke walker is the
wrong place to spend v0.1's complexity budget. None of them produce a UX *judgment*.

### F19 — ⛔ PROVED UNUSABLE ON STABLE. Two escape hatches tried, both closed.
Attempt 1 — the `--dart-define` implied by F18:
```
$ flutter run -d macos --dart-define=FLUTTER_ENABLED_FEATURE_FLAGS=accessibility_evaluations
FLUTTER_ENABLED_FEATURE_FLAGS is used by the framework and cannot be set using --dart-define
or --dart-define-from-file.

Use the "flutter config" command to enable feature flags.
```
Attempt 2 — `flutter config`, which *appears* to succeed on stable:
```
$ flutter config --enable-accessibility-evaluations
Setting "enable-accessibility-evaluations" value to "true".
$ flutter config --list | grep accessib
  enable-accessibility-evaluations: true (Unavailable)      <-- note "(Unavailable)"
```
Rebuilt and re-ran the app with that config set. **Still throws, identically, all three types.**
flutter_tools accepts the setting but refuses to inject the define on a non-master channel.
```
$ curl -s -G "${BASE}ext.flutter.accessibilityEvaluations" --data-urlencode "isolateId=$ISO" \
    --data-urlencode "type=MinimumTapTargetEvaluation" --data-urlencode "targetSize=48.0"
... "Unsupported operation: Accessibility evaluations APIs are not enabled." ...
```
(config restored to `false` afterwards — the machine's global flutter config is back as found.)

**CONCLUSION: `ext.flutter.accessibilityEvaluations` is unavailable to any user on a stable,
beta or dev Flutter. A public skill CANNOT depend on it.** Revisit when it reaches beta.

### F21 — ✅ THE STABLE-CHANNEL ANSWER. `package:flutter_test` AccessibilityGuideline. RAN IT.
Same probe app, `flutter test` on stable 3.47.2, calling `guideline.evaluate(tester)` directly.
Real output, verbatim:
```
GUIDELINE Tappable objects should be at least Size(48.0, 48.0) passed=false
  reason=SemanticsNode#4(Rect.fromLTRB(394.0, 254.0, 406.0, 266.0), actions: [tap],
  label: "tiny", textDirection: ltr): expected tap target size of at least Size(48.0, 48.0),
  but found Size(12.0, 12.0)
  See also: https://support.google.com/accessibility/android/answer/7101858?hl=en

GUIDELINE Tappable objects should be at least Size(44.0, 44.0) passed=false
  reason=SemanticsNode#4(Rect.fromLTRB(394.0, 254.0, 406.0, 266.0), ...): expected tap target
  size of at least Size(44.0, 44.0), but found Size(12.0, 12.0)
  See also: https://developer.apple.com/design/human-interface-guidelines/ios/visual-design/adaptivity-and-layout/

GUIDELINE Tappable widgets should have a semantic label passed=false
  reason=SemanticsNode#5(Rect.fromLTRB(370.0, 266.0, 430.0, 326.0), actions: [tap]):
  expected tappable node to have semantic label, but none was found.

GUIDELINE Text contrast should follow WCAG guidelines passed=false
  reason=SemanticsNode#6(Rect.fromLTRB(314.5, 326.0, 485.5, 346.0), label: "low contrast", ...):
  Expected contrast ratio of at least 4.5 but found 1.10 for a font size of 14.0.
  The computed colors was: light - Color(... red: 0.9961, green: 0.9686, blue: 1.0000 ...),
  dark - Color(... 0.9333, 0.9333, 0.9333 ...)
  See also: https://www.w3.org/TR/UNDERSTANDING-WCAG20/visual-audio-contrast-contrast.html
```
Declared in `/opt/homebrew/share/flutter/packages/flutter_test/lib/src/accessibility.dart`:
```
:785  const AccessibilityGuideline androidTapTargetGuideline = MinimumTapTargetGuideline(...48dp)
:800  const AccessibilityGuideline iOSTapTargetGuideline     = MinimumTapTargetGuideline(...44pt)
:818  const AccessibilityGuideline textContrastGuideline     = MinimumTextContrastGuideline();
:825  const AccessibilityGuideline labeledTapTargetGuideline = LabeledTapTargetGuideline._();
```
Test-file usage: `await expectLater(tester, meetsGuideline(androidTapTargetGuideline));`
Probe files kept at `<scratch>/a11yprobe/` (`lib/main.dart`, `test/a11y_test.dart`).

**Why this is the whole ballgame.** Each violation arrives with:
- an exact **pixel `Rect`** -> feeds annotate.py directly, no LLM coordinate guessing (F10)
- the **measured vs required value** ("found Size(12.0,12.0)", "found 1.10") -> "counts not vibes"
- the **semantics label** (or its absence) -> journey-level recall/jargon analysis
- a **canonical citation URL** (Google a11y / Apple HIG / W3C WCAG) -> Elia's "cite by name" rule
- stable, non-experimental, in every Flutter install, **zero new dependencies**
The same `WidgetTester` API is what `package:integration_test` runs on a real device/simulator,
so a journey walk written as an integration_test can call these at every step.

### F22 — awesome-list coverage: nothing to worry about, nothing to reuse.
`ComposioHQ/awesome-claude-skills` (75k stars) and `travisvn/awesome-claude-skills` (15k): fetching
each README and grepping `-iE "\bux\b|flutter"` returned **zero lines** in both. No UX-audit and
no Flutter skill is listed in the two largest directories. Discovery there is an open lane.

## Exact interface

**`package:flutter_test` accessibility guidelines — VERIFIED WORKING, stable 3.47.2 (use this)**
```dart
// flutter_test/lib/src/accessibility.dart
const AccessibilityGuideline androidTapTargetGuideline;  // 48x48 dp
const AccessibilityGuideline iOSTapTargetGuideline;      // 44x44 pt
const AccessibilityGuideline textContrastGuideline;      // WCAG 4.5 / 3.0
const AccessibilityGuideline labeledTapTargetGuideline;  // tappable must have a label

abstract class AccessibilityGuideline {
  Future<Evaluation> evaluate(WidgetTester tester);   // -> Evaluation(passed: bool, reason: String?)
  String get description;
}
Matcher meetsGuideline(AccessibilityGuideline guideline);
```
Requires `final handle = tester.ensureSemantics();` before pumping, `handle.dispose()` after.
`reason` is a newline-joined block, one paragraph per violation, each beginning
`SemanticsNode#<id>(Rect.fromLTRB(l, t, r, b), actions: [...], label: "...")` and ending
`See also: <citation url>`. **Parseable with one regex; no JSON, no `nodeId` indirection.**

**`ext.flutter.accessibilityEvaluations` — DO NOT USE (master channel only, F17/F19)**
```
GET http://127.0.0.1:<port>/<token>/ext.flutter.accessibilityEvaluations
    ?isolateId=isolates/<n>&type=MinimumTapTargetEvaluation&targetSize=48.0
    ?isolateId=...&type=LabeledTapTargetEvaluation
    ?isolateId=...&type=MinimumTextContrastEvaluation
        &minNormalTextContrastRatio=4.5&minLargeTextContrastRatio=3.0
-> on master: {"result":[{"nodeId":"<semantics id>","message":"<reason>"}]}
-> on stable: JSON-RPC error -32000, "Accessibility evaluations APIs are not enabled."
```
All params are strings. `type` required. Missing `type` -> `Exception: type parameter is required`.

**dart_mcp_server v1.1.2** — prompt `flutter_driver_user_journey_test(user_journey?: String)`.
Tools incl. `flutter_driver_command`, `widget_inspector`, `vm_service`, `launch_app`, `list_devices`.
Already installed in this user's Claude Code as `mcp__plugin_dart-flutter_dart-mcp-server__*`.

**EliaAlberti annotate.py** — `python3 annotate.py annotations.json`, where annotations.json is
`[{"image","out","marks":[{"id","sev","x","y","w","h"}]}]`, x/y/w/h fractions of W/H.
`COLORS = {4:"#D32F2F",3:"#F57C00",2:"#F9A825",1:"#1976D2",0:"#2E7D32"}`. 74 lines, Pillow only.

**kakzaki fork static scanner** — `python scripts/mobile_ux_static_scan.py <project-root>`,
flags `--stack auto|flutter|all`.

## Plan impact

1. **Kill the "empty seat" claim from all public copy.** It is refuted (F2/F11/F12). Replace with
   the claim the evidence actually supports: *the only Flutter UX audit that measures instead of
   guessing — real pixel Rects, real contrast ratios, real semantics labels, pulled from a running
   app.* Every competitor found either guesses from screenshots (Elia, dungnotnull), greps source
   (AjnasNB/kakzaki), or is web-only (dmsakamoto, denysosadchyi).

2. **REPLACE the plan's step-2 runtime layer.** Plan says `flutter_skill` CLI for a11y tree +
   RenderBox measurement + step timing. `package:flutter_test`'s four guidelines (F21) deliver
   tap-target (48dp AND 44pt), contrast, and missing-label — measured, cited, with pixel Rects —
   from the SDK the user already has. No third-party package, no app modification (flutter_skill
   requires editing 2 lines of the target app, per flutter_skill.md), no unverified-uploader
   supply-chain risk. **Recommendation: the journey walk is an `integration_test` that calls the
   guidelines at each step, not a shell CLI driving a detached app.** That collapses steps 1-2 of
   the pipeline and kills two dependencies.

3. **Delete `ext.flutter.accessibilityEvaluations` from the plan entirely.** Master-channel only,
   `@internal`, and Flutter explicitly promises "breaking changes ... even in patch versions"
   (F18). Note it as a future upgrade path in a comment; do not write code against it.

4. **Do not build a journey walker.** Maestro (accessibility-layer driving, works on Flutter,
   ships an MCP server), callstack/agent-device, and dart_mcp_server's `flutter_driver_command`
   all already walk apps (F20/F5). v0.1's complexity budget belongs in the *judgment* layer —
   goal-anchored severity, cross-step findings, the merge — which is the part nobody has.

5. **Licensing: green light, with one obligation.** Elia's MIT (F9) permits copying annotate.py
   and the framework tables; ship his copyright + permission notice in a `NOTICE`/`THIRD_PARTY.md`.
   AjnasNB MIT, dmsakamoto MIT, conalyz MIT (prior run), flutter_skill MIT (prior run).
   Flutter SDK is BSD-3 — using its public API imposes nothing.
   **No license found anywhere forbids the assumed borrowing.**
   Two precision corrections to what the plan says it is borrowing: the severity scale is
   `4/3/2/1/✓Positive`, not a literal 0-4 (F10); "16 frameworks" is right only if you expand
   section E's five behavioural laws (F10).

6. **PUBLIC-REPO CONSTRAINT — what F21 changes.** The guideline output embeds the app's own
   `Semantics` labels verbatim (`label: "tiny"` above would be real product copy) and pixel
   geometry of real screens. **Findings JSON and any annotated screenshot are therefore
   private-product artifacts and must never be committed.** Concretely for v0.1:
   - ship the skill + `annotate.py` + the probe app only; `.gitignore` the entire output dir
   - the repo's worked example must use a **synthetic** app built for the purpose — the
     `a11yprobe` app in this scratchpad is already exactly that and is safe to publish
   - never commit `journey.yaml` from the dogfood app (route names + goal text are product info)

## Unknowns
- `denysosadchyi/ux-auditor`'s actual annotation implementation — listed, not read.
- `kakzaki`'s `mobile_ux_static_scan.py` rule inventory (14.6KB) — not read; needed before deciding
  whether the static pass is even worth writing vs. borrowing (it is MIT).
- Whether `package:integration_test` on a real iOS simulator lets `AccessibilityGuideline.evaluate`
  run mid-journey (proved in `flutter test` only, which is a headless 800x600 harness).
  **This is the single riskiest untested assumption in recommendation #2 — test it first.**
- `flutter_driver_command` vs `flutter_skill` head-to-head — not run.
- skills.sh directory — not reachable/checked; only the two largest awesome-lists were grepped.
- Whether any of the 182 `ux-audit-skill` repos beyond the 13 listed is a closer duplicate.
