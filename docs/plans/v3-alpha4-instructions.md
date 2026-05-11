# v3 Alpha 4 — Feature Instructions

## Baseline (v3 Alpha 1-3) — What's Already Working

### MCP Server (debugger-tool/mcp-server/)
- Full debugger toolset over DBGp protocol on port 9000
- **Error loop**: `capture_error` → `analyze_error` → `apply_fix`
- **Execution control**: `debug_run`, `debug_step_into`, `debug_step_over`, `debug_step_out`, `debug_stop`, `debug_status`
- **Breakpoints**: `breakpoint_set` (with conditions), `breakpoint_remove`, `breakpoint_list`
- **Inspection**: `variables_get`, `evaluate`, `stack_trace`
- **Source intelligence**: `source_outline`, `workspace_symbols`
- **Raw passthrough**: `debug_command` for arbitrary DBGp commands

### Headless Error Agent (debugger-tool/ahk-error-agent/)
- Captures runtime errors via DBGp without UI
- Outputs JSON or Markdown with full context (source, stack, variables)
- Watch mode (`-w`) for continuous development loops

### Custom AHK Engine (source/)
- `/Headless` — suppresses all dialogs
- `/Diag=json` — structured JSON diagnostics to stdout
- `check script.ahk` — syntax validation
- `test script.ahk` — test runner with pass/fail exit codes
- `_ScriptGetLines()` — programmatic source context retrieval
- Exit code taxonomy: 0/10/11/12/13/14/64

### CloudAHK Error Handlers (debugger-tool/ahk-error-agent/include/)
- `cloudahk-error-handler.ahk` — works with stock AHK v2
- `cloudahk-error-handler-enhanced.ahk` — requires `_ScriptGetLines` build

---

## Feature 1: Claude API Integration

**Goal**: Wire up the Anthropic API inside `analyze_error` so the MCP server can autonomously diagnose errors without relying on the client-side LLM.

**Current state**: `analyze_error` with `use_api: true` returns `"api_not_configured"` (see `mcp-server/src/index.ts:672-686`). The analysis prompt is already constructed — it just needs to be sent to the API.

### Implementation Steps

1. **Add `@anthropic-ai/sdk` dependency**
   ```bash
   cd debugger-tool/mcp-server
   npm install @anthropic-ai/sdk
   ```

2. **Add API key configuration** in `mcp-server/src/index.ts`
   - Read `ANTHROPIC_API_KEY` from environment
   - Fail gracefully if key is missing when `use_api: true` is requested
   - Do not hardcode keys anywhere

3. **Replace the TODO block** at line 672 of `mcp-server/src/index.ts`
   - Import `Anthropic` from the SDK
   - Create client instance (lazy, only when first needed)
   - Send `analysisPrompt` as a user message to `claude-sonnet-4-5-20250929`
   - Parse the JSON response
   - Return the structured diagnosis alongside the raw analysis

   Pseudocode:
   ```typescript
   import Anthropic from '@anthropic-ai/sdk';

   let anthropicClient: Anthropic | null = null;

   function getAnthropicClient(): Anthropic {
     const apiKey = process.env.ANTHROPIC_API_KEY;
     if (!apiKey) throw new Error('ANTHROPIC_API_KEY not set');
     if (!anthropicClient) anthropicClient = new Anthropic({ apiKey });
     return anthropicClient;
   }

   // Inside the use_api block:
   const client = getAnthropicClient();
   const response = await client.messages.create({
     model: 'claude-sonnet-4-5-20250929',
     max_tokens: 1024,
     messages: [{ role: 'user', content: analysisPrompt }],
   });
   const analysisText = response.content[0].type === 'text'
     ? response.content[0].text : '';
   ```

4. **Return structured result**
   ```typescript
   return {
     content: [{
       type: 'text',
       text: JSON.stringify({
         status: 'analyzed',
         error,
         analysis: JSON.parse(analysisText), // parsed diagnosis
         raw_response: analysisText,
       }),
     }],
   };
   ```

5. **Fallback**: If the API call fails (network, auth, quota), return the prompt as before with `status: 'api_error'` and the error message, so the client LLM can still do the analysis.

### Files to Modify
| File | Change |
|------|--------|
| `debugger-tool/mcp-server/src/index.ts` | Import SDK, add client init, replace TODO at L672 |
| `debugger-tool/mcp-server/package.json` | Add `@anthropic-ai/sdk` dependency |

### Testing
- Set `ANTHROPIC_API_KEY` in shell, start MCP server
- Trigger an error in a test AHK script with `/Debug`
- Call `capture_error` → `analyze_error` with `use_api: true`
- Verify JSON diagnosis comes back with `status: 'analyzed'`
- Unset the key and verify graceful fallback with `status: 'api_error'`

---

## Feature 2: Variable Watch / Change Notifications

**Goal**: Automatically detect when watched variables change value during stepping, and surface those changes to the AI client.

**Current state**: `variables_get` fetches all variables in a scope on demand, and `evaluate` can check a single expression. But there is no mechanism to track changes across steps — the client must manually diff snapshots.

### Design

Add a `watch_add` / `watch_remove` / `watch_list` tool set and an internal snapshot-and-diff engine:

```
watch_add("myVar")  →  registers variable for tracking
debug_step_over     →  internally snapshots watched vars
                       returns step result + change list
watch_list          →  shows all watches with current values
watch_remove("myVar")
```

### Implementation Steps

1. **Add watch state** to `mcp-server/src/index.ts`
   ```typescript
   interface WatchEntry {
     name: string;
     lastValue: string | null;
     lastType: string | null;
   }

   const watchList: Map<string, WatchEntry> = new Map();
   ```

2. **Add tool schemas**
   ```typescript
   const WatchAddSchema = z.object({
     name: z.string().describe('Variable name or expression to watch'),
   });
   const WatchRemoveSchema = z.object({
     name: z.string().describe('Variable name or expression to remove'),
   });
   ```

3. **Register tools** in `ListToolsRequestSchema` handler
   - `watch_add` — Add a variable or expression to the watch list
   - `watch_remove` — Remove a watch entry
   - `watch_list` — List all watches with current values and last-changed status

4. **Implement snapshot helper** in `dbgp-client.ts`
   ```typescript
   async snapshotWatches(names: string[]): Promise<Map<string, { value: string; type: string }>> {
     const results = new Map();
     for (const name of names) {
       const value = await this.evaluateExpression(name);
       results.set(name, { value, type: typeof value });
     }
     return results;
   }
   ```

5. **Integrate with step commands** (`debug_step_into`, `debug_step_over`, `debug_step_out`)
   - After each step completes, if `watchList.size > 0`:
     - Snapshot all watched variables via `evaluateExpression`
     - Compare to previous snapshot
     - Build a `changes` array for any values that differ
     - Update stored `lastValue`/`lastType`
   - Append the changes array to the step result

   Example enriched step response:
   ```json
   {
     "status": "break",
     "file": "script.ahk",
     "line": 15,
     "watches": [
       { "name": "counter", "value": "5", "previous": "4", "changed": true },
       { "name": "name", "value": "\"Alice\"", "previous": "\"Alice\"", "changed": false }
     ]
   }
   ```

6. **Implement `watch_list` tool**
   - Snapshot all watches at call time
   - Return current values plus metadata (name, value, type, whether it changed since last snapshot)

### Files to Modify
| File | Change |
|------|--------|
| `debugger-tool/mcp-server/src/index.ts` | Watch state, 3 new tools, step-command integration |
| `debugger-tool/mcp-server/src/dbgp-client.ts` | `snapshotWatches()` helper |

### Testing
- Start MCP server + AHK script with `/Debug`
- `breakpoint_set` on a line inside a loop
- `debug_run` to hit breakpoint
- `watch_add` for the loop counter variable
- `debug_step_over` repeatedly — verify `watches` array in response shows changes
- `watch_list` — verify current values are shown
- `watch_remove` — verify it stops tracking

### Edge Cases to Handle
- Variable not in scope (return `"<undefined>"` or similar)
- Expression evaluation errors (catch and report per-watch)
- Watch list persists across debug sessions (clear on disconnect)
- Large objects — truncate value display to a reasonable length (e.g., 500 chars)

---

## Update V3_MILESTONE_STATUS.md

Once both features are implemented, add this section to `V3_MILESTONE_STATUS.md`:

```markdown
## Milestone 4 (`v3-alpha.4`) Complete

Scope:

- Direct Claude API integration for autonomous error analysis
- Variable watch/change notification system

Implemented:

1. Claude API integration in `analyze_error`:
   - `use_api: true` sends analysis prompt to Anthropic API
   - Graceful fallback when API key missing or call fails
   - Files: `debugger-tool/mcp-server/src/index.ts`
2. Variable watch system:
   - `watch_add`, `watch_remove`, `watch_list` tools
   - Automatic change detection on step commands
   - Files: `debugger-tool/mcp-server/src/index.ts`, `debugger-tool/mcp-server/src/dbgp-client.ts`
```
