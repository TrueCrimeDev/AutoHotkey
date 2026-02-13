# LLM-Powered Error Interception Setup

## Overview

The error interception system now includes real-time Claude AI analysis of errors. When an error occurs, it's immediately sent to Claude API for intelligent analysis and suggestions.

## Setup Steps

### 1. Get Claude API Key

1. Visit [claude.ai/account/keys](https://claude.ai/account/keys)
2. Create a new API key
3. Copy the key (you won't be able to see it again)

### 2. Set Environment Variable

Set `CLAUDE_API_KEY` environment variable with your API key:

**Windows (CMD):**
```cmd
setx CLAUDE_API_KEY "your-api-key-here"
```

**Windows (PowerShell):**
```powershell
[Environment]::SetEnvironmentVariable("CLAUDE_API_KEY", "your-api-key-here", [EnvironmentVariableTarget]::User)
```

**After setting, restart your terminal/IDE** for the change to take effect.

### 3. Verify Setup

Run `ErrorInterceptor.ahk` and check the Configuration section. If you see:
```
LLM Analysis: ENABLED (requires CLAUDE_API_KEY env var)
```

Then LLM integration is ready. If you see:
```
LLM Analysis: ENABLED (requires CLAUDE_API_KEY env var)
```

but no API key is set, the system will silently fall back to basic error reporting.

## Usage

### Enable/Disable LLM Analysis

In `ErrorInterceptor.ahk`, modify the configuration:

```autohotkey
class ErrorConfig {
    static enableLLMAnalysis := true    ; Set to false to disable
    static llmAnalysisTimeout := 5000   ; Max wait (ms)
}
```

### What LLM Analysis Provides

When an error occurs, Claude analyzes it and provides:
1. **Explanation** - What went wrong (1-2 sentences)
2. **Cause** - Most likely root cause
3. **Fix** - Quick fix or workaround if obvious
4. **Prevention** - Tips to prevent in future

Example output:
```
EXPLANATION: Attempted to divide 100 by zero, which is mathematically undefined.
CAUSE: The denominator variable was set to 0 without validation.
FIX: Add a check before division: if (denominator != 0) result := numerator / denominator
PREVENTION: Validate numeric inputs before arithmetic operations
```

### Integrating with Your Scripts

In any AutoHotkey script, simply include ErrorInterceptor at the top:

```autohotkey
#Include ErrorInterceptor.ahk

; Your script code here...
```

## How It Works

1. **Error Occurs** → Caught by `OnError()` callback
2. **Report Generated** → Stack trace, file location, timestamp
3. **LLM Analysis** → Sent to Claude API (with 5-second timeout)
4. **Display** → Error GUI shows both report and analysis
5. **Logging** → All errors logged to timestamped files
6. **Monitoring** → GlobalErrorMonitor watches logs and alerts

## Architecture

```
AutoHotkey Script
     ↓ (error occurs)
GlobalErrorInterceptor.HandleError()
     ↓
BuildErrorReport()
     ↓
LLMAnalyzer.GetErrorAnalysis()  ←→  Claude API
     ↓
DisplayErrorDialog() (shows report + analysis)
     ↓
LogToFile()
     ↓
GlobalErrorMonitor watches & alerts
```

## Configuration

### ErrorConfig in ErrorInterceptor.ahk

| Setting | Default | Description |
|---------|---------|-------------|
| `enableLogging` | true | Write errors to log files |
| `logDirectory` | `./logs` | Where to store error logs |
| `showStackTrace` | true | Include stack trace in dialog |
| `maxStackDepth` | 10 | Max stack frames to display |
| `enableLLMAnalysis` | true | Get Claude analysis of errors |
| `llmAnalysisTimeout` | 5000 | Max wait for API response (ms) |

### LLMAnalyzer in LLMAnalyzer.ahk

| Setting | Default | Description |
|---------|---------|-------------|
| `apiKey` | "" | Claude API key (auto-loaded from env) |
| `apiUrl` | Claude v1 endpoint | API endpoint for requests |
| `model` | claude-3-5-sonnet | Claude model to use |
| `timeout` | 10000 | HTTP request timeout (ms) |

## Troubleshooting

### API Key Not Found
- Ensure `CLAUDE_API_KEY` environment variable is set
- Restart IDE/terminal after setting the variable
- Check: `echo %CLAUDE_API_KEY%` (cmd) or `$env:CLAUDE_API_KEY` (PowerShell)

### LLM Analysis Not Appearing
- Check if `enableLLMAnalysis` is true in ErrorConfig
- Verify API key is set (see above)
- Check if timeout is too short (increase `llmAnalysisTimeout`)
- API might be slow - allow up to 5 seconds for response

### Slow Error Dialogs
- LLM analysis is synchronous and may take 1-5 seconds
- Set `llmAnalysisTimeout` lower if you want faster display
- Set `enableLLMAnalysis := false` to disable LLM calls

### API Rate Limits
- Claude API has rate limits
- Errors will silently fail without disrupting script execution
- Check [Anthropic dashboard](https://console.anthropic.com) for usage

## Security Notes

- **API Key**: Never commit `CLAUDE_API_KEY` to version control
- **Error Data**: Error reports may contain sensitive information
- **Network**: Errors are sent to Anthropic servers
- **Disable if Needed**: Set `enableLLMAnalysis := false` if concerned

## Examples

### Example 1: Test with Division by Zero
1. Run `ErrorInterceptor.ahk`
2. Click "1. Division by Zero"
3. Wait 1-5 seconds for LLM analysis
4. See error report + Claude's analysis

### Example 2: Monitor Multiple Scripts
1. Run `GlobalErrorMonitor.ahk` (stays in background)
2. Run any script that includes `ErrorInterceptor.ahk`
3. When errors occur, monitor shows notifications
4. Click tray icon to view recent errors

### Example 3: Custom Script with Error Handling
```autohotkey
#Include ErrorInterceptor.ahk

TestFunction() {
    x := 10
    y := 0
    result := x / y  ; Error will be caught & analyzed by Claude
}

TestFunction()
```

## API Costs

Claude API is billed per 1M tokens. Error analysis typically uses 500-1000 tokens per error:
- Input: ~400 tokens (error report)
- Output: ~200 tokens (analysis)
- Cost: ~$0.001 - $0.003 per error analyzed

## Disabling LLM Analysis

To use basic error interception without LLM:

```autohotkey
class ErrorConfig {
    static enableLLMAnalysis := false  ; Disable LLM analysis
}
```

Or comment out the #Include:
```autohotkey
; #Include LLMAnalyzer.ahk
```

## Next Steps

1. Set `CLAUDE_API_KEY` environment variable
2. Run `ErrorInterceptor.ahk` to test
3. Try different error scenarios
4. Integrate into your own scripts
5. Run `GlobalErrorMonitor.ahk` for background monitoring
