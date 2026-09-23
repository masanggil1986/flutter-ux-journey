# flutter_skill

## VERDICT: confirmed (with important caveats)

Short form: it is a **real, installable, machine-callable CLI + MCP server**, not markdown-for-an-LLM,
and not web-only. But it is an unverified-uploader solo package with heavy marketing copy, and it
**requires modifying the target app** (2 lines).

**Verified end-to-end on an iOS simulator**: it dumps a structured interactive-element list with
real per-element `bounds`, taps by widget Key, enters text, and drives a real route change (F12,
F15, F16). v0.1 CAN depend on it for the RUNTIME layer — using exactly two subcommands,
`inspect` and `act`.

**The caveat that shapes the whole design**: `act` returns `{"success":true}` and exit 0 even when
the target widget does not exist, and a tap-by-text reported success while doing nothing (F15, F19).
The tool reports dispatch, not outcome. The journey runner MUST verify each step by diffing
`inspect` before/after; it can never trust `success` or the exit code.

Not usable from it: screenshots (CLI path is web-only — use `xcrun simctl io` instead, F17),
step timing (absent on the working path, F18), and the semantics/accessible-name layer
(it returns a *widget* list, not the semantics tree — my `Semantics(label:)` never surfaced, F13).

## Facts

### F1 — package identity (CONFIRMED)
- `flutter_skill` on pub.dev. latest **0.9.37**, published **2026-09-01T11:57:27.007731Z**.
  - `curl -s https://pub.dev/api/packages/flutter_skill`
    → `{"name":"flutter_skill","latest":{"version":"0.9.37",...,"published":"2026-09-01T11:57:27.007731Z"}}`
- repo/homepage: **https://github.com/ai-dashboad/flutter-skill**
- license **MIT**; tags from `curl -s https://pub.dev/api/packages/flutter_skill/score`:
  `{"grantedPoints":140,"maxPoints":160,"likeCount":25,"downloadCount30Days":12651,
    "tags":[...,"license:mit","license:osi-approved","has:executable",
            "platform:android","platform:ios","platform:windows","platform:linux","platform:macos","platform:web"]}`
- publisher: **`{"publisherId":null}`** → pub.dev page says **"unverified uploader"**. No org backing.
- first release **0.1.0 on 2026-01-30**; 0.1.0→0.1.3 all pushed within ~13 min. Early versions had
  placeholder homepage `https://github.com/yourusername/flutter-skill`. ~8 months old, 37 releases.
- deps: `flutter(sdk)`, `vm_service >=14.0.0 <16.0.0`, `http ^1.1.0`, `path ^1.8.0`, `logging ^1.2.0`, `crypto ^3.0.0`
- also distributed as npm `flutter-skill`, brew, scoop, docker, VSCode/JetBrains ext (per README).

### F2 — it installs and is a real CLI (CONFIRMED, ran it)
```
$ dart pub global activate flutter_skill
...
+ flutter_skill 0.9.37
+ vm_service 15.3.0
Building package executables...
Built flutter_skill:server.
Built flutter_skill:flutter_skill.
Installed executable flutter_skill.
Activated flutter_skill 0.9.37.
```
Local env: Flutter 3.47.2 stable / Dart 3.13.2 — no version conflict.

Binary: `~/.pub-cache/bin/flutter_skill`. Note: `--help` and `help` are BOTH rejected
(`Unknown command: --help`); the bare command prints usage.

### F3 — NOT web-only. It has a native/Flutter-runtime path. (CONFIRMED by source)
Package source (`/…/scratchpad/day1/pkg/`) contains distinct drivers:
```
lib/src/drivers/flutter_driver.dart      lib/src/drivers/native_driver.dart
lib/src/drivers/bridge_driver.dart       lib/src/drivers/web_bridge_driver.dart
lib/src/drivers/app_driver.dart
lib/src/bridge/cdp_driver.dart           (Chrome DevTools Protocol — the WEB path)
native/ios-hid/fs-ios-bridge             (prebuilt iOS HID bridge binary + fs_ios_bridge.m)
native/cdp-engine/ (Rust)
lib/src/discovery/dtd_service_discovery.dart, process_based_discovery.dart
```
So: web/CDP is ONE of several backends, not the only one. The `vm_service` dependency +
`dtd_service_discovery.dart` is the Flutter-app-on-device path.

### F4 — IT REQUIRES MODIFYING THE TARGET APP (CONFIRMED, from README)
README "Quick Start" step 3, verbatim:
```dart
import 'package:flutter_skill/flutter_skill.dart';

void main() {
  if (kDebugMode) FlutterSkillBinding.ensureInitialized();
  runApp(MyApp());
}
```
Not `enableFlutterDriverExtension()` but the same class of requirement: **the app must add a
dependency and a line in `main()`**. `flutter_skill init` claims to auto-patch the project.
=> A v0.1 that depends on this cannot audit an arbitrary unmodified app.

### F5 — CLI surface (verbatim from `flutter_skill` with no args)
```
flutter-skill v0.9.37 - AI Agent Bridge for Flutter Apps

Commands:
  init         Auto-setup any project (Flutter/iOS/Android/RN/Web)
  quickstart   Guided demo — see flutter-skill in action in 30s
  demo         Launch a built-in demo app — zero setup needed
  launch       Launch and auto-connect to an app
  connect      Attach to a running Flutter app and name it
  ping         Health check one or more named server instances
  server       Start MCP server / manage named server instances
  servers      List all running named server instances
  inspect      Inspect interactive elements
  act          Perform actions (tap, enter_text, scroll)
  screenshot   Take a screenshot of the running app
  serve <url>  Zero-config WebMCP server — any site → AI tools

Client commands (connect to running serve):
  nav <url>      Navigate to URL
  snap           Accessibility tree snapshot
  screenshot     Take screenshot
  tap <text>     Tap element by text, ref, or coordinates
  type <text>    Type text via keyboard
  ...
  doctor       Check installation and environment health
```
Note the split: `inspect` / `act` / `screenshot` / `connect` / `launch` are the **app** commands;
`nav` / `eval` / `hover` / `upload` are the **web client** commands. The two are different surfaces.

### F6 — advertised capability vs the 5 things the plan needs (from README, NOT yet all verified on device)
- (a) a11y/semantics tree → `snapshot`, `inspect`, `inspect_interactive`, `get_widget_tree`. Claims
  "structured element tree instead of an image — 87–99% fewer tokens".
- (b) tap by text/key/semantics label → YES, and it has a **semantic ref** scheme:
  `tap(ref: "button:Login")`, `input:Email`; "7 roles: button, input, toggle, slider, select, link, item".
- (c) screenshot → `screenshot`, `screenshot_region`, `screenshot_element`, `native_screenshot`.
- (d) element sizes → **unclear**. No documented size/rect tool in the 253-tool list; `inspect`
  output shape must be checked empirically.
- (e) step timing → **unclear**. README quotes per-op benchmarks (`tap 1ms`) and lists
  "Performance monitoring" as a feature, but no documented per-step timing output.

### F7 — scale claims to treat with suspicion
README claims 253 MCP tools, 10 platforms, "656/664 tests passing", `tap` in **1 ms** and
"50–100× faster than Playwright". A 1 ms end-to-end tap including a frame is not physically
plausible as a user-visible action; it is at best in-process dispatch latency. Treat the numbers as
marketing, not as a measured contract. 253 tools is also a red flag for a skill whose philosophy is
Simplicity — we would be importing a very large surface to use ~5 of it.

### F8 — `doctor` works and sees real devices (CONFIRMED, ran it)
```
$ flutter_skill doctor
🔍 flutter-skill doctor
  Environment:
    ✅ flutter-skill v0.9.37
    ✅ Dart SDK: Dart SDK version: 3.13.2 (stable) ... on "macos_arm64"
    ✅ Chrome: Google Chrome 153.0.8010.53
    ✅ CDP port 9222 available
    ✅ Bridge port 18118 available
  Mobile:
    ✅ Android SDK found (android-37.0)
    ✅ ADB connected: emulator-5554 (sdk_gphone64_arm64)
    ✅ Xcode 26.6
    ✅ iOS Simulator: iPhone 17 Pro Max (booted)
    ✅ iOS Simulator: iPad Pro 13-inch (M5) (booted)
    ✅ iOS Simulator: iPhone SE (3rd gen) (booted)
  ...
  16 OK, 3 warnings
```
It genuinely enumerates iOS simulators and the Android emulator. This is NOT a web-only tool.

### F9 — `bounds` ARE in the documented output shape (source-confirmed, device test pending)
`pkg/lib/src/cli/tool_handlers/tool_definitions.dart:1417` defines tool `inspect_interactive`,
`[OUTPUT FORMAT]` verbatim:
```json
{
  "elements": [
    {
      "type": "ElevatedButton",
      "text": "Submit",
      "selector": {"by": "text", "value": "Submit"},
      "actions": ["tap", "long_press"],
      "bounds": {"x": 100, "y": 200, "width": 120, "height": 48},
      "enabled": true,
      "visible": true
    },
    { "type": "TextField", "label": "Email",
      "selector": {"by": "key", "value": "email_field"},
      "actions": ["tap", "enter_text"], "currentValue": "", "enabled": true, "visible": true }
  ],
  "summary": "Found 5 interactive elements: 2 buttons, 2 text fields, 1 switch"
}
```
=> answers plan requirement **(d) element sizes**: `bounds.width/height` per element. This is
exactly what a "tap target < 44pt" heuristic needs, WITHOUT us writing a RenderBox measurement step.

### F10 — step timing exists on the native path, but thin (source-confirmed)
- `pkg/lib/src/cli/act.dart:378`:
  `print('[${r.serverId}] ${r.action} completed (${r.durationMs}ms)');`
  → per-action wall-clock duration IS reported. Good enough for "step took N ms".
- BUT `pkg/lib/src/cli/tool_handlers/performance_handlers.dart` is **web-only**: it runs
  `performance.now()` / `window.__fpsStart` JS. FPS/jank perf tooling does not apply to a
  simulator run.
- A `get_frame_stats`-style tool is declared (`tool_definitions.dart:2995`,
  "Get frame rendering statistics (FPS, jank, build/raster times)") — unverified on device.

### F11 — command shapes actually read from source
```
flutter_skill connect --id=<name> [--port=<port>|--uri=<uri>] [--project=<p>] [--device=<d>]
flutter_skill act [vm-uri] <action> <params...>        # auto-discovers VM URI if omitted
flutter_skill inspect [--server=<id>] [--output=json|human]
```
`--output=json` is a real global-ish flag (`resolveOutputFormat` / `stripOutputFormatFlag` in
`lib/src/cli/output_format.dart`, used by `inspect`, `act`, others). **Machine-callable: yes.**
`act` auto-discovers the VM service URI via `FlutterSkillClient.resolveUri([])` — no URI plumbing needed.

### F12 — ***DECISIVE: IT REALLY DRIVES A FLUTTER APP ON AN iOS SIMULATOR.*** (CONFIRMED, ran it)
Setup (throwaway probe app, NOT the private dogfood app):
```
$ flutter create --project-name fs_probe --platforms=ios testapp
$ cd testapp && flutter pub add flutter_skill
$ # lib/main.dart: FlutterSkillBinding.ensureInitialized() + a few probe widgets
$ flutter run -d A258A9DE-D8C3-481C-80C8-7A5E9491B145 --debug      # iPhone 17 Pro Max simulator
A Dart VM Service on iPhone 17 Pro Max is available at: http://127.0.0.1:63245/Z9HuD6N1Eh4=/
flutter: Flutter Skill: Test indicators enabled
flutter: 🎭 Test Indicators Auto-Enabled (detailed mode)
```
Then:
```
$ flutter_skill inspect "ws://127.0.0.1:63245/Z9HuD6N1Eh4=/ws" --output=json
DEBUG: Connecting to ws://127.0.0.1:63245/Z9HuD6N1Eh4=/ws
DEBUG: Connected to VM Service
DEBUG: Got VM info
{"elements":[...]}
```
REAL output (excerpt, verbatim — 13 elements returned):
```json
{"elements":[
 {"id":"elem_001","type":"Button","widgetType":"ElevatedButton","key":"big_button",
  "text":"Increment","ancestors":["Column","KeyedSubtree","MediaQuery"],
  "bounds":{"x":41,"y":138,"width":117,"height":48},"center":{"x":100,"y":162},
  "visible":true,"coordinatesReliable":true,"hittable":true},
 {"id":"elem_004","type":"Button","widgetType":"IconButton","key":"tiny_button",
  "text":"","icon":"IconData(U+0E047)","ancestors":["SizedBox","Column","KeyedSubtree"],
  "bounds":{"x":90,"y":186,"width":20,"height":20},"center":{"x":100,"y":196},
  "visible":true,"coordinatesReliable":true,"hittable":true},
 {"id":"elem_007","type":"TextField","widgetType":"TextField","key":"email_field",
  "ancestors":["SizedBox","Column","KeyedSubtree"],
  "bounds":{"x":0,"y":206,"width":200,"height":56},"center":{"x":100,"y":234},
  "visible":true,"coordinatesReliable":true,"hittable":true},
 {"id":"elem_008","type":"Button","widgetType":"IconButton","key":"unlabeled_icon",
  "text":"","icon":"IconData(U+0E57F)","bounds":{"x":76,"y":262,"width":48,"height":48},...},
 {"id":"elem_011","type":"Button","widgetType":"TextButton","key":"nav_button","text":"Next",
  "bounds":{"x":68,"y":310,"width":64,"height":48},...}
]}
```
**This settles the assignment's deciding question: it is a machine-callable CLI that drives a real
Flutter app on an iOS simulator. Not Chrome-only. Not markdown-for-an-LLM.**

Notes on the real output shape (differs from the README's advertised `inspect_interactive` shape):
- Actual `inspect` keys: `id, type, widgetType, key, text, icon, ancestors, bounds{x,y,width,height},
  center{x,y}, visible, coordinatesReliable, hittable`. There is **no** `selector`, `actions`,
  `enabled`, `currentValue`, or `summary` — those belong to the separate `inspect_interactive`
  MCP tool, not to the `inspect` CLI command. Don't code against the README shape.
- `bounds` are in **logical pixels** (screen is 440pt wide; `x:41..158` for a centered 117pt button).
- **Duplicate coverage**: one logical button yields 3 entries (`Button`/ElevatedButton +
  `Tappable`/InkWell + `Tappable`/GestureDetector) with near-identical bounds. Any consumer MUST
  dedupe, e.g. keep `type != "Tappable"` or group by `center`.
- `icon` is exposed as raw `IconData(U+0E047)` — no semantics label. Useful for an
  "icon-only control with no accessible name" finding.

### F13 — the plan's requirements (a)-(e), settled
- **(a) a11y/semantics tree** — PARTIAL. `inspect` returns a flat **widget/interactive-element list
  with an `ancestors` array**, NOT the Flutter semantics tree. It is structured JSON (which the
  native `debugDumpSemanticsTree` is not — _PRIOR.md noted that comes out as prose), so it is
  strictly better than the native dump for our purpose, but it is a *widget* view, not a
  *semantics* view. Semantics labels (`Semantics(label: 'Go to second page')` on my probe's
  nav_button) did **not** appear as a label field in the output — only `text:"Next"`.
  => flutter_skill does NOT give us the accessible-name layer. That is a real gap for a UX audit.
- **(b) tap by text/key/semantics label** — YES for key and text (`flutter_skill act tap <key|text>`),
  see F14. Not by semantics label.
- **(c) screenshot** — command exists (`flutter_skill screenshot`), see F14.
- **(d) element sizes** — **YES, and this is the strongest result.** `bounds.width/height` per
  element, real values, correct: my deliberately 20x20 `tiny_button` came back as
  `"bounds":{"x":90,"y":186,"width":20,"height":20}`. A "tap target < 44pt" Nielsen finding is
  computable directly from this with zero extra code. **The plan's separate "RenderBox measurement"
  step is unnecessary — delete it.**
- **(e) step timing** — WEAK. `act` prints `... completed (NNNms)` wall-clock per action
  (`lib/src/cli/act.dart:378`). That is host-side round-trip time, NOT user-perceived latency and
  NOT frame/jank data. `performance_handlers.dart` (FPS/jank) is **web-only JS**
  (`performance.now()`, `window.__fpsStart`) and does not apply on a simulator.

### F14 — OPERATIONAL LANDMINE: the VM Service wedges, and auto-discovery hangs (CONFIRMED, hit it)
1. `flutter_skill inspect --output=json` with **no URI** (relying on `FlutterSkillClient.resolveUri`
   auto-discovery) produced **zero output and never returned** — killed at 120s, then again at 45s.
   Always pass the VM Service ws:// URI explicitly.
2. After several killed clients piled up, the app's VM Service went **unresponsive while still
   LISTENING**. Evidence:
   ```
   $ lsof -nP -iTCP:62601
   dartvm  3407 ... 127.0.0.1:62989->127.0.0.1:62601 (ESTABLISHED)
   dartvm 88192 ... 127.0.0.1:62604->127.0.0.1:62601 (ESTABLISHED)
   dart   91062 ... 127.0.0.1:62601 (LISTEN)
   $ curl -s --max-time 8 "http://127.0.0.1:62601/TYlHcEa5Eok=/getVM"
   exit=28        # 28 = curl operation timeout
   ```
   A plain `vm_service` Dart client of my own hung identically on the same port — so this is the
   **VM Service / abandoned-socket problem, not a flutter_skill bug**. A clean app restart fixed it
   instantly (`curl ... /getVM` → `exit=0`, full VM JSON).
   => Any journey walker MUST use a per-call timeout and be prepared to restart the app. An
   unattended multi-step walk that leaks a hung client will wedge the whole run.

### F15 — tap / enter_text / navigation: WHAT ACTUALLY WORKS (CONFIRMED, ran it, verified by pixels)
All against the live simulator app, verified independently with
`xcrun simctl io <udid> screenshot` (NOT with flutter_skill's own report).

| attempt | flutter_skill said | what ACTUALLY happened |
|---|---|---|
| `act <uri> tap big_button` (by **key**) | `Tapped "big_button"` | ✅ worked — screenshot showed `count: 1` |
| `act <uri> tap Next` (by **text**) | `Tapped "Next"` | ❌ **NOTHING HAPPENED.** Still on Probe Home. **FALSE POSITIVE.** |
| `act <uri> tap nav_button` (by **key**) | `Tapped "nav_button"` | ✅ navigated — screenshot showed "Second Page / You made it" |
| `act <uri> tap BackButton` | `Tapped "BackButton"` | ✅ returned to Probe Home |
| `act <uri> enter_text email_field "hello@test.com"` | `Entered text "hello@test.com" into "email_field"` | ✅ accepted |

**THE SINGLE MOST IMPORTANT FINDING: `tap` by text reported success and did nothing.**
The CLI does not verify its own action. A journey walker built naively on this will silently
"complete" a journey it never actually walked, and then confidently report UX findings about
screens it never reached. **Every step must be verified by re-inspecting after the action** —
by state change, not by the tool's return value.

Corollary: **prefer `Key` over text for targeting.** Key-based taps were 3/3; text-based 0/1.

### F16 — route transitions are visible in `inspect`, which is genuinely useful (CONFIRMED)
After `tap nav_button`, `inspect` returned **17** elements instead of 13 — both routes at once.
The outgoing route's elements had **negative x and `hittable:false`**, the new route's were positive
and `hittable:true`:
```json
{"widgetType":"ElevatedButton","key":"big_button","bounds":{"x":-105,"y":138,"width":117,"height":48},
 "center":{"x":-47,"y":162},"visible":true,"coordinatesReliable":true,"hittable":false}
{"widgetType":"BackButton","text":"","bounds":{"x":4,"y":66,"width":48,"height":48},
 "center":{"x":28,"y":90},"visible":true,"coordinatesReliable":true,"hittable":true}
```
Note `"visible":true` is TRUE for the offscreen outgoing route — **`visible` is useless, `hittable`
is the real filter.** Filter `hittable == true` to get "what the user can actually act on now".
The appearance of a `BackButton` is also a free, reliable "we changed route" signal.

### F17 — `screenshot` CLI subcommand is WEB-ONLY (CONFIRMED, ran it)
```
$ flutter_skill screenshot "ws://127.0.0.1:63245/Z9HuD6N1Eh4=/ws" shot.png
Error: flutter-skill serve not running on http://127.0.0.1:3000
Start it with: flutter-skill serve <url>
```
Cause, from source `pkg/bin/flutter_skill.dart:210-231`: `screenshot` falls into the
`case 'nav': case 'snap': case 'screenshot': ... await runClient(...)` block — i.e. it is
dispatched to the **HTTP web-serve client**, despite the usage text claiming
"screenshot   Take a screenshot of the running app".
The Flutter capability DOES exist in the driver —
`pkg/lib/src/drivers/flutter_driver.dart:387` `takeScreenshot()` /
`:394 takeScreenshotWithInfo()` → `ext.flutter.flutter_skill.screenshot`, returning
base64 PNG + `imageWidth`/`imageHeight` — but it is **not reachable from the plain CLI with a VM URI.**
Reachable only via MCP server mode (`flutter_skill server`) or the `connect --id=` / `--server=` path.
**For v0.1, `xcrun simctl io <udid> screenshot out.png` is simpler, already installed, and worked
first try.** (Android: `adb exec-out screencap -p`.) Climb the ladder — don't route screenshots
through flutter_skill.

### F18 — no per-step timing on the direct-VM path (CONFIRMED — corrects F10)
```
$ flutter_skill act "<uri>" tap big_button --output=json
{"success":true,"action":"tap","target":"big_button"}
```
No `durationMs`. The `durationMs` print at `pkg/lib/src/cli/act.dart:378` is only in the
**`--server=` multi-server** branch, not the direct-VM branch. So on the path that actually works,
**flutter_skill gives you no timing at all.** Time the subprocess yourself — that is one line of
whatever drives it, and it is the honest number anyway (host round-trip, not user-perceived latency).

### F19 — ***`success:true` IS MEANINGLESS. EXIT CODE IS MEANINGLESS.*** (CONFIRMED, ran it)
The hardest finding of this investigation. Tapping a widget key **that does not exist anywhere in
the app**:
```
$ flutter_skill act "ws://127.0.0.1:63245/Z9HuD6N1Eh4=/ws" tap no_such_widget_xyz --output=json
exit=0
{"success":true,"action":"tap","target":"no_such_widget_xyz"}

$ flutter_skill act "<uri>" scroll down --output=json
exit=0
{"success":true,"action":"scroll","target":"down"}          # nothing scrollable on this screen
```
`success:true` and `exit=0` for a tap on a widget that **does not exist**. The tool does not check
whether the target was found, let alone whether anything changed. It reports the *dispatch*, not
the *outcome*.

The only thing that DOES produce a non-zero exit is a connection failure:
```
$ flutter_skill inspect "ws://127.0.0.1:1/bogus/ws" --output=json
exit=1
Error: Exception: ❌ Failed to connect to VM Service at ws://127.0.0.1:1/bogus/ws
...
Error details: SocketException: Connection refused (OS Error: Connection refused, errno = 61)
```
(Its error message is good — clear causes and next steps. Credit where due.)

**Consequence, and it is the whole design constraint for v0.1's runtime layer:**
a journey runner CANNOT use `success` or the exit code as its step oracle. The ONLY trustworthy
oracle is **diffing `inspect` output before and after each step**. This makes plan item 5 (verify
after every step) mandatory, not defensive-programming taste — without it the skill will emit
confident UX findings about screens it never reached, which is worse than emitting nothing.

Also note `scroll` IS accepted (`act <uri> scroll <direction>`), but since it returns `success:true`
unconditionally, this run proves only that the command exists — not that it scrolls.

## Exact interface

**VERIFIED working, exact commands, direct-VM path (this is the whole usable surface for v0.1):**

```bash
dart pub global activate flutter_skill          # installs ~/.pub-cache/bin/flutter_skill

# app must already be running via `flutter run -d <device-id> --debug`,
# and must have called FlutterSkillBinding.ensureInitialized() (see F4).
# Grab the ws:// URI from flutter run's stdout.

flutter_skill inspect <ws-uri> --output=json
flutter_skill act     <ws-uri> tap        <key-or-text>
flutter_skill act     <ws-uri> enter_text <key> <text>
flutter_skill act     <ws-uri> scroll     <direction>        # declared; untested here
flutter_skill act     <ws-uri> <action> ... --output=json
flutter_skill doctor
```
- `--output=json|human` is real (`pkg/lib/src/cli/output_format.dart`).
- **Always pass `<ws-uri>` explicitly.** Auto-discovery (`FlutterSkillClient.resolveUri`) hung
  indefinitely twice with zero output (F14).
- `--help` / `help` do NOT work (`Unknown command: --help`). Bare `flutter_skill` prints usage.

**`inspect --output=json` real output shape (verified, F12):**
```json
{"elements":[{
  "id":"elem_001", "type":"Button|Tappable|TextField", "widgetType":"ElevatedButton",
  "key":"big_button", "text":"Increment", "icon":"IconData(U+0E047)",
  "ancestors":["Column","KeyedSubtree","MediaQuery"],
  "bounds":{"x":41,"y":138,"width":117,"height":48}, "center":{"x":100,"y":162},
  "visible":true, "coordinatesReliable":true, "hittable":true
}]}
```
- logical pixels. `key`/`text`/`icon` optional. **No** `selector`/`actions`/`enabled`/`summary`
  (those are the MCP tool's shape, not the CLI's — the README misleads here).
- **dedupe required**: one button → 3 rows (Button + InkWell + GestureDetector). Keep `type != "Tappable"`.
- **filter `hittable == true`** for the current route. `visible` is true even for offscreen routes.

**`act ... --output=json` real output shape (verified):**
```json
{"success":true,"action":"tap","target":"big_button"}
```
`success:true` means "the command was dispatched", **NOT** "the target existed" and **NOT** "the UI
changed" (F15, F19). Exit code is 0 even for a tap on a nonexistent widget; only a connection
failure exits 1.

**Driver-only, NOT reachable from the CLI's direct-VM path** (would need MCP server mode):
`ext.flutter.flutter_skill.screenshot` → base64 PNG + `imageWidth`/`imageHeight`
(`pkg/lib/src/drivers/flutter_driver.dart:387,394`), `screenshotRegion`, `screenshotElement`,
`interactiveStructured`.

## Plan impact

**1. RUNTIME layer: keep flutter_skill, but use only `inspect` + `act`. (verdict: yes, v0.1 can depend on it)**
It is the only thing tested that returns **structured JSON with per-element `bounds`** from a real
Flutter app on a simulator. The native alternative (`debugDumpSemanticsTree`) is prose (per _PRIOR.md).
Writing that ourselves means a VM-service client + widget-tree walker — real work flutter_skill already
did. MIT, 12.6k downloads/mo. Take it.

**2. DELETE the plan's "RenderBox measurement" step.** `inspect` already returns
`bounds{x,y,width,height}` per element. My deliberately-undersized 20x20 button came back as
`"bounds":{"x":90,"y":186,"width":20,"height":20}`. A "tap target < 44pt" Nielsen finding is a
comparison on JSON we already have. Zero code.

**3. DELETE "step timing" from v0.1.** flutter_skill gives none on the working path (F18), and
host-side subprocess round-trip is not user-perceived latency — reporting it as a UX finding would be
dishonest. If timing matters later, it needs `Timeline`/frame stats, which is its own project.

**4. REPLACE the screenshot source: use `xcrun simctl io <udid> screenshot out.png`**
(Android: `adb exec-out screencap -p > out.png`). Already installed, no dependency, worked first try.
flutter_skill's `screenshot` subcommand is web-only (F17). This also decouples the visual pass from
flutter_skill entirely.

**5. ADD a mandatory verify-after-every-step loop.** This is not optional polish — it is the
difference between a real report and a fabricated one. `act` returns `success:true` for taps that
do nothing (F15). After each step: re-`inspect`, and assert the expected state change (route
changed / element appeared / `hittable` set changed). If unchanged → abort the journey and report
"step N did not take effect", never continue and never report findings for unreached screens.

**6. Journey steps should target `Key`, not text.** Key 3/3, text 0/1 (F15). This is a real
constraint on `journey.yaml`'s schema: a step should name a widget key. It also means the
skill's static pass has a job: find the keys. Apps without keys are a documented limitation,
not something to paper over with fuzzy text matching.

**7. The a11y/semantics gap is the plan's real hole.** `inspect` gives a *widget* list, not the
*semantics* tree. My `Semantics(label: 'Go to second page')` wrapper **did not surface** — only
`text:"Next"`. So flutter_skill cannot tell you "this control has no accessible name" from
semantics; you can only infer it (`type:"Button"` with empty `text` and an `icon:` — e.g. my
`unlabeled_icon` came back `"text":"", "icon":"IconData(U+0E57F)"`, which IS a usable heuristic).
Either accept the heuristic and say so plainly in the report, or drop a11y-naming findings from v0.1.

**8. Add hardening for the wedge (F14).** Per-call timeout on every flutter_skill invocation, never
leak a killed client, and be able to restart the app. Unattended runs otherwise hang forever.

**9. PUBLIC-REPO CONSTRAINT — what this settles.**
flutter_skill is a **dev-machine dependency, not repo content**: the committed skill needs only
prose instructions + a small runner. That is good for the public/private split. BUT the artifacts it
produces — `inspect` JSON — contain **widget keys, route/screen names, `ancestors` chains, and all
visible UI copy** verbatim. My probe leaked `"key":"email_field"`, `"text":"Increment"`,
`ancestors:["Column","KeyedSubtree","MediaQuery"]`. Screenshots leak everything.
=> v0.1 must ship: the skill + the runner + a **synthetic example app and example journey** to
demo on. It must NOT ship fixtures, findings.json, report.md or screenshots from the dogfood app.
Put the output dir in `.gitignore` and make the skill write there by default.

**10. YAGNI check against the 253-tool surface.** We use exactly two subcommands. Do not
adopt `server`/MCP mode, `explore`, `monkey`, `security`, `diff`, or the web/CDP half. Pin the
version (`flutter_skill 0.9.37`) — it is an unverified solo uploader shipping ~37 releases in 8
months, so treat an unpinned range as a live liability.

## Unknowns
- **`scroll` accepted but unproven.** `act <uri> scroll down` returns `{"success":true,...}`, but
  since that is returned unconditionally (F19) this proves only that the command parses. Needs a
  scrollable screen and a before/after `inspect` diff to actually verify.
- **Android emulator untested.** All evidence here is iOS simulator (iPhone 17 Pro Max, iOS 26.2).
  `doctor` saw `emulator-5554`, but nothing was driven on it.
- **Why tap-by-text silently failed is not diagnosed.** Could be the `Semantics` wrapper, could be
  ambiguity across the 3 duplicate rows, could be a general text-matching bug. I only know it
  reported success and did nothing.
- **MCP server mode (`flutter_skill server`) not tested at all** — so the screenshot/`bounds`-rich
  `inspect_interactive`/`get_frame_stats` tools remain unverified. If the direct-VM path proves too
  thin, this is the next thing to try, at the cost of a much bigger surface.
- `flutter_skill init`'s auto-patching of a project was not run (deliberately: it edits source).
- The `conalyz` open items from _PRIOR.md (license, exit codes) were out of scope here.
