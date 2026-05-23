# AHK v2.1-alpha 20 → 30 Reference Documentation

**Date:** 2026-05-22
**Owner:** TrueCrimeDev
**Type:** Documentation generation

## Goal

Produce reference-style markdown documentation for AutoHotkey v2.1-alpha.20
through v2.1-alpha.30 (11 versions), covering every new feature, behavior
change, breaking change, and bug fix lexikos shipped in each release.

Audience: AHK v2 users adopting the v2.1 alpha branch, fork maintainers
tracking upstream churn, and Claude Code sessions that need authoritative
version context for upgrade work.

## Scope

- **In scope:** Upstream v2.1-alpha.20 → alpha.30. One file per version.
- **Out of scope:** Fork-only additions (`Print`, `Eval`, `SyntaxError`,
  `_ScriptGetLines`, `/Headless`, `/Diag`, etc.). Those belong in `updates.md`.
- **Out of scope:** Earlier alphas (a1–a19), later alphas (a31+ if any), and
  v2.0.x stable releases.

## Source of truth

Primary: **`git log <prev-tag>..<this-tag>`** in this fork's local repo.
All 11 tags (`v2.1-alpha.20` through `v2.1-alpha.30`) exist locally with full
lexikos commit messages.

Secondary cross-reference: existing showcase scripts in the project root —
`Alpha22_Example.ahk`, `Alpha23_Example.ahk`, …, `Alpha30_Example.ahk` (a21
and a27 are missing examples) — and `examples/v2.1-alpha-features.ahk`.

Fallback (only if commit messages are ambiguous): AutoHotkey community
forum thread `t=118744`. WebFetch returns 403; the workaround is asking the
user to paste the relevant post.

GitHub Releases does **not** publish v2.1-alpha changelogs (only v2.0.x
stable). Forum is blocked. Git history is the only mechanical source.

## Output

```
docs/alpha/
  v2.1-alpha.20.md
  v2.1-alpha.21.md
  v2.1-alpha.22.md
  v2.1-alpha.23.md
  v2.1-alpha.24.md
  v2.1-alpha.25.md
  v2.1-alpha.26.md
  v2.1-alpha.27.md
  v2.1-alpha.28.md
  v2.1-alpha.29.md
  v2.1-alpha.30.md
```

## Per-file structure

```markdown
# AutoHotkey v2.1-alpha.NN

**Released:** YYYY-MM-DD (from tag date)
**Previous:** [v2.1-alpha.NN-1](./v2.1-alpha.NN-1.md)
**Next:** [v2.1-alpha.NN+1](./v2.1-alpha.NN+1.md)
**Upstream tag:** [`v2.1-alpha.NN`](https://github.com/AutoHotkey/AutoHotkey/tree/v2.1-alpha.NN)

## Overview
2-4 sentence summary of what this release is about.

## New features
### <Feature name>
Prose description. What it does, why it matters.

```autohotkey
; minimal runnable example
```

## Changes
Behavior changes to existing features. Each entry: short paragraph + code
example where the change is non-obvious.

## Breaking changes
What scripts must update. Migration notes.
(Omit section entirely if none.)

## Bug fixes
- Short bullet per fix, paraphrased from commit message.

## Internal / build / parser changes
- Short bullet per change. (Omit if none.)

## Sources
- Commit range: `git log v2.1-alpha.NN-1..v2.1-alpha.NN`
- Example script: `Alpha NN_Example.ahk` (if exists)
```

Length target: 300–600 lines per file (reference-style depth).

## Execution plan

1. For each version 20→30, in order:
   - Extract commit list: `git log --no-merges v2.1-alpha.{N-1}..v2.1-alpha.{N} --pretty=format:"%h %s"`
   - For commits with non-obvious messages, read full commit body: `git show --no-patch <sha>`
   - Read corresponding `Alpha{N}_Example.ahk` if it exists; lift code samples
     that illustrate features cleanly
   - Draft the doc to the template above
   - Write to `docs/alpha/v2.1-alpha.{N}.md`

2. Parallelism: dispatch 3 research subagents per wave so I keep the main
   context clean. Each subagent gets one version, the exact `git log` command
   to run, the example file path, and the template. Returns: ready-to-write
   markdown.

3. After all 11 files are written, do a final consistency pass: verify each
   "Previous"/"Next" link resolves, and that no fork-only feature leaked in.

## Non-goals

- A combined index/README. (User chose per-file, not per-file + index.)
- Cross-version diff articles ("what changed from a20 to a30").
- Migration guides from v2.0 to v2.1.
- Translation into other languages.

## Risks

- **Commit messages may understate user-visible impact.** Mitigation: for any
  commit whose subject line is terse ("Refactor X", "Tweak Y"), read the full
  commit body and the touched source file to confirm whether it's user-visible.
- **Some features land across multiple commits.** Mitigation: group commits
  by feature in the doc, not by commit order.
- **A21 and A27 have no local example script.** Mitigation: write minimal
  runnable examples from commit descriptions; mark clearly in commit message
  rather than copying from local showcase.
