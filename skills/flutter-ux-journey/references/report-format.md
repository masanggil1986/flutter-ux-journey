# report-format.md — the report and findings.json shapes

- [Rules](#rules)
- [Section order](#section-order)
- [report.md skeleton](#reportmd-skeleton)
- [When the app is healthy](#when-the-app-is-healthy)
- [findings.json](#findingsjson)

## Rules

- Use the skeleton below exactly: same sections, same order, same table columns. There is one
  ordering and it is the one in [Section order](#section-order).
- **Screenshots are referenced by relative path** (`screens/step_2.png`), never absolute. The report
  must still read when it is shared without its image directory, and an absolute path leaks the
  machine's directory layout.
- Every finding carries an evidence layer and a confidence. A finding with neither does not ship.
- Quote measurements with units and quote guideline `reason` strings verbatim. Never round a measured
  value into an adjective.
- Every severity rationale names the goal. "Below the minimum" is not a rationale; "the only way to
  reach the goal, at 24×24 logical px" is.
- **Findings state contradictions. Proposals live in Direction.** No finding may say "would be better
  as X" — that is a counterfactual and nothing in the run measures it. A finding says what was
  measured and what it conflicts with; the rearrangement goes in Direction, marked as a proposal,
  citing the measurement it stands on.
- The **Not Assessable** section is mandatory and is never empty — at minimum it states the platform
  limit. What was not observed is stated, never silently omitted.

## Section order

1. **Verdict** — two or three sentences of plain user vocabulary. No tables above it.
2. **Journey walk** — the step table.
3. **Findings** — severity-ordered, each with its measured evidence quoted verbatim.
4. **Flow and placement** — the cross-step and surface measurements. Omitted entirely when nothing
   fired; see [When the app is healthy](#when-the-app-is-healthy).
5. **Positives.**
6. **Direction** — now / next / structural, ordered by effort against reach. The only section
   anyone acts on, and the only one allowed to propose.
7. **Feature map** — declared routes grouped into areas, with the coverage line. Below the findings
   on purpose: it bounds the report's validity, it is not the report's news.
8. **Score** — per-dimension pass rates with the weighting shown inline.
9. **Not Assessable** — split two ways, below.
10. **Method** and **Tool notes.**

## report.md skeleton

````markdown
# UX Journey Audit — <journey name>

**Goal:** <the goal, one sentence>
**Result:** <reached | reached with friction | not reached> — <one sentence of why>
**Run:** <N> steps, <N> taps, <N> findings (<n> critical, <n> major, <n> minor, <n> cosmetic), <n> positives
**Environment:** Flutter <version> · <device> · <platform version> · <YYYY-MM-DD>

## Verdict

<Two or three sentences, in the words a user would use, naming what happens to the person trying to
do this and what stops them. No check IDs, no widget names, no framework vocabulary. Then one clause
stating the scope, because it is the reader's second question and it belongs here rather than at the
bottom: this is one declared path, walked once, at one device size under one set of conditions.
**Quote the conditions from `conditions` in the walk data — do not assert them.** The run records
`platformBrightness`, `textScaleFactor` and the accessibility flags precisely so this clause is a
measurement; without it, a walk on a dark emulator reports dark-theme contrast ratios under a
sentence that says "light", and nothing in the artifact contradicts it.>

> A user who removes a saved item cannot get back to the list: the screen the app lands on has no
> way out, and the removal happened with no confirmation, so a mis-tap costs data permanently. One
> declared path, walked once, on an iPhone SE in light mode — nothing here says how common it is.

## Journey walk

| Step | Action | Expected | Status | Taps | Screen | Screenshot |
|---|---|---|---|---|---|---|
| setup | <login, permissions> | — | OK / FAILED | — | — | — |
| 1 | tap "Orders" | order list | OK | 1 | `a131d0c1` | `screens/step_1.png` |
| 2 | tap first order card | order detail | OK | 2 | `5d28ed30` | `screens/step_2.png` |
| 3 | back | order list, scroll kept | FAILED — scroll reset | 2 | `a131d0c1` | `screens/step_3.png` |

Setup is excluded from measurement and scoring. `Screen` is the walk's `screenSig` — it is there so
a reader can see a revisit or a loop (step 3 above returns to step 1's screen), not because the
string means anything on its own. Drop the column on a journey that never revisits a screen.

Positions in a guideline `reason` string are **node-local** and do not match the dump's global
rects — sizes are comparable, positions are not. Quote the reason for the node and the measured
value; take the position from the dump, and say so in Tool notes.

## Findings

| # | Check | Sev | Evidence Layer | Confidence | Step | Where | Screenshot |
|---|---|---|---|---|---|---|---|
| 1 | DEAD-END | 4 | RUNTIME, JOURNEY | high | 3 | order detail, no way out | `screens/step_3.png` |
| 2 | TOUCH-TARGET | 3 | RUNTIME | high | 2 | "Continue" @ (175.5, 233.5) 24.0×24.0 lpx | `screens/step_2.png` |

### 1. DEAD-END — severity 4

**What happened.** <observation, in the user's terms, tied to the step.>

**Evidence.**
- RUNTIME: <the predicate's measured terms, e.g. `canPop=false`, `tappableCount=0`, `modalOpen=false`>
  — and for a DEAD-END, **what the screen says**: print its labels. "There is no way out" without
  "and it reads: …" leaves the reader unable to picture where the user is stuck.
- JOURNEY: step 3 <what the walk data shows>
- VISUAL: `screens/step_3.png` — <what is visible>

**Why severity 4.** <the goal, and whether this blocks it or can be worked around.>

**Suggested fix.** <one or two sentences. Optional — omit rather than pad.>

<repeat per finding, most severe first>

## Flow and placement

**Reach cost.** <N> taps on the declared path, across <N> screens. Never "N taps deep" and never a
minimum: the walk knows the path it was given, not the shortest one, and finding the shortest means
exploring paths nobody declared.

**Priorities.** <declared in journey.md | taken from the goal | **not declared**>

Only rows where the declaration and the surface disagree. Surface order is reading order — top,
then the leading edge (left in ltr, right in rtl); quote `viewport.textDirection`. Exclude nodes
flagged `coversSurface` (the full-screen keyboard-dismiss `GestureDetector` is always first and
always largest) and nodes with `onScreen == false` (a scrollable's cache extent).

| Ranked task | Taps to reach | Where its entry point is | Ahead of it |
|---|---|---|---|
| 1. open a saved product | 1 | 6th of 8 tap targets on the entry screen, y=239 lpx, above the fold | 5 controls, none ranked |
| 4. request a refund | 4 | not on the entry surface at all; 7th of 9 on the screen reached at step 3 | 6 controls, 1 ranked |

`Taps to reach` is `tapsSoFar` at the step whose target is that task's entry point — so a ranked
task the journey never reaches has no number, and the row says that instead of guessing one.
**Look past the entry screen.** Every visited screen is dumped with rects, `onScreen`, `aboveFold`
and `coversSurface`, so a task whose entry point is three screens in is measurable exactly the same
way; only the entry screen being special is a habit, not a limit.

> The entry screen carries 8 tap targets and this journey traverses 1. Your rank-1 task is the 6th
> of those 8, at y=239 lpx. None of the five controls above it appears in any declared priority:
> search, sort, the promo row (319×48 lpx), its dismiss × (24×24 lpx), and "View cart (3 items)"
> (343×48 lpx).

Cite the definition of prime real estate rather than asserting it: NN/g's eye-tracking study
(120 users, ~130,000 fixations) found 57% of viewing time above the fold. When `foldY` is null the
run measured Flutter's test surface, not a device — every fold sentence becomes
`not measurable here`.

## Positives

- ✓ <something the journey does well, with the step and the evidence.>

## Direction

Ordered by effort against reach, not by severity alone. A theme-level fix that clears two findings
across every screen outranks a severity-3 defect on one screen. The new measurements reorder this
section: a control the journey needs that is only partly hittable outranks three contrast findings.

- **Now** (effort S, global reach): …
- **Next** (effort M): …
- **Structural** (effort L, or needs a decision): …

**Proposal — at most one per audit.** The only place the report may say "arrange it differently".
It carries no severity, it names the measurement it stands on, and it names what would disprove it.

> Measured: the rank-1 task is the 6th of 8 tap targets at y=239 lpx, with five controls above it
> and none of them ranked. Proposal: move the promo row below the product list. Predicted effect:
> the rank-1 task moves from 6th to 4th in reading order. Disproved if the promo is the revenue
> path, in which case the ranking in `journey.md` is what is wrong.

A proposal must state the **predicted change in the measurement it cites**. Without it there is
nothing to check on the next run, and a proposal nobody can check is an opinion with a citation
stapled to it.

## Feature map

| Area | Routes | Walked |
|---|---|---|
| … | … | … |

Walked <N> of <M> declared routes (<X>%). The score below is valid over that range and no further.

## Score

| Dimension | Measured | Pass |
|---|---|---|
| Tap target ≥44/48 lpx | screens with zero violations / screens measured | … |
| Text contrast | screens passing `textContrastGuideline` / screens measured | … |
| Accessible name | screens passing `labeledTapTargetGuideline` / screens measured | … |
| Screen stability | steps that settled / steps measured | … |
| Reach | taps on the declared path; screens with a way out / screens visited | … |
| Error handling | qualitative — marked as such | — |

Weighting shown inline so a reader can disagree with it. **No composite score**: a single number
over these would imply a measurement that was not performed. This score does not cover information
architecture beyond what is listed, copy, visual design, or conversion.

## Not Assessable

Two buckets, split by what the reader can do about it. Never one list.

**Not declared** — say the word and the next run measures it.
- Feature priorities were not declared in `journey.md`, so placement is reported as position only
  and the findings that would have depended on it are capped at severity 2: #3, #5.

**Not reached, or not measurable here** — nothing the reader can do.
- Steps 3–4 were never reached, so every check on those screens is untested, not clean.
- Screen-reader announcement order, focus order, keyboard navigation, dynamic type, motion and
  reduced-motion: not measured by this run.
- Platform: <platform and version from `conditions`>, one device size, `<platformBrightness>` at
  text scale `<textScaleFactor>`. Any other theme or text size is a second run, not an inference —
  name it here so the reader knows to ask. Real devices untested.
- When `semantics.panesPossiblyBlocked` is true, the dump covers only the last-painted pane: two
  sibling `Navigator`s (a tablet master-detail `Row`) let the later pane's `BlockSemantics` delete
  the earlier one. Every dump-derived check — `TOUCH-TARGET`, `HIERARCHY-FLAT`, `FAKE-AFFORDANCE`,
  the placement table — is `not assessable` for that pane, not clean.
- <static candidates that no walked screen confirmed>

## Method

Static pass (`package:analyzer`, name matching, no type resolution) · journey walk
(`integration_test` under `flutter drive`, measured semantics rects in logical px, the four built-in
Flutter accessibility guidelines, viewport and fold, effective tap area, route state) · visual pass
(screenshots read by the model) · merge and goal-relative rescoring.

This report covers one journey. Runs are not aggregated and there is no cross-journey score —
averaging several of these by hand would be worse than not having the number.

Named Check IDs and severity scale from EliaAlberti/ux-audit-skill (MIT, Copyright (c) 2026
Elia Alberti). Step timings are recorded as evidence and are not scored: they measure host
round-trip under a test harness, not user-perceived latency.

## Tool notes

Anything the run revealed about the audit itself — a dump-vs-guideline disagreement that was
cross-checked out of the findings, a predicate that could not be evaluated, a capture that failed.
````

## When the app is healthy

A tool that only reads well when it finds something gets run once. Every section has a defined
rendering for a clean run, and the answer is usually **absence plus one line**.

| Section | Nothing fired |
|---|---|
| Verdict | "A user can finish this journey. <what worked>." Still names the scope clause. |
| Findings | "No findings at or above cosmetic on the walked path." Keep the table out. |
| Flow and placement | Section **omitted**. One ✓ under Positives: "the declared priorities and the app's surface agree." Not Assessable has no bucket for good news. |
| Positives | This is where a healthy run has its content. Longer here than usual is correct. |
| Direction | "Nothing to do now." The proposal is omitted, not filled with something. |
| Not Assessable | Unchanged — it is never empty. |

## findings.json

Same content, machine-readable, same order as the report. One object per merged finding.

```json
{
  "goal": "Find the last order and see its delivery status.",
  "result": "reached with friction",
  "environment": {"flutter": "3.47.2", "device": "iPhone SE (3rd gen)", "platform": "iOS 18.6", "date": "2026-09-22"},
  "conditions": {"platformBrightness": "light", "textScaleFactor": 1.0, "boldText": false,
                 "highContrast": false, "invertColors": false, "disableAnimations": false},
  "reach": {"tapsLanded": 3, "screens": 3, "basis": "the declared path, not a minimum; a gesture that never dispatched is not reach cost"},
  "priorities": {"source": "journey.md", "declared": ["open a saved product", "remove a product"]},
  "steps": [
    {"index": 1, "action": "tap \"Orders\"", "expected": "order list", "status": "OK", "elapsedMs": 546,
     "tapsSoFar": 1, "dispatched": true, "semanticsUnchanged": false, "screenshot": "screens/step_1.png",
     "surface": {"canPop": false, "tappableCount": 8, "tappableAboveFold": 8, "modalOpen": false,
                 "navigatorCount": 1, "coverNodes": 0}}
  ],
  "findings": [
    {
      "id": 2,
      "check": "TOUCH-TARGET",
      "severity": 3,
      "layers": ["RUNTIME"],
      "confidence": "high",
      "steps": [2],
      "where": "\"Continue\"",
      "measurement": {"rectLogicalPx": [175.5, 233.5, 24.0, 24.0], "required": [44.0, 44.0], "unit": "logical px"},
      "evidence": "iOSTapTargetGuideline: expected tap target size of at least Size(44.0, 44.0), but found Size(24.0, 24.0)",
      "screenshot": "screens/step_2.png",
      "rationale": "On the goal path: this is the only control that advances checkout."
    }
  ],
  "positives": [{"check": "PROGRESS-BLIND", "note": "loading state shown on step 2", "steps": [2]}],
  "notAssessable": {
    "notDeclared": ["feature priorities: none declared, so placement is position only"],
    "notReached": ["step 4 not reached: the app crashed on back navigation"]
  }
}
```

`elapsedMs` is carried for traceability and has no `severity`. Positives use `✓` in the report and
appear under `positives` here, never in `findings`. `notAssessable` is an object with two keys, not
a list — the split is the point.
