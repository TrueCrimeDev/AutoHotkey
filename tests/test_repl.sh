#!/usr/bin/env bash
# End-to-end tests for the `repl` subcommand. Pipe-driven; run from WSL/bash:
#   bash tests/test_repl.sh [path-to-AutoHotkey64.exe]
# Exit 0 = all pass, 1 = failure (mirrors the binary's test-subcommand contract).

set -u
AHK="${1:-/mnt/c/Users/uphol/Documents/Design/Coding/AutoHotkey/bin/AutoHotkey64.exe}"
fails=0

check() { # name expected actual
    if [[ "$2" == "$3" ]]; then
        echo "PASS: $1"
    else
        echo "FAIL: $1"
        echo "  expected: $2"
        echo "  actual:   $3"
        fails=$((fails+1))
    fi
}

# 1. Values, state persistence across lines, compound expressions, clean exit.
out=$(printf '1+2\nx := 10\nx * 4\ny := x ** 2, y + 1\n.exit\n' | "$AHK" repl 2>/dev/null)
rc=$?
check "basic session output" "$(printf '3\n10\n40\n101')" "$out"
check "basic session exit code" "0" "$rc"

# 2. Errors stay in-session: state set before an error survives after it.
out=$(printf 'a := 5\n1 +\nnosuchvar * 2\na + 1\n' | "$AHK" repl 2>/dev/null)
rc=$?
check "errors keep session alive" "$(printf '5\n6')" "$out"
check "EOF exit code" "0" "$rc"
err=$(printf '1 +\n' | "$AHK" repl 2>&1 >/dev/null)
case "$err" in
    SyntaxError:*) echo "PASS: syntax error on stderr" ;;
    *) echo "FAIL: syntax error on stderr"; echo "  actual: $err"; fails=$((fails+1)) ;;
esac

# 3. JSON mode: one stdout line per input line, ok:false for errors.
out=$(printf '6*7\n1 +\nSetTimer(() => 0, 0)\n' | "$AHK" repl /Diag=json 2>/dev/null)
expected='{"kind":"result","ok":true,"type":"Integer","value":"42"}
{"kind":"result","ok":false,"type":"SyntaxError","value":"Missing operand."}
{"kind":"result","ok":true,"type":"Unset","value":""}'
check "json mode" "$expected" "$out"

# 4. ExitApp passthrough.
printf 'ExitApp(7)\n' | "$AHK" repl 2>/dev/null
check "ExitApp exit code" "7" "$?"

# 5. Script-hosted session: globals, functions, classes from the loaded script.
host="$(dirname "$0")/.test-tmp.repl-host.ahk"
cat > "$host" << 'EOF'
#Requires AutoHotkey v2.1-alpha.30
global counter := 100
Bump(n := 1) {
    global counter
    counter += n
    return counter
}
EOF
hostwin=$(wslpath -w "$host")
out=$(printf 'counter\nBump(5)\ncounter\n.exit\n' | "$AHK" repl "$hostwin" 2>/dev/null)
check "script-hosted session" "$(printf '100\n105\n105')" "$out"
rm -f "$host"

echo
if [[ $fails -eq 0 ]]; then
    echo "REPL TESTS: all checks passed"
    exit 0
else
    echo "REPL TESTS: $fails failure(s)"
    exit 1
fi
