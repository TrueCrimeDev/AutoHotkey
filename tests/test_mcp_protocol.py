"""Native MCP envelope regressions; stdlib only, bounded subprocess per exchange.

Protocol: https://modelcontextprotocol.io/specification/2025-06-18/basic
Lifecycle: https://modelcontextprotocol.io/specification/2025-06-18/basic/lifecycle
Usage: python tests/test_mcp_protocol.py [AutoHotkey.exe]
"""
import json
from pathlib import Path
import subprocess
import sys
import unittest

EXE = Path(sys.argv.pop(1) if len(sys.argv) > 1 and not sys.argv[1].startswith("-")
           else "bin/AutoHotkey64.exe").resolve()


def request(method="ping", id=1, **fields):
    return {"jsonrpc": "2.0", "id": id, "method": method, **fields}


def init_params(version="2025-06-18"):
    return {"protocolVersion": version, "capabilities": {},
            "clientInfo": {"name": "protocol-regression", "version": "1"}}


class McpProtocolTests(unittest.TestCase):
    def exchange(self, *messages):
        data = "".join((m if isinstance(m, str) else json.dumps(m)) + "\n" for m in messages)
        r = subprocess.run([str(EXE), "mcp"], input=data, capture_output=True,
                           text=True, encoding="utf-8", errors="strict", timeout=8,
                           creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stderr, "")
        return [json.loads(line) for line in r.stdout.splitlines()]

    def assert_error(self, message, code, id=None):
        rows = self.exchange(message)
        self.assertEqual(len(rows), 1, rows)
        self.assertEqual(rows[0]["jsonrpc"], "2.0")
        self.assertEqual(rows[0]["id"], id)
        self.assertEqual(rows[0].get("error", {}).get("code"), code, rows)

    def test_jsonrpc_version_is_required_and_exact(self):
        for version in (None, "1.0", 2, True):
            with self.subTest(version=version):
                message = request()
                if version is None:
                    del message["jsonrpc"]
                else:
                    message["jsonrpc"] = version
                self.assert_error(message, -32600, 1)

    def test_initial_utf8_bom_from_powershell_is_accepted_once(self):
        rows = self.exchange("\ufeff" + json.dumps(request(id=1)), request(id=2),
                             "\ufeff" + json.dumps(request(id=3)))
        self.assertEqual(rows[0], {"jsonrpc":"2.0", "id":1, "result":{}})
        self.assertEqual(rows[1], {"jsonrpc":"2.0", "id":2, "result":{}})
        self.assertEqual(rows[2]["error"]["code"], -32700)

    def test_ids_are_strings_or_integers(self):
        for id in (None, True, [], {}, 1.5):
            with self.subTest(id=id):
                self.assert_error(request(id=id), -32600)
        for id in (0, -4, "", "request-α", 123456789012345678901234567890):
            with self.subTest(id=id):
                rows = self.exchange(request(id=id))
                self.assertEqual(rows[0]["id"], id)
                self.assertEqual(rows[0]["result"], {})

    def test_known_notifications_do_not_emit_responses_or_run_tools(self):
        messages = [{"jsonrpc": "2.0", "method": method} for method in
                    ("ping", "tools/list", "initialize", "notifications/initialized", "unknown")]
        messages += [{"jsonrpc": "2.0", "method": "tools/call", "params": {"name": "server_status"}},
                     request(id="last"), request("tools/call", id="status", params={"name": "server_status"})]
        rows = self.exchange(*messages)
        self.assertEqual(len(rows), 2, rows)
        self.assertEqual(rows[0], {"jsonrpc": "2.0", "id": "last", "result": {}})
        self.assertEqual(rows[1]["id"], "status")
        status = json.loads(rows[1]["result"]["content"][0]["text"])
        self.assertEqual(status["toolCalls"]["server_status"], 1)

    def test_initialize_validates_required_fields(self):
        bad = [None, {}, {**init_params(), "protocolVersion": 9},
               {**init_params(), "protocolVersion": ""},
               {**init_params(), "capabilities": []},
               {**init_params(), "clientInfo": {}},
               {**init_params(), "clientInfo": {"name": "client", "version": 1}}]
        for params in bad:
            with self.subTest(params=params):
                self.assert_error(request("initialize", params=params), -32602, 1)

    def test_initialize_negotiates_only_supported_versions(self):
        for proposed, expected in (("2025-06-18", "2025-06-18"),
                                   ("2024-11-05", "2024-11-05"),
                                   ("2099-01-01", "2025-06-18")):
            with self.subTest(proposed=proposed):
                rows = self.exchange(request("initialize", params=init_params(proposed)))
                self.assertEqual(rows[0]["result"]["protocolVersion"], expected)
                self.assertEqual(rows[0]["result"]["capabilities"], {"tools": {}})

    def test_invalid_methods_and_params_report_protocol_errors(self):
        self.assert_error(request(method=42), -32600, 1)
        self.assert_error(request(method="missing"), -32601, 1)
        self.assert_error(request(params=[]), -32602, 1)
        self.assert_error(request("tools/call", params={"name": "server_status", "arguments": []}), -32602, 1)
        self.assert_error(request("notifications/initialized"), -32601, 1)

    def test_parse_errors_do_not_kill_session(self):
        rows = self.exchange('{"jsonrpc":', request(id="after-error"))
        self.assertEqual(rows[0]["error"]["code"], -32700)
        self.assertEqual(rows[1]["id"], "after-error")

    def test_invalid_json_numbers_and_control_characters_are_parse_errors(self):
        for raw in ('{"jsonrpc":"2.0","id":01,"method":"ping"}',
                    '{"jsonrpc":"2.0","id":1.,"method":"ping"}',
                    '{"jsonrpc":"2.0","id":1,"method":"pi\tng"}'):
            with self.subTest(raw=raw):
                self.assert_error(raw, -32700)

    def test_integral_number_ids_round_trip_without_float_conversion(self):
        for lexeme in ("1.0", "1e3", "100e-2", "1e100"):
            with self.subTest(lexeme=lexeme):
                rows = self.exchange('{"jsonrpc":"2.0","id":' + lexeme + ',"method":"ping"}')
                self.assertEqual(rows[0]["id"], json.loads(lexeme))
                self.assertEqual(rows[0]["result"], {})


if __name__ == "__main__":
    unittest.main()
