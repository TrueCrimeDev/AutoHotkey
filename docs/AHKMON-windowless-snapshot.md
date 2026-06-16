# AHKMON — Windowless Diagnostic Snapshot

**Audience:** a coding agent building a VS Code extension (or any external tool) that reads a running AutoHotkey script's diagnostic lists. This document is self-contained: it specifies the wire protocol, the recommended integration architecture, verified reference code, and the parsing/error-handling rules. Implement to this and it will work.

---

## 1. What this gives you

A way to retrieve a **running** AutoHotkey script's four diagnostic lists —

| View name (token) | Content (same as the script's main-window View menu) |
|---|---|
| `ListLines` | recently executed lines (the line-history log) |
| `ListVars` | global variables: name, size, and value preview |
| `ListHotkeys` | registered hotkeys/hotstrings table |
| `KeyHistory` | recent keyboard/mouse events + timings |

— **without the script's main window ever becoming visible, activating, or stealing focus.** The text returned is byte-identical to what the View menu would show.

This replaces the old technique of sending the View-menu `WM_COMMAND` to the target and scraping its `Edit1` control, which calls `ShowWindow` and flashes/steals focus on every read.

## 2. Hard constraint

The handler runs **inside the target process**, so the monitored script **must be running under the patched AutoHotkey +Console fork** (`A_AhkVersion` ends in `+Console`, with the AHKMON `WM_COPYDATA` handler — engine PR “windowless diagnostic snapshot”). Stock AutoHotkey will not respond. If you query a non-fork script you get **no reply** (treat as “unsupported target”, see §7).

## 3. Wire protocol (authoritative)

Standard Windows `WM_COPYDATA` (`0x004A`) request/response between two windows.

### 3.1 Request — reader → target's **main window**

Send `WM_COPYDATA` with a `COPYDATASTRUCT`:

| Field | Value |
|---|---|
| `dwData` | `0x41484B51` (the ASCII bytes `'AHKQ'`) |
| `cbData` | **byte length** of `lpData` (UTF-8 bytes; trailing NUL not required and not counted) |
| `lpData` | UTF-8 string: `"<replyHwndDecimal>\n<views CSV>"` |

- `wParam` may be your reply HWND (informational); the target uses the **payload's** first line for the reply target.
- `lpData` layout: the **first line** (up to the first `\n`) is your reply window's HWND as a **decimal** integer; the **remainder** is a comma-separated list of view tokens from `{ListLines, ListHotkeys, ListVars, KeyHistory}`.
  - View tokens are **case-insensitive**; surrounding spaces are trimmed; unknown tokens are skipped. A trailing `\r` on the first line (CRLF) is tolerated.
  - Order matters: the reply emits view blocks **in the order you list them**.
- Example payload: `723456\nListLines,ListHotkeys,ListVars,KeyHistory`

The target handles this **before** any script-level `OnMessage(WM_COPYDATA)` monitor, so it works even if the script uses `WM_COPYDATA` for its own purposes. The handler returns `TRUE`.

### 3.2 Reply — target → your `replyHwnd`

The target sends `WM_COPYDATA` back to `replyHwnd` (via `SendMessageTimeout`, 5 s, `SMTO_ABORTIFHUNG`):

| Field | Value |
|---|---|
| `dwData` | `0x41484B52` (the ASCII bytes `'AHKR'`) |
| `cbData` | byte length of the UTF-8 blob |
| `lpData` | UTF-8 blob (see §3.3); **no BOM** |

The reply is delivered **synchronously while your request `SendMessage` is still blocked** (standard `WM_COPYDATA` reentrancy: the OS pumps the incoming sent-message to your window procedure while you wait). Your reply window proc must therefore exist and return promptly. See §5 for why this makes a tiny helper process the easiest integration.

### 3.3 Reply blob format

UTF-8 text, line-oriented, `\n`-separated sentinels:

```
@@AHKMON snapshot ts=<unixMillis> target=<mainHwndDecimal> title=<window title>@@
@@AHKMON view=<Name>@@
<verbatim view text>
@@AHKMON view=<Name>@@
<verbatim view text>
@@AHKMON end@@
```

Rules:
- One header line, then **one block per requested+recognized view, in requested order**, then the `end` line.
- `ts` = Unix epoch **milliseconds**; `target` = the target's main-window HWND in **decimal**; `title` = the main-window title (CR/LF neutralized to spaces so the header stays single-line).
- `<Name>` is the exact token you requested (e.g. `ListVars`).
- `<verbatim view text>` is the raw View-menu text. **It may contain tabs and may use `\r\n` line endings** (the generators' native output). An **empty** list still emits its `@@AHKMON view=...@@` block (with empty/near-empty body) — the sentinels are always present.
- Always terminated by `@@AHKMON end@@`.

#### 3.3.1 What each view's body looks like

The body is raw generator text (tab-separated where noted). Display it as-is; you don't need to parse inside a view. Shapes for reference:

- **ListVars** — `Global Variables (alphabetical)` header, a `---` rule, then one `Name[used of allocated]: <value preview>` per global (objects render as `{address: 0x…}`).
- **ListHotkeys** — header row `Type⇥Off?⇥Level⇥Running⇥Name`, a `---` rule, then one tab-separated row per hotkey/hotstring. No hotkeys defined → header only.
- **ListLines** — a descriptive header paragraph, then `---- <scriptPath>`, then executed lines as `NNN: <source>` (oldest first) with `(secondsElapsed)` annotations; ends with a literal `Press [F5] to refresh.` line.
- **KeyHistory** — a multi-line status header (active window, hook state, enabled timers, modifier states), explanatory `NOTE:` paragraphs, then a `VK SC⇥Type⇥Up/Dn⇥Elapsed⇥Key⇥Window` event table (empty rows when the keyboard hook isn't installed); ends with `Press [F5] to refresh.`

> Note: ListLines and KeyHistory include a trailing `Press [F5] to refresh.` line — a verbatim menu artifact. Strip it for display if you like; it is always the last non-empty line of those two views.

**A short or empty body is always valid, never an error** — the only structural guarantee is the surrounding `@@AHKMON view=…@@` … next-sentinel framing. Do not infer failure from body length.

### 3.4 Magic constants (copy these)

```
WM_COPYDATA = 0x004A
AHKMON_REQUEST  dwData = 0x41484B51   // 'AHKQ'
AHKMON_REPLY    dwData = 0x41484B52   // 'AHKR'
View tokens: ListLines | ListHotkeys | ListVars | KeyHistory   (case-insensitive)
```

## 4. Finding the target & matching it to a file

You send the request to the target script's **main window** HWND (AHK's hidden message window), not a GUI it created. You almost never need Windows API bindings in Node — **let the helper enumerate** for you.

### 4.1 Discover running scripts (`list`)

Spawn the helper with the single argument `list`; it prints one line per running AutoHotkey script:

```
<mainHwndDecimal>\t<pid>\t<title>
```

Real output:

```
2753144	59660	C:\Users\me\scripts\_.ahk - AutoHotkey v2.1-alpha.30+Console
788186	40660	C:\…\AutoHotkey.dll - AutoHotkey v1.1.33.02
```

The **title is `"<scriptFullPath> - AutoHotkey <version>"`** — so one `list` call gives you, for every running script: its main-window HWND, PID, **file path**, and **engine version**.

```ts
interface AhkTarget { hwnd: number; pid: number; path: string; version: string; }

export async function listTargets(ahkExe: string, readerScript: string): Promise<AhkTarget[]> {
  const out = await run(ahkExe, [readerScript, "list"]);           // execFile, utf8
  return out.split("\n").filter(Boolean).map(line => {
    const [hwnd, pid, title] = line.split("\t");
    const m = title.match(/^(.*) - AutoHotkey (.+)$/);              // split path / version
    return { hwnd: Number(hwnd), pid: Number(pid),
             path: m ? m[1] : title, version: m ? m[2] : "" };
  });
}
```

### 4.2 Match the editor's file to a running script

To show diagnostics for the file open in VS Code:
1. Call `listTargets()`.
2. Pick entries whose `path` equals the active document's path (case-insensitive on Windows; compare with `path.win32.normalize`/`toLowerCase`).
3. If **none**, the script isn't running (offer to run it). If **several**, prompt the user to choose (show `pid`).
4. Query the chosen entry with `hwnd:<hwnd>`.

If your extension **launched** the script itself, just keep the `pid` from `child_process.spawn` and pass `pid:<pid>` — the helper resolves the HWND (`WinExist("ahk_pid " pid)`).

### 4.3 Validate AHKMON support (which targets answer)

The `version` from `list` tells you the engine (`+Console` = the fork, `v1.1.x` = stock v1 which never answers). But the **definitive** check is a query: if the helper exits `1` with stderr `no AHKR reply`, that target is stock AHK or a fork build without the AHKMON handler. There is no separate handshake — **a successful blob _is_ the capability proof.** Cache the result per `(exe, hwnd)` if you poll often.

## 5. Recommended architecture: spawn the AHK reader helper

A VS Code extension runs in Node.js, which has **no window procedure** and cannot easily receive a `WM_COPYDATA` reply (the reply requires a real HWND pumping sent-messages mid-`SendMessage`). Writing a native N-API addon to do this is possible but heavy.

**The simple, robust approach: spawn a tiny AutoHotkey helper that does the round-trip and prints the blob to stdout.** You already ship the fork engine; reuse it. The helper is `tools/ahkmon-reader.ahk` (below, **tested and verified**). Your extension spawns:

```
AutoHotkey64.exe  tools\ahkmon-reader.ahk  <target>  [viewsCSV]  [timeoutMs]
```

and reads its **stdout** (UTF-8, no BOM) — that's the raw `@@AHKMON@@` blob. Exit code: `0` ok, `1` no reply / bad window, `2` bad args. Errors go to stderr.

### 5.0 Packaging: where the engine and helper come from

- **The helper** (`ahkmon-reader.ahk`): **bundle it inside your extension** (e.g. `resources/ahkmon-reader.ahk`) and resolve at runtime with `path.join(context.extensionPath, "resources", "ahkmon-reader.ahk")`. Pass that path straight to `execFile` (Node handles separators; no manual quoting needed). It also provides the `list` discovery mode (§4.1).
- **The engine** (`AutoHotkey64.exe`, the +Console fork) is **not** a stock install — do **not** probe `Program Files`. Obtain its path from, in order: (1) a setting your extension exposes (e.g. `ahkmon.enginePath`); (2) an engine you bundle with the extension; (3) the executable a running target is already using (a running script's process image path is the fork engine). Validate once by running `AutoHotkey64.exe ahkmon-reader.ahk list` — exit `0` with parseable lines confirms a usable engine; otherwise prompt the user to set `ahkmon.enginePath`.

### 5.1 Reference helper (`tools/ahkmon-reader.ahk`) — verified working

```autohotkey
#Requires AutoHotkey v2.1-alpha.30
#SingleInstance Off
; ahkmon-reader.ahk <target> [views] [timeoutMs]
;   <target>  = decimal main-window HWND, "hwnd:<n>", or "pid:<n>"
;   [views]   = subset of ListLines,ListHotkeys,ListVars,KeyHistory (default: all)
;   [timeoutMs] default 4000
; Writes the raw @@AHKMON@@ blob (UTF-8, no BOM) to stdout. Exit 0 ok / 1 err / 2 usage.
DetectHiddenWindows(true)
AHKQ := 0x41484B51, AHKR := 0x41484B52, WM_COPYDATA := 0x4A
if (A_Args.Length < 1) {
    FileOpen("**", "w", "UTF-8-RAW").Write("usage: ahkmon-reader.ahk <hwnd|hwnd:N|pid:N> [views] [timeoutMs]`n")
    ExitApp(2)
}
arg := A_Args[1], target := 0
if (SubStr(arg, 1, 4) = "pid:")
    target := WinExist("ahk_pid " Integer(SubStr(arg, 5)))
else if (SubStr(arg, 1, 5) = "hwnd:")
    target := Integer(SubStr(arg, 6))
else
    target := Integer(arg)
if (!target || !DllCall("IsWindow", "Ptr", target)) {
    FileOpen("**", "w", "UTF-8-RAW").Write("error: no live target window from '" arg "'`n")
    ExitApp(1)
}
views := A_Args.Length >= 2 && A_Args[2] != "" ? A_Args[2] : "ListLines,ListHotkeys,ListVars,KeyHistory"
timeoutMs := A_Args.Length >= 3 ? Integer(A_Args[3]) : 4000
global g_reply := "", g_got := false
OnMessage(WM_COPYDATA, Recv)
Recv(wParam, lParam, msg, hwnd) {
    global g_reply, g_got, AHKR
    if (NumGet(lParam, 0, "UPtr") != AHKR)
        return 0
    cb := NumGet(lParam, A_PtrSize, "UInt"), p := NumGet(lParam, A_PtrSize * 2, "Ptr")
    g_reply := (p && cb) ? StrGet(p, cb, "UTF-8") : "", g_got := true
    return 1
}
payload := A_ScriptHwnd "`n" views
buf := Buffer(StrPut(payload, "UTF-8"))
StrPut(payload, buf, "UTF-8")
cds := Buffer(A_PtrSize * 2 + 8, 0)
NumPut("UPtr", AHKQ, cds, 0)
NumPut("UInt", buf.Size - 1, cds, A_PtrSize)
NumPut("Ptr", buf.Ptr, cds, A_PtrSize * 2)
DllCall("SendMessageW", "Ptr", target, "UInt", WM_COPYDATA, "Ptr", A_ScriptHwnd, "Ptr", cds.Ptr)
waited := 0
while (!g_got && waited < timeoutMs)
    Sleep(10), waited += 10
if (!g_got) {
    FileOpen("**", "w", "UTF-8-RAW").Write("error: no AHKR reply within " timeoutMs "ms (target not the +Console fork?)`n")
    ExitApp(1)
}
FileOpen("*", "w", "UTF-8-RAW").Write(g_reply)
ExitApp(0)
```

> The committed copy in `tools/ahkmon-reader.ahk` adds the `list` discovery mode (§4.1) and more comments; its **query** behavior is identical to the above.

### 5.2 Spawning it from a VS Code extension (Node/TypeScript)

```ts
import { execFile } from "node:child_process";

export interface AhkmonSnapshot {
  ts: number;                       // unix millis from the header
  target: number;                   // target main HWND (decimal)
  title: string;                    // target window title
  views: Record<string, string>;    // e.g. { ListVars: "...", ListHotkeys: "..." }
  raw: string;                      // the full blob, if you need it
}

/** Query a running fork script's diagnostic lists, windowlessly. */
export function readSnapshot(opts: {
  ahkExe: string;                   // path to AutoHotkey64.exe (the +Console fork)
  readerScript: string;             // path to tools/ahkmon-reader.ahk
  target: string;                   // "pid:1234" | "hwnd:723456" | "723456"
  views?: string[];                 // default all four
  timeoutMs?: number;               // helper-side reply timeout (default 4000)
}): Promise<AhkmonSnapshot> {
  const views = (opts.views ?? ["ListLines", "ListHotkeys", "ListVars", "KeyHistory"]).join(",");
  const args = [opts.readerScript, opts.target, views, String(opts.timeoutMs ?? 4000)];
  return new Promise((resolve, reject) => {
    execFile(
      opts.ahkExe, args,
      {
        encoding: "utf8",
        // All four views can total ~256 KB. 64 MB is generous headroom — execFile
        // ERRORS (does not truncate) if stdout exceeds maxBuffer, so don't set it small.
        maxBuffer: 64 * 1024 * 1024,
        windowsHide: true,
        // Helper's reply wait + ~5 s for process startup. The monitored script is never
        // at risk: the engine replies via SendMessageTimeout(5 s), so killing the helper
        // on timeout cannot stall the target.
        timeout: (opts.timeoutMs ?? 4000) + 5000,
      },
      (err, stdout, stderr) => {
        if (err) {
          // Distinguish failure modes for the UI (see §7).
          const why = (err as NodeJS.ErrnoException & { killed?: boolean }).killed ? "timed out"
            : /no AHKR reply/.test(stderr)  ? "target is not an AHKMON-capable fork script"
            : /no live target/.test(stderr) ? "target window not found (closed?)"
            : (stderr.trim() || err.message);
          return reject(new Error(`ahkmon-reader: ${why}`));
        }
        try { resolve(parseSnapshot(stdout)); }
        catch (e) { reject(e); }
      }
    );
  });
}
```

## 6. Parsing the blob

The blob is line-oriented; split on `\n`, then walk sentinel lines. Reference parser:

```ts
const HEADER = /^@@AHKMON snapshot ts=(\d+) target=(\d+) title=(.*)@@$/;
const VIEW   = /^@@AHKMON view=(.+)@@$/;
const END    = "@@AHKMON end@@";

export function parseSnapshot(raw: string): AhkmonSnapshot {
  // Normalize only the sentinel-delimiting newlines; keep view text verbatim.
  const lines = raw.split("\n");
  let ts = 0, target = 0, title = "";
  const views: Record<string, string> = {};

  let i = 0;
  // header
  const h = lines[i++]?.replace(/\r$/, "").match(HEADER);
  if (!h) throw new Error("AHKMON: missing snapshot header");
  ts = Number(h[1]); target = Number(h[2]); title = h[3];

  let curName: string | null = null;
  let body: string[] = [];
  const flush = () => { if (curName !== null) views[curName] = body.join("\n").replace(/\n$/, ""); };

  for (; i < lines.length; i++) {
    const line = lines[i];
    const stripped = line.replace(/\r$/, "");
    if (stripped === END) { flush(); curName = null; break; }
    const v = stripped.match(VIEW);
    if (v) { flush(); curName = v[1]; body = []; continue; }
    if (curName !== null) body.push(line);   // verbatim (keep tabs/CRLF inside the value)
  }
  return { ts, target, title, views, raw };
}
```

Notes:
- View **values are verbatim** — preserve tabs; do not trim interior whitespace. Only the trailing newline that precedes the next sentinel is removed.
- A view you didn't request simply won't be a key in `views`.
- The header `title` may be any path-like string; treat it as opaque.

## 7. Error handling & edge cases

| Situation | What you observe | Handle by |
|---|---|---|
| Target is **not** the +Console fork (or lacks AHKMON) | helper exits `1`, stderr “no AHKR reply” | tell the user the script must run the patched engine |
| Target window closed mid-query | helper exits `1` (`IsWindow` false or no reply) | re-resolve the target / report gone |
| Wrong / dead HWND or PID | helper exits `1` | validate target before querying |
| Reader process itself hung reader | target's `SendMessageTimeout` returns after 5 s; **target is never blocked** | n/a — the target is protected by design |
| Empty list (e.g. KeyHistory disabled) | `@@AHKMON view=KeyHistory@@` block present, body empty/short | parser yields `views.KeyHistory === ""` (or a short notice) |
| Very large lists | each view is bounded (~64 K chars); blob can be ~256 KB+ | keep `maxBuffer` generous (example uses 64 MB) |
| Unknown view token requested | silently skipped (no block) | only request the four known tokens |

**Turning failures into messages.** Every hard failure is helper exit `1`; **branch on stderr** (the Node wrapper in §5.2 already does this):

| Signal | Suggested user-facing message |
|---|---|
| stderr contains `no AHKR reply` | “This script isn’t running an AHKMON-capable AutoHotkey build. Run it with the +Console fork.” |
| stderr contains `no live target` | “That script is no longer running.” → refresh via `list` |
| `err.killed` (timeout) | “The script didn’t respond in time.” → offer retry (it may be mid uninterruptible section) |
| exit `2` | usage bug in how you invoked the helper — fix the call, not user-facing |

## 8. Security / scope note

The handler returns the **full** diagnostic text (it does **not** honor `g_AllowMainWindow`, the flag compiled scripts use to hide source). For normal dev scripts this is identical to the View menu. If you query a compiled/protected script, you still get its lists. This is intended for a trusted local developer tool.

## 9. Native alternative (only if you must avoid spawning AHK)

If you implement the reader natively (N-API / C++), the requirements are exactly §3:
1. Create a hidden message-only window with a `WndProc` that handles `WM_COPYDATA` and checks `dwData == 0x41484B52`.
2. Pack the request `COPYDATASTRUCT` (UTF-8 payload, `cbData` = byte length, `dwData = 0x41484B51`).
3. `SendMessageW(targetHwnd, WM_COPYDATA, myHwnd, &cds)` — your `WndProc` receives the `AHKR` reply **during** this call (pump sent-messages); copy the blob out, then the call returns.
4. Decode `lpData` as UTF-8 using `cbData` bytes.

The spawn-the-helper approach (§5) avoids all of this and is recommended.

## 10. Verified example

Real reply for a target with `global demoVar := "hello-from-target"` and hotkey `^!+F12`, requesting `ListVars,ListHotkeys`:

```
@@AHKMON snapshot ts=1781571666858 target=1445298 title=C:\…\_rtest_tgt.ahk - AutoHotkey v2.1-alpha.30+Console@@
@@AHKMON view=ListVars@@
Global Variables (alphabetical)
--------------------------------------------------
A_Args: Array object {address: 0x…}
demoVar[17 of 63]: hello-from-target
f: File object {address: 0x…}

@@AHKMON view=ListHotkeys@@
Type	Off?	Level	Running	Name
-------------------------------------------------------------------
reg				^!+F12

@@AHKMON end@@
```

(Order honored: `ListVars` before `ListHotkeys`, exactly as requested. The View-menu text is reproduced verbatim, including the tab-separated hotkey columns.)

---

### Engine side (for reference; you do not implement this)

- `source/script2.cpp`: `BuildMainView()` (the four generators, no window shown), `AHKMon_HandleQuery()` (parse → build → reply), and an early `WM_COPYDATA` intercept in `MainWindowProc` (before MsgMonitor).
- `source/script.h`: `BuildMainView` declaration.
- Test: `tests/test_ahkmon.ahk` (asserts foreground/visibility unchanged across 100 requests, view order, content).
