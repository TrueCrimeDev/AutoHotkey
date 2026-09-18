# Install ClautoHotkey

ClautoHotkey packages AHK guidance, rules, skills, and validation hooks for Claude Code. Its strongest Console integration comes from pointing it at the exact interpreter you use in the terminal.

## Plugin route

Run in Claude Code:

```text
/plugin marketplace add TrueCrimeDev/ClautoHotkey
/plugin install clautohotkey@clautohotkey
```

The current plugin's hooks require **WSL or Git Bash and `jq`**. Python 3 is used for module lint and the grading checker. Ensure these dependencies exist in the environment Claude Code actually starts, not just a different interactive shell.

```bash
command -v bash
command -v jq
jq --version
python3 --version
```

## Pin the interpreter in your project

```bash
# harness.env — project root
AHK_BIN_WIN="C:\Tools\AutoHotkey64Console.exe"
AHK_DIAG_JSON=1
RUNTIME_PROBE=1
NO_AUTO_RELOAD="demo.ahk"
DEMO_DIR="C:\Scripts\Demo"
```

`AHK_DIAG_JSON=1` requires the Console fork's `check /Diag=json` behavior. For stock AutoHotkey, use `0`. The resolver prefers project `harness.env`, then installation-root configuration, then standard-location auto-detection. Explicit configuration makes a demonstration reproducible.

| Setting | Purpose |
| --- | --- |
| `AHK_BIN_WIN` | Actual Windows interpreter path |
| `MAIN_SCRIPT`, `DEPENDENCY_SCRIPTS` | Main-script rechecks after dependency edits |
| `RUNTIME_PROBE` | Enable or disable a bounded runtime probe |
| `NO_RUNTIME_CHECK` | Scripts to exclude from probing |
| `NO_AUTO_RELOAD` | Scripts/modules not to automatically restart |
| `DEMO_DIR` | Location for new demo scripts |
| `GIT_GUARD_ENABLED` | Optional git identity guard; configure deliberately |

## Clone route

```bash
git clone https://github.com/TrueCrimeDev/ClautoHotkey.git
cd ClautoHotkey
./setup.sh
```

For an explicit local plugin session, Claude Code accepts `--plugin-dir /path/to/ClautoHotkey`. Read the repository's [setup instructions](https://github.com/TrueCrimeDev/ClautoHotkey#install) and [environment example](https://github.com/TrueCrimeDev/ClautoHotkey/blob/main/harness.env.example).

## Verify that hooks actually ran

Ask Claude to make a harmless `.ahk` edit using Write or Edit. Inspect the post-edit result for syntax and runtime status. A zero exit or absence of output alone is not proof that the hook parsed a filename and validated it. A missing `jq` in the launch PATH caused a silent skip in an earlier demo run; [troubleshooting](/reference/troubleshooting) explains the check.
