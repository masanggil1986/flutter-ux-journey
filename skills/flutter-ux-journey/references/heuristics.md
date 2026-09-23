# heuristics.md — Named Checks, severity, merge

- [Attribution](#attribution)
- [Severity scale](#severity-scale)
- [Severity is scored against the goal](#severity-is-scored-against-the-goal)
- [Evidence layers and confidence](#evidence-layers-and-confidence)
- [Named Checks](#named-checks)
- [Evidence to check mapping](#evidence-to-check-mapping)
- [Cross-step checks](#cross-step-checks)
- [Merge and dedupe](#merge-and-dedupe)
- [Never scored](#never-scored)

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
6. **`RUNTIME` refutes `STATIC`.** A measurement beats a source-pattern guess, always. The static pass
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
