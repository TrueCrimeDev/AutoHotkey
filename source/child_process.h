#ifndef child_process_h
#define child_process_h

#include <windows.h>
#include <string>

// A child process with UTF-8 stdio pipes, held in a job so the whole tree
// dies with it. Pure Win32; used by the ProcessPipe script class and by the
// mcp verb's check/run/test tools.
class ChildProcess
{
public:
	ChildProcess() = default;
	~ChildProcess();
	ChildProcess(const ChildProcess &) = delete;
	ChildProcess &operator=(const ChildProcess &) = delete;

	// Starts aCommandLine (Windows command-line syntax; see AppendQuotedArg).
	// Inherits only stdio. A kill-on-close job is required; failure to create,
	// configure or assign it fails the start before any child code executes.
	// Returns false and leaves GetLastError() set on failure.
	bool Start(LPCTSTR aCommandLine, LPCTSTR aWorkingDir);
	bool Started() const { return mProcess != nullptr; }
	DWORD Pid() const { return mPid; }

	// Writes to stdin without ever blocking the pipes: the write is overlapped,
	// and while it is pending the child's stdout/stderr keep being pumped, so a
	// child that is busy writing cannot deadlock us. aIdle (may be null) is
	// called between polls, e.g. to run the script's message loop. Returns
	// false on error, or with GetLastError() == WAIT_TIMEOUT after aTimeoutMs
	// (the pending write is cancelled; the child may have received a prefix).
	bool Write(const char *aBytes, size_t aLen, DWORD aTimeoutMs = INFINITE, void (*aIdle)() = nullptr);
	void CloseStdIn();

	// Reads a bounded slice from each stream, alternating which runs first.
	// UTF-8 tails carry across slices. Never waits for more bytes; callers must
	// check deadlines and yield between slices even if output keeps arriving.
	bool Pump(DWORD aBytesPerStream = 64 * 1024);
	bool OutEof() const { return mOutEof; }
	bool ErrEof() const { return mErrEof; }
	void SetOutputLimit(size_t aBytes) { mOutputLimit = aBytes; }
	bool OutputLimitExceeded() const { return mOutputLimitExceeded; }

	// Polls the exit state; records the exit code once the process is gone.
	bool HasExited();
	DWORD ExitCode() const { return mExitCode; }

	// Kills the job even if the original process has already exited.
	void Terminate();

	std::wstring &Out() { return mOut; }
	std::wstring &Err() { return mErr; }

private:
	bool PumpPipe(HANDLE &aPipe, std::string &aPending, std::wstring &aText, bool &aEof, DWORD aBudget);
	void CloseAll();

	HANDLE mProcess = nullptr, mJob = nullptr, mStdIn = nullptr, mStdOut = nullptr, mStdErr = nullptr;
	DWORD mPid = 0, mExitCode = 0;
	bool mExited = false, mOutEof = false, mErrEof = false;
	bool mErrFirst = false, mOutputLimitExceeded = false;
	size_t mOutputLimit = (size_t)-1, mOutputBytes = 0;
	std::string mOutPending, mErrPending;
	std::wstring mOut, mErr;
};

// Appends one argument to a command line the way CommandLineToArgvW parses it.
void AppendQuotedArg(std::wstring &aCmdLine, LPCTSTR aArg);

// Runs a command to completion (or aTimeoutMs), collecting both streams.
struct ChildResult
{
	std::wstring out, err;
	DWORD exit_code = 0;
	DWORD last_error = 0; // when !started
	bool started = false, timed_out = false, output_limit_exceeded = false;
};
void RunChildCapture(LPCTSTR aCommandLine, LPCTSTR aWorkingDir, DWORD aTimeoutMs, ChildResult &aResult,
	size_t aOutputLimit = (size_t)-1);

#endif
