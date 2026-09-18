# Skills, rules & knowledge

ClautoHotkey gives Claude task-specific AutoHotkey context. Its current repository exposes 19 skill commands, path-triggered rules, knowledge modules, and optional investigator agents.

## Command directory

| Command | Best starting point |
| --- | --- |
| `/ahk-gui` | GUI objects, controls, layout, events |
| `/ahk-gui-gen` | Generate a GUI from a description |
| `/ahk-oop` | Classes, properties, Map, object patterns |
| `/ahk-new-class` | Scaffold a class |
| `/ahk-text` | Strings, regex, escaping, parsing |
| `/ahk-com` | COM automation and events |
| `/ahk-dllcall` | DllCall, buffers, structs, callbacks |
| `/ahk-winapi` | Windows messages and platform APIs |
| `/ahk-fix` | Diagnose and repair an error |
| `/ahk-debug-dashboard` | Organize live debugging state |
| `/ahk-run` | Run a selected script and inspect output |
| `/ahk-eval` | Work with a live REPL |
| `/ahk-audit-errors` | Find silent failures and empty catches |
| `/ahk-mistakes` | Review recurring mistakes |
| `/ahk-convert` | Convert v1 code to v2 |
| `/ahk-modernize` | Update older v2 patterns |
| `/ahk-versions` | Check version and portability constraints |
| `/ahk-docs` | Look up AHK documentation |
| `/ahk-ref` | Broader multi-domain reference |

Exact command availability follows the installed plugin revision. A skill may depend on optional tools or integrations; installation does not itself prove those services work.

## Rules follow files

The rule injection hook matches paths before edits. Examples include `ahk-v2-syntax`, `ahk-target`, `ahk-fork-features`, `gui-work`, `lib-development`, and `demo-location`. Read the active rule and the actual target build when advice conflicts with an older example.

## Modules provide depth

The `Modules/` directory covers language, objects, arrays, COM, WinAPI, DllCall, errors, formatting, and testing. These are instructions and reference material, not a replacement for interpreter checks or observed application behavior.

## Agents are optional

The repository also provides roles for analysis, tests, dependencies, COM/UIA exploration, profiling, context, orchestration, and layout. Use them when the task warrants separate investigation; a simple script edit does not require a multi-agent workflow.

Source: [ClautoHotkey skills and modules](https://github.com/TrueCrimeDev/ClautoHotkey).
