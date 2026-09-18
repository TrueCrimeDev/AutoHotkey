---
description: How the AutoHotkey Console engine and the ClautoHotkey Claude Code plugin fit together.
---
# Two projects. One useful loop.

**AutoHotkey Console** is a Windows interpreter. **ClautoHotkey** is a Claude Code plugin and development harness. You can use either independently; together, they connect an edit to an observable result.

| Layer | Responsibility | What you see |
| --- | --- | --- |
| Console engine | Parse and execute AHK; expose command-line and inspection tools | stdout, stderr, exit codes, diagnostics, trace, coverage |
| ClautoHotkey plugin | Load AHK rules and skills; validate edits through hooks | Task-specific guidance and post-edit check results |
| Grading harness | Run static and dry-run checks with a shared result format | Findings, parser confidence, intercepted intent, checker verdicts |
| MCP client | Discover and call local engine tools | Structured results for source exploration and execution |

## Follow one change through the system

<WorkflowDemo />

The walkthrough is illustrative. The [session gallery](/showcase) contains actual Claude Code captures and recorded results. This website is static: it does not execute AHK in your browser or connect to your desktop.

## Choose your entry point

- **I write AHK already:** start with the [CLI](/console/cli) and [native JSON](/console/print-json).
- **I use Claude Code:** install [ClautoHotkey](/clautohotkey/setup) and verify its hooks.
- **I build libraries:** add [runtime assertions and CI](/recipes/testing-ci).
- **I build local tools:** explore [ProcessPipe](/console/process-pipe) and [native MCP](/clautohotkey/mcp).

These are independent projects built on AutoHotkey v2, not an official AutoHotkey or Anthropic product. The engine is GPL-2.0; the ClautoHotkey repository is MIT-licensed.

Sources: [Console repository](https://github.com/TrueCrimeDev/AutoHotkey), [ClautoHotkey repository](https://github.com/TrueCrimeDev/ClautoHotkey).
