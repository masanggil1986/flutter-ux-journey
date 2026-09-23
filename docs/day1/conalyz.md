# conalyz

## VERDICT: refuted — do NOT depend on conalyz. Write ~60 lines of `package:analyzer` instead.

It works, it's MIT, it's real. It is still the wrong dependency for this project, for three
independent reasons, any one of which is sufficient:
1. It POSTs a machine-fingerprinted profile of the scanned codebase to a third-party server on
   every run, by default, and fires a beacon even when you opt out. (Fact 3)
2. 70% of its output is two rules that are pure noise, and its single most important rule for
   THIS project — tap target size — is a regex that never fires. (Facts 5, 6)
3. The whole useful part is ~60 lines of `package:analyzer`, which I wrote and ran. (Fact 8)

---

## Facts

### 1. LICENSE — MIT. Legally fine to depend on, shell out to, or fork.
`~/.pub-cache/hosted/pub.dev/conalyz-1.1.0/LICENSE`:
```
MIT License

Copyright (c) 2025 Conalyz Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, ...
```
GitHub API confirms `"license": {"spdx_id": "MIT"}` on https://github.com/conalyz/conalyz_cli.
No copyleft. Copyright holder is the vague "Conalyz Contributors", not a named legal entity.
**So the answer to "can a public MIT skill depend on it?" is: legally yes. Fact 3 is why the
answer is still no.**

### 2. It is a small `analyzer`-based AST linter. 13 lib files, 5904 lines total.
`pubspec.yaml` verbatim:
```
environment:
  sdk: ">=3.0.0 <4.0.0"
dependencies:
  args: ^2.4.2
  path: ^1.8.3
  analyzer: ^13.0.0
  glob: ^2.1.2
  intl: ^0.20.2
  yaml: ^3.1.2
  http: ^1.6.0
  crypto: ^3.0.7
```
`wc -l lib/src/*.dart`: optimized_ast_analyzer 2606, usage_storage_service 731,
ast_report_generator 637, flutter_specific_rules 599, usage_models 355, telemetry 276,
usage_command 227, line_counter_service 225, web_rules 205, update_command 31,
platform_type 11, constants 1. **The actual rules are 804 lines (flutter_specific_rules +
web_rules); 1289 lines are usage-tracking and telemetry machinery.** `http` and `crypto` exist
only to phone home and self-update.

### 3. *** BLOCKER *** It phones home on every run, by default, with a stable machine id.
`~/.pub-cache/hosted/pub.dev/conalyz-1.1.0/lib/src/telemetry.dart`:
```dart
const String _telemetryUrl = 'https://conalyz.codeanalyer.workers.dev';

String _computeMachineId() {
  final raw = Platform.localHostname + Platform.operatingSystemVersion;
  return sha256.convert(utf8.encode(raw)).toString();
}
```
`bin/conalyz.dart:297` calls `Telemetry.trackAnalysis(...)` unconditionally at the end of every
successful analysis. Payload keys, verbatim from `_doTrackAnalysis`:
```dart
'client_id': _computeMachineId(),   // persistent per-machine fingerprint
'event': 'analysis_complete',
'files_scanned', 'lines_scanned', 'total_issues',
'severity_breakdown': severityBreakdown,
'issues_summary': issueCounts,       // per-rule defect counts for the scanned app
'project_size', 'is_flutter', 'is_monorepo', 'has_tests',
'is_ci', 'platform', 'first_time_run',
'issues_fixed_since_last_run', 'regression_detected', 'exit_reason',
```
The first-run notice is technically accurate on its narrow claim:
```
💡 [conalyz] Notice: conalyz collects anonymous usage data (OS, issue types, command flags).
   No code, filenames, or personal data is collected.
   Opt out anytime: export CONALYZ_NO_ANALYTICS=true
```
No source and no filenames leave the machine. What DOES leave is a longitudinal behavioural
fingerprint of a private codebase — repo shape, size bucket, monorepo-or-not, test presence,
per-rule defect profile, and whether defects rose or fell since the last run — keyed to a stable
machine id, sent to a Cloudflare Worker whose hostname is a misspelling of "codeanalyzer".

**It also defies `DO_NOT_TRACK`.** Opting out sends one beacon announcing that you opted out:
```dart
bool _shouldSkip() {
  if (env['CONALYZ_NO_ANALYTICS'] == 'true') return true;
  if (env['DO_NOT_TRACK'] == '1') return true;
  if (env.containsKey('CI') && env['CONALYZ_ANALYTICS'] != 'true') return true;
  return false;
}
...
// in checkFirstRunNotice(), which runs before every analysis:
if (_shouldSkip()) { await _maybeTrackOptOut(); }
// -> POST {'client_id': <machine id>, 'event': 'opted_out', 'version', 'platform'}
```
The comment in-source says the quiet part out loud:
```dart
// Fire a single one-time event when the user has opted out, so we can
// understand which regions opt out.
```
A public skill cannot ship a default path that does this to other people's proprietary apps.
Telling users "also set CONALYZ_NO_ANALYTICS=true" is a documentation burden we would be
creating for ourselves, and it still fires the opt-out beacon once per machine.

Working kill-switch, for local use: `CONALYZ_NO_ANALYTICS=true` (or `DO_NOT_TRACK=1`, or any
`CI` var set) suppresses all analysis/error events. To also suppress the opt-out beacon:
`touch ~/.config/conalyz/opt_out_tracked.flag` before the first run. (I verified both — after my
runs `~/.config/conalyz/last_run.json` does not exist, i.e. `_doTrackAnalysis` never ran.)

### 4. It is an upsell funnel for a paid/brew product.
`bin/conalyz.dart:419`:
```dart
hints.add('  Runtime analysis available → brew install conalyz/tap/conalyz');
```
printed on every run. The pub.dev CLI is the free static tier; runtime analysis — **exactly what
this project's step 2 does** — is the thing they are selling. Building our step-1 on their
free tier means building on a competitor's lead-gen funnel.

### 5. Rule inventory: ~50 rule types, ALL a11y — no code-style noise. But the distribution is brutal.
Full type list extracted from `grep -hoE "type: '[^']+'" lib/src/*.dart` (50 distinct):
Animation Without Motion Control, Button Without Label, Color Contrast Issue, Color-Only
Information, Disabled Element Without Explanation, Empty Text Widget, Error Identification,
Error Not Announced, GestureDetector Without Semantics, Heading Structure, Incomplete Semantics,
Live Region, Missing Alt Text, Missing ARIA Labels, Missing Checkbox Semantics, Missing
Dismissible Handler, Missing Focus Management, Missing Focus Order, Missing Form Grouping,
Missing Icon Label, Missing IconButton Label, Missing InkWell Semantics, Missing Navigation
Structure, Missing Page Title, Missing Progress Indicator Label, Missing Reduced Motion Support,
Missing Refresh Semantics, Missing Semantic HTML, Missing Slider Semantics, Missing Switch
Semantics, Missing Tab Semantics, Missing Timeout Control, Non-semantic Interactive Element,
Scaffold Navigation, Semantic Exclusion Review, Semantic Traversal Order, Semantic Traversal,
Small Tap Target, Small Text Size, Tab Order, Table Structure, TextField Without Label, Theme
Color Recommendation, Unnecessary MergeSemantics, Vague Text Content, Web ARIA, Web Focus,
Web Semantics, Web Title, Text Scaling Issue.

Severity is a hardcoded string per rule site: 3 `critical`, 19 `high`, 22 `medium`, 4 `low`.

**So the "2369 issues = code-style noise" hypothesis is REFUTED — there is no code-style rule in
it at all. The noise is false positives inside a11y rules.** Measured, aggregate over 5 real
local Flutter projects, 1083 files, 2634 violations (2.4/file):

| n | % | severity | type |
|---|---|---|---|
| 1104 | 41.9% | low | Theme Color Recommendation |
| 741 | 28.1% | medium | Text Scaling Issue |
| 244 | 9.3% | medium | Missing Icon Label |
| 173 | 6.6% | high | GestureDetector Without Semantics |
| 91 | 3.5% | medium | Missing Progress Indicator Label |
| 89 | 3.4% | high | Button Without Label |
| 66 | 2.5% | critical | Missing Alt Text |
| 44 | 1.7% | critical | Missing IconButton Label |
| 27 | 1.0% | low | Missing Navigation Structure |
| 18 | 0.7% | medium | Missing Refresh Semantics |
| 16 | 0.6% | medium | Missing Reduced Motion Support |
| 7 | 0.3% | high | Small Text Size |
| 5 | 0.2% | high | Missing Checkbox Semantics |
| 4 | 0.2% | medium | Missing Form Grouping |
| 3 | 0.1% | medium | Missing Slider Semantics |
| 2 | 0.1% | high | Missing Switch Semantics |

**Two rules are 70% of all output.** `Theme Color Recommendation` (41.9%) is not a contrast
measurement — it is a blanket "you wrote a color literal" nag; `optimized_ast_analyzer.dart:1041`
`if (_usesCustomColorsWithoutTheme(widget))` → message `'Consider using Theme colors for better
accessibility compliance'`. Zero actual contrast math. `Text Scaling Issue` (28.1%) is the same
shape.

**Signal-to-noise: ~30% usable at best.** Drop those two rules and you are at 789 findings over
1083 files (0.73/file), of which the genuinely actionable label rules (Missing Icon Label,
GestureDetector Without Semantics, Button Without Label, Missing Alt Text, Missing IconButton
Label) are 616 = 23% of raw output. **Filtering is mandatory, not optional.** And 34 of its 50
rules produced zero hits across 1083 files.

### 6. *** Its tap-target rule is broken. 0 hits in 1083 files. ***
This matters more than anything else here, because tap target is a core UX-journey measurement.
`lib/src/flutter_specific_rules.dart:103`:
```dart
bool _hasAdequateTapTargetSize(WidgetInfo widget) {
  final code = widget.sourceCode;
  // Check for explicit sizing
  if (code.contains(RegExp(r'width:\s*[4-9][0-9]')) ||
      code.contains(RegExp(r'height:\s*[4-9][0-9]')) ||
      code.contains('constraints:') ||
      code.contains('padding:')) {
    return true;
  }
  // IconButton and buttons typically have adequate default sizes
  return ['IconButton', 'ElevatedButton', 'TextButton'].contains(widget.type);
}
```
A substring search for `padding:` anywhere in the widget's source text = "tap target is fine".
`width:\s*[4-9][0-9]` also matches `width: 400`. It is a regex pretending to be a measurement.
Empirically it produced **0 `Small Tap Target` findings across 1083 files**, while the sibling
rule over the same widget set (`GestureDetector Without Semantics`) fired 173 times — proving
the rule ran and always returned "adequate".

**Conclusion for the plan: tap target size is not statically knowable and conalyz does not know
it. It must come from the runtime RenderBox pass (step 2). This de-values step 1 and confirms
step 2 is the load-bearing part of the pipeline.**

### 7. Maintenance: young, thin, single-vendor, low adoption.
- pub.dev API `https://pub.dev/api/packages/conalyz`: latest **1.1.0, published 2026-07-02**
  (~2.7 months before today 2026-09-22). 10 versions total, first 0.1.2 on 2026-04-06.
  Whole lifetime is 3 months of releases, then quiet.
- pub.dev score API: `grantedPoints 150 / maxPoints 160`, `likeCount 11`,
  `downloadCount30Days 299`.
- GitHub API `conalyz/conalyz_cli`: `stargazers_count 13`, `open_issues_count 1`,
  `pushed_at 2026-07-02T01:07:39Z`, `created_at 2025-11-22`, `archived false`.
- No named maintainer; copyright is "Conalyz Contributors".

299 downloads/month and 13 stars is a hobby project with a commercial tail. Not something to
make a load-bearing dependency of a public skill.

### 8. The fallback is not a fallback — it's the better primary. I built and ran it.
**custom_lint resolves fine on this SDK — the plan's worry is refuted.** `dart pub get` with
`custom_lint: ^0.8.0`, `custom_lint_builder: ^0.8.0`, `analyzer: ^8.0.0` on the local SDK:
`Changed 43 dependencies!`, exit 0. (Local SDK resolves `analyzer 8.x`, not the `^13.0.0` in
conalyz's pubspec — conalyz is `dart pub global activate`d so it carries its own resolution.)

But **custom_lint is the wrong tool anyway**: it is a plugin framework for IDE/`dart analyze`
integration, which this skill does not need. A skill needs a headless AST walk. That is
`package:analyzer` alone.

Proof — `<scratch>/astprobe/bin/probe.dart`, **60 lines, one dependency**,
run against a real local Flutter app's `lib/`:
```
gradient_btn_icon_top.dart:27  GestureDetector  args={onTap, child}
pagenation.dart:26  InkWell  args={onHighlightChanged, onTap, child}
pagenation.dart:107  InkWell  args={onHighlightChanged, onTap, borderRadius, child}
idle_detector.dart:43  GestureDetector  args={behavior, onTap, onPanUpdate, child}
bounce_btn.dart:65  GestureDetector  args={onTapDown, onTapUp, onTapCancel, onTap, child}
== targets seen: 68, unlabeled: 68
```
~3s wall clock. Same finding class as conalyz's #4 rule, plus the actual argument list as
evidence — which conalyz's JSON does not give you.

**GOTCHA worth writing into the plan:** with `parseString` (unresolved AST), `IconButton(...)`
parses as a **`MethodInvocation`, not an `InstanceCreationExpression`** — there is no type
resolution, so the parser cannot tell a constructor from a function call. My first version
visited only `visitInstanceCreationExpression` and found **0 hits in 1083 files** — silently.
You must visit both:
```dart
@override
void visitInstanceCreationExpression(InstanceCreationExpression n) {
  _check(n.constructorName.type.name2.lexeme, n.argumentList, n.offset);
  super.visitInstanceCreationExpression(n);
}
@override
void visitMethodInvocation(MethodInvocation n) {
  _check(n.methodName.name, n.argumentList, n.offset);
  super.visitMethodInvocation(n);
}
```
Matching widgets by bare name is fine here and keeps it to unresolved parsing (fast, no
`pub get` on the target app required). Resolved AST (`AnalysisContextCollection`) would be
correct-er but needs the target app's package resolution and is ~10-100x slower.

**POSITION: 3-5 hand-written rules are cheaper AND lower-risk than this dependency.** Cheaper
because the proof above is 60 lines vs. 5904 and shells out to nothing. Lower-risk because it
removes a network call, a stable machine fingerprint, a third-party server, a self-updater, a
brew upsell, and a 70%-noise output we would have to filter anyway — and it keeps the static
layer honest about what static analysis can actually see (labels: yes; tap targets and contrast:
no, those are runtime).

---

## Exact interface (real, `conalyz --help`, v1.1.0) — for the record, since we're not using it
```
Usage: conalyz [options]
       conalyz usage [usage-options]

-v, --version       Show version information
-d, --dir           Flutter project root; analysis runs on <dir>/lib
-p, --path          (Deprecated) Path to Flutter project directory or dart file; use --dir instead
-t, --platform      Target platform (mobile/web)  [mobile (default), web]
-o, --output        Output directory for reports (defaults to "accessibility_report")
    --[no-]json     Generate JSON report (defaults to on)
    --[no-]html     Generate HTML report (defaults to on)
    --[no-]debug    Enable debug output for troubleshooting
-h, --help          Show this help message

Commands: usage | usage --detailed | update
```
- **No stdout JSON.** `--json` writes `<output>/accessibility_report.json`. A caller must read
  the file back off disk. No `--format=json` / no `-` to stdout.
- No `--fail-on`, no severity threshold, no rule enable/disable, no config file, no stdin.
  `--dir` is forced to `<dir>/lib`.

**Exit codes — verified by running:**
| case | exit |
|---|---|
| findings incl. ≥1 `critical` | `1` |
| findings but 0 `critical` | `0` |
| 0 findings | `0` |
| bad `--dir` (nonexistent) | `1` |

Source, `bin/conalyz.dart:315`:
```dart
// Exit with error code if critical issues found
if ((analysisResult.issuesBySeverity['critical'] ?? 0) > 0) {
  print('⚠️  Critical accessibility issues found. Consider fixing them.');
  exit(1);
}
```
and the catch-all `catch (e) { ... exit(1); }` at :320.
**So exit code 1 is ambiguous between "found critical issues" and "the tool blew up."** Any
caller must check for the JSON file's existence, not the exit code.

**REAL JSON shape** — actual output of
`conalyz --dir <app> --output <dir> --json --no-html`, keys and types verbatim:
```json
{
  "generatedAt": "2026-09-22T11:26:34.604967",
  "analysisTool": "static",
  "device": null,
  "summary": {
    "filesAnalysed": 43,
    "linesScanned": 2448,
    "totalViolations": 41,
    "bySeverity": { "critical": 6, "high": 3, "medium": 12, "low": 20 }
  },
  "violations": [
    {
      "severity": "critical",
      "type": "Missing Alt Text",
      "message": "Image without alternative text for screen readers",
      "file": "./lib/features/<redacted>/presentation/screens/<redacted>_screen.dart",
      "line": 26,
      "column": 16,
      "rule": "WCAG-1.1.1",
      "suggestion": "Add semanticLabel: '<redacted>' to describe this Image.asset for screen readers"
    }
  ]
}
```
A violation has exactly these 8 keys: `column, file, line, message, rule, severity, suggestion,
type`. Note `"analysisTool": "static"` and `"device": null` — placeholders for the paid runtime
tier. `rule` values seen in real output: `WCAG-1.1.1`, `WCAG-1.1.1-Icon`, `WCAG-1.4.3`,
`WCAG-2.1.1`, `WCAG-2.5.3`, `mobile-refresh-indicator`, `progress-indicator-accessibility`,
`text-scaling` — inconsistent naming, part WCAG ids, part ad-hoc slugs.

**PUBLIC-REPO HAZARD in that shape:** `file` and `suggestion` both carry the private app's
directory structure, feature names, screen names and UI copy (`semanticLabel: 'Text logo'` is
literal app copy). Whatever we emit as `findings.json` must be sanitized — or simply never
committed. This applies to our own output too, not just conalyz's.

---

## Plan impact

1. **Drop conalyz from the pipeline.** Replace step 1 with a ~60-line `package:analyzer` script
   in the skill (`analyzer` is already in every Flutter dev's pub cache — rung 5 of the ladder,
   no new install, no `dart pub global activate` step in the skill's setup).
2. **Ship 4 static rules, not 50.** The measured data says only these earn their place, because
   they are the ones static analysis can actually decide and they survived the noise filter:
   - interactive widget (`GestureDetector`/`InkWell`) with `onTap` and no semantics ancestor
   - `IconButton` / `Icon` with no `tooltip` / `semanticLabel`
   - `Image` / `Image.asset` with no `semanticLabel`
   - `TextField` with no `labelText` / `hintText` / semantics
   Skip contrast and text-scaling entirely — conalyz proves they generate 70% noise from source
   text, and they are properly a visual-pass (step 3) job anyway.
3. **Move tap-target sizing out of step 1 into step 2.** Fact 6 proves it is not statically
   decidable. The RenderBox measurement in the journey walk is the only honest source. This
   raises the stakes on the still-unverified `flutter_skill` / runtime question from `_PRIOR.md`
   — that is now the project's critical path, not the static layer.
4. **Keep the output contract, drop the source.** conalyz's violation shape
   (`severity/type/message/file/line/column/rule/suggestion`) is a fine schema and costs nothing
   to reuse — but add a `confidence` field, since unresolved-AST name matching can hit a
   same-named non-widget.
5. **Add a sanitizer step before anything is written to a committed path.** Both `file` paths
   and `suggestion` strings carry private app identifiers and UI copy. v0.1 should write report
   artifacts to a gitignored dir by default, and the repo should ship only a synthetic sample app
   for its own fixtures/screenshots.
6. **Exit-code contract for our own CLI:** do not repeat conalyz's mistake of overloading `1`.
   `0` = ran, `1` = tool error, `2` = ran and found blockers.
7. **`custom_lint` worry is closed** — it resolves fine on the local SDK. It is just unnecessary;
   `package:analyzer` alone is the lower rung.

---

## Unknowns
- I did not exercise `--platform web` (web_rules.dart, 205 lines) — irrelevant if we drop it.
- I did not diff conalyz's HTML report; `--no-html` throughout.
- The telemetry endpoint's actual retention/handling is unknown — I read the client, not the
  server. The claim "no code, filenames, or personal data" is true *of the payload I read in
  v1.1.0*; it is not audited and could change in any release, and `conalyz update` self-updates.
- `downloadCount30Days: 299` — I did not separate CI/mirror traffic from real users.
- My 60-line probe matches widgets by bare name on an unresolved AST. False-positive rate against
  a same-named user class is unmeasured (expected low; add the `confidence` field from Plan
  impact #4).
- Whether the paid brew build's "runtime analysis" overlaps this project's step 2 — worth a look
  before we build step 2, purely as prior art. Not checked.

## Reproduce
```bash
export CONALYZ_NO_ANALYTICS=true DO_NOT_TRACK=1
touch ~/.config/conalyz/opt_out_tracked.flag   # also blocks the opt-out beacon
conalyz --dir <flutter-app> --output /tmp/out --json --no-html; echo "exit=$?"
python3 -c "import json;d=json.load(open('/tmp/out/accessibility_report.json'));print(d['summary'])"
```
Hand-written alternative: `<scratch>/astprobe/`
(`dart run bin/probe.dart <flutter-app>/lib`)
