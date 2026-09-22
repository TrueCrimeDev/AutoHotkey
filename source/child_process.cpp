#include "stdafx.h"
#include "child_process.h"
#include <vector>

namespace {

// Preserve the original Win32 error while unwinding partially started children.
struct OwnedHandle
{
	HANDLE value = nullptr;
	OwnedHandle() = default;
	explicit OwnedHandle(HANDLE aHandle) : value(aHandle) {}
	OwnedHandle(const OwnedHandle &) = delete;
	OwnedHandle &operator=(const OwnedHandle &) = delete;
	~OwnedHandle()
	{
		DWORD error = GetLastError();
		if (value && value != INVALID_HANDLE_VALUE) CloseHandle(value);
		SetLastError(error);
	}
	HANDLE Release() { HANDLE handle = value; value = nullptr; return handle; }
};

struct AttributeListOwner
{
	LPPROC_THREAD_ATTRIBUTE_LIST value;
	~AttributeListOwner()
	{
		DWORD error = GetLastError();
		DeleteProcThreadAttributeList(value);
		SetLastError(error);
	}
};

} // namespace

ChildProcess::~ChildProcess()
{
	Terminate();
	CloseAll();
}

void ChildProcess::CloseAll()
{
	for (HANDLE *h : { &mStdIn, &mStdOut, &mStdErr, &mProcess, &mJob })
		if (*h)
		{
			CloseHandle(*h);
			*h = nullptr;
		}
}

bool ChildProcess::Start(LPCTSTR aCommandLine, LPCTSTR aWorkingDir)
{
	if (mProcess)
	{
		SetLastError(ERROR_ALREADY_INITIALIZED);
		return false;
	}
	std::wstring cmd(aCommandLine); // CreateProcessW may modify the buffer.
	SIZE_T attribute_bytes = 0;
	InitializeProcThreadAttributeList(nullptr, 1, 0, &attribute_bytes);
	std::vector<BYTE> attribute_storage(attribute_bytes);
	auto attributes = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(attribute_storage.data());
	if (!InitializeProcThreadAttributeList(attributes, 1, 0, &attribute_bytes))
		return false;
	AttributeListOwner attribute_owner { attributes };
	SECURITY_ATTRIBUTES sa = { sizeof(sa), nullptr, TRUE };
	OwnedHandle in_r, in_w, out_r, out_w, err_r, err_w;
	// A large buffer keeps a chatty child running between our polls.
	const DWORD pipe_size = 1 << 20;
	if (!CreatePipe(&out_r.value, &out_w.value, &sa, pipe_size)
		|| !CreatePipe(&err_r.value, &err_w.value, &sa, pipe_size))
		return false;
	// stdin is a named pipe so our write end can be overlapped (see Write()).
	// Anonymous pipes cannot be cancelled or waited on with a timeout.
	static LONG s_serial = 0;
	wchar_t pipe_name[128];
	swprintf_s(pipe_name, L"\\\\.\\pipe\\ahk-stdin-%lu-%ld", GetCurrentProcessId(), InterlockedIncrement(&s_serial));
	in_w.value = CreateNamedPipeW(pipe_name, PIPE_ACCESS_OUTBOUND | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
		PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, 1, pipe_size, pipe_size, 0, nullptr);
	if (in_w.value == INVALID_HANDLE_VALUE)
		return false;
	in_r.value = CreateFileW(pipe_name, GENERIC_READ, 0, &sa, OPEN_EXISTING, 0, nullptr);
	if (in_r.value == INVALID_HANDLE_VALUE)
		return false;
	// Only the child's ends may be inherited; otherwise EOF never arrives.
	if (!SetHandleInformation(out_r.value, HANDLE_FLAG_INHERIT, 0)
		|| !SetHandleInformation(err_r.value, HANDLE_FLAG_INHERIT, 0))
		return false;
	HANDLE inherited[] = { in_r.value, out_w.value, err_w.value };
	if (!UpdateProcThreadAttribute(attributes, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
		inherited, sizeof(inherited), nullptr, nullptr))
		return false;

	OwnedHandle job(CreateJobObjectW(nullptr, nullptr));
	if (!job.value)
		return false;
	JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {};
	limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
	if (!SetInformationJobObject(job.value, JobObjectExtendedLimitInformation, &limits, sizeof(limits)))
		return false;

	STARTUPINFOEXW si = {};
	si.StartupInfo.cb = sizeof(si);
	si.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
	si.StartupInfo.hStdInput = in_r.value;
	si.StartupInfo.hStdOutput = out_w.value;
	si.StartupInfo.hStdError = err_w.value;
	si.lpAttributeList = attributes;
	PROCESS_INFORMATION pi = {};
	if (!CreateProcessW(nullptr, &cmd[0], nullptr, nullptr, TRUE,
		CREATE_SUSPENDED | CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT | EXTENDED_STARTUPINFO_PRESENT,
		nullptr, aWorkingDir && *aWorkingDir ? aWorkingDir : nullptr, &si.StartupInfo, &pi))
		return false;
	OwnedHandle process(pi.hProcess), thread(pi.hThread);
	// Never run uncontained code: callers rely on Kill/release terminating its
	// descendants. Windows 10 supports nested jobs; incompatible host jobs fail
	// explicitly rather than silently weakening this contract.
	if (!AssignProcessToJobObject(job.value, process.value) || ResumeThread(thread.value) == (DWORD)-1)
	{
		DWORD error = GetLastError();
		TerminateProcess(process.value, 1);
		WaitForSingleObject(process.value, 2000);
		SetLastError(error);
		return false;
	}
	mProcess = process.Release();
	mJob = job.Release();
	mPid = pi.dwProcessId;
	mStdIn = in_w.Release();
	mStdOut = out_r.Release();
	mStdErr = err_r.Release();
	return true;
}

bool ChildProcess::Write(const char *aBytes, size_t aLen, DWORD aTimeoutMs, void (*aIdle)())
{
	if (!mStdIn)
	{
		SetLastError(ERROR_INVALID_HANDLE);
		return false;
	}
	OVERLAPPED ov = {};
	ov.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
	if (!ov.hEvent)
		return false;
	ULONGLONG deadline = aTimeoutMs == INFINITE ? ~0ULL : GetTickCount64() + aTimeoutMs;
	bool ok = true;
	while (aLen && ok)
	{
		DWORD written = 0;
		ResetEvent(ov.hEvent);
		if (!WriteFile(mStdIn, aBytes, (DWORD)aLen, &written, &ov))
		{
			if (GetLastError() != ERROR_IO_PENDING)
			{
				ok = false;
				break;
			}
			// The child has not consumed the pipe yet. Keep its output flowing
			// while we wait, otherwise a child blocked on a full stdout and a
			// parent blocked on a full stdin would wait for each other forever.
			for (;;)
			{
				if (WaitForSingleObject(ov.hEvent, 5) == WAIT_OBJECT_0)
					break;
				Pump();
				if (GetTickCount64() >= deadline)
				{
					CancelIoEx(mStdIn, &ov);
					GetOverlappedResult(mStdIn, &ov, &written, TRUE); // Wait for the cancel so the buffer is no longer in use.
					SetLastError(WAIT_TIMEOUT);
					ok = false;
					break;
				}
				if (aIdle)
					aIdle();
			}
			if (!ok)
				break;
			if (!GetOverlappedResult(mStdIn, &ov, &written, FALSE))
			{
				ok = false;
				break;
			}
		}
		aBytes += written;
		aLen -= written;
	}
	DWORD err = GetLastError();
	CloseHandle(ov.hEvent);
	SetLastError(err);
	return ok;
}

void ChildProcess::CloseStdIn()
{
	if (mStdIn)
	{
		CloseHandle(mStdIn);
		mStdIn = nullptr;
	}
}

// Number of bytes at the end of aPending that form an incomplete UTF-8 sequence.
static size_t IncompleteUtf8Tail(const std::string &aPending)
{
	size_t len = aPending.size();
	for (size_t back = 1; back <= 3 && back <= len; ++back)
	{
		unsigned char b = (unsigned char)aPending[len - back];
		if ((b & 0xC0) == 0x80)
			continue; // continuation byte; keep looking for its lead
		if (b >= 0xC0)
		{
			size_t need = b >= 0xF0 ? 4 : b >= 0xE0 ? 3 : 2;
			return back < need ? back : 0;
		}
		return 0; // ASCII or invalid lead: nothing pending
	}
	return 0;
}

bool ChildProcess::PumpPipe(HANDLE &aPipe, std::string &aPending, std::wstring &aText, bool &aEof, DWORD aBudget)
{
	bool got = false;
	while (aPipe && aBudget && !mOutputLimitExceeded)
	{
		DWORD avail = 0;
		if (!PeekNamedPipe(aPipe, nullptr, 0, nullptr, &avail, nullptr))
		{
			// ERROR_BROKEN_PIPE: the child closed its end and the buffer is drained.
			CloseHandle(aPipe);
			aPipe = nullptr;
			aEof = true;
			break;
		}
		if (!avail)
			break;
		if (mOutputLimit != (size_t)-1 && mOutputBytes >= mOutputLimit)
		{
			mOutputLimitExceeded = true;
			break;
		}
		char chunk[16384];
		DWORD read = 0;
		DWORD take = avail < sizeof(chunk) ? avail : sizeof(chunk);
		if (take > aBudget) take = aBudget;
		if (take > mOutputLimit - mOutputBytes) take = (DWORD)(mOutputLimit - mOutputBytes);
		if (!ReadFile(aPipe, chunk, take, &read, nullptr) || !read)
		{
			CloseHandle(aPipe);
			aPipe = nullptr;
			aEof = true;
			break;
		}
		aPending.append(chunk, read);
		if (mOutputLimit != (size_t)-1) mOutputBytes += read;
		aBudget -= read;
		got = true;
	}
	size_t tail = aEof ? 0 : IncompleteUtf8Tail(aPending);
	size_t decodable = aPending.size() - tail;
	if (decodable)
	{
		int wide = MultiByteToWideChar(CP_UTF8, 0, aPending.data(), (int)decodable, nullptr, 0);
		if (wide > 0)
		{
			size_t start = aText.size();
			aText.resize(start + wide);
			MultiByteToWideChar(CP_UTF8, 0, aPending.data(), (int)decodable, &aText[start], wide);
		}
		aPending.erase(0, decodable);
	}
	return got;
}

bool ChildProcess::Pump(DWORD aBytesPerStream)
{
	bool got;
	if (mErrFirst)
	{
		got = PumpPipe(mStdErr, mErrPending, mErr, mErrEof, aBytesPerStream);
		got |= PumpPipe(mStdOut, mOutPending, mOut, mOutEof, aBytesPerStream);
	}
	else
	{
		got = PumpPipe(mStdOut, mOutPending, mOut, mOutEof, aBytesPerStream);
		got |= PumpPipe(mStdErr, mErrPending, mErr, mErrEof, aBytesPerStream);
	}
	mErrFirst = !mErrFirst;
	return got;
}

bool ChildProcess::HasExited()
{
	if (mExited || !mProcess)
		return mExited;
	if (WaitForSingleObject(mProcess, 0) != WAIT_OBJECT_0)
		return false;
	DWORD code;
	if (!GetExitCodeProcess(mProcess, &code))
		return false;
	mExitCode = code;
	mExited = true;
	return true;
}

void ChildProcess::Terminate()
{
	if (!mProcess)
		return;
	if (mJob)
		TerminateJobObject(mJob, 1);
	else if (!HasExited())
		TerminateProcess(mProcess, 1);
	WaitForSingleObject(mProcess, 2000);
	HasExited();
}

void AppendQuotedArg(std::wstring &aCmdLine, LPCTSTR aArg)
{
	if (!aCmdLine.empty())
		aCmdLine += L' ';
	bool needs_quotes = !*aArg || wcspbrk(aArg, L" \t\n\v\"") != nullptr;
	if (!needs_quotes)
	{
		aCmdLine += aArg;
		return;
	}
	aCmdLine += L'"';
	for (LPCTSTR p = aArg; ; ++p)
	{
		size_t backslashes = 0;
		while (*p == L'\\')
		{
			++backslashes;
			++p;
		}
		if (!*p)
		{
			aCmdLine.append(backslashes * 2, L'\\'); // before the closing quote they must be doubled
			break;
		}
		if (*p == L'"')
		{
			aCmdLine.append(backslashes * 2 + 1, L'\\');
			aCmdLine += L'"';
		}
		else
		{
			aCmdLine.append(backslashes, L'\\');
			aCmdLine += *p;
		}
	}
	aCmdLine += L'"';
}

void RunChildCapture(LPCTSTR aCommandLine, LPCTSTR aWorkingDir, DWORD aTimeoutMs, ChildResult &aResult,
	size_t aOutputLimit)
{
	ChildProcess child;
	child.SetOutputLimit(aOutputLimit);
	if (!child.Start(aCommandLine, aWorkingDir))
	{
		aResult.last_error = GetLastError();
		return;
	}
	aResult.started = true;
	child.CloseStdIn(); // A tool child that waits for input would otherwise hang until the timeout.
	ULONGLONG deadline = GetTickCount64() + aTimeoutMs;
	ULONGLONG drain_until = 0;
	for (;;)
	{
		bool got = child.Pump();
		if (child.OutputLimitExceeded())
		{
			aResult.output_limit_exceeded = true;
			child.Terminate();
			break;
		}
		if (child.HasExited())
		{
			// A grandchild may keep the pipe open after its launcher exits. Keep
			// bounded pumping/limit checks during the finite final drain too.
			if (!drain_until) drain_until = GetTickCount64() + 500;
			if ((child.OutEof() && child.ErrEof()) || GetTickCount64() >= drain_until)
				break;
		}
		else if (GetTickCount64() >= deadline)
		{
			child.Terminate();
			// Drain the finite pipe buffers after stopping the entire job.
			child.Pump(1 << 20);
			aResult.timed_out = true;
			aResult.output_limit_exceeded = child.OutputLimitExceeded();
			break;
		}
		if (!got)
			Sleep(drain_until ? 1 : 5);
	}
	aResult.exit_code = child.ExitCode();
	aResult.out.swap(child.Out());
	aResult.err.swap(child.Err());
}
