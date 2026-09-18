# Troubleshooting

## The shell and hook disagree

Run `Get-Command ahk`, `ahk --version`, and the explicitly configured interpreter's `--version`. Read project `harness.env`. A cached or older binary can have the same filename but different capabilities. Align the alias, plugin, and MCP paths.

## The hook appears to succeed without doing anything

Check `command -v jq` in the exact environment that launches Claude Code. In an earlier demo, jq existed but its folder was missing from the launch PATH; the hook extracted no filename and skipped validation. Repair the launch PATH and verify a controlled valid/invalid `.ahk` edit. Silence alone is not validation evidence.

## An unknown function or switch appears

Read `--capabilities`. The development build adds APIs that may be absent from an older executable or a clean public branch build. `#Requires` alone does not identify a fork. See [availability](/guide/compatibility).

## Windows and WSL paths do not resolve

Windows interpreters and Windows Python need Windows paths. Linux Python and shell tools need `/mnt/c/...` paths. Keep executable command paths appropriate for the **host that starts the process**, and arguments appropriate for the **child that receives them**.

Do not set a Linux application's temporary directory to a raw `C:\...` string. If sharing temporary directories through WSL, use deliberate path translation and keep the Linux tool's own temp directory valid.

## Static passed, but parse is partial

That is possible: the interpreter accepted the script while tree-sitter could not fully model it. Preserve `parse=partial` and finding confidence. Do not turn an incomplete lint result into a claim of complete validation.

## Dry-run output is not valid NDJSON

Candidate stdout can mix with the gate result. Preserve the raw file and the checker failure. A separately extracted, schema-checked harness row can aid diagnosis, but is not a fix for stream separation. See [grading gates](/clautohotkey/harness).

## Headless still shows a dialog or times out

An explicit script `MsgBox`, persistent timer, hotkey, or GUI can still interact or remain resident. `/Headless` is not a sandbox. Use a controlled script, disable runtime probes where inappropriate, and set bounded execution timeouts.

## AST tools cannot load the grammar

Check architecture and DLL placement. The bundled `tree-sitter-ahk.dll` is x64-only and must be available to the x64 engine. Use the regex `source_outline` with its stated limits if grammar-backed analysis is unavailable.

## A shared screenshot exposes a profile path

Start a fresh demo in a neutral folder such as `C:\ClautoHotkey-Demo`; copy the interpreter and required inputs there. Old conversation history, command discovery, diagnostics, and temp paths can still expose account folders. Inspect the exact screenshot and any downloadable logs before sharing.
