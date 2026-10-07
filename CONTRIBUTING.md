# Contributing

This repository is public and the tool it ships reads private apps. The leak rules come first;
everything after them is ordinary.

## Never commit somebody else's product

A walk's output — screenshots, route names, semantic labels, endpoints — *is* the audited app's
product. Do not commit any of it:

- screenshots or screen recordings of any app but `example/ux_demo_app`
- an app's name, bundle id, package name or repository path
- its route, screen or widget names, its UI copy, its domain vocabulary
- API endpoints, base URLs, hostnames
- accounts, passwords, tokens, API keys, certificates, `.env`
- the `report.md`, `findings.json` or `ux-audit-out/` a run left behind

Audit your own app locally. `.gitignore` already blocks the paths a run writes — do not unblock
them. Where a document has to point at a private target, write `the private app`. Read what you
staged before every commit:

```bash
git diff --cached --name-only   # read the file list first; stop if an image or binary is in it
git diff --cached | grep -inE 'token|secret|password|api[_-]?key|bearer|://' \
  | grep -viE 'github\.com|flutter\.dev|dart\.dev|api\.flutter\.dev|docs\.claude\.com|w3\.org'
```

The second command should print nothing. A line that does appear is yours to judge, not a rule's to
resolve. CI runs a mechanical form of the same check over the whole tree.

## Run both suites

```bash
cd example/ux_demo_app && flutter pub get && flutter test
cd tools/astprobe     && dart pub get    && dart test
```

Neither needs a simulator. Red is the only failure. Do not write test or line counts into the docs:
they are stale within a day of the next check landing.

CI also runs the walk exactly as the README prints it (`flutter test ux_audit/ux_journey_test.dart`)
and reads `ux-audit-out/walk.json` back: the step statuses must match the committed
`example/walk.json`, and nothing the run wrote may be committable. Run it before a change to the
walker or the fixture.

## Do not fix the demo app's six seeded defects

`example/ux_demo_app` exists to be audited and its defects are the oracle. Fixing one invalidates
`example/expected-findings.json` and the worked report. They are listed, with line numbers and what
each one exercises, in [`example/ux_demo_app/README.md`](example/ux_demo_app/README.md).

## Format before you push

`dart format` is a CI gate — the tree was reformatted for it, so a stray reflow now fails the build.
From the repo root, after `pub get` in both packages:

```bash
dart format example/ux_demo_app tools/astprobe
```

`pub get` first is not optional: without `.dart_tool/package_config.json` the formatter cannot read
the package's language version, and picks a different style.

## Where to extend

- **A static rule**: `tools/astprobe/bin/probe.dart`, plus a case in `test/probe_test.dart`. A rule
  with no test is a string nag, which is why this project has its own probe instead of a dependency.
- **A Named Check**: `skills/flutter-ux-journey/references/heuristics.md`. The sixteen IDs are not a
  closed set, but a seventeenth has to pass that file's admission test — some field the walk records
  must be able to prove or refuse it. No field, no check; earn the field in the walker first.
