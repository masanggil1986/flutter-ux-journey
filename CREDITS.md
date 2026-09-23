# Credits

## EliaAlberti/ux-audit-skill

<https://github.com/EliaAlberti/ux-audit-skill> — MIT.

**What this project borrows:** the sixteen **Named Check IDs** and the shape of the report skeleton.

```
CTA-AMBIGUITY   DEAD-END       FAKE-AFFORDANCE   CONTRAST-FAIL
TOUCH-TARGET    JARGON-LEAK    PROGRESS-BLIND    ERROR-VAGUE
FORM-FRICTION   OVERLOAD       PATTERN-DRIFT     TRUST-GAP
DARK-PATTERN    STATE-GAP      HIERARCHY-FLAT    RECALL-TAX
```

Stable IDs across audits are the single most reusable thing in that repo, and re-inventing a parallel
vocabulary would help nobody. The heuristics themselves (Nielsen, WCAG, Fitts) are not anyone's
property; the expression of that check list is, so the notice below is reproduced as MIT requires.

**Not borrowed:** `scripts/annotate.py`. It draws boxes from fractional, model-estimated coordinates;
this project has real pixel `Rect`s from a running app and no Pillow dependency to spend.

**Two corrections to how that project has been described** (verified against the repo, 2026-09-22):

1. "16 frameworks" is accurate only under one particular count. The Framework Reference has **12
   lettered sections A–L**; section E ("Behavioural Laws") expands to five named laws (Hick, Fitts,
   Miller, Jakob, Peak-End). 11 + 5 = 16.
2. Its severity scale is **not** literally "Nielsen 0–4". The table reads
   `4 Critical / 3 Major / 2 Minor / 1 Cosmetic / ✓ Positive` — there is no "0 = not a problem" row;
   `0` appears only as the *positive* colour in `annotate.py`. This project uses a true 0–4 scale
   scored against the journey's goal, which is a different scale that happens to share the digits.

### MIT notice

```
MIT License

Copyright (c) 2026 Elia Alberti

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Others

- **Jakob Nielsen** — the 10 usability heuristics (1994) and the 0–4 severity scale. Method, cited,
  not copied.
- **Flutter SDK** (BSD-3-Clause, Google) — `package:flutter_test`'s accessibility guidelines,
  `package:integration_test`, and `package:analyzer` do all the measuring. Used as published
  dependencies of the audited app, not vendored here.
- Prior art surveyed in [`docs/day1/prior-art.md`](docs/day1/prior-art.md); the ones this project
  competes with rather than borrows from are listed in the README.
