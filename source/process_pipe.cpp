#include "stdafx.h"
#include "defines.h"
#include "globaldata.h"
#include "script.h"
#include "application.h"
#include "script_object.h"
#include "script_func_impl.h"
#include "process_pipe.h"
#include <cmath>

ObjectMemberMd ProcessPipe::sMembers[] =
{
	md_member(ProcessPipe, __New, CALL, (In, String, Command), (In_Opt, Variant, Args), (In_Opt, String, WorkingDir)),
	md_member(ProcessPipe, Close, CALL, md_arg_none),
	md_member(ProcessPipe, Kill, CALL, md_arg_none),
	md_member(ProcessPipe, Read, CALL, (In_Opt, Float64, Timeout), (Ret, String, RetVal)),
	md_member(ProcessPipe, ReadLine, CALL, (In_Opt, Float64, Timeout), (Ret, String, RetVal)),
	md_member(ProcessPipe, ReadStdErr, CALL, (Ret, String, RetVal)),
	md_member(ProcessPipe, Send, CALL, (In, String, Text), (In_Opt, Float64, Timeout)),
	md_member(ProcessPipe, SendLine, CALL, (In, String, Text), (In_Opt, Float64, Timeout)),
	md_member(ProcessPipe, Wait, CALL, (In_Opt, Float64, Timeout), (Ret, Int32, RetVal)),

	md_property_get(ProcessPipe, AtEOF, Bool32),
	md_property_get(ProcessPipe, ExitCode, Int32),
	md_property_get(ProcessPipe, PID, Int32),
	md_property_get(ProcessPipe, Running, Bool32),
};
int ProcessPipe::sMemberCount = _countof(sMembers);

Object *ProcessPipe::sPrototype;


FResult ProcessPipe::__New(StrArg aCommand, ExprTokenType *aArgs, optl<StrArg> aWorkingDir)
{
	if (!*aCommand)
		return FR_E_ARG(0);
	std::wstring cmdline;
	if (!aArgs || aArgs->symbol == SYM_MISSING)
		cmdline = aCommand; // Already a complete command line.
	else if (auto arr = dynamic_cast<Array *>(TokenToObject(*aArgs)))
	{
		AppendQuotedArg(cmdline, aCommand);
		for (Object::index_t k = 0; k < arr->Length(); ++k)
		{
			ExprTokenType item;
			if (!arr->ItemToToken(k, item))
				return FR_E_ARG(1);
			TCHAR num_buf[MAX_NUMBER_SIZE];
			AppendQuotedArg(cmdline, TokenToString(item, num_buf));
		}
	}
	else if (!TokenToObject(*aArgs))
	{
		TCHAR num_buf[MAX_NUMBER_SIZE];
		cmdline = aCommand;
		LPCTSTR extra = TokenToString(*aArgs, num_buf);
		if (*extra)
		{
			cmdline += L' ';
			cmdline += extra; // A raw argument string, appended verbatim.
		}
	}
	else
		return FR_E_ARG(1);
	if (!mChild.Start(cmdline.c_str(), aWorkingDir.value_or_null()))
		return FR_E_WIN32;
	return OK;
}


static void PumpMessagesWhileWriting()
{
	MsgSleep(-1);
}

// Keep finite timeouts representable in Win32 milliseconds. In particular,
// never wrap a large timeout into INFINITE or a small, unrelated duration.
static bool TimeoutMillis(optl<double> aTimeout, DWORD &aMilliseconds)
{
	if (!aTimeout.has_value())
	{
		aMilliseconds = INFINITE;
		return true;
	}
	double seconds = aTimeout.value();
	if (!std::isfinite(seconds) || seconds > (INFINITE - 1) / 1000.0)
		return false;
	aMilliseconds = seconds <= 0 ? 0 : (DWORD)(seconds * 1000);
	return true;
}

static FResult WriteUtf8(ChildProcess &aChild, LPCTSTR aText, bool aNewline, optl<double> aTimeout)
{
	DWORD timeout_ms;
	if (!TimeoutMillis(aTimeout, timeout_ms))
		return FR_E_ARG(1);
	int len = (int)_tcslen(aText);
	int bytes = len ? WideCharToMultiByte(CP_UTF8, 0, aText, len, nullptr, 0, nullptr, nullptr) : 0;
	std::string u8((size_t)bytes + (aNewline ? 1 : 0), '\0');
	if (bytes)
		WideCharToMultiByte(CP_UTF8, 0, aText, len, &u8[0], bytes, nullptr, nullptr);
	if (aNewline)
		u8[bytes] = '\n';
	if (u8.empty())
		return OK;
	if (aChild.Write(u8.data(), u8.size(), timeout_ms, PumpMessagesWhileWriting))
		return OK;
	if (GetLastError() == WAIT_TIMEOUT)
		return FError(ERR_TIMEOUT, nullptr, ErrorPrototype::Timeout);
	return FR_E_WIN32;
}

FResult ProcessPipe::Send(StrArg aText, optl<double> aTimeout)
{
	return WriteUtf8(mChild, aText, false, aTimeout);
}

FResult ProcessPipe::SendLine(StrArg aText, optl<double> aTimeout)
{
	return WriteUtf8(mChild, aText, true, aTimeout);
}

FResult ProcessPipe::Close()
{
	mChild.CloseStdIn();
	return OK;
}

FResult ProcessPipe::Kill()
{
	mChild.Terminate();
	return OK;
}


bool ProcessPipe::LineReady()
{
	return mChild.Out().find(L'\n') != std::wstring::npos || mChild.OutEof();
}

bool ProcessPipe::DataReady()
{
	return !mChild.Out().empty() || mChild.OutEof();
}

bool ProcessPipe::Exited()
{
	return mChild.HasExited();
}

// Pumps the pipes until aDone holds, the timeout (seconds; omitted = forever)
// elapses, or the child is gone. Sleeps via MsgSleep so timers, hotkeys and GUI
// events keep running, like WinWait and InputHook.Wait.
FResult ProcessPipe::WaitFor(optl<double> aTimeout, bool (ProcessPipe::*aDone)())
{
	if (!mChild.Started())
		return FError(_T("The process was not started."));
	DWORD timeout_ms;
	if (!TimeoutMillis(aTimeout, timeout_ms))
		return FR_E_ARG(0);
	ULONGLONG deadline = timeout_ms == INFINITE ? ~0ULL : GetTickCount64() + timeout_ms;
	for (;;)
	{
		bool got = mChild.Pump();
		if ((this->*aDone)())
		{
			// Wait() preserves output already queued by the exited process. Its
			// pipe buffers are finite; descendants cannot extend this drain.
			if (aDone == &ProcessPipe::Exited)
				mChild.Pump(1 << 20);
			return OK;
		}
		if (GetTickCount64() >= deadline)
			return FError(ERR_TIMEOUT, nullptr, ErrorPrototype::Timeout);
		// Check messages even while output is continuously available. The
		// non-sleeping form preserves throughput without starving timers/UI.
		MsgSleep(got ? -1 : 5);
	}
}

FResult ProcessPipe::ReadLine(optl<double> aTimeout, StrRet &aRetVal)
{
	FResult fr = WaitFor(aTimeout, &ProcessPipe::LineReady);
	if (fr != OK)
		return fr;
	std::wstring &out = mChild.Out();
	size_t nl = out.find(L'\n');
	size_t take = nl == std::wstring::npos ? out.size() : nl;
	size_t len = take;
	if (len && out[len - 1] == L'\r')
		--len;
	bool ok = aRetVal.Copy(out.c_str(), len);
	out.erase(0, nl == std::wstring::npos ? take : take + 1);
	return ok ? OK : FR_E_OUTOFMEM;
}

FResult ProcessPipe::Read(optl<double> aTimeout, StrRet &aRetVal)
{
	// Read() returns what is buffered now; Read(t) waits up to t seconds for something.
	FResult fr = aTimeout.has_value() ? WaitFor(aTimeout, &ProcessPipe::DataReady) : (mChild.Pump(), OK);
	if (fr != OK)
		return fr;
	std::wstring &out = mChild.Out();
	bool ok = aRetVal.Copy(out.c_str(), out.size());
	out.clear();
	return ok ? OK : FR_E_OUTOFMEM;
}

FResult ProcessPipe::ReadStdErr(StrRet &aRetVal)
{
	mChild.Pump();
	std::wstring &err = mChild.Err();
	bool ok = aRetVal.Copy(err.c_str(), err.size());
	err.clear();
	return ok ? OK : FR_E_OUTOFMEM;
}

FResult ProcessPipe::Wait(optl<double> aTimeout, int &aRetVal)
{
	FResult fr = WaitFor(aTimeout, &ProcessPipe::Exited);
	if (fr != OK)
		return fr;
	aRetVal = (int)mChild.ExitCode();
	return OK;
}

FResult ProcessPipe::get_ExitCode(int &aRetVal)
{
	aRetVal = mChild.HasExited() ? (int)mChild.ExitCode() : -1;
	return OK;
}

FResult ProcessPipe::get_AtEOF(BOOL &aRetVal)
{
	mChild.Pump();
	aRetVal = mChild.OutEof() && mChild.Out().empty();
	return OK;
}
