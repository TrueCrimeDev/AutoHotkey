#include "stdafx.h"
#include "crashlog.h"
#include "globaldata.h"

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

// All recorders are stubs in this task; real bodies come in later tasks.
void CrashLog::LogStart(LPCTSTR, LPCTSTR) {}
void CrashLog::LogParse(LPCTSTR, int, LPCTSTR) {}
void CrashLog::LogError(LPCTSTR, LPCTSTR, LPCTSTR, LPCTSTR, int, LPCTSTR, LPCTSTR, LPCTSTR) {}
void CrashLog::LogFatal(DWORD, PVOID, LPCTSTR, int, LPCTSTR) {}
void CrashLog::LogExit(int, LPCTSTR) {}
void CrashLog::MirrorStderr(const void *, size_t) {}

void CrashLog::InstallExceptionFilter() {}
void CrashLog::InstallConsoleHandler() {}
