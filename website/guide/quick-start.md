# Your first feedback loop

Start with a compatible Windows Console executable. If you do not have one, follow [Build & install](/guide/installation). These examples use a neutral folder, `C:\Tools`, and a project folder, `C:\Scripts`.

## 1. Identify the executable

```powershell
$engine = 'C:\Tools\AutoHotkey64Console.exe'
& $engine --version
& $engine --capabilities
```

The filename is not a version guarantee. Read the build revision, architecture, commands, and feature flags. The [compatibility guide](/guide/compatibility) explains the development features used throughout this site.

## 2. Write a small program

Save this as `hello.ahk` in your project:

```ahk
#Requires AutoHotkey v2.1-alpha.31
Print("Hello from {}", A_AhkVersion)
Print("Literal {braces} stay literal")
```

## 3. Check, then execute

```powershell
& $engine check .\hello.ahk
if ($LASTEXITCODE -ne 0) { throw 'Syntax check failed' }
& $engine /Headless /Diag=json .\hello.ahk 1>result.txt 2>diagnostics.jsonl
$runExit = $LASTEXITCODE
Get-Content result.txt
"Exit: $runExit"
```

`check` parses the script. The second command executes it. A clean check does not prove correct behavior; add assertions when an outcome matters.

## 4. Add ClautoHotkey

In Claude Code:

```text
/plugin marketplace add TrueCrimeDev/ClautoHotkey
/plugin install clautohotkey@clautohotkey
```

Create `harness.env` in the project root:

```bash
AHK_BIN_WIN="C:\Tools\AutoHotkey64Console.exe"
AHK_DIAG_JSON=1
RUNTIME_PROBE=1
NO_AUTO_RELOAD="hello.ahk"
```

The hooks require a working Bash environment and `jq`. Ask Claude to edit `hello.ahk`, then inspect the actual validation output. See [Plugin setup](/clautohotkey/setup) for WSL paths, dependency checks, and hook verification.

## What next?

Build a [JSON CLI](/recipes/json-cli), explore [the REPL](/console/eval-repl), or run the [26-assertion demonstration](/showcase).
