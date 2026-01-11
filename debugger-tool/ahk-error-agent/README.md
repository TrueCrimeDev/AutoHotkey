# AHK Error Agent

Headless AutoHotkey error capture for AI coding agents. Captures runtime errors with full context and outputs AI-readable reports for automated code fixing.

## Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     AI Coding Workflow                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. AI Agent writes/modifies AHK code                       │
│                    ↓                                         │
│  2. Script runs with: AutoHotkey.exe /Debug script.ahk      │
│                    ↓                                         │
│  3. Error Agent captures exceptions automatically            │
│                    ↓                                         │
│  4. Structured report sent back to AI Agent                 │
│                    ↓                                         │
│  5. AI reads error context, fixes the code                  │
│                    ↓                                         │
│  6. Repeat until success                                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Installation

```bash
cd debugger-tool/ahk-error-agent
npm install
npm run build
```

## Usage

### Basic Usage

Start the error agent:

```bash
# Output markdown to stdout
npm start

# Or after global install
ahk-error-agent
```

Then run your AutoHotkey script:

```bash
AutoHotkey.exe /Debug your_script.ahk
```

When an error occurs, the agent captures it and outputs a detailed report.

### Command Line Options

```
Options:
  -p, --port <number>      Port to listen on (default: 9000)
  -f, --format <type>      Output format: json, markdown, both (default: markdown)
  -o, --output <file>      Write output to file instead of stdout
  -w, --watch              Watch mode - restart after each session
  -g, --no-globals         Don't include global variables in report
  -d, --depth <number>     Max property inspection depth (default: 2)
  -v, --verbose            Verbose logging to stderr
  -h, --help               Show this help
```

### Examples

```bash
# JSON output to file (ideal for AI consumption)
ahk-error-agent -f json -o errors.json

# Watch mode for continuous development
ahk-error-agent -w -v

# Pipe directly to another process
ahk-error-agent -f json | your-ai-agent

# Write to file that AI agent monitors
ahk-error-agent -f markdown -o /tmp/ahk-errors.md -w
```

## Output Format

### Markdown Output

```markdown
## Runtime Error Report

**Timestamp:** 2024-01-15T10:30:45.123Z
**Script:** `C:/scripts/example.ahk`

### Error Details

- **Type:** RuntimeException
- **Message:** This value of type "Object" has no property named "email"
- **Location:** `C:/scripts/example.ahk:47`

### Source Code Context

    42: ProcessUser(user) {
    43:     name := user.name
    44:     id := user.id
    45:
    46:     ; Try to get email
>>> 47:     result := user.email    ; ERROR HERE
    48:     return result
    49: }

### Stack Trace

| Level | Function | Location |
|-------|----------|----------|
| 0 | ProcessUser | example.ahk:47 |
| 1 | Main | example.ahk:12 |

### Local Variables

- **user** (Object): `[Object]`
- **name** (String): `John Doe`
- **id** (Integer): `123`

### Suggested Fix

The property "email" does not exist on the object.
Check if the object was properly initialized.
Available local variables: user, name, id
```

### JSON Output

```json
{
  "timestamp": "2024-01-15T10:30:45.123Z",
  "script": "C:/scripts/example.ahk",
  "error": {
    "type": "RuntimeException",
    "message": "This value of type \"Object\" has no property named \"email\"",
    "line": 47,
    "file": "C:/scripts/example.ahk",
    "sourceCode": ">>> 47:     result := user.email"
  },
  "stackTrace": [
    { "level": 0, "type": "file", "filename": "example.ahk", "lineno": 47, "where": "ProcessUser" },
    { "level": 1, "type": "file", "filename": "example.ahk", "lineno": 12, "where": "Main" }
  ],
  "variables": {
    "local": [
      { "name": "user", "type": "Object", "value": "[Object]" },
      { "name": "name", "type": "String", "value": "John Doe" },
      { "name": "id", "type": "Integer", "value": "123" }
    ],
    "global": []
  },
  "context": {
    "surroundingCode": ["...", ">>> 47: result := user.email", "..."],
    "suggestion": "The property \"email\" does not exist on the object."
  }
}
```

## Integration with AI Agents

### File-Based Integration

```bash
# Terminal 1: Run error agent
ahk-error-agent -f json -o /tmp/ahk-errors.json -w -v

# Terminal 2: AI agent monitors the file
# When errors.json changes, AI reads it and fixes the code
```

### Pipe Integration

```bash
# Pipe error reports directly to an AI CLI tool
ahk-error-agent -f json | ai-code-fixer --lang autohotkey
```

### Programmatic Integration

```typescript
import { spawn } from 'child_process';

// Start error agent as subprocess
const agent = spawn('ahk-error-agent', ['-f', 'json']);

agent.stdout.on('data', (data) => {
  const report = JSON.parse(data.toString());

  // Send to AI for analysis
  const fix = await ai.analyzeError(report);

  // Apply fix
  applyFix(report.error.file, fix);
});

// Run the AHK script
spawn('AutoHotkey.exe', ['/Debug', 'script.ahk']);
```

### Claude Code Integration

Add to your workflow:

1. Error agent runs in background: `ahk-error-agent -f markdown -o errors.md -w`
2. When testing AHK scripts, run with `/Debug` flag
3. If error occurs, read `errors.md` for full context
4. AI can read the structured error report and fix the code

## How It Works

1. **Listens** on port 9000 for AutoHotkey debug connections
2. **Sets exception breakpoint** to catch all runtime errors
3. **Runs** the script until completion or error
4. **Captures** on error:
   - Full stack trace
   - Local and global variables
   - Surrounding source code
   - Error message and type
5. **Outputs** structured report for AI consumption
6. **Repeats** in watch mode for continuous development

## Protocol

Uses the DBGp (Debug Protocol) - same as Xdebug, Komodo IDE, etc.

Key commands used:
- `breakpoint_set -t exception` - Catch all exceptions
- `run` - Execute script
- `stack_get` - Get call stack
- `context_get` - Get variables
- `source` - Get source code

## Requirements

- Node.js 18+
- AutoHotkey v2 (with debug support)

## License

MIT
