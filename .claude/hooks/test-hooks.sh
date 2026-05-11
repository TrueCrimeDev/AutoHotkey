#!/bin/bash
# test-hooks.sh — Test harness for Claude Code hooks
# Exercises each hook with the same JSON payloads Claude Code sends,
# checking exit codes and output content.
# Usage: bash test-hooks.sh

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors (using $'...' for real escape characters)
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[1;33m'
BOLD=$'\033[1m'
NC=$'\033[0m'

PASS=0
FAIL=0
SKIPPED=0

# --- Helpers ---

# Run a hook with CRLF stripped (hooks live on Windows filesystem).
# Stdin is forwarded to the hook. Captures stdout+stderr.
# Usage: out=$(echo "$json" | run_hook "$hook_path" 2>&1); rc=$?
run_hook() {
    bash <(tr -d '\r' < "$1")
}

# --- Assertions ---

assert_exit() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  ${GREEN}PASS${NC} $label"
        PASS=$((PASS + 1))
    else
        echo "  ${RED}FAIL${NC} $label (expected exit $expected, got $actual)"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local label="$1" output="$2" needle="$3"
    if printf '%s' "$output" | grep -qF -- "$needle"; then
        echo "  ${GREEN}PASS${NC} $label"
        PASS=$((PASS + 1))
    else
        echo "  ${RED}FAIL${NC} $label (missing '${needle}')"
        echo "    Got: ${output:0:200}"
        FAIL=$((FAIL + 1))
    fi
}

assert_empty() {
    local label="$1" output="$2"
    if [[ -z "$(printf '%s' "$output" | tr -d '[:space:]')" ]]; then
        echo "  ${GREEN}PASS${NC} $label"
        PASS=$((PASS + 1))
    else
        echo "  ${RED}FAIL${NC} $label (expected silent)"
        echo "    Got: ${output:0:200}"
        FAIL=$((FAIL + 1))
    fi
}

assert_json_eq() {
    local label="$1" output="$2" expected="$3"
    local trimmed
    trimmed=$(printf '%s' "$output" | tr -d '[:space:]')
    if [[ "$trimmed" == "$expected" ]]; then
        echo "  ${GREEN}PASS${NC} $label"
        PASS=$((PASS + 1))
    else
        echo "  ${RED}FAIL${NC} $label (expected '${expected}')"
        echo "    Got: ${trimmed}"
        FAIL=$((FAIL + 1))
    fi
}

skip() {
    local label="$1" reason="$2"
    SKIPPED=$((SKIPPED + 1))
    echo "  ${YELLOW}SKIP${NC} $label ($reason)"
}

# --- Prerequisites ---

echo "${BOLD}Prerequisites${NC}"

if ! command -v jq &>/dev/null; then
    echo "  ${RED}FATAL: jq is required but not installed${NC}"
    exit 1
fi
echo "  jq: found"

CUSTOM_AHK="/mnt/c/Users/uphol/Documents/Design/Coding/AutoHotkey/bin/AutoHotkey64.exe"
STOCK_AHK="/mnt/c/Program Files/AutoHotkey/v2/AutoHotkey64.exe"
AHK_AVAILABLE=false

if [[ -f "$CUSTOM_AHK" ]]; then
    echo "  AHK: custom engine found"
    AHK_AVAILABLE=true
elif [[ -f "$STOCK_AHK" ]]; then
    echo "  ${YELLOW}AHK: stock only (custom engine not found)${NC}"
    AHK_AVAILABLE=true
else
    echo "  ${YELLOW}AHK: not found — post-edit syntax tests will skip${NC}"
fi

# Temp .ahk files on Windows filesystem so AHK engine can access them
WIN_TEMP="/mnt/c/Users/uphol/AppData/Local/Temp"
VALID_AHK=$(mktemp "${WIN_TEMP}/test-valid-XXXX.ahk")
INVALID_AHK=$(mktemp "${WIN_TEMP}/test-invalid-XXXX.ahk")
trap 'rm -f "$VALID_AHK" "$INVALID_AHK"' EXIT

printf 'MsgBox "Hello"\n' > "$VALID_AHK"
printf 'MsgBox(\n' > "$INVALID_AHK"

# Pre-flight: verify the hook can actually validate a file.
# The hook delegates to the AHK engine; if the engine's check command
# can't resolve paths (known issue with some custom builds), skip.
AHK_CHECK_WORKS=false
if $AHK_AVAILABLE; then
    probe_out=$(printf '{"tool_input":{"file_path":"%s"}}' "$VALID_AHK" \
        | run_hook "$HOOKS_DIR/ahk-post-edit.sh" 2>&1); probe_rc=$?
    if [[ $probe_rc -eq 0 ]]; then
        AHK_CHECK_WORKS=true
        echo "  AHK check: ${GREEN}working${NC}"
    else
        echo "  ${YELLOW}AHK check: engine can't validate temp files (check subcommand issue)${NC}"
        echo "  ${YELLOW}  Post-edit syntax tests will skip; other tests unaffected${NC}"
    fi
fi

echo ""

# ============================================================
# Hook 1: ahk-post-edit.sh (8 tests)
# ============================================================
echo "${BOLD}=== ahk-post-edit.sh (8 tests) ===${NC}"
HOOK="$HOOKS_DIR/ahk-post-edit.sh"

# 1-2: Valid .ahk file → exit 0, silent
if $AHK_CHECK_WORKS; then
    out=$(printf '{"tool_input":{"file_path":"%s"}}' "$VALID_AHK" | run_hook "$HOOK" 2>&1); rc=$?
    assert_exit "valid .ahk → exit 0" 0 "$rc"
    assert_empty "valid .ahk → silent" "$out"
else
    skip "valid .ahk → exit 0" "AHK check unavailable"
    skip "valid .ahk → silent" "AHK check unavailable"
fi

# 3-5: Invalid .ahk file → exit 1, output contains "decision" and "block"
if $AHK_CHECK_WORKS; then
    out=$(printf '{"tool_input":{"file_path":"%s"}}' "$INVALID_AHK" | run_hook "$HOOK" 2>&1); rc=$?
    assert_exit "invalid .ahk → exit 1" 1 "$rc"
    assert_contains "invalid .ahk → has decision" "$out" '"decision"'
    assert_contains "invalid .ahk → has block" "$out" 'block'
else
    skip "invalid .ahk → exit 1" "AHK check unavailable"
    skip "invalid .ahk → has decision" "AHK check unavailable"
    skip "invalid .ahk → has block" "AHK check unavailable"
fi

# 6-7: .txt file → exit 0, silent (non-.ahk files are skipped)
out=$(printf '{"tool_input":{"file_path":"/tmp/test.txt"}}' | run_hook "$HOOK" 2>&1); rc=$?
assert_exit ".txt file → exit 0" 0 "$rc"
assert_empty ".txt file → silent" "$out"

# 8: Empty JSON → exit 0 (no file_path = skip)
out=$(printf '{}' | run_hook "$HOOK" 2>&1); rc=$?
assert_exit "empty JSON → exit 0" 0 "$rc"

# ============================================================
# Hook 2: ahk-debug-context.sh (8 tests)
# ============================================================
echo ""
echo "${BOLD}=== ahk-debug-context.sh (8 tests) ===${NC}"
HOOK="$HOOKS_DIR/ahk-debug-context.sh"

out=$(printf '' | run_hook "$HOOK" 2>&1); rc=$?
assert_exit "exits 0" 0 "$rc"
assert_contains "mentions MCP" "$out" "MCP"
assert_contains "mentions debug_run" "$out" "debug_run"
assert_contains "mentions capture_error" "$out" "capture_error"
assert_contains "mentions watch_add" "$out" "watch_add"
assert_contains "mentions analyze_error" "$out" "analyze_error"
assert_contains "mentions apply_fix" "$out" "apply_fix"
assert_contains "mentions AHK v2" "$out" "AHK v2"

# ============================================================
# Hook 3: check-ahk-connection.sh (5 tests)
# ============================================================
echo ""
echo "${BOLD}=== check-ahk-connection.sh (5 tests) ===${NC}"
HOOK="$HOOKS_DIR/check-ahk-connection.sh"

# debug_run → additionalContext with /Debug hint
out=$(printf '{"tool_name":"mcp__autohotkey-debug__debug_run"}' | run_hook "$HOOK" 2>&1); rc=$?
assert_contains "debug_run → additionalContext" "$out" "additionalContext"
assert_contains "debug_run → /Debug hint" "$out" "/Debug"

# capture_error → additionalContext
out=$(printf '{"tool_name":"mcp__autohotkey-debug__capture_error"}' | run_hook "$HOOK" 2>&1); rc=$?
assert_contains "capture_error → additionalContext" "$out" "additionalContext"

# breakpoint_set → additionalContext
out=$(printf '{"tool_name":"mcp__autohotkey-debug__breakpoint_set"}' | run_hook "$HOOK" 2>&1); rc=$?
assert_contains "breakpoint_set → additionalContext" "$out" "additionalContext"

# Non-debug tool → empty pass-through ({})
out=$(printf '{"tool_name":"some_other_tool"}' | run_hook "$HOOK" 2>&1); rc=$?
assert_json_eq "non-debug tool → {}" "$out" "{}"

# ============================================================
# Hook 4: post-capture-guidance.sh (9 tests)
# ============================================================
echo ""
echo "${BOLD}=== post-capture-guidance.sh (9 tests) ===${NC}"
HOOK="$HOOKS_DIR/post-capture-guidance.sh"

# capture_error + timeout → mentions "timed out"
out=$(echo '{"tool_name":"mcp__autohotkey-debug__capture_error","tool_output":"{\"status\":\"timeout\"}"}' \
    | run_hook "$HOOK" 2>&1); rc=$?
assert_contains "capture_error timeout → timed out" "$out" "timed out"

# capture_error + error → mentions "analyze_error" and "apply_fix"
out=$(echo '{"tool_name":"mcp__autohotkey-debug__capture_error","tool_output":"{\"error_type\":\"ValueError\"}"}' \
    | run_hook "$HOOK" 2>&1); rc=$?
assert_contains "capture_error success → analyze_error" "$out" "analyze_error"
assert_contains "capture_error success → apply_fix" "$out" "apply_fix"

# analyze_error + status:"analyzed" → mentions "apply_fix"
out=$(echo '{"tool_name":"mcp__autohotkey-debug__analyze_error","tool_output":"{\"status\":\"analyzed\"}"}' \
    | run_hook "$HOOK" 2>&1); rc=$?
assert_contains "analyze_error analyzed → apply_fix" "$out" "apply_fix"

# analyze_error + status:"api_error" → mentions "analyze the error yourself"
out=$(echo '{"tool_name":"mcp__autohotkey-debug__analyze_error","tool_output":"{\"status\":\"api_error\"}"}' \
    | run_hook "$HOOK" 2>&1); rc=$?
assert_contains "analyze_error api_error → analyze yourself" "$out" "analyze the error yourself"

# analyze_error + prompt only (no status) → mentions "client-side"
out=$(echo '{"tool_name":"mcp__autohotkey-debug__analyze_error","tool_output":"{\"prompt\":\"Analyze this\"}"}' \
    | run_hook "$HOOK" 2>&1); rc=$?
assert_contains "analyze_error prompt → client-side" "$out" "client-side"

# apply_fix + success → mentions "re-run"
out=$(echo '{"tool_name":"mcp__autohotkey-debug__apply_fix","tool_output":"{\"success\":true}"}' \
    | run_hook "$HOOK" 2>&1); rc=$?
assert_contains "apply_fix success → re-run" "$out" "re-run"

# apply_fix + failure → mentions "mismatch"
out=$(echo '{"tool_name":"mcp__autohotkey-debug__apply_fix","tool_output":"{\"success\":false}"}' \
    | run_hook "$HOOK" 2>&1); rc=$?
assert_contains "apply_fix failure → mismatch" "$out" "mismatch"

# Unrelated tool → empty pass-through ({})
out=$(echo '{"tool_name":"some_other_tool","tool_output":"{}"}' \
    | run_hook "$HOOK" 2>&1); rc=$?
assert_json_eq "unrelated tool → {}" "$out" "{}"

# ============================================================
# Summary
# ============================================================
echo ""
echo "${BOLD}========================================${NC}"
TOTAL=$((PASS + FAIL))
if [[ $FAIL -eq 0 && $SKIPPED -eq 0 ]]; then
    echo "${GREEN}ALL TESTS PASSED: ${PASS}/${TOTAL}${NC}"
elif [[ $FAIL -eq 0 ]]; then
    echo "${GREEN}PASSED: ${PASS}/${TOTAL}${NC} (${YELLOW}${SKIPPED} skipped${NC})"
else
    printf "${RED}FAILED: %d/%d passed, %d failed${NC}" "$PASS" "$TOTAL" "$FAIL"
    [[ $SKIPPED -gt 0 ]] && printf " (${YELLOW}%d skipped${NC})" "$SKIPPED"
    printf "\n"
fi
echo "${BOLD}========================================${NC}"

exit "$FAIL"
