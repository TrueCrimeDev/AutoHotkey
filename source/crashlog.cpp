#include "stdafx.h"
#include "crashlog.h"
#include "globaldata.h"
#include "ahkversion.h"

namespace
{
    LPTSTR s_crash_path = nullptr;
    LPTSTR s_stderr_path = nullptr;
    CRITICAL_SECTION s_lock;
    bool s_lock_initialized = false;

    void EnsureLock()
    {
        if (!s_lock_initialized)
        {
            InitializeCriticalSection(&s_lock);
            s_lock_initialized = true;
        }
    }

    // Append a complete UTF-8 record to the path specified. Open-write-flush-close.
    // Silent no-op if path is null or open fails. NOT reentrant; caller holds s_lock.
    void AppendRaw(LPCTSTR aPath, const char *aBytes, DWORD aLen)
    {
        if (!aPath || aLen == 0) return;
        HANDLE h = CreateFile(aPath,
                              FILE_APPEND_DATA,
                              FILE_SHARE_READ | FILE_SHARE_WRITE,
                              nullptr,
                              OPEN_ALWAYS,
                              FILE_ATTRIBUTE_NORMAL,
                              nullptr);
        if (h == INVALID_HANDLE_VALUE) return;
        DWORD written = 0;
        WriteFile(h, aBytes, aLen, &written, nullptr);
        FlushFileBuffers(h);
        CloseHandle(h);
    }

    // Format a [TAG] line with timestamp + kv pairs. Returns bytes written into aBuf.
    // aBuf must be UTF-8 sized; caller picks (4 KB is plenty for one event header).
    DWORD FormatHeader(char *aBuf, size_t aBufSize, const char *aTag, const char *aRest)
    {
        SYSTEMTIME st;
        GetLocalTime(&st);
        int n = _snprintf_s(aBuf, aBufSize, _TRUNCATE,
            "[%04d-%02d-%02d %02d:%02d:%02d] [%s] %s\n",
            st.wYear, st.wMonth, st.wDay,
            st.wHour, st.wMinute, st.wSecond,
            aTag, aRest);
        return n > 0 ? (DWORD)n : 0;
    }

    // Convert a TCHAR string to a UTF-8 buffer the caller provides.
    // Returns number of bytes written (incl. trailing NUL) or 0 on failure / null input.
    int TToUtf8(LPCTSTR aSrc, char *dst_buf, int dst_cap)
    {
        if (!aSrc) { if (dst_cap > 0) dst_buf[0] = 0; return 0; }
        int n = WideCharToMultiByte(CP_UTF8, 0, aSrc, -1, dst_buf, dst_cap, nullptr, nullptr);
        return n > 0 ? n : 0;
    }
}

void CrashLog::SetCrashLogPath(LPCTSTR aPath)
{
    EnsureLock();
    free(s_crash_path);
    s_crash_path = aPath ? _tcsdup(aPath) : nullptr;
}

void CrashLog::SetStdErrFilePath(LPCTSTR aPath)
{
    EnsureLock();
    free(s_stderr_path);
    s_stderr_path = aPath ? _tcsdup(aPath) : nullptr;
}

bool CrashLog::IsCrashLogEnabled()  { return s_crash_path != nullptr; }
bool CrashLog::IsStdErrFileEnabled(){ return s_stderr_path != nullptr; }

void CrashLog::LogStart(LPCTSTR aScriptPath, LPCTSTR aCmdLine)
{
    EnsureLock();
    if (!s_crash_path) return;
    EnterCriticalSection(&s_lock);

    char script_u8[1024] = {};
    char cmdline_u8[2048] = {};
    TToUtf8(aScriptPath, script_u8, sizeof(script_u8));
    TToUtf8(aCmdLine,    cmdline_u8, sizeof(cmdline_u8));

    char rest[3500];
    _snprintf_s(rest, sizeof(rest), _TRUNCATE,
        "pid=%lu ahk=%s script=%s cmdline=\"%s\"",
        GetCurrentProcessId(),
        RAW_AHK_VERSION,
        script_u8, cmdline_u8);

    char header[4096];
    DWORD n = FormatHeader(header, sizeof(header), "START", rest);
    AppendRaw(s_crash_path, header, n);

    LeaveCriticalSection(&s_lock);
}

void CrashLog::LogParse(LPCTSTR aFile, int aLine, LPCTSTR aMessage)
{
    EnsureLock();
    if (!s_crash_path) return;
    EnterCriticalSection(&s_lock);

    char file_u8[1024] = {}, msg_u8[2048] = {};
    TToUtf8(aFile, file_u8, sizeof(file_u8));
    TToUtf8(aMessage, msg_u8, sizeof(msg_u8));

    char rest[1280];
    _snprintf_s(rest, sizeof(rest), _TRUNCATE,
        "pid=%lu file=%s line=%d",
        GetCurrentProcessId(), file_u8, aLine);

    char header[1536];
    DWORD n = FormatHeader(header, sizeof(header), "PARSE", rest);
    AppendRaw(s_crash_path, header, n);

    char body[2560];
    int bn = _snprintf_s(body, sizeof(body), _TRUNCATE,
        "  Message: %s\n", msg_u8);
    if (bn > 0)
        AppendRaw(s_crash_path, body, (DWORD)bn);

    LeaveCriticalSection(&s_lock);
}

void CrashLog::LogError(LPCTSTR aType, LPCTSTR aMode, LPCTSTR aMessage,
                        LPCTSTR aFile, int aLine, LPCTSTR aWhat, LPCTSTR aExtra,
                        LPCTSTR aStack)
{
    EnsureLock();
    if (!s_crash_path) return;
    EnterCriticalSection(&s_lock);

    char type_u8[128] = {}, mode_u8[64] = {};
    char msg_u8[2048] = {}, file_u8[1024] = {};
    char what_u8[256] = {}, extra_u8[2048] = {};
    char stack_u8[8192] = {};
    TToUtf8(aType,    type_u8,   sizeof(type_u8));
    TToUtf8(aMode,    mode_u8,   sizeof(mode_u8));
    TToUtf8(aMessage, msg_u8,    sizeof(msg_u8));
    TToUtf8(aFile,    file_u8,   sizeof(file_u8));
    TToUtf8(aWhat,    what_u8,   sizeof(what_u8));
    TToUtf8(aExtra,   extra_u8,  sizeof(extra_u8));
    TToUtf8(aStack,   stack_u8,  sizeof(stack_u8));

    char rest[256];
    _snprintf_s(rest, sizeof(rest), _TRUNCATE,
        "pid=%lu type=%s mode=%s",
        GetCurrentProcessId(), type_u8, mode_u8);

    char header[1024];
    DWORD n = FormatHeader(header, sizeof(header), "ERROR", rest);
    AppendRaw(s_crash_path, header, n);

    // Indented continuation lines.
    char body[16384];
    int bn = _snprintf_s(body, sizeof(body), _TRUNCATE,
        "  Message: %s\n"
        "  File: %s\n"
        "  Line: %d\n"
        "  What: %s\n"
        "  Extra: %s\n"
        "  Stack:\n%s",
        msg_u8, file_u8, aLine, what_u8, extra_u8, stack_u8);
    if (bn > 0)
        AppendRaw(s_crash_path, body, (DWORD)bn);

    LeaveCriticalSection(&s_lock);
}

void CrashLog::LogFatal(DWORD aExceptionCode, PVOID aAddress,
                        LPCTSTR aLastFile, int aLastLine, LPCTSTR aLastHotkey)
{
    EnsureLock();
    if (!s_crash_path) return;
    EnterCriticalSection(&s_lock);

    char file_u8[1024] = {}, hotkey_u8[256] = {};
    TToUtf8(aLastFile,   file_u8,   sizeof(file_u8));
    TToUtf8(aLastHotkey, hotkey_u8, sizeof(hotkey_u8));

    char rest[256];
    _snprintf_s(rest, sizeof(rest), _TRUNCATE,
        "pid=%lu code=0x%08lX address=%p",
        GetCurrentProcessId(), (unsigned long)aExceptionCode, aAddress);

    char header[1024];
    DWORD n = FormatHeader(header, sizeof(header), "FATAL", rest);
    AppendRaw(s_crash_path, header, n);

    char body[2048];
    int bn = _snprintf_s(body, sizeof(body), _TRUNCATE,
        "  LastFile: %s\n  LastLine: %d\n  LastHotkey: %s\n",
        file_u8, aLastLine, hotkey_u8);
    if (bn > 0)
        AppendRaw(s_crash_path, body, (DWORD)bn);

    LeaveCriticalSection(&s_lock);
}

void CrashLog::LogExit(int aCode, LPCTSTR aReason)
{
    EnsureLock();
    if (!s_crash_path) return;
    EnterCriticalSection(&s_lock);

    char reason_u8[256] = {};
    TToUtf8(aReason, reason_u8, sizeof(reason_u8));

    char rest[512];
    _snprintf_s(rest, sizeof(rest), _TRUNCATE,
        "pid=%lu code=%d reason=%s",
        GetCurrentProcessId(), aCode, reason_u8);

    char header[1024];
    DWORD n = FormatHeader(header, sizeof(header), "EXIT", rest);
    AppendRaw(s_crash_path, header, n);

    LeaveCriticalSection(&s_lock);
}

void CrashLog::LogExitWithCode(int aCode)
{
    LPCTSTR reason;
    TCHAR buf[32];
    switch (aCode) {
        case 0:  reason = _T("Normal");   break;
        case 10: reason = _T("Error");    break;
        case 11: reason = _T("Critical"); break;
        case 12: reason = _T("Parse");    break;
        case 13: reason = _T("Check");    break;
        case 14: reason = _T("Test");     break;
        case 64: reason = _T("Usage");    break;
        default:
            _stprintf_s(buf, _countof(buf), _T("ExitApp(%d)"), aCode);
            reason = buf;
            break;
    }
    LogExit(aCode, reason);
}

void CrashLog::MirrorStderr(const void *, size_t) {}

namespace
{
    LONG WINAPI UnhandledExceptionFilter_Impl(EXCEPTION_POINTERS *pInfo)
    {
        // Defensive: wrap everything in __try so our filter can't itself become a crash.
        // DEADLOCK RISK (v1 known limitation): LogFatal/LogExit each call
        // EnterCriticalSection(&s_lock). If the main thread crashed while holding s_lock,
        // this filter will block indefinitely. TryEnterCriticalSection would mitigate this
        // but would require refactoring the internal locking in both functions. Accepted for
        // v1 — crashes-while-holding-the-lock are an extreme edge case.
        __try
        {
            DWORD code = pInfo ? pInfo->ExceptionRecord->ExceptionCode    : 0;
            PVOID addr = pInfo ? pInfo->ExceptionRecord->ExceptionAddress : nullptr;

            // Script-context fields (LastFile/LastLine/LastHotkey): left empty for v1.
            // Pulling g_script accessors here would require including script.h, which
            // creates circular include chains through globaldata.h. Even with extern
            // declarations, reading these globals inside an SEH filter is risky — the
            // script state may be partially corrupt. A future task can expose safe
            // accessor function pointers for this purpose.
            LPCTSTR last_file = _T("");
            int     last_line = 0;
            LPCTSTR last_hk   = _T("");

            CrashLog::LogFatal(code, addr, last_file, last_line, last_hk);
            CrashLog::LogExit(11, _T("Fatal"));
        }
        __except (EXCEPTION_EXECUTE_HANDLER)
        {
            // Our own filter faulted — swallow and proceed.
        }
        // Return CONTINUE_SEARCH so Windows performs its normal crash handling
        // (WER dialog, JIT debugger, etc.).
        return EXCEPTION_CONTINUE_SEARCH;
    }
}

void CrashLog::InstallExceptionFilter()
{
    SetUnhandledExceptionFilter(UnhandledExceptionFilter_Impl);
}

void CrashLog::InstallConsoleHandler() {}
