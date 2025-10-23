#Requires AutoHotkey v2.0
; ============================================================================
; LLMAnalyzer.ahk
; ============================================================================
; Real-time LLM-powered error analysis using Claude API
; Sends error details to Claude and gets intelligent analysis
; ============================================================================

class LLMAnalyzer {
    static apiKey := ""  ; Set via SetApiKey() before use
    static apiUrl := "https://api.anthropic.com/v1/messages"
    static model := "claude-3-5-sonnet-20241022"
    static timeout := 10000  ; 10 second timeout

    /**
     * Initialize LLM analyzer with API key
     * @param key - Claude API key from environment or config
     */
    static SetApiKey(key) {
        this.apiKey := key
    }

    /**
     * Get LLM analysis of an error
     * @param errorReport - Full error report from GlobalErrorInterceptor
     * @return Analysis string or empty if failed
     */
    static GetErrorAnalysis(errorReport) {
        if (!this.apiKey) {
            return ""  ; Silent fail if no API key
        }

        try {
            ; Build analysis prompt
            prompt := this.BuildAnalysisPrompt(errorReport)

            ; Call Claude API
            response := this.CallClaudeAPI(prompt)

            return response

        } catch Error as err {
            ; Silently fail - don't interrupt error handling
            return ""
        }
    }

    /**
     * Build prompt for LLM analysis
     */
    static BuildAnalysisPrompt(errorReport) {
        return "
(
Analyze this AutoHotkey v2 error and provide:
1. Brief explanation of what went wrong (1-2 sentences)
2. Most likely cause
3. Quick fix or workaround (if obvious)
4. Prevention tips for future

Error Report:
---
" . errorReport . "
---

Be concise and actionable. Format as:
EXPLANATION: ...
CAUSE: ...
FIX: ...
PREVENTION: ...
)"
    }

    /**
     * Call Claude API synchronously
     */
    static CallClaudeAPI(prompt) {
        ; Create HTTP request
        http := ComObject("WinHttp.WinHttpRequest.5.1")

        try {
            ; Open connection
            http.Open("POST", this.apiUrl, false)

            ; Set headers
            http.SetRequestHeader("Content-Type", "application/json")
            http.SetRequestHeader("x-api-key", this.apiKey)
            http.SetRequestHeader("anthropic-version", "2023-06-01")

            ; Build request body
            requestBody := this.BuildRequestBody(prompt)

            ; Send request with timeout
            http.Send(requestBody)

            ; Check response
            if (http.Status != 200) {
                return ""
            }

            ; Parse response
            response := this.ParseResponse(http.ResponseText)
            return response

        } finally {
            http := ""  ; Cleanup
        }
    }

    /**
     * Build JSON request body for Claude API
     */
    static BuildRequestBody(prompt) {
        ; Build JSON manually to avoid string escaping issues
        json := "{"
        json .= "`"model`":`"" . this.model . "`","
        json .= "`"max_tokens`":500,"
        json .= "`"messages`":[{"
        json .= "`"role`":`"user`","
        json .= "`"content`":`"" . this.EscapeJson(prompt) . "`""
        json .= "}]"
        json .= "}"

        return json
    }

    /**
     * Escape string for JSON
     */
    static EscapeJson(str) {
        ; Escape special characters for JSON
        str := StrReplace(str, "\", "\\")
        str := StrReplace(str, """", "\"""")
        str := StrReplace(str, "`n", "\n")
        str := StrReplace(str, "`r", "\r")
        str := StrReplace(str, "`t", "\t")
        return str
    }

    /**
     * Parse Claude API response
     */
    static ParseResponse(responseText) {
        try {
            ; Try to extract content from JSON response
            ; Looking for: "text":"..." in the response

            if (RegExMatch(responseText, '"text"\s*:\s*"([^"]*(?:\\.[^"]*)*)"', &match)) {
                ; Unescape JSON string
                text := match[1]
                text := StrReplace(text, "\n", "`n")
                text := StrReplace(text, "\r", "`r")
                text := StrReplace(text, "\t", "`t")
                text := StrReplace(text, "\\", "\")
                text := StrReplace(text, "\""", """")
                return text
            }

            return ""

        } catch {
            return ""
        }
    }
}

; Auto-initialize from environment variable if available
if (apiKey := EnvGet("CLAUDE_API_KEY")) {
    LLMAnalyzer.SetApiKey(apiKey)
}
