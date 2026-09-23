# report-format.md — the report and findings.json shapes

- [Rules](#rules)
- [report.md skeleton](#reportmd-skeleton)
- [findings.json](#findingsjson)

## Rules

- Use the skeleton below exactly: same sections, same order, same table columns.
- **Screenshots are referenced by relative path** (`screens/step_2.png`), never absolute. The report
  must still read when it is shared without its image directory, and an absolute path leaks the
  machine's directory layout.
- Every finding carries an evidence layer and a confidence. A finding with neither does not ship.
- Quote measurements with units and quote guideline `reason` strings verbatim. Never round a measured
  value into an adjective.
- Every severity rationale names the goal. "Below the minimum" is not a rationale; "the only way to
  reach the goal, at 24×24 logical px" is.
- The **Not Assessable** section is mandatory and is never empty — at minimum it states the platform
  limit. What was not observed is stated, never silently omitted.

## report.md skeleton

````markdown
# UX Journey Audit — <journey name>

**Goal:** <the goal, one sentence>
**Result:** <reached | reached with friction | not reached> — <one sentence of why>
**Run:** <N> steps walked, <N> findings (<n> critical, <n> major, <n> minor, <n> cosmetic), <n> positives
**Environment:** Flutter <version> · <device> · <platform version> · <YYYY-MM-DD>

## Journey walk

| Step | Action | Expected | Status | Screenshot |
|---|---|---|---|---|
| setup | <login, permissions> | — | OK / FAILED | — |
| 1 | tap "Orders" | order list | OK | `screens/step_1.png` |
| 2 | tap first order card | order detail | OK | `screens/step_2.png` |
| 3 | tap back | order list, scroll kept | FAILED — scroll reset | `screens/step_3.png` |

Setup is excluded from measurement and scoring.

## Findings

| # | Check | Sev | Evidence Layer | Confidence | Step | Where | Screenshot |
|---|---|---|---|---|---|---|---|
| 1 | DEAD-END | 4 | JOURNEY, VISUAL | high | 3 | order detail, no back affordance | `screens/step_3.png` |
| 2 | TOUCH-TARGET | 3 | RUNTIME | high | 2 | "Continue" @ (175.5, 233.5) 24.0×24.0 lpx | `screens/step_2.png` |
| 3 | RECALL-TAX | 2 | STATIC, RUNTIME | medium | 1 | unlabeled icon button, top right | `screens/step_1.png` |

### 1. DEAD-END — severity 4

**What happened.** <observation, in the user's terms, tied to the step.>

**Evidence.**
- JOURNEY: step 3 <what the walk data shows>
- RUNTIME: <measured value, verbatim guideline reason, or the semantics node>
- VISUAL: `screens/step_3.png` — <what is visible>

**Why severity 4.** <the goal, and whether this blocks it or can be worked around.>

**Suggested fix.** <one or two sentences. Optional — omit rather than pad.>

<repeat per finding, most severe first>

## Positives

- ✓ <something the journey does well, with the step and the evidence.>

## Not Assessable

State what was not observed and why. Never leave this empty.

- <steps not reached, and what blocked them>
- <checks not run, and why>
- Screen-reader announcement order, focus order, keyboard navigation, dynamic type, motion and
  reduced-motion: not measured by this run.
- Platform: iOS simulator only, one device size, one theme. Android is untested.
- <static candidates that no walked screen confirmed>

## Method

Static pass (`package:analyzer`, name matching, no type resolution) · journey walk
(`integration_test` under `flutter drive`, measured semantics rects in logical px and the four
built-in Flutter accessibility guidelines) · visual pass (screenshots read by the model) ·
merge and goal-relative rescoring.

Named Check IDs and severity scale from EliaAlberti/ux-audit-skill (MIT, Copyright (c) 2026
Elia Alberti). Step timings are recorded as evidence and are not scored: they measure host
round-trip under a test harness, not user-perceived latency.
````

## findings.json

Same content, machine-readable, same order as the report. One object per merged finding.

```json
{
  "goal": "Find the last order and see its delivery status.",
  "result": "reached with friction",
  "environment": {"flutter": "3.47.2", "device": "iPhone SE (3rd gen)", "platform": "iOS 18.6", "date": "2026-09-22"},
  "steps": [
    {"index": 1, "action": "tap \"Orders\"", "expected": "order list", "status": "OK", "elapsedMs": 546, "screenshot": "screens/step_1.png"}
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
  "notAssessable": ["step 4 not reached: the app crashed on back navigation"]
}
```

`elapsedMs` is carried for traceability and has no `severity`. Positives use `✓` in the report and
appear under `positives` here, never in `findings`.


## Required sections, in order

1. **Feature map** — the app's declared routes grouped into areas, with a coverage column and an
   explicit "walked N of M routes (X%)" line. The score is valid only over that range.
2. **Score** — per-dimension pass rates with the weighting shown inline, and a sentence naming what
   the score does not cover.
3. **Findings** — severity-ordered, each with its measured evidence quoted verbatim.
4. **Direction** — now / next / structural, ordered by effort against reach.
5. **Not Assessable** — everything unmeasured, including the routes not walked.
6. **Tool notes** — anything the run revealed about the audit itself, including any dump-vs-guideline
   disagreement that was cross-checked out of the findings.
