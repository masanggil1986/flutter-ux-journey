# Goal

Remove one product from the saved list and get back to the list to keep browsing.
Done = the list is on screen again, without that product and with the others still there.

App: `example/ux_demo_app`. No backend and no login, so there is no `## Setup` block — the app
opens straight onto step 1.

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
