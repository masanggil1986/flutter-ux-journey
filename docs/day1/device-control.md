# device-control
## VERDICT: confirmed

## Facts

### F1. Flutter semantics are NOT on by default in debug. Debug/release is irrelevant. (CONFIRMED, source)
Claim: `semanticsEnabled` is true ONLY if the platform asked for it, or `ensureSemantics()` was called.
There is no debug-mode branch anywhere in that decision.
Evidence verbatim — /opt/homebrew/share/flutter/packages/flutter/lib/src/semantics/binding.dart:58-68,144-166
(Flutter 3.47.2 stable, framework d3b14c8769):
```dart
  /// Whether semantics information must be collected.
  ///
  /// Returns true if either the platform has requested semantics information
  /// to be generated or if [ensureSemantics] has been called otherwise.
  bool get semanticsEnabled {
    assert(_semanticsEnabled.value == (_outstandingHandles > 0));
    return _semanticsEnabled.value;
  }

  late final ValueNotifier<bool> _semanticsEnabled = ValueNotifier<bool>(
    platformDispatcher.semanticsEnabled,
  );

  SemanticsHandle ensureSemantics() {
    _outstandingHandles++;
    _semanticsEnabled.value = true;
    return SemanticsHandle._(_didDisposeSemanticsHandle);
  }

  void _handleSemanticsEnabledChanged() {
    if (platformDispatcher.semanticsEnabled) {
      _semanticsHandle ??= ensureSemantics();
    } else {
      _semanticsHandle?.dispose();
      _semanticsHandle = null;
    }
  }
```
So there are exactly two switches: (a) the embedder sets `platformDispatcher.semanticsEnabled`
when an a11y client attaches, (b) app code calls `ensureSemantics()`.
=> A platform driver works iff it ITSELF counts as an a11y client (a), or the app was
   modified (b). This is the make-or-break fork.

### F2. Android: `adb shell uiautomator dump` DOES see real Flutter widgets. No app change needed. (CONFIRMED, run)
The dumping tool is itself the a11y client that flips switch (a) — UiAutomation connects as an
accessibility service, AccessibilityManager goes enabled, the Flutter engine turns semantics on.

Control app: stock `flutter create` counter app (`com.example.semdemo`), debug build,
`main()` is just `runApp(const MyApp())` — NO `ensureSemantics()`, no Semantics widgets.
Source: <scratchpad>/semdemo/lib/main.dart
No screen reader running:
```
$ adb shell settings get secure enabled_accessibility_services
null
$ adb shell settings get secure accessibility_enabled
0
```
Command and result:
```
$ adb shell uiautomator dump /sdcard/dump_before.xml
UI hierchary dumped to: /sdcard/dump_before.xml
$ adb shell cat /sdcard/dump_before.xml
```
13 nodes. Flattened (class / clickable / focusable / bounds / content-desc):
```
android.widget.FrameLayout   clickable=false focusable=false [0,0][1080,1920]      desc=''
android.widget.LinearLayout  clickable=false focusable=false [0,0][1080,1920]      desc=''
android.widget.FrameLayout   clickable=false focusable=false [0,0][1080,1920]      desc=''
android.widget.FrameLayout   clickable=false focusable=true  [0,0][1080,1920]      desc=''
android.view.View            clickable=false focusable=false [0,0][1080,1920]      desc=''   x4
android.view.View            clickable=false focusable=false [0,0][1080,210]       desc=''
android.view.View            clickable=false focusable=true  [42,100][689,173]     desc='Flutter Demo Home Page'
android.view.View            clickable=false focusable=true  [160,992][920,1044]   desc='You have pushed the button this many times:'
android.view.View            clickable=false focusable=true  [519,1044][561,1139]  desc='0'
android.widget.Button        clickable=true  focusable=true  [891,1668][1038,1815] desc='Increment'
```
Real labels, real device-pixel rects, correct role mapping (the FAB became
`android.widget.Button` with `clickable=true`), tooltip 'Increment' surfaced as content-desc.
NOTE: Flutter labels land in `content-desc`, NOT in `text` — every `text=""` in the dump.
Any parser that reads `text=` finds nothing.


### F3. Android: tap + screenshot round-trip verified with plain adb. (CONFIRMED, run)
```
$ adb shell am force-stop com.example.semdemo && adb shell am start -n com.example.semdemo/.MainActivity
$ adb shell uiautomator dump /sdcard/r1.xml   # FIRST dump after cold start
  -> content-desc="0" ... "Increment"          # no race; semantics present on dump #1
$ adb shell input tap 964 1741                 # center of Button bounds [891,1668][1038,1815]
$ adb shell input tap 964 1741
$ adb shell uiautomator dump /sdcard/r2.xml
  -> content-desc="2"                          # counter went 0 -> 2. Tap landed on the Flutter widget.
$ adb exec-out screencap -p > and.png
$ file and.png
  and.png: PNG image data, 1080 x 1920, 8-bit/color RGBA, non-interlaced
```
Full loop (find named element -> tap it -> observe the state change -> screenshot) works with
`adb` alone. No MCP, no Appium, no app change.

### F4. mobile-mcp on ANDROID adds nothing over raw adb; it IS the same a11y path. (CONFIRMED, run)
`mobile_list_elements_on_screen(device="flutter_emulator")` on the same screen returned:
```json
[{"ref":"@e1","type":"ConstrainedBox","coordinates":{"x":0,"y":0,"width":1080,"height":1920}},
 {"ref":"@e2","type":"Text","text":"You have pushed the button this many times:","label":"You have pushed the button this many times:","coordinates":{"x":160,"y":992,"width":760,"height":53}},
 {"ref":"@e3","type":"Text","text":"2","label":"2","coordinates":{"x":519,"y":1044,"width":41,"height":95}},
 {"ref":"@e4","type":"Header","text":"Flutter Demo Home Page","label":"Flutter Demo Home Page","coordinates":{"x":42,"y":100,"width":647,"height":74}},
 {"ref":"@e5","type":"Button","coordinates":{"x":891,"y":1668,"width":147,"height":147}}]
```
Identical rects to my raw dump ([891,1668][1038,1815] == x891 y1668 w147 h147). It is a JSON
re-serialization of the uiautomator tree.
It is also LOSSY: `@e5` (the FAB) has no `text`/`label`, but the raw dump had
`content-desc="Increment"`. Raw `adb` beats the MCP on fidelity here.

### F5. mobile-mcp on iOS requires installing an on-device agent. (CONFIRMED, run)
```
> mobile_list_elements_on_screen(device="A258A9DE-...-iPhone 17 Pro Max")
Error: Command failed: .../@mobilenext/mobilecli-darwin-arm64/mobilecli-darwin-arm64 agent status --device A258A9DE-D8C3-481C-80C8-7A5E9491B145
Agent is not installed on the device
```
Its CLI confirms the model:
```
$ mobilecli agent --help
Commands for managing the on-device agent.
Available Commands:
  install     Install the agent on a device
  status      Check agent installation status on a device
  uninstall   Uninstall the agent from a device
```
i.e. a WebDriverAgent-shaped helper app must be installed on the simulator. That is a
hard dependency, and it is per-device state a distributable skill cannot assume.

### F6. `xcrun simctl` CANNOT tap. Screenshot only. (CONFIRMED, run)
Full subcommand list from `xcrun simctl help` (Xcode on this machine) contains NO input/tap/
gesture/press subcommand. The closest, `io` and `ui`, are:
```
$ xcrun simctl io help
Supported operations:
	enumerate [--poll]
	poll
	recordVideo [--codec=<codec>] [--display=<display>] [--mask=<policy>] [--force] <file or url>
	screenshot ...
$ xcrun simctl ui <udid>
Supported Options:
    appearance [light | dark]
    content_size [increment | decrement | desired_size]
    increase_contrast [enabled | disabled]
```
Note `simctl ui` has NO VoiceOver / screen-reader toggle either — so there is no simctl way
to flip Flutter's semantics on from outside.
Screenshot does work:
```
$ xcrun simctl io A258A9DE-D8C3-481C-80C8-7A5E9491B145 screenshot /tmp/ios.png
Wrote screenshot to: /tmp/ios.png
$ file /tmp/ios.png
/tmp/ios.png: PNG image data, 1320 x 2868, 8-bit/color RGBA, non-interlaced
```
So on iOS, the baseline CLI gives you HALF the loop: capture yes, control no.


### F7. The Dart VM Service is the platform-independent element source, and it needs ZERO new deps. (CONFIRMED, run)
Every `flutter run` debug app already prints its VM Service URI. A single-file Dart script using
only `dart:io` `WebSocket` + `dart:convert` (NO pubspec, NO `pub get`) speaks its JSON-RPC.
Script: /tmp/vmprobe.dart, /tmp/vm2.dart (20-30 lines).
`dart` is guaranteed present for any Flutter user, so this is rung 3 (stdlib), not rung 5.

On the STOCK unmodified counter app on the iOS simulator:
```
$ dart run vmprobe.dart "ws://127.0.0.1:63888/Q7DlnTN5Nvw=/ws"
ISOLATE: isolates/4036012384802787
--- 74 extension RPCs ---
```
Relevant ones present with no app change:
```
ext.flutter.accessibilityEvaluations
ext.flutter.debugDumpSemanticsTreeInTraversalOrder
ext.flutter.debugDumpSemanticsTreeInInverseHitTestOrder
ext.flutter.inspector.getRootWidgetTree
ext.flutter.inspector.getRootWidgetSummaryTreeWithPreviews
ext.flutter.inspector.getDetailsSubtree
ext.flutter.inspector.getLayoutExplorerNode
ext.flutter.inspector.screenshot
ext.flutter.inspector.setSelectionById
```
There is NO tap/gesture extension (`ext.flutter.driver.*` is absent — that only appears if the
app calls `enableFlutterDriverExtension()`).

`ext.flutter.inspector.getRootWidgetTree` on the stock app returned:
```json
{"description":"MyHomePage","widgetRuntimeType":"MyHomePage","valueId":"inspector-11","createdByLocalProject":true,"children":[
 {"description":"Scaffold",...,"createdByLocalProject":true,"children":[
  {"description":"Text","valueId":"inspector-19","createdByLocalProject":true,"textPreview":"You have pushed the button this many times:","children":[]},
  {"description":"Text","valueId":"inspector-20","createdByLocalProject":true,"textPreview":"0","children":[]},
  {"description":"AppBar",...},{"description":"FloatingActionButton","valueId":"inspector-15",...}]}]}
```
KEY: it carries `createdByLocalProject` — i.e. whether the widget is the USER'S code or framework
code. A platform a11y tree can never tell you that. It is the join key between the static pass
and the runtime pass. It does NOT carry rects; those need `getDetailsSubtree`/`getLayoutExplorerNode`.

### F8. RETRACTED BY F12 — DO NOT PLAN ON THIS. Flutter's native a11y audits are experimental and OFF on stable. (see F12)
`ext.flutter.accessibilityEvaluations` is registered by WidgetsBinding in stock Flutter 3.47.2.
Calling it with no args:
```
{"code":-32000,"message":"Server error","data":{"details":"{\"exception\":\"Exception: type parameter is required\",
 \"stack\":\"#0 WidgetsBinding.initServiceExtensions.<anonymous closure> (package:flutter/src/widgets/binding.dart:762:13)\"}"}}
```
Source at that line, /opt/homebrew/share/flutter/packages/flutter/lib/src/widgets/binding.dart:757-790:
```dart
      registerServiceExtension(
        name: WidgetsServiceExtensions.accessibilityEvaluations.name,
        callback: (Map<String, String> parameters) async {
          final String? type = parameters['type'];
          if (type == null) { throw Exception('type parameter is required'); }
          switch (type) {
            case 'MinimumTextContrastEvaluation':   // params minNormalTextContrastRatio, minLargeTextContrastRatio
            case 'MinimumTapTargetEvaluation':      // param targetSize
            case 'LabeledTapTargetEvaluation':      // no params
```
So contrast, tap-target-size and missing-label checks are ALREADY a one-RPC call against a
running app, on any platform, with no package and no app change. The plan should not
re-implement these three.

### F9. VM Service `evaluate` needs `flutter run`'s resident compiler. `--no-hot` kills it. (CONFIRMED, run)
Attempting to inject a pointer event by evaluating Dart in the scope of
`package:flutter/src/gestures/binding.dart`:
```
$ dart run vm3.dart "ws://127.0.0.1:63888/..../ws" 396 878
LIB: package:flutter/src/gestures/binding.dart -> libraries/@161304576
sanity => {"code":113,"message":"Expression compilation error",
           "details":"_compileExpression: No compilation service available; cannot evaluate from source."}
```
Cause: the app had been launched with `flutter run --no-hot`, which drops the resident
frontend_server that services `_compileExpression`. Retesting with plain `flutter run`.


### F10. iOS tap CONFIRMED on a completely unmodified app, via VM Service `evaluate`. (CONFIRMED, run)
`evaluate` resolves names in the scope of the TARGET LIBRARY. Target
`package:flutter/src/gestures/binding.dart` and `GestureBinding`, `PointerDownEvent`, `Offset`
are all in scope, so a pointer event can be synthesized with no app change and no package.
```
$ dart run vm5.dart "ws://127.0.0.1:64216/NzhDuuIe3Ho=/ws" 396 878
tap 1: 7 -> 8
tap 2: 8 -> 9
tap 3: 9 -> 10
tap 4: 10 -> 11
tap 5: 11 -> 12
```
5/5 taps landed on the stock counter app's FloatingActionButton on the iOS simulator.
The exact expression pair (this is the whole iOS tap mechanism):
```
evaluate(isolateId, targetId=<libid of package:flutter/src/gestures/binding.dart>, expression=
  "GestureBinding.instance.handlePointerEvent(PointerDownEvent(position: const Offset(396, 878), pointer: 501, timeStamp: const Duration(milliseconds: 1000)))")
evaluate(... "GestureBinding.instance.handlePointerEvent(PointerUpEvent(position: const Offset(396, 878), pointer: 501, timeStamp: const Duration(milliseconds: 1080)))")
```
Coordinates are LOGICAL pixels (440x956 on iPhone 17 Pro Max), not device pixels.

### F11. CALIBRATION KNOB — naive tap injection silently drops ~1 in 3 taps. (CONFIRMED, run)
First attempt, down+up with no `timeStamp` and a 400ms settle:
```
counter BEFORE: 1
counter AFTER 1 tap: 2
counter AFTER 3 more taps: 4     <-- expected 5. One tap vanished.
```
Re-run with a unique `pointer:` id per tap but still no timeStamp:
```
counter BEFORE: 4
counter AFTER 1 tap: 5
counter AFTER 3 more taps: 7     <-- expected 8. Still dropping.
```
Unique pointer id was NOT the fix. The fix was an explicit monotonically increasing `timeStamp`
plus a real press duration:
  - unique `pointer:` id per tap
  - `timeStamp:` monotonic, down and up differing by ~80ms
  - 80ms between the down and up RPCs, ~800ms settle before reading state
=> 5/5 (F10). Without timestamps every event carries Duration.zero and the gesture recognizers
   treat the stream as degenerate.
This MUST be in the skill. A journey walker that silently drops a third of its taps produces
confident nonsense.

### F12. Flutter's native a11y evaluations are EXPERIMENTAL and HARD-OFF on stable. (CONFIRMED, run)
This retracts F8. The RPC is registered and callable, but the implementation refuses:
```
$ call ext.flutter.accessibilityEvaluations {type: MinimumTapTargetEvaluation, targetSize: 48.0}
{"code":-32000,"message":"Server error","data":{"details":"{\"exception\":
 \"Unsupported operation: Accessibility evaluations APIs are not enabled.\\n\\n
  Accessibility evaluations APIs are currently experimental. Do not use accessibility evaluations
  APIs in production applications or plugins published to pub.dev.\\n\\n
  To try experimental accessibility evaluations APIs:\\n
  1. Switch to Flutter's main release channel.\\n
  2. Turn on the accessibility evaluations feature flag. (See flutter config --help)\\n\",
 \"stack\":\"#0 AccessibilityEvaluation.evaluate (package:flutter/src/widgets/_accessibility_evaluations.dart:71:7)\"}"}}
```
Local env is Flutter 3.47.2 **stable**. A distributable skill cannot require users to switch to
the main channel and flip a `flutter config` flag. Do not build on this. Presence in the
extensionRPCs list is NOT evidence an extension works — I only caught this by calling it.

### F13. `evaluate` name resolution is scoped to the target library. (CONFIRMED, run)
Targeting the app's own `package:semdemo/main.dart` (which imports only material.dart):
```
expression: SemanticsBinding.instance.semanticsEnabled
{"code":113,"message":"Expression compilation error","details":
 "org-dartlang-debug:synthetic_debug_expression:1:1: Error: Undefined name 'SemanticsBinding'."}
```
material.dart does not re-export `SemanticsBinding`. The same expression must be targeted at
`package:flutter/src/semantics/binding.dart`. Rule for the skill: **target the framework library
that DEFINES the symbol, not the app's library.**

### F14. `evaluate` accepts ONE EXPRESSION only — no statements, no closure bodies. (CONFIRMED, run)
An attempt to walk the element tree in one `(() { ... })()` IIFE:
```
{"code":113,"message":"Expression compilation error","details":
 "org-dartlang-debug:synthetic_debug_expression:1:5: Error: Can't find '}' to match '{'.\n(() {\n    ^"}
```
So you CANNOT ship a tree-walking probe as an evaluate string. Element enumeration must come from
the inspector/semantics RPCs, not from injected Dart. Injected Dart is only good for single calls
like `handlePointerEvent(...)`.

### F15. WITHDRAWN — superseded by F18. (The dump RPC does NOT enable semantics; source
`rendering/binding.dart:190-196` shows the callback only calls `_debugCollectSemanticsTrees(...)`,
and its doc says "If a semantics tree is not available, a notice about the missing semantics tree
is printed instead." What I saw was a tree mid-construction.)
ORIGINAL OBSERVATION, kept for the record:
Two back-to-back calls to `ext.flutter.debugDumpSemanticsTreeInTraversalOrder`, with a FAILED
(therefore no-op) ensureSemantics attempt in between, on the unmodified app:
call #1:
```
SemanticsNode#0
 │ Rect.fromLTRB(0.0, 0.0, 1320.0, 2868.0)
 └─SemanticsNode#1
   │ Rect.fromLTRB(0.0, 0.0, 440.0, 956.0) scaled by 3.0x
   │ textDirection: ltr
```
call #2 (nothing else changed):
```
   └─SemanticsNode#2
     │ Rect.fromLTRB(0.0, 0.0, 440.0, 956.0)
     └─SemanticsNode#3
       │ flags: scopesRoute
       ├─SemanticsNode#6
       │ └─SemanticsNode#7
       │     Rect.fromLTRB(105.1, 76.0, 334.9, 104.0)
       │     flags: isHeader
       │     label: "Flutter Demo Home Page"
```
Full labels + logical rects + flags, on iOS, on a stock app. If this holds on a cold start it is
the iOS element source. Output is PROSE, not JSON (matches _PRIOR.md) — it needs a parser.
Retesting from a cold app start now.


### F16. DECISIVE: `SemanticsBinding.instance.ensureSemantics()` IS callable from outside, via `evaluate`. (CONFIRMED, run)
Target library `package:flutter/src/semantics/binding.dart` (NOT the app's library — see F13):
```
> evaluate(isolateId, targetId=<libid package:flutter/src/semantics/binding.dart>,
           expression="SemanticsBinding.instance.ensureSemantics()")
  -> SemanticsHandle
> evaluate(... "SemanticsBinding.instance.semanticsEnabled")  -> "true"
```
This dissolves the entire premise of the assignment's question 1. The app does NOT have to be
modified and a screen reader does NOT have to be running: the driver turns semantics on itself,
at runtime, over the VM Service, on a stock release-of-the-day app. One RPC.

### F17. The iOS semantics dump gives labels + logical rects + actions + flags. (CONFIRMED, run)
Cold-launched stock app, `ext.flutter.debugDumpSemanticsTreeInTraversalOrder`:
```
SemanticsNode#0
 │ Rect.fromLTRB(0.0, 0.0, 1320.0, 2868.0)
 └─SemanticsNode#1
   │ Rect.fromLTRB(0.0, 0.0, 440.0, 956.0) scaled by 3.0x
   ...
       │     Rect.fromLTRB(105.1, 76.0, 334.9, 104.0)
       │     flags: isHeader
       │     label: "Flutter Demo Home Page"
       │   Rect.fromLTRB(66.5, 509.0, 373.5, 529.0)
       │   label: "You have pushed the button this many times:"
       │   Rect.fromLTRB(211.5, 529.0, 228.5, 565.0)
       │   label: "0"
         │ Rect.fromLTRB(0.0, 0.0, 56.0, 56.0) with transform
             Rect.fromLTRB(0.0, 0.0, 56.0, 56.0)
             actions: tap
             flags: isButton, hasEnabledState, isEnabled, isFocusable
```
Everything a journey walker needs: label, logical rect, `actions: tap`, role flags.
Note the FAB's node is `Rect.fromLTRB(0,0,56,56) with transform` — leaf rects are LOCAL and the
transform must be composed down the chain. A naive parser that reads the leaf Rect gets (0,0).
Second calibration knob.
Output is PROSE (box-drawing characters), not JSON — confirms _PRIOR.md. A parser is required,
and the `with transform` case means the parser is not trivial.

### F18. `semanticsEnabled == true` at cold start on THIS machine is ambient state, not a guarantee. (CONFIRMED, run)
The cold-start probe surprised me by reporting semantics already on before any dump:
```
semanticsEnabled at cold start: true
```
Cause, not a Flutter property — the simulator has accessibility flagged on at the OS level:
```
$ xcrun simctl spawn A258A9DE-D8C3-481C-80C8-7A5E9491B145 defaults read com.apple.Accessibility
{
    AccessibilityEnabled = 1;
    ApplicationAccessibilityEnabled = 1;
    ...
}
$ defaults read com.apple.Accessibility ApplicationAccessibilityEnabled   # the host mac
1
```
This is per-machine state (some tool turned it on at some point). It explains the confusing
F15 observation, which is now withdrawn as an artifact of a partially-built tree.
=> The skill must NEVER assume it. Always call `ensureSemantics()` (F16) first and verify
   `semanticsEnabled` reads back true. On a clean CI machine the ambient value will be false.

## Exact interface

### The recommended mechanism — one transport, both platforms, zero new dependencies
Everything below is verified on this machine against Flutter 3.47.2 stable / Dart 3.13.2.

**Transport.** A single-file Dart script, `dart:io` `WebSocket` + `dart:convert` only.
No pubspec, no `pub get`, no `package:vm_service`. `dart` ships with Flutter, so a Flutter
user already has it. JSON-RPC 2.0 over the WS URI that `flutter run` prints:
```
A Dart VM Service on iPhone 17 Pro Max is available at: http://127.0.0.1:64521/uOzKmUib7Gc=/
                                                     -> ws://127.0.0.1:64521/uOzKmUib7Gc=/ws
```
Bootstrap:
```
getVM                                        -> result.isolates[0].id
getIsolate {isolateId}                       -> result.libraries[] (uri -> id), result.extensionRPCs[]
```

**1. Turn semantics on (ALWAYS — never assume, see F18).**
```
evaluate {isolateId, targetId: <lib id of "package:flutter/src/semantics/binding.dart">,
          expression: "SemanticsBinding.instance.ensureSemantics()"}          -> SemanticsHandle
evaluate {... expression: "SemanticsBinding.instance.semanticsEnabled"}       -> "true"
```

**2. List elements (label + rect + actions + role).**
```
ext.flutter.debugDumpSemanticsTreeInTraversalOrder {isolateId}  -> {data: "<prose tree>"}
```
Prose, box-drawing indented. Per node: `Rect.fromLTRB(l,t,r,b)` (LOGICAL px), `label: "..."`,
`actions: tap, ...`, `flags: isButton, isHeader, hasEnabledState, ...`.
Leaf rects can be local with `with transform` on an ancestor — compose down the chain.
Complement with, for source attribution the semantics tree cannot give:
```
ext.flutter.inspector.getRootWidgetTree {isolateId, groupName, isSummaryTree:"true",
                                         withPreviews:"true", fullDetails:"false"}
   -> nodes with widgetRuntimeType, textPreview, valueId, createdByLocalProject
```

**3. Tap a named element** (resolve name -> rect from step 2, tap its center in LOGICAL px):
```
evaluate {isolateId, targetId: <lib id of "package:flutter/src/gestures/binding.dart">,
  expression: "GestureBinding.instance.handlePointerEvent(PointerDownEvent("
              "position: const Offset(396, 878), pointer: 501, "
              "timeStamp: const Duration(milliseconds: 1000)))"}
   (wait ~80ms)
evaluate {... "GestureBinding.instance.handlePointerEvent(PointerUpEvent("
              "position: const Offset(396, 878), pointer: 501, "
              "timeStamp: const Duration(milliseconds: 1080)))"}
   (settle ~800ms before reading state)
```
MANDATORY per F11: unique `pointer:` per tap, monotonic `timeStamp:`, ~80ms press, ~800ms settle.
Without these, ~1 tap in 3 is silently dropped.

**4. Screenshot** — here the native CLI wins; use it, not the VM Service.
```
iOS:      xcrun simctl io <udid> screenshot out.png
          # -> "Wrote screenshot to: out.png"; PNG 1320x2868 (device px = logical x3)
Android:  adb exec-out screencap -p > out.png
          # -> PNG 1080x1920
```
(`ext.flutter.inspector.screenshot` exists but is per-widget and needs a valueId; the CLI gives
the real composited frame including platform chrome, which is what a VISUAL pass wants.)

### Android-only alternative, fully verified, even lighter
If a run is Android-only, plain `adb` closes the whole loop with no Dart script at all (F2/F3):
```
adb shell uiautomator dump /sdcard/ui.xml && adb shell cat /sdcard/ui.xml
   # Flutter labels arrive in content-desc=, NOT text=. bounds="[l,t][r,b]" in DEVICE px.
adb shell input tap <X> <Y>          # device px
adb exec-out screencap -p > out.png
adb shell settings get secure accessibility_enabled     # 0 here; semantics still worked
```
uiautomator's own UiAutomation is the a11y client that flips Flutter's semantics on, so no
app change and no screen reader is needed. Verified: first dump after a cold start is already
populated (no race).

### Rejected
- `xcrun simctl` for control — has no tap/input/gesture subcommand at all (F6). Screenshot only.
- mobile-mcp — needs a per-device agent installed on iOS (F5), and on Android it is a lossy
  re-serialization of the uiautomator tree that drops labels raw `adb` keeps (F4).
- `ext.flutter.accessibilityEvaluations` — experimental, hard-off on stable (F12).
- idb / WebDriverAgent / XCUITest — new dependencies (brew + pip, or an Xcode test target).
  Not evaluated in depth because F10/F16 removed the need.
- `flutter_driver` / `integration_test` — needs the app to call `enableFlutterDriverExtension()`
  or a generated Dart test + rebuild. `ext.flutter.driver.*` is absent from a stock app's
  extensionRPCs (F7), confirming it is opt-in.

## Plan impact

1. **The plan's step-2 "journey walk" should NOT depend on `flutter_skill`, mobile-mcp, or any
   MCP server.** Everything step 2 needs — a11y tree, screenshot, RenderBox measurement, step
   timing — is reachable from the VM Service that `flutter run` already exposes, plus one
   native screenshot command per platform. This is the single biggest simplification available:
   it deletes a dependency, a distribution problem and a support surface. `flutter_skill` (whose
   probe app _PRIOR.md/run2.log covers) is doing exactly this behind a package; for a
   PUBLIC distributable skill, ~150 lines of dependency-free Dart beats taking the dependency.

2. **Kill the "app must call ensureSemantics()" requirement from the design.** F16 proves the
   driver flips it remotely. The skill must not ask users to edit `main.dart`. It also must not
   assume semantics are already on (F18) — call it, then read `semanticsEnabled` back and fail
   loudly if false.

3. **Two calibration knobs must be in v0.1, not deferred.** (a) tap timestamps/pointer ids, or
   ~1/3 of taps vanish and the journey report is fiction (F11); (b) the semantics-tree transform
   composition, or every nested element reports rect (0,0) and the tap-target-size heuristic
   reports garbage (F17). Both are the kind of thing that looks fine on the happy path.

4. **Do not build on `ext.flutter.accessibilityEvaluations`** (F12) even though it looks like it
   would hand you three Nielsen-adjacent checks for free. It is main-channel + feature-flag only.
   Implement contrast / tap-target / missing-label from the semantics rects yourself. Re-check
   when it graduates — it is exactly the right API and would delete a chunk of the heuristic pass.

5. **Coordinate spaces differ per source and per platform — pick one and normalize at the edge.**
   VM Service semantics rects = logical px (440x956). `adb uiautomator` bounds and `adb input tap`
   = device px (1080x1920). `simctl` screenshot = device px (1320x2868, dpr 3). Annotated
   screenshots need logical->device scaling. This is a likely source of silent wrongness.

6. **PUBLIC-REPO SAFETY — this mechanism is the safe one.** It reads only what the running app
   exposes and writes nothing to the repo. But note the artifacts it produces are radioactive:
   the semantics dump contains every UI string, `getRootWidgetTree` contains the private app's
   widget names AND `createdByLocalProject` source attribution, and screenshots contain
   everything. v0.1 should ship: the walker, the parsers, the heuristics, and a journey.yaml
   SCHEMA with a synthetic example journey against a `flutter create` counter app (as used for
   every experiment here — `com.example.semdemo` is stock scaffolding and leaks nothing).
   Dogfood output (report.md, findings.json, annotated screens) must be written to a
   gitignored directory by default. Do not commit a sample report generated from the real app,
   and do not use the private app's package id as the example.

## Unknowns

- **Not tested on a physical device.** iOS-simulator-only for the `evaluate` path. On a physical
  iOS device the VM Service is reachable over the forwarded port that `flutter run` sets up, so
  it should work identically, but it is unverified. `simctl` screenshot obviously does not apply
  to a real device (`idevicescreenshot` would be needed).
- **Not tested in profile/release.** The inspector and dump extensions are `!kReleaseMode`;
  `evaluate` needs the resident compiler from `flutter run` (F9). A release-mode audit is out.
- **Not tested: whether `evaluate` latency makes step timing untrustworthy.** The plan wants
  per-step timing as evidence; the driver's own RPC round-trips are inside that window. Needs a
  measurement before any timing-based finding is reported.
- **Not tested: scrolling / text entry / multi-touch** through the same mechanism. Only tap.
  `PointerMoveEvent` presumably composes the same way; unverified.
- **Not tested: a truly clean machine** where `com.apple.Accessibility AccessibilityEnabled = 0`.
  F16 should make that irrelevant, but the claim "works on a fresh CI box" is unproven.
- **Not tested: the semantics prose parser against a real, deep app.** The counter app has 9
  semantics nodes. `with transform`, merged nodes, `SemanticsNode#N` reuse across frames, and
  offscreen nodes are all likely to bite on a real screen.
- **`idb` was never benchmarked.** If the physical-iOS-device case turns out to matter, it
  deserves a look before being dismissed.
