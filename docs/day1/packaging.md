# packaging

## VERDICT: partial

The plan's *container* (a Claude Agent Skill, distributed as a plugin) is correct and cheap — one
extra file makes the repo installable. The plan's *contents* are wrong: five Python scripts, a JSON
Schema and a Jinja2 template are all either unsupported-by-default, duplicating the model, or both.
Verified against the live spec on 2026-09-22, including running the real `claude plugin` CLI.

(Raw append-ordered research log preserved at `packaging.raw.md` in this directory.)

---

## Facts

### F1. Docs moved host. `docs.claude.com` 302s to `platform.claude.com`.
- evidence verbatim (WebFetch on https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview):
  `Status: 302 Found` -> `https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview`
- Three spec surfaces exist and they do NOT agree with each other:
  1. `platform.claude.com/docs/en/agents-and-tools/agent-skills/*` — the Anthropic product spec
  2. `code.claude.com/docs/en/skills` + `/plugin-marketplaces` — Claude Code's superset
  3. `agentskills.io/specification` — the **open standard**, now implemented by ~45 clients
     (Cursor, Copilot/VS Code, Codex, Gemini CLI, Goose, OpenCode, Amp, Kiro, Firebender...).
     > The Agent Skills format was originally developed by Anthropic, released as an open standard

### F2. The open-standard frontmatter spec (agentskills.io/specification) — the one to write to.
- evidence verbatim, the complete table:
  > | Field           | Required | Constraints |
  > | `name`          | Yes      | Max 64 characters. Lowercase letters, numbers, and hyphens only. Must not start or end with a hyphen. |
  > | `description`   | Yes      | Max 1024 characters. Non-empty. Describes what the skill does and when to use it. |
  > | `license`       | No       | License name or reference to a bundled license file. |
  > | `compatibility` | No       | Max 500 characters. Indicates environment requirements (intended product, system packages, network access, etc.). |
  > | `metadata`      | No       | Arbitrary key-value mapping for additional metadata (a map from string keys to string values). |
  > | `allowed-tools` | No       | Space-separated string of pre-approved tools the skill may use. (Experimental) |
- extra `name` rules, verbatim:
  > * Must not contain consecutive hyphens (`--`)
  > * **Must match the parent directory name**
- `compatibility` examples, verbatim — this is exactly where "you need Flutter" belongs:
  > `compatibility: Requires git, docker, jq, and access to the internet`
  > `compatibility: Requires Python 3.14+ and uv`
  > Most skills do not need the `compatibility` field.
- `metadata` is **string->string only**. Don't stuff structured config in it.

### F3. Anthropic's product spec agrees on the required two, and adds reserved words.
- evidence verbatim (platform.claude.com .../overview, "Skill structure"):
  > **Required fields:** `name` and `description`
  > `name`: Maximum 64 characters · Must contain only lowercase letters, numbers, and hyphens ·
  > Cannot contain XML tags · **Cannot contain reserved words: "anthropic", "claude"**
  > `description`: Must be non-empty · Maximum 1024 characters · Cannot contain XML tags
- `flutter-ux-journey` satisfies every rule in F2 and F3. Keep it.

### F4. Claude Code's frontmatter is a big superset — `name` is optional THERE, so don't rely on that.
- source: https://code.claude.com/docs/en/skills, frontmatter reference table. Verbatim rows:
  > | `name` | **No** | Display name shown in skill listings. Defaults to the directory name. |
  > | `description` | Recommended | ... the combined `description` and `when_to_use` text is truncated at **1,536 characters** in the skill listing |
  > | `when_to_use` | No | Additional context for when Claude should invoke the skill ... counts toward the 1,536-character cap. |
  > | `allowed-tools` | No | Tools Claude can use without asking permission during the turn that invokes this skill. The grant clears when you send your next message. |
  > | `disallowed-tools` | No | Tools removed from Claude's available pool while this skill is active. |
  > | `disable-model-invocation` | No | Set to `true` to prevent Claude from automatically loading this skill. Default: `false`. |
  > | `user-invocable` | No | Set to `false` when only Claude should invoke the skill. Default: `true`. |
  > | `argument-hint` / `arguments` | No | autocomplete hint / named positional args for `$name` substitution |
  > | `model` / `effort` | No | model + effort override for the turn |
  > | `context` | No | Set to `fork` to run in a forked subagent context. |
  > | `agent` / `background` | No | subagent type; `background: false` waits for the result (v2.1.218+) |
  > | `hooks` / `paths` / `shell` | No | session hooks; activation globs; `bash` (default) or `powershell` |
  > | `metadata` | No | Free-form YAML map ... Claude Code doesn't act on its contents |
  > | `license` / `compatibility` | No | "Part of the Agent Skills spec ... Claude Code accepts the field but doesn't act on it." |
- **Claude-Code-only fields (`when_to_use`, `context: fork`, `paths`, `model`, `hooks`) are portability
  poison for a public skill** that also wants to work in Cursor/Copilot/Codex. Use them only if you
  accept Claude-Code-only. `allowed-tools` is the one extra that is in both specs (experimental there).

### F5. Frontmatter keys actually in the wild on this machine (1069 skill dirs, 1317 SKILL.md).
- command:
  `find ~/.claude/plugins ~/.agents -name SKILL.md | while read f; do awk '/^---$/{n++;next} n==1{print} n==2{exit}' "$f"; done | grep -E '^[a-zA-Z_-]+:' | cut -d: -f1 | sort | uniq -c | sort -rn`
- real output:
  ```
  1059 description   1055 name    444 origin    104 metadata   104 license    82 version
    56 user-invocable  53 argument-hint  46 triggers  46 homepage  42 disable-model-invocation
    24 compatibility   22 hooks   20 allowed-tools  16 tools  2 repository  2 author
     1 requires_bin    1 maintainer   1 command
  ```
- `triggers`, `homepage`, `version`, `requires_bin`, `tools` are **third-party invention, not spec**.
  Don't copy them. (`version` belongs in `plugin.json`, not SKILL.md.)

### F6. Progressive disclosure + token budget — three first-party numbers, all consistent.
- platform.claude.com overview table, verbatim:
  > | **Level 1: Metadata**     | Always (at startup)     | ~100 tokens per Skill | `name` and `description` |
  > | **Level 2: Instructions** | When Skill is triggered | **Under 5k tokens**   | SKILL.md body |
  > | **Level 3+: Resources**   | As needed               | **None until accessed** | Bundled files. Reference files load into context when read. Scripts run through bash, and only their output enters context |
  > **No practical limit on bundled content:** Files don't consume context until accessed
- best-practices, verbatim (section literally titled "Token budgets"):
  > Keep SKILL.md body under 500 lines for optimal performance. If your content exceeds this, split it
  > into separate files using the progressive disclosure patterns described earlier.
- agentskills.io/specification, verbatim:
  > 2. **Instructions** (< 5000 tokens recommended) ... Keep your main `SKILL.md` under 500 lines.
- **Budget: <=5k tokens / <=500 lines for SKILL.md. Unlimited for `references/`.**

### F7. Layout conventions — `scripts/`, `references/`, `assets/` are the standard names.
- agentskills.io/specification, verbatim:
  ```
  skill-name/
  |- SKILL.md          # Required: metadata + instructions
  |- scripts/          # Optional: executable code
  |- references/       # Optional: documentation
  |- assets/           # Optional: templates, resources
  ```
  > ### `references/` ... Keep individual reference files focused. Agents load these on demand, so
  > smaller files mean less use of context.
  > ### `assets/` ... Templates (document templates, configuration templates) · Images · Data files
- lazy-loading rules, verbatim (best-practices):
  > **Keep references one level deep from SKILL.md**. All reference files should link directly from
  > SKILL.md to ensure Claude reads complete files when needed.
  > Claude may partially read files when they're referenced from other referenced files ... Claude
  > might use commands like `head -100` to preview content rather than reading entire files,
  > resulting in incomplete information.
  > For reference files longer than 100 lines, include a table of contents at the top.
- Use **relative paths, forward slashes**, from the skill root:
  > Good: `scripts/helper.py`, `reference/guide.md`   Avoid: `scripts\helper.py`

### F8. How bundled scripts are invoked: the model types a bash command. That is the whole API.
- platform overview, verbatim:
  > When instructions mention executable scripts, Claude runs them through bash and receives only the
  > output (the script code itself never enters context).
- code.claude.com gives the one real mechanism — `${CLAUDE_SKILL_DIR}` — and its own worked example, verbatim:
  > | `${CLAUDE_SKILL_DIR}` | The directory containing the skill's `SKILL.md` file. For plugin skills, this is the skill's subdirectory within the plugin, not the plugin root. Use this in bash injection commands to reference scripts or files bundled with the skill, regardless of the current working directory. |
  > | `${CLAUDE_PLUGIN_ROOT}` | The plugin's installation directory. Substituted only in plugin skills. |
  > | `${CLAUDE_PLUGIN_DATA}` | The plugin's persistent data directory ... Use this to reference **installed dependencies**, generated files, or caches that must outlive an update. |
  ```yaml
  ---
  name: render-chart
  description: Render a chart from a CSV file
  allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/render.sh *)
  ---
  Run `${CLAUDE_SKILL_DIR}/scripts/render.sh <csv-file>` to render the chart.
  ```
  > The `allowed-tools` rule with `${CLAUDE_SKILL_DIR}` pre-approves the exact script path, so it runs
  > without prompting when the skill is invoked.
- There is **no entrypoint manifest, no arg schema, no typed return**. A "5-script pipeline" is five
  bash command lines the model must get right in order, with no orchestrator enforcing the order.

### F9. Shell can also run BEFORE the model sees the skill — and can hard-abort it.
- code.claude.com, verbatim:
  > **How injected commands run:** Working directory: runs in the session shell's current working
  > directory. stderr: merged into stdout. Timeout: 2-minute timeout per the Bash tool's defaults.
  > **When an injected command fails:** A failed command aborts the entire skill invocation, not just
  > its placeholder. Claude never sees the skill content for that invocation. Non-zero exit code counts
  > as failure ... Append `|| true` to any command you expect to exit non-zero.
  > Injected commands never prompt for permission while the skill renders ... A deny rule match aborts.
  > Set `"disableSkillShellExecution": true` in settings to disable `` !`<command>` `` execution.
- Usable for journey-file validation (fail fast, zero tokens), **but Claude-Code-only, 2-min capped,
  and disable-able by policy** — so SKILL.md must still be correct when it's off.

### F10. Runtime guarantees: none for Python. Claude Code inherits the user's machine, period.
- platform overview, "Runtime environment constraints", verbatim:
  > * **Claude API:** **No network access** ... **No runtime package installation:** Only pre-installed
  >   packages are available. You cannot install new packages during execution.
  > * **Claude Code:** **Full network access:** Skills have the same network access as any other program
  >   on the user's computer. **Global package installation discouraged:** Skills should only install
  >   packages locally to avoid interfering with the user's computer.
- best-practices, "Package dependencies", verbatim:
  > * **claude.ai:** Can install packages from npm and PyPI and pull from GitHub repositories
  > * **Claude API:** Has no network access and no runtime package installation
  > List required packages in your SKILL.md and verify they're available
- best-practices, "Avoid assuming tools are installed", verbatim:
  > **Bad example: Assumes installation**: "Use the pdf library to process the file."
  > **Good example: Explicit about dependencies**: "Install required package: `pip install pypdf`"
- **There is no dependency-install story. The entire mechanism is a sentence in SKILL.md.** Every
  third-party import is a runtime failure the user discovers mid-audit.

### F11. MEASURED: Python on macOS is Xcode's 3.9.6. Jinja2 is absent on the author's own machine.
```
$ which -a python3
/usr/bin/python3
/opt/homebrew/bin/python3
$ python3 -VV
Python 3.9.6 (default, May 22 2026, 11:13:45) [Clang 21.0.0 (clang-2100.1.1.101)]
$ python3 -c 'import sys; print(sys.executable)'
/Applications/Xcode.app/Contents/Developer/usr/bin/python3
$ python3 -c "import jinja2"     -> ModuleNotFoundError: No module named 'jinja2'
$ python3 -c "import yaml"       -> ModuleNotFoundError: No module named 'yaml'
$ python3 -c "import PIL; print(PIL.__version__)"  -> 11.3.0    (incidental, not a guarantee)
$ dart --version -> Dart SDK version: 3.13.2 (stable) on "macos_arm64"
```
- `/usr/bin/python3` on macOS is the **Xcode/CLT shim**: present only because Xcode is installed, pinned
  at **3.9** (no `match`, no `X | Y` unions, no `tomllib`), and on a bare Mac it pops a CLT install prompt.
- **Jinja2 fails on the machine of the skill's own author.** Pillow happens to be there; a user's won't be.
- Dart 3.13.2 is present **and is implied by the skill's premise** — you cannot audit a Flutter app
  without a Flutter SDK, and Flutter ships Dart. It is the only runtime this skill can actually assume.

### F12. MEASURED: `dart run` needs no project, no pubspec, no pub get — if imports are `dart:` only.
```
$ ls pkgtest/pubspec.yaml                    -> No such file or directory
$ dart run hello.dart   # dart:io + dart:convert
{"lines":10}
dart run hello.dart  0.15s user 0.04s system   0.356s total      (cold == warm)
$ python3 hello.py
{"lines": 10}                                  0.024s total
$ dart run yy.dart      # import 'package:yaml/yaml.dart'
Error: Couldn't resolve the package 'yaml' in 'package:yaml/yaml.dart'.
$ dart compile exe hello.dart -o hello_bin   -> Generated: hello_bin  (5.7 MB)
```
- Dart startup 0.36s vs Python 0.024s — 15x slower, still irrelevant for a per-step tool.
- **NEITHER stdlib has YAML.** `journey.yaml` needs a third-party parser in *any* language, on a machine
  where PyYAML is already proven missing. This alone kills the YAML+JSON-Schema plan (see Plan impact).

### F13. EMPIRICAL PRECEDENT: the OFFICIAL Dart/Flutter Claude plugin ships 25 skills and ZERO scripts.
```
$ find ~/.claude/plugins/marketplaces/dart-flutter/skills -name SKILL.md | wc -l
      25
$ find .../skills -type f | sed 's/.*\.//' | sort | uniq -c
   5 dart
  27 md
```
- All 5 `.dart` files are **reference examples under `examples/`**, not runnable scripts:
  `/// Example template for a single-command Dart CLI script or utility.`
- SKILL.md sizes: n=26, **median 162 lines, max 528**.
- Their build tooling is Dart and lives **outside** the shipped tree.
  `resources/flutter_skills.yaml` header, verbatim:
  > `# To generate skills, use the following command (from the `tool` directory):`
  > `# dart run skills generate-skill --config ../resources/flutter_skills.yaml --output ../skills`
- Their frontmatter, verbatim:
  ```yaml
  ---
  name: flutter-add-integration-test
  description: Configures Flutter Driver for app interaction and converts MCP actions into permanent integration tests. Use when adding integration testing to a project, exploring UI components via MCP, or automating user flows with the integration_test package.
  metadata:
    model: models/gemini-3.1-pro-preview
    last_modified: Tue, 21 Apr 2026 18:29:20 GMT
  ---
  ```
- And note what `flutter-add-integration-test` actually instructs — **drive MCP tools, don't ship a runner**:
  > 2. **Interactive Exploration (Flutter Driver MCP)** ... 1. **Launch**: Use `launch_app` ...
  > 2. **Inspect**: Use `get_widget_tree` ... 3. **Interact**: Use `tap`, `enter_text`, and `scroll`

### F14. EMPIRICAL: across 1069 skill dirs here, only 10% bundle executable code at all.
```
skill dirs: 1069        dirs bundling executable code: 107 / 1069
language histogram:  386 py · 107 sh · 33 js · 10 dart · 5 ts
```
- Python dominates *when* code is bundled, but markdown-only is the 90% case.

### F15. The docs' own rule for script-vs-instructions: match freedom to fragility.
- best-practices, verbatim:
  > **High freedom** (text-based instructions): Use when: Multiple approaches are valid; Decisions
  > depend on context; **Heuristics guide the approach**
  > **Medium freedom** (pseudocode or scripts with parameters): A preferred pattern exists; Some
  > variation is acceptable; Configuration affects behavior
  > **Low freedom** (specific scripts, few or no parameters): Operations are fragile and error-prone;
  > Consistency is critical; A specific sequence must be followed
  > **Analogy:** ... **Narrow bridge with cliffs on both sides:** ... (low freedom) ... **Open field
  > with no hazards:** Many paths lead to success. Give general direction and trust Claude.
- pro-script side, verbatim:
  > **Prefer scripts for deterministic operations:** Write `validate_form.py` rather than asking Claude
  > to generate validation code
  > **Benefits of utility scripts:** More reliable than generated code; Save tokens; Save time; Ensure
  > consistency across uses
- the pattern that *does* justify a script here, verbatim:
  > ### Create verifiable intermediate outputs
  > The "plan-validate-execute" pattern catches errors early by having Claude first create a plan in a
  > structured format, then validate that plan with a script before executing it.
  > **When to use:** Batch operations, destructive changes, complex validation rules, high-stakes operations.
  > **Implementation tip:** Make validation scripts verbose with specific error messages
- A heuristic UX audit is, in the docs' own words, an **open field**. "Heuristics guide the approach"
  is the literal trigger condition for high freedom / no script.

### F16. The docs explicitly say the MODEL does the visual analysis; the script only converts.
- best-practices, "Use visual analysis", verbatim:
  > When inputs can be rendered as images, have Claude analyze them:
  > `1. Convert PDF to images: python scripts/pdf_to_images.py form.pdf`
  > `2. Analyze each page image to identify form fields`
  > `3. Claude can see field locations and types visually`
  > Claude's vision capabilities help analyze layouts and structures.
- The bundled script *produces* the image. The annotation/judgement is the model's. This is exactly the
  planned visual pass — and it needs no Pillow and no drawing code.

### F17. The docs put report templates INSIDE SKILL.md as a markdown fence — not in a template engine.
- best-practices, "Template pattern", verbatim:
  > **For strict requirements** (such as API responses or data formats):
  > "## Report structure / ALWAYS use this exact template structure:" followed by a fenced markdown skeleton
  > **For flexible guidance** (when adaptation is useful):
  > "Here is a sensible default format, but use your best judgment based on the analysis"
- No first-party guidance anywhere recommends a template engine. Jinja2 has zero support in the spec.

### F18. DISTRIBUTION — ran the real CLI. `claude --version` -> `2.1.267 (Claude Code)`.
- minimum installable plugin, per code.claude.com/docs/en/plugin-marketplaces, verbatim:
  ```
  plugin-directory/
  |- .claude-plugin/
  |   |- plugin.json
  |- skills/
      |- skill-name/
          |- SKILL.md
  ```
  > The `.claude-plugin/plugin.json` file is required. Skills are automatically discovered in the
  > `skills/` directory, or you can specify custom paths.
  > plugin.json Required Fields: `{ "name": "plugin-name" }`
  > marketplace.json Required Fields: `name`, `owner.name`, `plugins[]` each with `name` + `source`
- install, verbatim: `/plugin marketplace add owner/repo` then `/plugin install plugin-name@marketplace-name`
- **I built the minimum and validated it for real** (`.../scratchpad/day1/pkgtest`):
  ```
  $ claude plugin validate /.../pkgtest
  Validating marketplace manifest: /.../pkgtest/.claude-plugin/marketplace.json
  Found 2 warnings:
    - description: No marketplace description provided...
    - plugins[0] plugin.json -> author: No author information provided...
  Validation passed with warnings
  ```
  Three files total. That is the entire distribution requirement.
- real-world minimal marketplace on disk (`~/.claude/plugins/marketplaces/saar120-skillgate/.claude-plugin/marketplace.json`) is 14 lines. The official Flutter one adds `owner.email`, `category`, `tags`, `source: "./"`.
- Anthropic's own directory uses `"$schema": "https://anthropic.com/claude-code/marketplace.schema.json"`
  and pinned entries: `"source": {"source":"git-subdir","url":...,"path":...,"ref":"v1.5.5","sha":...}`.

### F19. MEASURED: Claude Code's validator tolerates unknown keys AND reserved-word names.
```
# SKILL.md carrying bogus_key_xyz: 1  and  triggers: a,b
$ claude plugin validate --strict /.../pkgtest/skills     -> Validation passed
# SKILL.md with name: claude-ux-journey   (reserved word per F3)
$ claude plugin validate --strict /.../pkgtest/skills     -> Validation passed
# SKILL.md with no description
- description: No description in frontmatter. A description helps users and Claude understand when to use this skill.
Validation failed (--strict treats warnings as errors)
# a bare skill dir is not a valid target:
$ claude plugin validate --strict /.../pkgtest/skills/flutter-ux-journey
- directory: No manifest found in directory. Expected .claude-plugin/marketplace.json or .claude-plugin/plugin.json
```
- Claude Code only really enforces `description`. The stricter F2/F3 name rules bite on the
  **Skills API / claude.ai upload / other clients**, not locally. Write to the strict spec anyway.

### F20. There is a REAL token-cost meter. Measure, don't estimate.
```
$ claude plugin details dart-flutter
Projected token cost
  Always-on:   ~2,483 tok   added to every session
  component                                  always-on  on-invoke
  dart-migrate-to-checks-package                   ~50      ~7.5k
  dart-setup-ffi-assets                           ~240      ~7.1k
  dart-collect-coverage                            ~40      ~1.8k
```
- Per-skill always-on ~= 40-240 tok; on-invoke 1.7k-7.5k. Official skills DO exceed the 5k guidance —
  it is guidance, not enforcement. `claude plugin details <plugin>` is how you check yours.

### F21. `claude plugin eval` is a shipped eval harness — the CI answer for a model-driven skill.
- `claude plugin eval --help`, verbatim:
  > Run eval cases (`<eval dir>/**/case.yaml` or `prompt.md` + `graders/*.md`) against a plugin and
  > report scored results. Target is a path, a plugin name, or a `plugin@marketplace` id
  > `--ablation <mode>  Run a no-plugin baseline arm and report the score delta (none | with-without;
  >   default: with-without ...)`
  > `--threshold <0..1>  Exit 1 if any case score is below this threshold (default: 1.0)`
  > `--runs <n>  Override per-case runs (default: case.runs ?? 3)`
  > `--judge-model <model>  Override LLM-grader model (default: haiku)`
  > `claude plugin eval init` — "Author an eval suite under the eval dir ... `--bare <name>` for a blank
  > single-case template."
- This matches best-practices' "Build evaluations first ... Create evaluations BEFORE writing extensive
  documentation ... Establish baseline: Measure Claude's performance without the Skill."
- **`claude plugin tag [path]`** also exists: "Create a {name}--v{version} git tag for a plugin release,
  validating that plugin.json and any enclosing marketplace entry agree."

### F22. PRIVACY LANDMINE in the eval harness — it publishes to claude.ai BY DEFAULT.
- `claude plugin eval --help`, verbatim:
  > `--no-publish        Keep the HTML report local only; skip publishing it to claude.ai`
  > `--publish-report    Also require publishing the report to claude.ai (already the default when your
  >                      account supports it); explains why if unavailable`
- The report contains "scores, prompts, grader verdicts". **Running `claude plugin eval` against the
  private dogfood app uploads prompts and transcripts to claude.ai unless `--no-publish` is passed.**
  Also `--scaffold` "runs author-supplied bash as you" and `--mocks off` "spawns the real servers".

---

## Exact interface

**SKILL.md frontmatter to ship (portable across all three specs):**
```yaml
---
name: flutter-ux-journey                  # must equal the parent dir name; <=64; [a-z0-9-]; no double hyphen
description: Audits a running Flutter app at the user-journey level, scoring findings against the
  journey's goal with Nielsen 0-4 severity. Use when the user asks to audit a Flutter app's UX,
  review a user journey or onboarding/checkout flow, or find usability problems in a running app.
license: MIT
compatibility: Requires the Flutter SDK (Dart included) and a running device or simulator
---
```
- <=1024 chars for `description`; third person ("Audits...", never "I can help you..."), verbatim:
  > **Always write in third person**. The description is injected into the system prompt
- Optional, Claude-Code-only, costs portability: `allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/... *)`

**Naming (best-practices, verbatim):**
> Consider using **gerund form** (verb + -ing) for Skill names ... **Acceptable alternatives:**
> Noun phrases: `pdf-processing`, `spreadsheet-analysis`

`flutter-ux-journey` is an acceptable noun phrase. `auditing-flutter-journeys` is the preferred form.

**Repo shape (complete, verified installable):**
```
flutter-ux-journey/                       # the repo IS the plugin
|- .claude-plugin/
|   |- plugin.json         {"name","description","version","author","license","homepage","repository","keywords"}
|   |- marketplace.json    {"name","owner":{"name"},"plugins":[{"name","source":"./","description"}]}
|- skills/
|   |- flutter-ux-journey/
|       |- SKILL.md                    # <=500 lines / <=5k tok — the whole workflow
|       |- references/                 # one level deep, TOC if >100 lines
|       |   |- heuristics.md           # Nielsen 10 + the 0-4 severity rubric + goal-relative scoring
|       |   |- journey-format.md       # the journey file format + a worked example
|       |   |- report-format.md        # the report + findings.json shapes
|       |- scripts/                    # ONLY if the runtime assignment proves MCP can't measure
|- evals/                              # claude plugin eval cases
|- LICENSE
|- README.md
```

**Commands (all verified to exist on 2.1.267):**
```
claude plugin validate --strict --json <plugin-root>   # CI gate; exit 1 on warnings
claude plugin details <plugin>                         # measured always-on / on-invoke token cost
claude plugin eval <path> --no-publish --threshold 0.8 # CI gate; ALWAYS pass --no-publish
claude plugin tag <path>                               # release tag {name}--v{version}
claude plugin marketplace add <owner/repo>             # user install, step 1
claude plugin install flutter-ux-journey@flutter-ux-journey   # step 2
```
`validate --strict --json` output keys:
`success, strict, target, manifest{file,type,errors[],warnings[],notes[]}, contents[]`.

**Script invocation contract:** there is none beyond bash. `${CLAUDE_SKILL_DIR}` resolves to the skill's
own dir (plugin-aware); `${CLAUDE_PLUGIN_ROOT}` to the plugin root; `${CLAUDE_PLUGIN_DATA}` to a
persistent dir that survives updates (the only sane place to `pub get` / `pip install` into).

---

## Plan impact

### 1. CUT `annotate.py` (Pillow). — REFUTED by F11 + F16.
Pillow is not guaranteed and F16 shows the first-party pattern is: produce an image, let the model look
at it. Drawing boxes on a screenshot serves the *human reading the report*, not the analysis. v0.1 ships
the raw screenshot plus the coordinates already in `findings.json`. Boxes are a v0.2 nice-to-have, and
when you want them, an HTML report with absolutely-positioned divs over an img costs zero
dependencies and is zoomable — strictly better than a baked PNG.

### 2. CUT the Jinja2 template outright. — REFUTED by F11 + F17.
Jinja2 fails to import on the author's own Mac. Three moving parts (engine + `.j2` + render script) to
emit prose the model writes better and adapts to what it actually found. F17's first-party pattern: put
the report skeleton in `references/report-format.md` as a markdown fence and say "use this structure".

### 3. CUT `run_static.py`. It is a wrapper around one bash line.
Prior evidence already has `conalyz` working with JSON output. SKILL.md says: run
`conalyz --format json <path> > static.json`, here's how to read it. A script whose body is one
subprocess call is the purest form of the thing YAGNI forbids.

### 4. CUT `merge_findings.py`. It launders the model's own judgement through JSON.
Merging static + runtime + visual findings and rescoring 0-4 **against the journey's goal** is exactly
F15's "heuristics guide the approach" = open field = high freedom. A script can't decide that a 44pt tap
target is fine *here* because the goal is "browse" and fatal *there* because the goal is "check out in
under 60s". What the script would actually do — dedup by key, sort by severity — is a rule you write in
`references/heuristics.md` in ten lines and the model applies. Deterministic dedup buys reproducibility
of a *shuffle*, not of the *scores*, which were never deterministic to begin with.

### 5. DEMOTE `validate_journey.py` + the JSON Schema -> make the journey file not need them.
- F12: **neither Dart nor Python stdlib parses YAML, and PyYAML is missing here.** A `journey.yaml`
  forces a dependency in any language. JSON Schema forces a *second* one (no schema validator in either
  stdlib either).
- The only consumer of the journey file is the model. So: **make it `journey.md`** — a goal line and a
  numbered list of steps with expected outcomes. Zero parser, zero schema, zero validator, and it is
  simultaneously the human-readable artifact you'd want in the repo anyway. Ship one worked example in
  `references/journey-format.md` and the model's parse is reliable.
- If you later need machine consumption, use **JSON, not YAML** — both stdlibs read it for free.
- The fail-fast value is preserved by F15's plan-validate-execute: the model restates the parsed journey
  (goal + steps + success criteria) as a checklist before touching a simulator, and stops if it's wrong.

### 6. `run_journey.py` -> Dart if a script survives at all, and it may not.
- **Position: if a runtime measurement tool is needed, write it in Dart, not Python.** F11: Dart is the
  only runtime this skill can assume (Flutter implies it); macOS Python is a 3.9 Xcode shim that may not
  exist at all. F12: `dart run x.dart` needs no pubspec/pub get for stdlib-only code. The target it must
  talk to — the Dart VM service, `RenderBox` geometry, the semantics tree — is Dart-native; reaching it
  from Python means reimplementing over a websocket what `package:vm_service` already does.
- **But first check whether it needs to exist.** The dart-flutter MCP server is already installed here
  and exposes `vm_service`, `widget_inspector`, `flutter_driver_command`, `get_runtime_errors`,
  `hot_reload`, `dtd`. F13 shows the official Flutter plugin's answer to exactly this problem: 25 skills,
  zero scripts, and `flutter-add-integration-test` instructs the model to *drive the MCP tools*. Prior
  evidence already flags `flutter_driver_user_journey_test` and `accessibilityEvaluations` in dart-lang/ai.
  -> **This decision belongs to the runtime assignment. Packaging's ruling: if MCP covers measurement,
  v0.1 ships ZERO scripts.** If it doesn't, ship exactly one Dart tool.
- If that one Dart tool needs `package:vm_service`, do NOT vendor it into `scripts/`. Publish it as an
  ordinary pub package and have SKILL.md instruct `dart pub global activate <pkg>` — the same path prior
  evidence already proved works for `conalyz`. `${CLAUDE_PLUGIN_DATA}` is the documented home for
  "installed dependencies ... that must outlive an update" if you prefer a local install.

### 7. So: 5 scripts + schema + template -> **SKILL.md + 3 reference files + at most 1 Dart tool.**
What genuinely needs to be deterministic code, honestly:
- **YES — numeric measurement of the running app**: RenderBox rects, tap-target sizes, contrast ratios,
  step wall-clock timings. A model eyeballing "is this 44pt" is neither accurate nor reproducible, and
  these are the numbers every finding cites. This is F15's "narrow bridge".
- **NO — everything else.** Severity scoring against a goal, cross-step coherence, visual judgement,
  merge/dedup, report prose. All open field. A script there is the model's opinion in a costume.
- **The CI/reproducibility argument for scripts is answered by F21, not by scripts.** `claude plugin eval`
  with `--ablation with-without --runs 3 --threshold 0.8` is the real regression gate for a
  model-driven skill. That is a better CI story than five scripts, because it tests the thing the user
  actually gets — the judgement — instead of testing that JSON got shuffled the same way twice.
- Honest cost of this position: a model-driven pipeline can skip a step, and nothing enforces order. The
  mitigations the docs give are the copy-this-checklist workflow pattern and the validate-before-execute
  loop, both of which are markdown. Accept that a step can be skipped; make it visible in the report
  ("step 4: not measured") rather than pretending a script prevents it.

### 8. Distribution: add 2 files, done. (F18)
`.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` with `"source": "./"`, skills under
`skills/`. Gate CI on `claude plugin validate --strict --json .`. Release with `claude plugin tag`.
No npm, no pub publish, no registry. A plain repo also works (users clone into `~/.claude/skills/`) but
costs them manual steps for zero saving on your side.

### 9. PUBLIC-REPO / PRIVATE-DOGFOOD constraints, concretely:
- **`claude plugin eval` publishes its HTML report to claude.ai by default (F22).** Any dogfood eval
  must pass `--no-publish`. Put this in CONTRIBUTING.md and in the eval make/npm target itself, not in
  someone's memory.
- **`evals/` is the leak vector, not `examples/`.** Eval cases embed prompts, fixtures and graders. Every
  committed case must run against a throwaway synthetic Flutter app built for the repo — never the real
  one. The dogfood journey files stay local and gitignored.
- SKILL.md must instruct output into the **audited project or a temp dir**, never into the skill dir: a
  plugin install dir is shared and gets overwritten on update, and any screenshot written there is one
  `git add -A` away from being public.
- `.gitignore` must cover the output names the skill emits (`report.md`, `findings.json`, `screens/`)
  at repo root, so a local dogfood run can't be committed by accident.
- Screenshots are the highest-risk artifact: they carry UI copy, real data and the product's identity in
  one file. The report format should reference screenshots by relative path, so a published report
  without the image dir is still readable and leaks nothing.

### 10. Frontmatter discipline:
Ship `name`, `description`, `license`, `compatibility` only (F2). Do NOT ship `triggers`, `homepage`,
`version`, `requires_bin` — not spec, ignored (F5). Keep `when_to_use`/`context: fork`/`paths` out
unless you accept Claude-Code-only (F4). `version` lives in `plugin.json`.

### 11. Budget check is a command, not a guess:
Keep SKILL.md <=500 lines / <=5k tokens (F6); verify with `claude plugin details flutter-ux-journey`
(F20). The official Flutter skills' median is 162 lines — that is the bar to aim at, not 500.

---

## Unknowns

- **Does the dart-flutter MCP server actually deliver the a11y tree / RenderBox geometry / step timings
  the journey walk needs?** This single answer sets v0.1's script count to 0 or 1. It is the runtime
  assignment's call; I did not test the MCP tools. Prior evidence flags
  `flutter_driver_user_journey_test` and `accessibilityEvaluations` in dart-lang/ai as possibly
  overlapping this entire project — unresolved.
- **Whether `allowed-tools` is actually honored in Claude Code today.** I verified the docs describe it
  and that `validate` accepts it; I did not observe a permission prompt being skipped. agentskills.io
  marks it "(Experimental). Support for this field may vary between agent implementations."
- **Whether `${CLAUDE_SKILL_DIR}` expands inside `allowed-tools` patterns** (as the docs' example
  implies) — not empirically confirmed.
- **Claude Code's own `description` cap.** code.claude.com says `description` + `when_to_use` are
  truncated at 1,536 chars in the listing; the spec caps `description` at 1024. Interaction untested.
- **Marketplace listing requirements beyond a valid manifest** — whether getting into
  `claude-plugins-official` needs a PR/review, and any naming or review policy. Not investigated;
  a self-hosted marketplace (`/plugin marketplace add owner/repo`) needs no one's permission and is
  sufficient for v0.1.
- **`claude plugin eval` case.yaml schema** — I read the flags, not a real case file. Field names and
  grader shapes unverified; `claude plugin eval init --bare <name>` will produce a real template.
- **Whether `conalyz` is license-compatible with a public repo** — still open from prior evidence, and
  it matters here: if SKILL.md instructs installing it, its license is the user's problem but its
  availability is yours.
- Did not verify Windows/Linux behavior of any of the above; all measurements are macOS arm64.
