#ifndef crashlog_h
#define crashlog_h

#include <windows.h>

namespace CrashLog
{
    // Path setters — accept caller-owned strings; CrashLog stores its own copy.
    void SetCrashLogPath(LPCTSTR aPath);
    void SetStdErrFilePath(LPCTSTR aPath);

    bool IsCrashLogEnabled();
    bool IsStdErrFileEnabled();

    // Event recorders. All are no-ops when IsCrashLogEnabled() is false.
    void LogStart(LPCTSTR aScriptPath, LPCTSTR aCmdLine);
    void LogParse(LPCTSTR aFile, int aLine, LPCTSTR aMessage);
    void LogError(LPCTSTR aType, LPCTSTR aMode, LPCTSTR aMessage,
                  LPCTSTR aFile, int aLine, LPCTSTR aWhat, LPCTSTR aExtra,
                  LPCTSTR aStack);
    void LogFatal(DWORD aExceptionCode, PVOID aAddress,
                  LPCTSTR aLastFile, int aLastLine, LPCTSTR aLastHotkey);
    void LogExit(int aCode, LPCTSTR aReason);
    // Like LogExit but maps the integer exit code to the canonical reason name
    // (Normal/Error/Critical/Parse/Check/Test/Usage/ExitApp(n)).
    void LogExitWithCode(int aCode);

    // StdErr tee: forward raw bytes that were already written to stderr.
    void MirrorStderr(const void *aBytes, size_t aLen);

    // OS-level installers. Call ONCE from WinMain, very early.
    void InstallExceptionFilter();
    void InstallConsoleHandler();
}

#endif
