# Goal

Remove one product from the saved list and get back to the list to keep browsing.
Done = the list is on screen again, without that product and with the others still there.

App: `example/ux_demo_app`. No backend and no login, so there is no `## Setup` block — the app
opens straight onto step 1. [`journey-gated.md`](journey-gated.md) walks these same three steps
behind a sign-in gate, which is where `## Setup` and the network stub are exercised.

## Device

`iphone-se` — 375x667 @2.0, the iPhone SE (3rd gen) simulator `walk.json` was measured on.

Under `flutter drive` the device supplies this and the section is ignored. Under `flutter test`
nothing does, so leaving it out makes the walk fall back to `iphone-se` and record
`deviceProfile: "iphone-se (default, not declared)"` — the report's scope clause quotes that
rather than asserting a screen nobody chose.

Only `iphone-se` ships as a preset. For anything else, name the numbers in **logical px** — the
units this line already uses and the ones the report quotes back:
`375x667 @2.0 contentTop 20 padBottom 0`. `references/walking.md` item 5 has the worked shape.

This journey declares no conditions, so the walk runs at the test defaults — light, text scale 1.0,
`en-US`, no bold text — and `conditions` records exactly that. A journey that wants another set adds
one line each under the screen: `- textScale 3.0`, `- dark`, `- locale ko-KR`, `- boldText`. One set
per run; a second set is a second run.

## Steps

1. tap "Walnut Side Table" — expect "189,000 KRW"
2. tap "Remove from list" — expect "Cancel"
3. tap "Back" — expect "Saved items"

## Priorities

What this app is for, ranked, by the person who knows. Optional — leave it out and the audit
reports placement as `not declared` rather than guessing.

1. Open a saved product and check its details
2. Remove a product I no longer want
3. Get back to the list and keep browsing

Anything on screen that is not on this list is **unranked**, which is not the same as unimportant —
it only means nobody declared it. The audit measures where the app puts each control and reports
where the two disagree; it never invents a ranking of its own.

---

Steps 2 and 3 are expected to fail on this app — it is a fixture with six deliberately seeded
defects.

- Step 2 asks for a way to back out *before* the data is destroyed. There is none: the product is
  gone on the first tap.
- Step 3 asks to go back. The screen the removal lands on has no back control and nothing below it
  on the stack.

Both are only visible at journey level: every widget on the screen that ends the journey passes
every per-screen accessibility check. The worked report is [`report.md`](report.md).
