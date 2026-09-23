# heuristics.md — Named Checks, severity, merge

- [Attribution](#attribution)
- [Severity scale](#severity-scale)
- [Severity is scored against the goal](#severity-is-scored-against-the-goal)
- [Evidence layers and confidence](#evidence-layers-and-confidence)
- [Named Checks](#named-checks)
- [Evidence to check mapping](#evidence-to-check-mapping)
- [Measurement predicates](#measurement-predicates)
- [Placement vs priority](#placement-vs-priority--the-only-honest-route-to-this-is-buried)
- [Cross-step checks](#cross-step-checks)
- [Merge and dedupe](#merge-and-dedupe)
- [Never scored](#never-scored)
- [Mechanisms measured and refuted](#mechanisms-measured-and-refuted--do-not-re-propose)

## Attribution

The Named Check IDs and the severity scale are borrowed from
[EliaAlberti/ux-audit-skill](https://github.com/EliaAlberti/ux-audit-skill), MIT,
Copyright (c) 2026 Elia Alberti. The underlying heuristics (Nielsen 1994, WCAG 2.1, Fitts) are not
anyone's property; the ID set and the scale are his expression, so the notice travels with them.

Two corrections to how that scale is usually cited:

- It is **not** a literal Nielsen 0-4. There is no "0 = not a problem" row; the rows are
  `4 / 3 / 2 / 1 / ✓`, where `✓` marks a positive.
- "16 frameworks" only counts to 16 if section E's five behavioural laws are expanded. Irrelevant
  here: this skill borrows the IDs and the scale, not the framework catalogue.

That skill's stated non-goal is this skill's whole thesis — it lists screen-reader semantics, focus
visibility and keyboard navigation as *"not assessable from static screens"*. Step 2 measures exactly
those from a running app. Acknowledge the prior art; do not claim the category is empty.

## Severity scale

| Severity | Name | Meaning on a journey |
|---|---|---|
| 4 | Critical | The goal cannot be reached, or is reached only by luck or insider knowledge |
| 3 | Major | The goal is reachable but the user is blocked, backtracks, or fails on first attempt |
| 2 | Minor | Friction: extra steps, hesitation, a workaround exists and is discoverable |
| 1 | Cosmetic | Noticed, not costly |
| ✓ | Positive | Something the journey does well — report these, a report of only defects gets discounted |

## Severity is scored against the goal

**The same defect is 4 if it blocks the goal and 2 if there is a way around it.** This is the whole
scoring rule; everything else is bookkeeping.

Ask, in order:

1. Did this stop the journey from reaching its goal? → **4**
2. Did it cost a backtrack, a retry, or a guess that only someone who read the code would make? → **3**
3. Is there a discoverable way around it? → **2**
4. Is it merely noticed? → **1**

Worked example, same defect, two goals: a 24×24 tap target on the only "Continue" button is **4** when
the goal is "complete checkout"; the identical widget as one of five ways to open a settings page is
**2**. Severity is never a property of the widget alone — always cite the goal in the rationale.

Findings that never appeared on a screen the journey visited do not get goal-relative severity at
all. Cap them at 2 and mark the confidence accordingly.

## Evidence layers and confidence

| Layer | Source | Confidence it earns |
|---|---|---|
| `STATIC` | step 1, name-matched AST, no type resolution | low alone; medium when a walked screen confirms it |
| `RUNTIME` | step 2, measured rects, guideline evaluations, semantics tree | high — quote the number |
| `VISUAL` | step 3, the model reading the PNG | medium; high when a measurement agrees |
| `JOURNEY` | step 4, cross-step reasoning over the walk | medium to high; always cite the steps |

A finding may carry more than one layer. `STATIC` + `RUNTIME` on the same node is the strongest
combination available and should be stated as both.

When eye and measurement disagree: geometry is settled by the measurement, meaning by the eye.

## Named Checks

Use these IDs verbatim. One finding, one ID; if two fit, pick the one the user would name.

| ID | Fires when | Layers that can prove it |
|---|---|---|
| `CTA-AMBIGUITY` | The action's label does not say what happens next | VISUAL, RUNTIME (label text) |
| `DEAD-END` | A screen offers no way to continue or return | JOURNEY, VISUAL |
| `FAKE-AFFORDANCE` | Looks tappable, carries no tap action — or the reverse | VISUAL + RUNTIME (`tappable`) |
| `CONTRAST-FAIL` | Text fails the WCAG AA ratio for its size | RUNTIME (`textContrastGuideline`) |
| `TOUCH-TARGET` | Tap target below 44×44 (iOS) / 48×48 (Android) logical px | RUNTIME (tap target guidelines) |
| `JARGON-LEAK` | Internal or domain vocabulary surfaced to the user | VISUAL, RUNTIME (labels) |
| `PROGRESS-BLIND` | No feedback that a slow or multi-step operation is running | JOURNEY, VISUAL |
| `ERROR-VAGUE` | An error states neither the cause nor the recovery | VISUAL, JOURNEY |
| `FORM-FRICTION` | Input demands more than the task needs, or rejects late | VISUAL, STATIC (unlabeled fields) |
| `OVERLOAD` | Too many competing choices at one decision point | VISUAL |
| `PATTERN-DRIFT` | The same concept behaves or is styled differently across steps | JOURNEY |
| `TRUST-GAP` | A commitment is asked for without the information it needs | JOURNEY, VISUAL |
| `DARK-PATTERN` | The design steers against the user's interest | JOURNEY, VISUAL |
| `STATE-GAP` | State is lost or silently changed — scroll position, filters, entered data | JOURNEY |
| `HIERARCHY-FLAT` | The primary action is not visually primary | VISUAL |
| `RECALL-TAX` | The user must remember what an unlabeled control does | RUNTIME (`labeledTapTargetGuideline`), STATIC |

## Evidence to check mapping

Runtime guidelines:

| Guideline | Check | Default anchor before the goal rule |
|---|---|---|
| `iOSTapTargetGuideline` / `androidTapTargetGuideline` | `TOUCH-TARGET` | 3 |
| `textContrastGuideline` | `CONTRAST-FAIL` | 2 (3 if it is the text that carries the goal) |
| `labeledTapTargetGuideline` | `RECALL-TAX` | 3 |

Quote the guideline's own `reason` string: it already contains the node, the rect, the measured value
and the required value. Its contrast **ratio** is advisory (the light/dark partition is naive); its
**node** is the signal.

Static rules:

| Static rule | Check | Note |
|---|---|---|
| `GestureDetector`/`InkWell` with `onTap`, no semantics | `RECALL-TAX` | confirm against the walk's `tappable` nodes |
| `IconButton`/`Icon` with no `tooltip` and no `semanticLabel` | `RECALL-TAX` | |
| `Image` with no `semanticLabel` | `RECALL-TAX` | 1 unless the image carries meaning the journey needs |
| unlabeled `TextField` | `FORM-FRICTION` | |

## Measurement predicates

Five of the sixteen checks are flow- and layout-shaped, and until v0.2 all five were
`VISUAL`/`JOURNEY` only — which in practice means the model invented a threshold per run. Each now
has a predicate over fields the walk measures. **A check listed here does not fire unless its
predicate holds.** The other eleven have no predicate and are unchanged: they stay model judgements
and say so.

| Check | Predicate (all terms come from the walk) | Layer it earns |
|---|---|---|
| `DEAD-END` | `surface.canPop == false` **and** `surface.tappableCount == 0` **and** `surface.modalOpen == false` **and** the screen is not the journey's entry. When `surface.navigatorCount > 1`, `canPop` is an answer about one navigator among several — require `VISUAL` before firing | `RUNTIME` |
| `FAKE-AFFORDANCE` | `dispatched == true` **and** `semanticsUnchanged == true` **and** a second layer agrees (below) | `RUNTIME` + `VISUAL` |
| `TOUCH-TARGET` *(effective-area variant only)* | `effectivePct < 1.0` **or** `centreCovered == true`, on a node the journey needs. The ordinary size variant is not gated — it fires from a guideline `reason` like any other measurement | `RUNTIME` + `VISUAL` |
| `HIERARCHY-FLAT` | the node the journey's own step taps is `aboveFold == false`, **or** tap targets that appear in no declared priority precede it in reading order | `RUNTIME` |

`aboveFold` means the node **starts** in the visible band (`top >= 0 && top < foldY`) — the user
can see it without scrolling. `fullyVisible` is the stricter question and is a separate field:
requiring the whole rect inside the fold reads *false* for every bottom-pinned CTA and every hero
taller than the fold, which is most apps on any device with a home indicator, and `aboveFold` is
the only term in HIERARCHY-FLAT's first clause. Measured both ways on the same widget: a 88 lpx
`Pay now` pinned to the bottom is `aboveFold: true, fullyVisible: false`.
| `STATE-GAP` | the walk establishes a state (text typed, a filter chosen, a scroll performed) whose `screenSig` is S2, leaves, and returns to a step whose `screenSig` equals the PRE-state signature S1 — i.e. S2 never recurs. Equal signature no longer *implies* equal state was lost; it implies the state itself is gone | `RUNTIME` |

Two exclusions apply to every surface predicate and to the placement table, because without them
both fire on nearly every real app:

- **Nodes flagged `coversSurface`.** An **unnamed** tappable covering more than half the surface is
  the tap-to-dismiss-the-keyboard `GestureDetector` that sits on most form screens. It has no
  label, it is always first in reading order and it is always the largest thing present — so an
  area- or order-based check that counts it fires unconditionally. Measured: 250,125 lpx² against
  a real primary action's 10,627 lpx². It is keyed on *unnamed and big*, not on *is the whole
  surface*: that idiom is written inside the `Scaffold`, so its rect starts below the app bar and
  a whole-surface test read false on exactly the screens it exists for. `surface.tappableCount`
  already excludes these; `surface.coverNodes` says how many were excluded.
- **Nodes with `onScreen == false`.** A scrollable builds rows past the viewport into its cache
  extent, and they arrive in the dump with rects to match. Counting them inflates every surface
  number; tapping one dispatches into nothing.

`OVERLOAD` and `PATTERN-DRIFT` deliberately get **no** predicate.

- `OVERLOAD`: every candidate threshold is folklore. Miller's 7±2 is misapplied (NN/g says so
  outright) and the "3–5 bottom-bar destinations" figure carries no cited validation. Print the
  count as an observation — "the entry screen carries 8 tap targets; this journey traverses 1" —
  and let the model fire the check on meaning, not on a number nobody can defend.
- `PATTERN-DRIFT`: the only mechanical candidate was "two screens with the same structure use
  different words", and the structural half of that was measured refuted (see below). It stays a
  `JOURNEY` judgement.

### Rules that keep the flow findings honest

1. **Depth is never a severity on its own.** "N taps deep" is an observation. It earns a severity
   only when paired with a *declared* priority or with an observed backtrack. The 3-click rule is
   disproved — Porter (2003, UIE), and NN/g: *"user dropoff does not increase when the task involves
   more than 3 clicks, nor does satisfaction decrease."* A tool whose pitch is measurement cannot
   ship a threshold the literature already killed.
2. **Taps are "on this journey", never "the minimum".** A minimum needs paths nobody declared, which
   is a crawl — an explicit non-goal. Write `3 taps on the declared path`, never `3 taps deep`.
3. **A dead tap needs two layers.** `semanticsUnchanged` is necessary and not sufficient: a control
   that only repaints — a selection chip, a tab highlight, a toggled icon colour — is byte-identical
   in semantics to one wired to nothing. Measured in the fixture's `walker_test.dart`. Confirm with
   the screenshots (`cmp -s screens/step_N.png screens/step_N+1.png`) before raising
   `FAKE-AFFORDANCE`. **Identical semantics with differing pixels is its own finding**: a state
   change invisible to assistive technology.
4. **`semanticsUnchanged` is null unless the gesture went out.** A step that fails while *resolving*
   its target never touched the app. Read `dispatched` first, or every selector miss reads as a dead
   tap — measured on the fixture's step 3.
5. **`effectivePct` is geometry, not a hit test.** The semantics tree carries no opacity and no
   `IgnorePointer`, so an overlapping decorative node counts and a transparent one does too. It
   needs `VISUAL` confirmation before it becomes a finding, and it is void on any step where
   `settled == false`.
6. **A blank fold blanks the column.** When `viewport.isTestDefault` is true the run measured
   Flutter's hardcoded 800×600 @ 3.0 test surface, not a device: `foldY` is null, `aboveFold` is
   null, and every fold-dependent sentence is `not measurable here`.

## Placement vs priority — the only honest route to "this is buried"

Feature importance appears in **no artifact**. It is not in the source, not in the semantics tree,
not in the router. A model that ranks features is guessing, and one guess here discredits every
measurement in the report. So the tool never ranks. It compares two things that were both
*declared*, and reports where they disagree:

| Declaration | Where it comes from | What it is |
|---|---|---|
| What matters | `## Priorities` in `journey.md`, or failing that the journey's **goal** | the user's statement |
| What the app promotes | the tap targets of **each visited screen**, in reading order, with rects and `aboveFold` — the entry screen first, but not only it | the team's statement |

Both halves are measured or quoted; neither is inferred. The finding is the **contradiction**, and
it is phrased as one:

> Your rank-1 task ("open a saved product") is the **6th** tap target on the entry screen, at
> y=239 lpx. Five controls sit above it, and **none of the five appears in any declared
> priority** — search, sort, the promo row (319×48 lpx), its dismiss × (24×24 lpx) and
> "View cart (3 items)" (343×48 lpx).

Rules:

- Order the surface by **reading order: top, then the leading edge** — left in ltr, right in rtl.
  The walk records `viewport.textDirection`; quote it, because the table is exactly reversed
  between the two and nothing else in the artifact says which was used. Never order by paint
  order. In paint order the
  first tap target of any Material app is an app-bar action, so "the primary action is not first"
  would be universally true and mean nothing.
- Print the ordinal and the count. **Do not print a percentage of the viewport**: the band above a
  task includes the status bar, the app bar and any hero image — chrome nobody ranks — so the
  percentage is disputable in a way the ordinal is not.
- "Prime real estate" means **the first viewport**, and that is a citable definition, not taste:
  NN/g's eye-tracking study (120 users, ~130,000 fixations) puts 57% of viewing time above the fold.
  Cite it; do not restate it as a rule of your own.
- Report **only the rows that disagree**, capped. A table whose rows mostly say "agrees" is a data
  dump with a verdict column.
- An unranked control is **not a defect**. It is a fact about two vocabularies. It becomes a finding
  only when it sits above a ranked task, and then the finding is about the ranked task's position.
- **Link each ranked task to the step that reaches it, and say how.** A journey step may carry an
  optional `priority: N` naming which declared priority it advances. Without it the link is the
  model prose-matching a task to a step — which is an inference, in the one place this tool
  promises never to infer. On a three-step journey nobody notices; on a twelve-step journey with
  six priorities that link *is* the finding. When the tag is absent, print the match the model made
  and mark it as a match, not as a measurement.
- If no priorities are declared and the goal names nothing on the surface, the answer is
  `Not declared` — findings that would have depended on it are capped at severity 2 and the report
  says which ones were capped. **Never infer a ranking from tab order, label size, route depth or
  "it is on the home screen, so it must matter".** The app's surface is one of the two declarations
  being compared; using it as the ranking too makes the tool agree with itself.

## Cross-step checks

These exist only at journey level and are the reason this skill audits journeys rather than screens.
Run them over the whole walk after the per-step checks:

- **Back recovery** — after a back step, is the user where they were? Scroll position, filters,
  entered text, selection. Lost state is `STATE-GAP`.
- **Dead end** — does any visited screen offer no forward and no return? `DEAD-END`, usually 4.
- **Destructive without confirmation** — an irreversible action reachable in one tap, with no
  confirmation and no undo. `DARK-PATTERN` or `TRUST-GAP`, usually 4.
- **Drift** — the same concept named or styled differently across steps. `PATTERN-DRIFT`.
- **Silent work** — a step whose expectation only appeared after a wait with no visible feedback.
  `PROGRESS-BLIND`.
- **Goal proof** — did the final step actually show what the goal defines as done? If not, that is
  the report's headline finding.

## Merge and dedupe

1. Dedupe key: `check ID` + node identity. Node identity is the normalised label (or tooltip, or
   identifier) plus the logical-px rect rounded to whole pixels. Same key across steps = one finding
   listing every step it appeared on.
2. Merge layers: union the evidence layers, keep every measurement, take the highest confidence with
   the reason it earned it.
3. Rescore against the goal (above). Do this **after** merging: a defect seen on three steps is more
   likely to sit on the goal path than the same defect seen once.
4. Sort by severity descending, then by first step index ascending.
5. A `STATIC` candidate that no walked screen confirmed stays in the report at low confidence with the
   caveat written out — it is not deleted and it is not promoted.
6. **The guideline beats the dump.** Both are RUNTIME, and they can disagree: the semantics dump
   accumulates transforms by hand, so a clipped or off-screen node can read as a few pixels tall
   when the framework's own measurement says otherwise. Measured: a screen's date chips read
   `48.2 x 7.4` in the dump while `androidTapTargetGuideline` did not flag them at all. When they
   disagree, **the guideline is right and the dump is an artifact** — the guidelines are the
   framework's own, calibrated code. Never report a size from the dump that no guideline flagged;
   cross-check first, and say so if the two disagree.
7. **`RUNTIME` refutes `STATIC`.** A measurement beats a source-pattern guess, always. The static pass
   reads an *unresolved* AST: it matches constructor names and cannot see what a widget's children
   contribute. So a tap target the static rule calls unlabeled is genuinely labeled if the walked
   semantics tree shows a label on it — measured on the demo fixture, where two `InkWell`s are
   labeled entirely by their child `Text`s. A refuted candidate moves to **Not Assessable** as
   *refuted by RUNTIME*, naming both the static location and the runtime node that refuted it. It is
   never reported as a finding, and never silently dropped either: the whole point of this tool is
   that it measures instead of guessing, so a guess the measurement overturned is worth showing.

## Never scored

- **Step timing.** Recorded as evidence only. It measures a host round-trip under a test harness, not
  user-perceived latency; scoring it would state something the measurement does not support.
- **Aesthetic taste.** "Is it pretty" is out of scope. Hierarchy and contrast are in scope because
  they are measurable or task-relevant.
- **Performance and frame timing.** Out of scope for v0.1.
- **Anything the run did not reach.** It goes in "Not Assessable", never in the findings table.
- **Predicted task time.** The inputs for a KLM/menu-performance model (tap targets per screen,
  every rect) are all measured here, but the constants are 1980s–2007 desktop-and-mouse
  calibration. This project already refuses to score `elapsedMs` for exactly that reason; a
  modelled number would be strictly worse, because nobody can check it.
- **Lostness** `L = √((N/S − 1)² + (R/N − 1)²)` (Smith 1996). The only fully validated navigation
  metric in the survey, and it still does not ship: `R` is the *minimum* screens necessary, which
  requires the whole graph, which is a crawl. Substituting the author's declared step count keeps
  the validated name on an operation nobody validated.
- **Information scent as a number.** Pirolli & Card measured semantic proximity. Substring or token
  overlap between the goal sentence and a label is not that, and borrowing the citation would
  borrow validation that was never performed. Print the goal beside the surface's labels and let
  the reader judge; a scent mismatch may lower confidence, never raise severity.

## Mechanisms measured and refuted — do not re-propose

Each of these looks right, is cheap, and is wrong. All were executed against the SDK, not reasoned
about. Recorded here because the next reader of the semantics flag list will think of them again.

| Idea | What actually happens |
|---|---|
| Count `scopesRoute` nodes for navigation depth | Stays **1 at five routes deep**: an opaque route removes everything below it from the semantics tree (23 nodes → 10 on one push). A bottom sheet *replaces* the count; an `AlertDialog` adds one on Android and **none on iOS** (`dialog.dart` gates the wrapper on `label != null`, which is null on iOS/macOS). |
| Use `namesRoute` as the screen's name | Rides on the `AppBar` title and nothing else, keyed to `defaultTargetPlatform`: **zero nodes on iOS, on every screen**, and zero on any `AppBar`-less screen. On modals it returns a localized generic ("Alert"), never the dialog's title. |
| A content-free structure signature (drop labels, keep quantised rects) to detect "the same screen template" | **Text width is content.** "Walnut Side Table" is 376 dp and "Oak Side Table" is 312 dp, and a longer blurb wraps 24 dp → 40 dp, so two instances of one screen differ at every grid from 1 dp to 64 dp. Only dropping rects entirely collides them — and nothing consumes that today. |
| `find.byType(ModalBarrier)` to detect an open dialog | **Every `ModalRoute` mounts a barrier**, so this reads true on every ordinary screen. |
| …so narrow it to `AnimatedModalBarrier` | Misses the whole `PopupRoute` family: `_PopupMenuRoute` and `_DropdownRoute` return a null `barrierColor` and build the plain barrier, while `canPop` flips to true. Measured: `popup menu open → canPop true, modalOpen false`. The probe that works is the barrier's **`dismissible`** flag — a page route's is false, a transient surface's is true. |
| `tester.firstState<NavigatorState>(...).canPop()` | Returns the **root** navigator. In any tab-shell app the root holds only the shell page, so it reads false while the user is pages deep inside a branch. |
| …so resolve the navigator from the deepest `Scaffold` | Not the same thing. In the common shell-owns-the-Scaffold shape that Scaffold sits **above** the per-tab Navigators, so the probe lands back on the root and reports the same false — measured — while claiming to be authoritative. It also answers null on any screen with no Scaffold. Read the deepest onstage `Navigator` directly. |
| Refuse to tap a target whose centre is covered | `effectivePct`/`centreCovered` are geometry, not a hit test, so this fails a step — and voids the audit — on overlays that block nothing. Measured: a badge whose padded layout box swallows a button's centre leaves the button tappable at 94% free area. Tap anyway; gate the FINDING on `VISUAL`, not the gesture. |
| Tap whatever the selector resolved | A scrollable's cache extent puts rows above and below the viewport into the dump. Tapping one dispatches into nothing: `dispatched` records true, the semantics do not change, the screenshots are identical — so a working list row passes the FAKE-AFFORDANCE predicate **and** its two-layer confirmation. Refuse only what is genuinely off the surface, and say that is what happened. |
| A sorted multiset of labels as the screen signature | Sorting throws order away, so every sort / reorder / move-up control in existence reports `semanticsUnchanged: true` — and then trips the finding reserved for a state change assistive tech cannot see. Prefix each part with its quantised position before sorting. |
| Bound the settle loop with a `Stopwatch` | `tester.pump(tick)` advances FAKE time while a Stopwatch measures real time, so under `flutter test` the loop simulates minutes inside one real second. Bound by the pump count as well. |
| Stop settling when the frame queue is quiet | An awaiting Future schedules no frames, so a screen rendering an empty state while a request is in flight reports settled on the first pump. The step then fails for the wrong reason while recording `settled: true`, which is also the flag that is supposed to void its measurements. Poll the step's own expectation inside the bound instead. |
| Count a tap when the walker issues it | `_tapTarget` throws on an unresolvable or off-surface target, so counting before it lands counts gestures ATTEMPTED. The report's headline reach cost is then wrong in the direction that flatters the app. |
| `tester.view.physicalSize / devicePixelRatio` as the viewport | That is the whole display, including the status bar, the notch and the home indicator, and it does not shrink for the keyboard. Subtract `padding` and `viewInsets`. In a plain `flutter test` it is Flutter's hardcoded 800×600 @ 3.0 and means nothing at all. |
| `ModalRoute.of(context)` for the route name | Registers an **inherited dependency** on the audited app's element, so reading it can make the app rebuild. An audit must not perturb what it measures. `Navigator.maybeOf` resolves through `findAncestorStateOfType` and is safe. |
| `tester.pageBack()` as the dead-end oracle | Good confirmation, bad oracle: it only looks for a tooltip-"Back" button or a Cupertino back button, so it throws on screens with a custom back affordance. Its exception text also names `CupertinoNavigationBarBackButton` — the *second* finder it tried — which reads as an iOS bug to anyone it is quoted at. |
