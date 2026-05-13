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
