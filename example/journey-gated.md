# Goal

Sign in, then remove one product from the saved list and get back to the list to keep browsing.
Done = the list is on screen again, without that product and with the others still there.

App: `example/ux_demo_app`, run from its **gated** entrypoint `lib/main_gated.dart`. That entrypoint
probes a session on its first frame and shows a sign-in screen when there is none, so this journey
has a `## Setup` block and the walk installs a network stub.

## Setup (excluded from measurement and scoring)

1. type "ux-audit@example.invalid" into "Email address" — expect "Password"
2. type "not-a-real-password" into "Password" — expect "Sign in"
3. tap "Sign in" — expect "Saved items"

The values are arbitrary and the address cannot resolve (RFC 2606 `.invalid`). **No credential is
asked for and none is used** — the stub in `integration_test/gate_stub.dart` answers the two calls
from inside the test process. This app speaks only through a `dart:io` `HttpClient`, which is what
the stub replaces, so none of its requests leave the process; an app with WebSockets, sockets,
background isolates or native clients would not get that promise
(`references/network-stub.md` → *What the stub cannot see*). If a shape in that stub is wrong, a
setup step fails and the run stops and says so; the fix is the route table, never a real account.

`integration_test/gated_journey_test.dart` is the `flutter drive` entry for this journey.
`test/gated_gate_test.dart` walks the same setup and steps headless, through the real
`walkJourney`, under plain `flutter test`.

## Device

`iphone-se` — the same screen [`journey.md`](journey.md) walks, so the two runs are comparable.

## Steps

1. tap "Walnut Side Table" — expect "189,000 KRW"
2. tap "Remove from list" — expect "Cancel"
3. tap "Back" — expect "Saved items"

## Priorities

1. Sign in
2. Open a saved product and check its details
3. Remove a product I no longer want
4. Get back to the list and keep browsing

---

The three journey steps are byte-identical to [`journey.md`](journey.md)'s. That is the point: the
only difference between the two runs is the gate, so any number that moves between
[`walk.json`](walk.json) and [`walk-gated.json`](walk-gated.json) moved because of the gate.

Steps 2 and 3 are still expected to fail — the six seeded defects are the same six.

## What this journey exercises that `journey.md` cannot

| Mechanism | Where it shows up in the walk data |
|---|---|
| `## Setup` runs, and is kept out of the score | `setupSteps[]` separate from `steps[]`; the journey's `tapsSoFar` reads 1, 2, 2, 2, the same as the ungated run, although setup tapped once |
| `HttpOverrides.global` installed before `app.main()` | the session probe is answered at all — it fires on the first frame |
| `networkCalls` | `["/session", "/auth/login"]`, in request order |
| A setup failure stops the run | `setupFailed: true` and an empty `steps[]`, rather than a short journey that reads as a healthy app |

The last row is the one worth keeping honest: a run that dies at the gate must not report the steps
that did run as a journey. `test/gated_gate_test.dart` holds that path down at `walkJourney` level
with a deliberately wrong route table: `setupFailed: true`, no journey steps, and `setup_3.png` as
the only screenshot.
