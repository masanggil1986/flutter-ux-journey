# UX Journey Audit — remove a saved item and keep shopping

**Goal:** Remove one product from the saved list and get back to the list to keep browsing.
**Result:** not reached — the screen the removal lands on has no way out, measured.
**Run:** 3 steps + outcome, 2 taps landed, 3 screens, 7 findings (2 critical, 1 major, 4 minor), 4 positives
**Environment:** Flutter 3.47.2 · iPhone SE (3rd gen) simulator · iOS 18.6 · 2026-09-23

> This is the worked example: `example/journey.md` walked against `example/ux_demo_app`, a fixture
> with six deliberately seeded defects. Every number below came out of the run; none was authored.

## Verdict

A user who removes a saved item cannot get back to their list: the screen they land on has nothing
to tap and nowhere to go, so the second half of what they came to do is impossible. The removal
itself happens on the first tap, with no confirmation and no undo, so a mis-tap costs the product
permanently. On the way in, the thing they came for is the sixth control on the home screen, behind
five the app was never declared to be for. One declared path, walked once, on one device size, in
the light theme at text scale 1.0 as recorded by the run — nothing here says how often real users
hit it.

## Journey walk

| Step | Action | Expected | Status | Taps | Screen | Screenshot |
|---|---|---|---|---|---|---|
| 1 | tap "Walnut Side Table" | 189,000 KRW | OK | 1 | `a9582ba2` | `screens/step_1.png` |
| 2 | tap "Remove from list" | Cancel | **FAILED** — `no semantics node matches "Cancel"` | 2 | `4ddc18db` | `screens/step_2.png` |
| 3 | tap "Back" | Saved items | **FAILED** — `no semantics node matches "Back"` | 2 | `3afe0168` | `screens/step_3.png` |
| outcome | — | — | OK | 2 | `3afe0168` | `screens/step_4.png` |

No setup: the fixture has no backend and no login.

Two columns are worth reading together. Step 3's tap is **not** counted (`dispatched: false`): it
failed while resolving its target, so no gesture ever reached the app — which is also why it is not
a dead control. And step 2 records `settled: false`: the walk waited out its whole bound for a
"Cancel" that was never going to appear.

Positions inside a guideline `reason` string are node-local and do not match the dump's global
rects; sizes are comparable, positions are not. See Tool notes.

## Findings

| # | Check | Sev | Evidence Layer | Confidence | Step | Where | Screenshot |
|---|---|---|---|---|---|---|---|
| 1 | TRUST-GAP | 4 | JOURNEY, RUNTIME, VISUAL | high | 2 | "Remove from list" on the product detail screen | `screens/step_3.png` |
| 2 | DEAD-END | 4 | RUNTIME, JOURNEY, VISUAL | high | 3 | the screen reached after removing an item | `screens/step_3.png` |
| 3 | FAKE-AFFORDANCE | 3 | RUNTIME, VISUAL | high | 1 | product cards on the saved list | `screens/step_1.png` |
| 4 | HIERARCHY-FLAT | 2 | RUNTIME | high | 1 | the saved list's entry surface | `screens/step_1.png` |
| 5 | TOUCH-TARGET | 2 | RUNTIME, VISUAL | high | 1 | "Dismiss promotion" — the × on the promo banner | `screens/step_1.png` |
| 6 | CONTRAST-FAIL | 2 | RUNTIME, VISUAL | high | 1 | "Free returns within 14 days" | `screens/step_1.png` |
| 7 | RECALL-TAX | 2 | STATIC, RUNTIME, VISUAL | high | 1 | the unlabelled search icon in the app bar | `screens/step_1.png` |

### 1. TRUST-GAP — severity 4

**What happened.** The delete happened on the first tap. Step 2 looked for a way to back out before
anything was destroyed and found none.

**Evidence.**
- JOURNEY: step 2 failed with `Bad state: no semantics node matches "Cancel"`, after waiting out
  its full settle bound (`settled: false`). The tap removed the product and replaced the whole
  navigation stack — no dialog, no undo, no snackbar.
- RUNTIME: the detail screen carries exactly 2 tap targets — "Back" (48×48 lpx at y=24) and
  "Remove from list" (343×48 lpx at y=603). Neither is a confirmation.
- VISUAL: `screens/step_3.png` is the state one tap later.

**Why severity 4.** The goal is to remove a product **and keep browsing**. An irreversible delete
with no confirmation means a mis-tap costs data that cannot be recovered, so reaching the goal
safely depends on never making a mistake.

### 2. DEAD-END — severity 4

**What happened.** The screen the removal lands on offers the user nothing. There is no back
control on it, and the system back gesture has nowhere to go either.

**Evidence.**
- RUNTIME: the predicate holds on every term — `canPop: false`, `tappableCount: 0`,
  `modalOpen: false`, and this is not the journey's entry screen. Seven semantics nodes, **zero of
  them tappable**. What the screen actually says, in full: *"Removed"* and *"Removed from your
  list"* — a confirmation with no next step attached to it.
- RUNTIME: all four accessibility guidelines **pass** on this screen. The defect is invisible
  per-screen and exists only at journey level — which is the whole argument for auditing journeys.
- JOURNEY: step 3 failed with `no semantics node matches "Back"`. The push that landed here used
  `pushAndRemoveUntil`, so there is no route below.
- VISUAL: `screens/step_3.png` shows an app bar with no leading control.

**Why severity 4.** The goal's second half — get back to the list and keep browsing — is
unreachable. There is no workaround short of killing the app.

### 3. FAKE-AFFORDANCE — severity 3

**What happened.** The product cards are tappable but nothing announces them as controls.

**Evidence.**
- RUNTIME: each card is one semantics node with `tappable: true` and flags `[isFocusable]` — no
  `isButton`, no role. Its label is the three child `Text`s merged:
  `"Walnut Side Table\n189,000 KRW\nOnly 2 left"`, 343×108 lpx at y=239.
- VISUAL: `screens/step_1.png` — the card reads as a panel, not a control.

**Why severity 3.** Tapping a card is the only entry to this journey; step 1 has no alternative
route to the detail screen. A user who cannot tell the card is actionable never starts.

### 4. HIERARCHY-FLAT — severity 2

**What happened.** The task the journey exists for is the sixth thing on its own home screen, and
everything ahead of it is something nobody said the app was for.

**Evidence.**
- RUNTIME: the entry surface carries 8 tap targets, all fully above the fold (viewport 375×667 lpx
  @ dpr 2.0, `contentTop` 20.0, `foldY` 667.0, `textDirection` ltr). In reading order the journey's
  own step-1 target is **6th**, at y=239 lpx, and **all five controls ahead of it are unranked** —
  which is the predicate.
- RUNTIME: none of the eight is `coversSurface`, so nothing here is the full-screen
  keyboard-dismiss shape that would make this check fire on any app.
- See *Flow and placement* for the full surface.

**Why severity 2.** The goal is still reachable, the card is visible without scrolling, and the
cost is ordering rather than a block. It would be 4 if the card were below the fold.

### 5. TOUCH-TARGET — severity 2

**What happened.** The × that closes the promotion banner is 24×24 lpx — roughly half the width a
finger reliably hits. Aiming for it on step 1 lands beside it, and the banner stays.

**Evidence.**
- RUNTIME: `iOSTapTargetGuideline` — `SemanticsNode#7(...): expected tap target size of at least
  Size(44.0, 44.0), but found Size(24.0, 24.0)`, label `"Dismiss promotion"`.
  `androidTapTargetGuideline` fails the same node against `Size(48.0, 48.0)`.
- RUNTIME: the dump puts it at `[335.0, 104.0, 24.0, 24.0]` lpx with `effectivePct: 1.00` and
  `centreCovered: false` — it is small, not covered. The defect is size alone.

**Why severity 2.** Off the goal path: dismissing the promo is not needed to remove an item, and
ignoring the banner works. Would be 4 if this were the control that advanced the journey.

### 6. CONTRAST-FAIL — severity 2

**What happened.** "Free returns within 14 days" is light grey on white. On the step 1 screenshot it
is very nearly invisible; a user skimming the saved list does not read it at all.

**Evidence.**
- RUNTIME: `textContrastGuideline` — `SemanticsNode#8(..., label: "Free returns within 14 days"):
  Expected contrast ratio of at least 4.5 but found 1.03 for a font size of 13.0`.
- The guideline's **ratio is advisory** — its light/dark partition returned `#FFFFFF` as the dark
  colour. The authored pair is `#DDDDDD` on `#FFFFFF`, which is 1.36:1. The **node** is the signal;
  both numbers are far under 4.5.

**Why severity 2.** Informational copy, not on the goal path; the journey completes without reading
it. Would be 3 if this text carried information the goal needs.

### 7. RECALL-TAX — severity 2

**What happened.** The magnifier in the app bar has no name. A screen reader announces a button and
nothing more, so a user who cannot see the icon has to press it to learn what it does — on the
entry screen of the journey.

**Evidence.**
- STATIC: `lib/main.dart:75` `IconButton` — "neither `tooltip:` nor `semanticLabel:` — the control
  has no name." (confidence medium on its own.)
- RUNTIME confirms it on a walked screen: `labeledTapTargetGuideline` — `SemanticsNode#21(...,
  flags: [isButton, hasEnabledState, isEnabled, isFocusable]): expected tappable node to have
  semantic label, but none was found.` The dump puts it at `[279.0, 24.0, 48.0, 48.0]` lpx. Its
  neighbour at the same size announces "Sort" via tooltip, so the gap is this one control.

**Why severity 2.** Off the goal path — the list holds three items and the target is visible
without searching. `STATIC` alone would have been low confidence; the walk raises it by finding the
same control unnamed on a screen the journey actually visited.

## Flow and placement

**Reach cost.** 2 taps landed on the declared path, across 3 screens. This is the path the journey
declared, not a minimum: finding a minimum means exploring paths nobody declared, which this tool
does not do.

**Priorities.** Declared in `example/journey.md`.

Surface order is reading order — top, then the leading edge (`textDirection: ltr`, so left).
Only rows where the declaration and the surface disagree:

| Ranked task | Taps to reach | Where its entry point is | Ahead of it |
|---|---|---|---|
| 1. open a saved product | 1 | **6th of 8** tap targets, y=239 lpx, above the fold | 5 controls, **none** ranked |
| 3. get back and keep browsing | — | no control exists: `tappableCount: 0`, `canPop: false` | — |

Rank 2 ("remove a product") agrees: it is 1 of 2 controls on the detail screen and 2 taps from the
start, so it is not listed.

The entry surface, measured (step 1, before its tap):

| # | y | size (lpx) | name |
|---|---|---|---|
| 1 | 24 | 48×48 | *(no accessible name — see finding 7)* |
| 2 | 24 | 48×48 | Sort |
| 3 | 92 | 319×48 | Autumn sale — 20% off every side table |
| 4 | 104 | 24×24 | Dismiss promotion |
| 5 | 175 | 343×48 | View cart (3 items) |
| 6 | **239** | 343×108 | **Walnut Side Table / 189,000 KRW / Only 2 left** |
| 7 | 347 | 343×108 | Oak Side Table / 164,000 KRW / In stock |
| 8 | 455 | 343×108 | Linen Floor Cushion / 72,000 KRW / In stock |

> The entry screen carries 8 tap targets and this journey traverses 1. Your rank-1 task is the 6th
> of those 8, at y=239 lpx. Five controls sit above it — search, sort, the promo row, its dismiss ×
> and "View cart (3 items)" — and none of the five appears in any declared priority.

Prime real estate means the first viewport, and that is a citable definition rather than a
preference: NN/g's eye-tracking study (120 users, ~130,000 fixations) found 57% of viewing time
above the fold. Here everything fits above it, so the finding is about *order*, not visibility.

**Effective tap area.** Every tap target on every walked screen measured `effectivePct: 1.00` and
`centreCovered: false` — nothing in this app is covered by an overlay.

**Dead taps.** None. Step 3 reports `semanticsUnchanged: null`, not `true` — the gesture never
dispatched, because the target could not be resolved. A selector miss is not a dead control.

## Positives

- ✓ "View cart (3 items)" is 343×48 lpx and labelled by its own text — it passes both tap-target
  guidelines and the label guideline. A report that flagged every control would be visibly wrong
  here.
- ✓ The product detail screen has a working back affordance (48×48 lpx, tooltip "Back",
  `canPop: true`). The dead end is created by the removal flow, not by the detail screen.
- ✓ Nothing on any walked screen is obscured: `effectivePct: 1.00` and `centreCovered: false`
  throughout.
- ✓ The app raised no errors of its own (`appErrors: []`), and every screen the walk settled on did
  settle (the one `settled: false` is step 2 waiting for a control that does not exist).

## Direction

- **Now** (S, global reach): give the removal a confirmation step, and give the screen after it a
  way back. Two edits, and they clear both severity-4 findings — the only two things stopping this
  journey.
- **Next** (M): name the search control (`tooltip:`), raise `#DDDDDD` to a passing value in the
  theme rather than at the call site, and grow the promo dismiss to 48×48 lpx. All three are
  per-widget and none is on the goal path.
- **Structural** (L, or needs a decision): the product cards announce themselves as text, not as
  controls. Fixing that properly is a card component change, not a one-line `Semantics` wrapper.

**Proposal — one per audit.** Measured: the rank-1 task is the 6th of 8 tap targets at y=239 lpx,
with five unranked controls above it, three of which (the promo row, its dismiss, the cart button)
occupy 96 lpx of the first viewport. Proposal: move the promo row below the product list.
**Predicted effect:** the rank-1 task moves from 6th to 4th in reading order and from y=239 to
y≈191 lpx; nothing crosses the fold, because on this device nothing is below it. **Disproved if**
the promo is the revenue path — in which case the ranking in `journey.md` is what is wrong, not the
layout. The report cannot tell which; only the team can.

## Feature map

| Area | Routes | Walked |
|---|---|---|
| Saved list | `/` (`ListScreen`) | ✓ |
| Product detail | pushed `MaterialPageRoute` (`DetailScreen`) | ✓ |
| Removal confirmation | pushed `MaterialPageRoute` (`RemovedScreen`) | ✓ |

Walked 3 of 3 declared screens (100%). The fixture uses plain `Navigator` with no declarative
router, so there is no route table to reconcile against — see Not Assessable.

## Score

| Dimension | Measured | Pass |
|---|---|---|
| Tap target ≥44/48 lpx | screens with zero violations / screens measured | 2 / 3 |
| Text contrast | screens passing `textContrastGuideline` | 2 / 3 |
| Accessible name | screens passing `labeledTapTargetGuideline` | 2 / 3 |
| Screen stability | steps that settled | 3 / 4 |
| Reach | screens with a way out / screens visited | 2 / 3 |
| Error handling | qualitative — no error state was reached | — |

Weighting: none. Each row is a count of measured things and is reported as a count. **There is no
composite score**: a single number over these rows would imply a measurement nobody performed. The
score does not cover copy, visual design, conversion, or any screen the journey did not visit.

## Not Assessable

**Not declared** — say the word and the next run measures it.
- `## Priorities` ranks this journey's three tasks and nothing else. The five controls above the
  rank-1 task are unranked because nobody ranked the entry surface, not because they are
  unimportant — rank them and the next run can say which of the five belongs there and which is
  taking the slot.

**Not reached, or not measurable here** — nothing the reader can do.
- Steps 2 and 3 did not reach their expected screens, so nothing past the removal screen was
  walked. Whether a real confirmation dialog would itself be accessible is untested, not clean.
- The app uses plain `Navigator`, so there is no declared route table, no route names and no
  navigation graph. Screens are identified by their semantics signature instead.
- Static candidates the walk refuted, kept rather than deleted: `lib/main.dart:126` and
  `lib/main.dart:163` (`InkWell` with `onTap` and no enclosing `Semantics`, confidence low). At
  runtime both nodes carry non-empty merged labels, so the probe's name matching missed the labels
  its children supply. Not findings. `lib/main.dart:251` (`Icon` with no label) is the decorative
  check mark on the removal screen; it produces no semantics node of its own.
- Screen-reader announcement order, focus order, keyboard navigation, dynamic type, motion and
  reduced-motion: not measured by this run.
- Platform, from `conditions`: iOS 18.6 simulator (iPhone SE 3rd gen, dpr 2.0),
  `platformBrightness: light`, `textScaleFactor: 1.0`, no accessibility flags set. One device size.
  Real devices untested. The SE has a home button, so `padBottom` is genuinely 0.0 here — a notched
  device would move the fold line and this run cannot say by how much.
- Other themes and text sizes: not measured here, and each is a separate run. Measured on this same
  fixture at `accessibility-extra-extra-extra-large`, the third product row leaves the semantics
  tree and the second drops below the fold — so a large-text reading of this report would be a
  different report, not this one adjusted.

## Method

Static pass (`package:analyzer`, name matching, no type resolution) · journey walk
(`integration_test` under `flutter drive`, measured semantics rects in logical px, the four built-in
Flutter accessibility guidelines, viewport and fold, effective tap area, route state) · visual pass
(screenshots read by the model) · merge and goal-relative rescoring.

This report covers one journey. Runs are not aggregated and there is no cross-journey score —
averaging several of these by hand would be worse than not having the number.

Named Check IDs and severity scale from EliaAlberti/ux-audit-skill (MIT, Copyright (c) 2026 Elia
Alberti). Step timings are recorded in the walk data as evidence and are not scored: they measure a
host round-trip under a test harness, not user-perceived latency.

## Tool notes

- **Two rects for one control, both correct.** Finding 5 quotes the guideline's own
  `Rect.fromLTRB(319.0, 12.0, 343.0, 36.0)`; the surface table puts the same control at y=104. A
  guideline `reason` prints the node's own rect plus one transform, not the accumulated chain, so
  **sizes are comparable and positions are not**. Positions above are taken from the dump.
- The screenshots referenced here are produced by the run into
  `example/ux_demo_app/screenshots/` and copied to `example/screens/` for this public fixture,
  which has no backend and no real data. **An audit of a real app keeps them local** — a screenshot
  is verbatim product copy. The report is written so it reads without them either way, which is
  what makes a private audit shareable.
- Three measurements changed between runs while this report was being produced, each because the
  first version was wrong: taps counted gestures *attempted* rather than landed; the settle bound
  returned mid-transition and every rect on the next screen came back shifted by 244 lpx; and a
  step that failed to resolve its target was being reported as a dead control. All three are pinned
  by tests now.
