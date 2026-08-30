#!/usr/bin/env python3
"""Conformance + differential tests for `AutoHotkey64 mcp` (native C++ MCP server).

Usage: conformance_native.py <path-to-engine-exe-with-mcp-verb>

Run from WSL; fixtures are created under the repo's temp/ dir (on C:, so the
Windows engine can read them) and removed afterwards.

- Protocol conformance: initialize/ping/tools-list/notifications/error codes,
  LF framing, exit 0 on EOF, -32700 recovery, concurrent instances.
- Differential: every file tool's payload must deep-equal the reference
  implementation (debugger-tool/mcp-ahk via the ahkmcp in-process CLI).
"""
import json, os, subprocess, sys, tempfile, shutil

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
AHKMCP = os.path.join(REPO, "debugger-tool/mcp-ahk/ahkmcp")
NATIVE = sys.argv[1]

passed = failed = 0
def check(label, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"ok   {label}")
    else:
        failed += 1
        print(f"FAIL {label}  {detail}")

def wslpath_w(p):
    return subprocess.run(["wslpath", "-w", p], capture_output=True, text=True).stdout.strip()

def run_session(lines, timeout=60):
    """Feed JSON-RPC lines to a fresh native server; return (stdout_lines, exit_code)."""
    payload = "".join(l + "\n" for l in lines).encode("utf-8")
    p = subprocess.Popen([NATIVE, "mcp"], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = p.communicate(payload, timeout=timeout)
    return [l for l in out.decode("utf-8").split("\n") if l.strip()], p.returncode

def rpc(method, id=None, params=None):
    m = {"jsonrpc": "2.0", "method": method}
    if id is not None: m["id"] = id
    if params is not None: m["params"] = params
    return json.dumps(m)

def tool_call(id, name, args=None):
    p = {"name": name}
    if args is not None: p["arguments"] = args
    return rpc("tools/call", id, p)

def tool_payload(resp):
    return json.loads(resp["result"]["content"][0]["text"])

def reference(tool, *args):
    """Run the reference implementation in-process via the ahkmcp CLI."""
    r = subprocess.run([AHKMCP, tool, *args, "--raw"], capture_output=True, timeout=60)
    if r.returncode != 0:
        return {"__error__": r.stdout.decode("utf-8", "replace") + r.stderr.decode("utf-8", "replace")}
    return json.loads(r.stdout.decode("utf-8"))

# ---- fixtures on the Windows filesystem ----
os.makedirs(os.path.join(REPO, "temp"), exist_ok=True)
fixdir = tempfile.mkdtemp(prefix="mcp-native-qa-", dir=os.path.join(REPO, "temp"))
FIXTURE = """; conformance fixture
class Foo {
    __New() {
    }
    Bar(a, b) {
    }
    Value {
        get => 1
    }
}

Baz(x) {
}

^j::Send("hi")

MyLabel:
return
"""
UNI = 'Uni() {\n    s := "héllo 日本語"\n}\nclass Ünicode {\n}\n'
paths = {}
for name, content in [("fix.ahk", FIXTURE), ("uni.ahk", UNI), ("empty.ahk", ""),
                      ("second.ahk", "Another() {\n}\nclass More {\n}\n")]:
    p = os.path.join(fixdir, name)
    with open(p, "w", encoding="utf-8", newline="\n") as f:
        f.write(content)
    paths[name] = wslpath_w(p)
fixdir_w = wslpath_w(fixdir)

try:
    # ================= main scripted session =================
    reqs = [
        rpc("initialize", 1, {"protocolVersion": "2025-06-18", "capabilities": {},
                              "clientInfo": {"name": "conf", "version": "0"}}),
        rpc("notifications/initialized"),
        rpc("ping", 2),
        rpc("tools/list", 3),
        tool_call(4, "ast_outline", {"file": paths["fix.ahk"]}),
        tool_call(5, "get_source_context", {"file": paths["fix.ahk"], "line": 9, "radius": 1}),
        tool_call(6, "source_outline", {"file": paths["fix.ahk"]}),
        tool_call(7, "workspace_symbols", {"root": fixdir_w, "query": ""}),
        tool_call(8, "workspace_symbols", {"root": fixdir_w, "max_results": 1}),
        rpc("no/such/method", 9),
        rpc("silent/notification"),                       # no id -> no response
        tool_call(10, "nope_tool", {}),
        rpc("tools/call", 11, {}),                        # missing tool name
        tool_call(12, "ast_outline", {}),                 # missing file arg
        tool_call(13, "ast_outline", {"file": "C:\\nope\\missing.ahk"}),
        tool_call(14, "get_source_context", {"file": paths["empty.ahk"], "line": 1}),
        tool_call(15, "ast_outline", {"file": paths["uni.ahk"]}),
        tool_call(16, "get_source_context", {"file": paths["uni.ahk"], "line": 2, "radius": 0}),
        tool_call(17, "workspace_symbols", {"root": fixdir_w, "query": "\u00dcni"}),  # Üni
        rpc("ping", 18),                                  # fence
        tool_call(19, "server_status"),
    ]
    lines, code = run_session(reqs)
    check("session.exit0", code == 0, f"exit={code}")
    resps = [json.loads(l) for l in lines]
    check("session.all-json-lines", True)
    expect_ids = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19]
    got_ids = [r.get("id") for r in resps]
    check("session.response-count+order (notifications silent)", got_ids == expect_ids,
          f"got {got_ids}")
    by_id = {r.get("id"): r for r in resps}

    # initialize
    r = by_id[1].get("result", {})
    check("init.protocolVersion-echo", r.get("protocolVersion") == "2025-06-18", str(r))
    check("init.serverInfo", r.get("serverInfo") == {"name": "ahk-mcp", "version": "0.1.0"}, str(r.get("serverInfo")))
    check("init.capabilities.tools", "tools" in r.get("capabilities", {}), str(r.get("capabilities")))

    # ping
    check("ping.empty-result", by_id[2].get("result") == {}, str(by_id[2]))

    # tools/list
    tools = by_id[3]["result"]["tools"]
    names = [t["name"] for t in tools]
    check("list.names", names == ["ast_outline", "get_source_context", "server_status",
                                  "source_outline", "workspace_symbols"], str(names))
    check("list.fields", all(set(t) == {"name", "description", "inputSchema"} for t in tools))
    gsc = next(t for t in tools if t["name"] == "get_source_context")
    check("list.gsc-required", gsc["inputSchema"]["required"] == ["file", "line"], str(gsc["inputSchema"]))

    # ---- differential: native tools/call vs reference CLI ----
    for tid, tool, ref_args, label in [
        (4, "ast_outline", [paths["fix.ahk"]], "fix"),
        (5, "get_source_context", [paths["fix.ahk"], "9", "1"], "fix@9r1"),
        (6, "source_outline", [paths["fix.ahk"]], "fix"),
        (15, "ast_outline", [paths["uni.ahk"]], "uni"),
        (16, "get_source_context", [paths["uni.ahk"], "2", "0"], "uni@2r0"),
    ]:
        native = tool_payload(by_id[tid])
        ref = reference(tool, *ref_args)
        check(f"diff.{tool}.{label}", native == ref,
              f"\n  native={json.dumps(native, ensure_ascii=False)[:400]}\n  ref   ={json.dumps(ref, ensure_ascii=False)[:400]}")

    for tid, ref_args, label in [
        (7, [fixdir_w], "all"),
        (8, [fixdir_w, "query=", "max_results=1"], "cap1"),
        (17, [fixdir_w, "query=\u00dcni"], "uni-query"),
    ]:
        native = tool_payload(by_id[tid])
        ref = reference("workspace_symbols", *ref_args)
        check(f"diff.workspace_symbols.{label}", native == ref,
              f"\n  native={json.dumps(native, ensure_ascii=False)[:400]}\n  ref   ={json.dumps(ref, ensure_ascii=False)[:400]}")

    # error cases
    def err_of(i): return by_id[i].get("error", {})
    check("err.-32601", err_of(9).get("code") == -32601 and "no/such/method" in err_of(9).get("message", ""), str(by_id[9]))
    check("err.unknown-tool", err_of(10).get("code") == -32602 and "Unknown tool: nope_tool" in err_of(10).get("message", ""), str(by_id[10]))
    check("err.missing-name", err_of(11).get("code") == -32602 and "missing tool name" in err_of(11).get("message", ""), str(by_id[11]))
    check("err.missing-file-arg", err_of(12).get("code") == -32603, str(by_id[12]))
    check("err.missing-file", err_of(13).get("code") == -32603 and "failed:" in err_of(13).get("message", ""), str(by_id[13]))

    # zero-byte file is valid input
    z = tool_payload(by_id[14])
    check("edge.empty-file", z.get("total") == 0 and z.get("context") == [], str(z))

    # server_status
    s = tool_payload(by_id[19])
    check("status.identity", s.get("name") == "ahk-mcp" and s.get("version") == "0.1.0", str(s)[:200])
    check("status.ahkVersion", "2.1-alpha.30" in s.get("ahkVersion", ""), str(s.get("ahkVersion")))
    check("status.pid", isinstance(s.get("pid"), int) and s["pid"] > 0)
    check("status.toolsRegistered", s.get("toolsRegistered") == 5, str(s.get("toolsRegistered")))
    # 21 method-bearing messages were sent (19 with ids + 2 notifications)
    check("status.requests", s.get("requests") == 21, f"requests={s.get('requests')}")
    check("status.errors", s.get("errors") == 5, f"errors={s.get('errors')}")
    bm = s.get("byMethod", {})
    check("status.byMethod", bm.get("tools/call") == 14 and bm.get("ping") == 2
          and bm.get("notifications/initialized") == 1 and bm.get("silent/notification") == 1, str(bm))
    tc = s.get("toolCalls", {})
    check("status.toolCalls-counts-self", tc.get("server_status") == 1 and tc.get("ast_outline") == 4
          and tc.get("workspace_symbols") == 3, str(tc))
    check("status.uptime-float", isinstance(s.get("uptimeSeconds"), (int, float)))
    check("status.lastActivity", isinstance(s.get("lastActivitySecondsAgo"), (int, float)))

    # ================= malformed-input session =================
    lines2, code2 = run_session(["this is not json {{{", "", "   ", rpc("ping", 1), "42", '"scalar"', rpc("ping", 2)])
    r2 = [json.loads(l) for l in lines2]
    check("bad.exit0", code2 == 0, f"exit={code2}")
    check("bad.count", len(r2) == 5, f"{len(r2)} lines: {lines2}")
    check("bad.-32700-id-null", r2[0].get("error", {}).get("code") == -32700 and r2[0].get("id") is None, str(r2[0]))
    check("bad.keeps-serving", r2[1].get("id") == 1 and r2[1].get("result") == {}, str(r2[1]))
    check("bad.-32600-scalar", r2[2].get("error", {}).get("code") == -32600, str(r2[2]))
    check("bad.-32600-string", r2[3].get("error", {}).get("code") == -32600, str(r2[3]))
    check("bad.final-ping", r2[4].get("id") == 2, str(r2[4]))

    # ================= parity edge-cases session =================
    # Non-UTF-8 bytes, embedded NULs, UTF-16LE BOMs, non-string method/name,
    # number-typed args, CR-padded numeric strings, junction cycles.
    edge = {}
    for name, data in [
        ("ansi.ahk", b"; caf\xe9 legacy\nfoo() {\n}\n"),          # invalid UTF-8 byte
        ("nul.ahk", b"A() {\n}\n\x00\nBar() {\n}\n"),             # embedded NUL
        ("utf16.ahk", "﻿Utf16Fn() {\n}\nclass U16C {\n}\n".encode("utf-16-le")),
    ]:
        p = os.path.join(fixdir, name)
        with open(p, "wb") as f:
            f.write(data)
        edge[name] = wslpath_w(p)
    jroot = os.path.join(fixdir, "jx")
    os.makedirs(jroot)
    with open(os.path.join(jroot, "a.ahk"), "w") as f:
        f.write("JFn() {\n}\n")
    jroot_w = wslpath_w(jroot)
    junction_ok = subprocess.run(
        ["cmd.exe", "/c", "mklink", "/J", jroot_w + "\\loop", jroot_w],
        capture_output=True).returncode == 0

    reqs3 = [
        rpc("initialize", 1, {"protocolVersion": "2025-06-18"}),
        tool_call(2, "ast_outline", {"file": edge["ansi.ahk"]}),
        tool_call(3, "ast_outline", {"file": edge["nul.ahk"]}),
        tool_call(4, "source_outline", {"file": edge["utf16.ahk"]}),
        tool_call(5, "get_source_context", {"file": edge["utf16.ahk"], "line": 1, "radius": 5}),
        '{"jsonrpc":"2.0","id":6,"method":true}',
        rpc("tools/call", 7, {"name": True}),
        tool_call(8, "workspace_symbols", {"root": 42, "query": 7}),
        tool_call(9, "get_source_context", {"file": paths["fix.ahk"], "line": "5\n"}),
        tool_call(10, "workspace_symbols", {"root": jroot_w}),
        '{"jsonrpc":"2.0","method":null}',   # non-string method, no id -> -32600 id null
    ]
    lines3, code3 = run_session(reqs3, timeout=90)
    r3 = [json.loads(l) for l in lines3]
    check("edge2.exit0", code3 == 0, f"exit={code3}")
    check("edge2.ids", [r.get("id") for r in r3] == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, None],
          str([r.get("id") for r in r3]))
    b3 = {r.get("id"): r for r in r3}
    for tid, tool, ref_args, label in [
        (2, "ast_outline", [edge["ansi.ahk"]], "ansi-bytes"),
        (3, "ast_outline", [edge["nul.ahk"]], "embedded-nul"),
        (4, "source_outline", [edge["utf16.ahk"]], "utf16le-bom"),
        (5, "get_source_context", [edge["utf16.ahk"], "1", "5"], "utf16le-bom"),
    ]:
        native = tool_payload(b3[tid])
        ref = reference(tool, *ref_args)
        check(f"diff.{tool}.{label}", native == ref,
              f"\n  native={json.dumps(native, ensure_ascii=False)[:400]}\n  ref   ={json.dumps(ref, ensure_ascii=False)[:400]}")
    check("edge2.bool-method--32600", b3[6].get("error", {}).get("code") == -32600, str(b3[6]))
    check("edge2.bool-name--32602", b3[7].get("error", {}).get("code") == -32602, str(b3[7]))
    ws8 = tool_payload(b3[8])
    check("edge2.number-args-echoed", ws8.get("root") == 42 and ws8.get("query") == 7, str(ws8)[:200])
    check("edge2.crlf-line-arg--32603", b3[9].get("error", {}).get("code") == -32603, str(b3[9]))
    if junction_ok:
        ws10 = tool_payload(b3[10])
        check("edge2.junction-no-hang-no-dupes",
              ws10.get("count") == 1 and ws10.get("truncated") is False
              and "\\loop\\" not in ws10["symbols"][0]["file"], str(ws10)[:300])
        subprocess.run(["cmd.exe", "/c", "rmdir", jroot_w + "\\loop"], capture_output=True)
    else:
        print("skip junction case (mklink unavailable)")
    check("edge2.null-method--32600", r3[-1].get("error", {}).get("code") == -32600
          and r3[-1].get("id") is None, str(r3[-1]))

    # ================= two concurrent instances =================
    p1 = subprocess.Popen([NATIVE, "mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    p2 = subprocess.Popen([NATIVE, "mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    ini = (rpc("initialize", 1, {"protocolVersion": "x"}) + "\n").encode()
    o1, _ = p1.communicate(ini, timeout=30)
    o2, _ = p2.communicate(ini, timeout=30)
    ok1 = json.loads(o1.decode().strip()).get("result", {}).get("protocolVersion") == "x"
    ok2 = json.loads(o2.decode().strip()).get("result", {}).get("protocolVersion") == "x"
    check("concurrent.two-instances", ok1 and ok2 and p1.returncode == 0 and p2.returncode == 0)

finally:
    # Remove any junction via cmd (unlinks the reparse point only) before the
    # recursive delete, so rmtree can never chase a directory cycle.
    jlink = os.path.join(fixdir, "jx", "loop")
    if os.path.lexists(jlink):
        subprocess.run(["cmd.exe", "/c", "rmdir", wslpath_w(jlink)], capture_output=True)
    shutil.rmtree(fixdir, ignore_errors=True)

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
