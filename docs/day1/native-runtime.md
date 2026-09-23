# native-runtime

## VERDICT: confirmed — the runtime layer needs ZERO third-party dependencies.
flutter_skill is redundant for everything the plan asked of it. The catch: structured semantics is
reachable ONLY from inside the app/test process, never over VM Service. The walker must be a
generated `integration_test` run by `flutter drive`, not an external driver.

SDK under test: /opt/homebrew/share/flutter — Flutter 3.47.2 stable, rev d3b14c8769, Dart 3.13.2
(`/opt/homebrew/share/flutter/bin/flutter --version`)

## Facts

### F1. There is NO semantics service extension that returns JSON. Only two, both prose.
Grep of the whole SDK for semantics-related service extensions yields exactly two, both in
`packages/flutter/lib/src/rendering/binding.dart:191,199`:

```dart
registerServiceExtension(
  name: RenderingServiceExtensions.debugDumpSemanticsTreeInTraversalOrder.name,
  callback: (Map<String, String> parameters) async {
    return <String, Object>{
      'data': _debugCollectSemanticsTrees(DebugSemanticsDumpOrder.traversalOrder),
    };
  },
);
registerServiceExtension(
  name: RenderingServiceExtensions.debugDumpSemanticsTreeInInverseHitTestOrder.name, ...
```
The payload is a single `data` String — `toStringDeep()` prose. Confirms _PRIOR.md.

### F2. `ext.flutter.inspector.*` has 32 extensions and NOT ONE of them is semantics.
Full enum, `packages/flutter/lib/src/widgets/service_extensions.dart:135` (`enum WidgetInspectorServiceExtensions`):

structuredErrors, show, trackRebuildDirtyWidgets, widgetLocationIdMap, trackRepaintWidgets,
disposeAllGroups, disposeGroup, isWidgetTreeReady, disposeId, setPubRootDirectories,
addPubRootDirectories, removePubRootDirectories, getPubRootDirectories, setSelectionById,
getParentChain, getProperties, getChildren, getChildrenSummaryTree, getChildrenDetailsSubtree,
getRootWidget, getRootWidgetTree, getRootWidgetSummaryTree, getRootWidgetSummaryTreeWithPreviews,
getDetailsSubtree, getSelectedWidget, getSelectedSummaryWidget, isWidgetCreationTracked,
screenshot, getLayoutExplorerNode, setFlexFit, setFlexFactor, setFlexProperties

The inspector serves the WIDGET tree, not the SEMANTICS tree. No label/flags/actions.

### F3. `androidTapTargetGuideline` / `iOSTapTargetGuideline` / `textContrastGuideline` /
`labeledTapTargetGuideline` all still exist in 3.47.2.
Source: `/opt/homebrew/share/flutter/packages/flutter_test/lib/src/accessibility.dart`
```dart
// :785
const AccessibilityGuideline androidTapTargetGuideline = MinimumTapTargetGuideline(
  size: Size(48.0, 48.0),
  link: 'https://support.google.com/accessibility/android/answer/7101858?hl=en',
);
// :800
const AccessibilityGuideline iOSTapTargetGuideline = MinimumTapTargetGuideline(
  size: Size(44.0, 44.0), link: '...human-interface-guidelines...');
// :818
const AccessibilityGuideline textContrastGuideline = MinimumTextContrastGuideline();
// :825
const AccessibilityGuideline labeledTapTargetGuideline = LabeledTapTargetGuideline._();
```
`meetsGuideline` matcher: `packages/flutter_test/lib/src/matchers.dart:1289`.


### F4. The inspector's widget-tree JSON carries creationLocation, NOT geometry, NOT semantics.
`InspectorSerializationDelegate.additionalNodeProperties`
(`packages/flutter/lib/src/widgets/widget_inspector.dart:4521`) adds only:
`summaryTree`, `valueId`, `locationId`, `creationLocation` (file/line/column), `createdByLocalProject`.
No rect, no size, no label, no flags.

### F5. The ONLY externally-reachable geometry is `ext.flutter.inspector.getLayoutExplorerNode`,
per node, by id.  `_getLayoutExplorerNode`, widget_inspector.dart:2307-2375, returns JSON:
```dart
additionalJson['constraints'] = {'type','description','minWidth','minHeight','maxWidth','maxHeight'};
if (renderObject is RenderBox) {
  additionalJson['isBox'] = true;
  additionalJson['size'] = {'width': ..., 'height': ...};       // RenderBox.size
  if (parentData is BoxParentData)
    additionalJson['parentData'] = {'offsetX': ..., 'offsetY': ...};  // parent-relative only
}
```
i.e. size yes, GLOBAL position no — there is no `localToGlobal` over the wire. You would have to
call it once per node (needing a valueId from a prior getRootWidgetSummaryTree) and accumulate
parent offsets yourself. That is O(n) VM-service round-trips per screen for a worse answer than
one in-process traversal.

### F6. **RAN IT.** All four built-in guidelines execute under `integration_test` on a REAL iOS
simulator and produce node-level failures. This is the single biggest finding.

Command (real, exit 0):
```
cd <scratch>/nrprobe
/opt/homebrew/share/flutter/bin/flutter test integration_test/probe_test.dart \
    -d ABE6021B-E22D-4627-95CA-0AE04EF3C941     # iPhone SE (3rd gen), iOS 18.6 simulator
```
Real stdout (verbatim, trimmed of blank lines):
```
Xcode build done.                                           11.9s
PROBE semanticsEnabled_before=true
PROBE semanticsEnabled_after=true
PROBE step_ms=546
PROBE getRect(Continue)=Rect.fromLTRB(156.6, 399.5, 218.4, 419.5)
PROBE getSize(Continue)=Size(61.7, 20.0)
PROBE bySemanticsLabel_hits=1
PROBE GUIDELINE iOSTapTargetGuideline passed=false reason=SemanticsNode#4(Rect.fromLTRB(175.5, 233.5, 199.5, 257.5), actions: [tap], flags: [isButton], label: "tiny labeled button", textDirection: ltr): expected tap target size of at least Size(44.0, 44.0), but found Size(24.0, 24.0)
See also: https://developer.apple.com/design/human-interface-guidelines/ios/visual-design/adaptivity-and-layout/
PROBE GUIDELINE androidTapTargetGuideline passed=false reason=SemanticsNode#4(...): expected tap target size of at least Size(48.0, 48.0), but found Size(24.0, 24.0)
PROBE GUIDELINE labeledTapTargetGuideline passed=false reason=SemanticsNode#5(Rect.fromLTRB(157.5, 257.5, 217.5, 317.5), actions: [tap]): expected tappable node to have semantic label, but none was found.
PROBE GUIDELINE textContrastGuideline passed=false reason=SemanticsNode#6(Rect.fromLTRB(130.3, 317.5, 244.7, 337.5), label: "low contrast text", textDirection: ltr):
Expected contrast ratio of at least 4.5 but found 3.68 for a font size of 14.0.
The computed colors was:
light - Color(... 1.0000, 1.0000, 1.0000 ...), dark - Color(... 0.9569, 0.2627, 0.2118 ...)
PROBE takeScreenshot bytes=45135
00:00 +1: All tests passed!
```
Notes:
- `textContrastGuideline` uses `renderView.debugLayer! as OffsetLayer` + `layer.toImage()` inside
  `tester.binding.runAsync` (accessibility.dart:318-330). It WORKS on the simulator (Impeller).
  It read real pixels — the reported dark color is the ElevatedButton's, i.e. the naive
  light/dark partition is noisy, but it runs.
- `semanticsEnabled` was ALREADY true before `tester.ensureSemantics()` on iOS sim. Call
  `ensureSemantics()` anyway; it is cheap and is what the docs require.
- Probe source: `<scratch>/nrprobe/integration_test/probe_test.dart`

### F7. **RAN IT.** Full structured semantics (label/value/hint/identifier/role/flags/actions/rect)
is trivially dumpable as JSON **from inside the test** — ~30 lines, zero dependencies.
`SemanticsNode.getSemanticsData()` returns `SemanticsData` with (semantics.dart:1127-1370):
```dart
final SemanticsFlags flagsCollection;   // .toStrings() -> ['isButton','isTextField',...]
final int actions;  bool hasAction(ui.SemanticsAction a);
final AttributedString attributedLabel/attributedValue/attributedHint;  // .string
final String identifier;  final String tooltip;  final int headingLevel;
final SemanticsRole role;  final Rect rect;  final Matrix4? transform;
final SemanticsInputType inputType;  final SemanticsValidationResult validationResult;
```
Real output from the run (excerpt, verbatim):
```json
{ "id": 8, "label": "Continue", "role": "none",
  "flags": ["isButton","hasEnabledState","isEnabled","isFocusable"],
  "actions": ["tap"],
  "localRect": [0.0, 0.0, 109.70446395874023, 48.0],
  "globalRect": [265.29553604125977, 771.0, 219.40892791748047, 96.0] }
{ "id": 7, "label": "a field",
  "flags": ["isTextField","hasEnabledState","isEnabled","isFocusable"],
  "actions": ["tap","focus"],
  "globalRect": [0.0, 675.0, 750.0, 96.0] }
```
globalRect is in PHYSICAL pixels (device is 750x1334 @ DPR 2) — divide by
`view.devicePixelRatio` for logical px, exactly as MinimumTapTargetGuideline does
(accessibility.dart:177 `paintBounds.size / view.devicePixelRatio`).

### F8. Tap-target geometry, externally vs internally — the answer is "internally".
| what | inside test | external VM Service |
|---|---|---|
| `SemanticsNode.rect` + `.transform` | YES (F7) | NO — prose dump only (F1) |
| `RenderBox.size` | YES `tester.getSize(f)` | partially: `getLayoutExplorerNode`, per node, by id (F5) |
| global position | YES `tester.getRect(f)` / `localToGlobal` | NO |
| a11y flags / actions / label | YES (F7) | NO |
Measured: `tester.getRect(find.text('Continue')) = Rect.fromLTRB(156.6, 399.5, 218.4, 419.5)`
(logical px), `tester.getSize(...) = Size(61.7, 20.0)`.

### F9. Finders that work at runtime
`packages/flutter_test/lib/src/finders.dart`:
```dart
Finder bySemanticsLabel(Pattern label, {bool skipOffstage = true});      // :592
Finder bySemanticsIdentifier(Pattern identifier, {bool skipOffstage = true}); // :623
Finder byTooltip(Pattern message, {bool skipOffstage = true});           // :396
Finder byIcon(IconData icon, {bool skipOffstage = true});                // :271
// plus find.text / find.byKey / find.byType / find.widgetWithText
```
Verified live: `find.bySemanticsLabel('tiny labeled button').evaluate().length == 1`.
Drive with `await tester.tap(finder); await tester.pumpAndSettle();`.
NOTE: `bySemanticsLabel` requires semantics enabled (it walks `RenderSemanticsAnnotations`).

### F10. Screenshot: `binding.takeScreenshot(name)` works under plain `flutter test`, no driver.
`packages/integration_test/lib/integration_test.dart:187`
```dart
Future<List<int>> takeScreenshot(String screenshotName, [Map<String, Object?>? args]) async
```
Went over the `integrationTestChannel` MethodChannel (`src/_callback_io.dart:82`) and returned
**45135 bytes** of PNG in the run above. Android requires
`await binding.convertFlutterSurfaceToImage();` first (`_callback_io.dart:65-79`, iOS is a no-op)
and it throws `StateError` otherwise.

### F11. Timing, zero deps.
- Per-step: a plain `Stopwatch` around `pumpWidget`/`tap`+`pumpAndSettle`. Measured 546 ms live.
- Frame timing: `IntegrationTestWidgetsFlutterBinding.watchPerformance(action, reportKey)`
  (integration_test.dart:387) → `FrameTimingSummarizer(...).summary` into `reportData[reportKey]`.
  Costs a hard `await Future.delayed(Duration(seconds: 2))` per call (line 417) plus a poll loop —
  ~4-6 s of wall clock per measured action. Do not put it on every step.
- Full timeline: `binding.traceAction(action, streams: ['all'], reportKey: 'timeline')`
  (integration_test.dart:350) → `vm.Timeline.toJson()` into `reportData`.

### F12. **RAN IT.** `flutter drive` is the transport that gets artifacts onto the HOST filesystem.
```
/opt/homebrew/share/flutter/bin/flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/probe_test.dart \
  -d ABE6021B-E22D-4627-95CA-0AE04EF3C941
```
test_driver/integration_test.dart (whole file, 15 lines):
```dart
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
  );
}
```
Real result:
```
DRIVER wrote <scratch>/nrprobe/screenshots/probe.png (45135 bytes)
All tests passed.
$ file screenshots/probe.png
screenshots/probe.png: PNG image data, 750 x 1334, 8-bit/color RGBA, non-interlaced
$ ls -la build/integration_response_data.json
-rw-r--r--  561433  build/integration_response_data.json
```
`binding.reportData` (any json-serialisable map — put the F7 semantics dump + findings there) is
written to `$FLUTTER_TEST_OUTPUTS_DIR/integration_response_data.json`, default `build/`
(`packages/flutter_driver/lib/src/driver/common.dart:32`
`String get testOutputsDirectory => Platform.environment['FLUTTER_TEST_OUTPUTS_DIR'] ?? 'build';`).
GOTCHA: `takeScreenshot` also stuffs the PNG into `reportData['screenshots']` as a JSON int array —
45 KB PNG became 561 KB of JSON. Pass your own `responseDataCallback` that strips
`data['screenshots']` before writing, or set `FLUTTER_TEST_OUTPUTS_DIR` and drop it.
Plain `flutter test integration_test/...` does NOT write that file (checked: `build/*.json` absent
after the F6 run) — you only get stdout. `flutter drive` also relays the app's `print()` to host
stdout prefixed `flutter: `, so stdout is a viable fallback channel.

## Exact interface

Everything below is SDK-only. `pubspec.yaml` dev_dependencies needed:
`integration_test: {sdk: flutter}` and `flutter_test: {sdk: flutter}`. Nothing else.

```dart
// --- binding ---
IntegrationTestWidgetsFlutterBinding.ensureInitialized() -> IntegrationTestWidgetsFlutterBinding
Future<List<int>> takeScreenshot(String screenshotName, [Map<String, Object?>? args])
Future<void>      convertFlutterSurfaceToImage()            // Android only, call before screenshot
Map<String, dynamic>? reportData                             // -> build/integration_response_data.json
Future<void> traceAction(Future<dynamic> Function() action,
    {List<String> streams = const ['all'], bool retainPriorEvents = false, String reportKey = 'timeline'})
Future<void> watchPerformance(Future<void> Function() action, {String reportKey = 'performance'})

// --- semantics (test-internal only) ---
SemanticsHandle WidgetTester.ensureSemantics()
tester.binding.renderViews -> Iterable<RenderView>
renderView.owner!.semanticsOwner!.rootSemanticsNode! -> SemanticsNode
SemanticsNode.getSemanticsData() -> SemanticsData
   .attributedLabel.string .attributedValue.string .attributedHint.string .identifier .tooltip
   .role (SemanticsRole) .rect (Rect) .transform (Matrix4?) .headingLevel .inputType
   .flagsCollection.toStrings() -> List<String>   // 'isButton','isTextField','isLink','isHidden',...
   .hasAction(ui.SemanticsAction.tap|longPress|focus|scrollUp|...)
SemanticsNode.visitChildren((SemanticsNode c) => true)
MatrixUtils.transformRect(Matrix4, Rect)     // accumulate up .parent chain -> physical-px global rect
// logical px  =  physicalRect / view.devicePixelRatio

// --- geometry ---
Rect WidgetTester.getRect(FinderBase<Element>)
Size WidgetTester.getSize(FinderBase<Element>)
Offset WidgetTester.getTopLeft/getCenter/getBottomRight(...)

// --- guidelines (flutter_test/lib/src/accessibility.dart) ---
abstract class AccessibilityGuideline { FutureOr<Evaluation> evaluate(WidgetTester tester); String get description; }
class Evaluation { final bool passed; final String? reason; }
const AccessibilityGuideline androidTapTargetGuideline;   // 48x48   :785
const AccessibilityGuideline iOSTapTargetGuideline;       // 44x44   :800
const AccessibilityGuideline textContrastGuideline;       // WCAG AA :818
const AccessibilityGuideline labeledTapTargetGuideline;   //         :825
class MinimumTextContrastGuidelineAAA extends MinimumTextContrastGuideline;  // :525 (AAA 7.0/4.5)
class CustomMinimumContrastGuideline extends AccessibilityGuideline {         // :559
  CustomMinimumContrastGuideline({required Finder finder, double minimumRatio, ...}); }
AsyncMatcher meetsGuideline(AccessibilityGuideline);      // matchers.dart:1300
AsyncMatcher doesNotMeetGuideline(AccessibilityGuideline);
// call `await guideline.evaluate(tester)` directly to COLLECT findings instead of failing the test.

// --- finders ---
find.bySemanticsLabel(Pattern) / find.bySemanticsIdentifier(Pattern) / find.byTooltip(Pattern)
find.text(String) / find.byKey(Key) / find.byType(Type) / find.byIcon(IconData)
await tester.tap(finder); await tester.enterText(finder, s); await tester.pumpAndSettle();

// --- external, over VM Service (the ONLY structured geometry) ---
ext.flutter.inspector.getRootWidgetTree  {groupName, isSummaryTree, withPreviews, fullDetails}
   -> widget tree JSON: description/type/valueId/creationLocation{file,line,column}/createdByLocalProject
      NO rect, NO size, NO semantics
ext.flutter.inspector.getLayoutExplorerNode {id, groupName, subtreeDepth}
   -> {..., isBox, size:{width,height}, constraints:{...}, parentData:{offsetX,offsetY}}
ext.flutter.inspector.screenshot {id, width, height, margin?, maxPixelRatio?, debugPaint?} -> base64 PNG
ext.flutter.debugDumpSemanticsTreeInTraversalOrder {} -> {"data": "<prose>"}   // NOT json
```

## Plan impact

1. **DROP `flutter_skill` from the runtime layer. The runtime layer needs ZERO third-party
   dependencies.** Everything the plan's step 2 wanted — a11y tree, screenshot, RenderBox
   measurement, step timing — is `flutter_test` + `integration_test`, both shipped in the SDK,
   both proven live above. Adding a package here buys nothing and costs a dependency, a license,
   and a version-compat surface.

2. **The architecture inverts: the walker runs INSIDE the app, not outside it.** The plan's
   "journey walk driven by an external process over VM Service" cannot work — semantics is prose
   over the wire (F1), the inspector has no semantics extension at all (F2), and geometry is
   per-node round-trips with no global position (F5, F8). The skill must GENERATE a Dart
   integration_test from journey.yaml, run it via `flutter drive`, and read
   `build/integration_response_data.json` + `screenshots/*.png` back on the host. That is the
   whole runtime layer. It also deletes the plan's separate "RenderBox measurement" step —
   `tester.getRect` is one line.

3. **Promote the a11y guidelines from v0.2 to v0.1 — they are free and they already work.**
   Four guidelines, node-level failures with rect + label + actions, running on a real simulator,
   for zero code. `evaluate(tester)` returns an `Evaluation`, so collect rather than assert.
   `textContrastGuideline` and `labeledTapTargetGuideline` map straight onto Nielsen #4
   (consistency/standards) and #6 (recognition over recall) at severity 2-3. Do NOT reimplement
   tap-target or contrast checking — it exists and it is calibrated.

4. **Screenshots, PUBLIC-REPO CONSTRAINT.** `flutter drive` writes real PNGs of the private app
   to `<app>/screenshots/`. The skill must (a) default its output dir to a gitignored path,
   (b) ship a `.gitignore` line in whatever it scaffolds, and (c) never write example output into
   the repo. Worse than screenshots: `ext.flutter.inspector.getRootWidgetTree` embeds
   `creationLocation{file,line,column}` = absolute source paths of the private app, and every
   semantics `label` is verbatim private UI copy. So: the v0.1 repo ships the GENERATOR and the
   guideline wiring, and zero captured artifacts — no golden fixtures from the dogfood app, no
   sample report.md, no sample findings.json with real labels. Fixtures must come from a throwaway
   `flutter create` app like `<scratch>/nrprobe`.

5. **Cost control on timing.** Use a plain `Stopwatch` for per-step duration (546 ms measured).
   `watchPerformance` costs 4-6 s of forced delay per call — offer it opt-in per step, never
   default. `traceAction(streams: ['all'])` dumps a whole VM timeline into reportData; that is
   a v0.2 profiling feature, not a v0.1 UX signal.

6. **Strip screenshots out of reportData** before `writeResponseData`, or the JSON is ~12x the
   PNG size (45 KB -> 561 KB measured).

## Unknowns

- **Android emulator not tested.** `convertFlutterSurfaceToImage()` + `takeScreenshot` is the
  documented Android path and it throws `StateError` if you skip it; the contrast guideline's
  `OffsetLayer.toImage()` under Impeller-on-Android is unverified here. iOS simulator only.
- **Physical device not tested** (iOS or Android).
- `MinimumTextContrastGuideline`'s naive light/dark colour partition produced a visibly wrong
  "dark" colour in the probe (it picked the ElevatedButton's red, not the text grey) while still
  flagging the right node. Expect false positives/negatives on busy backgrounds; treat its
  numeric ratio as advisory and its NODE as the real signal. Not quantified.
- Whether `ext.flutter.inspector.*` is reachable at all while the app is under `flutter drive`
  (DDS is already attached — the first `flutter test` attempt died with
  `JSON-RPC error 100: Feature is disabled ... A DDS instance is already connected`). If the
  static pass also wants VM Service access it will collide; not investigated.
- `getRootWidgetTree`'s exact JSON was read from source, not captured live.
- `flutter drive` on web/desktop targets: not investigated.
