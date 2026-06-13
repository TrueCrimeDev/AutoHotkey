/*
AutoHotkey

Copyright 2003-2009 Chris Mallett (support@autohotkey.com)

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
*/

#include "stdafx.h"
#include "script.h"
#include "globaldata.h"
#include "window.h"
#include "TextIO.h"
#include "abi.h"
#include "crashlog.h"
#include "application.h" // REPL: InitNewThread/ResumeUnderlyingThread.
#include "hook.h" // REPL: AHK_REPL_INPUT.
#include "ahkversion.h" // REPL banner.
#include <richedit.h>


ResultType Line::PreparseError(LPTSTR aErrorText, LPTSTR aExtraInfo)
{
	return LineError(aErrorText, FAIL, aExtraInfo);
}


#ifdef CONFIG_DEBUGGER
LPCTSTR Debugger::WhatThrew()
{
	// We want 'What' to indicate the function/sub/operation that *threw* the exception.
	// For BIFs, throwing is always explicit.  For a UDF, 'What' should only name it if
	// it explicitly constructed the Exception object.  This provides an easy way for
	// OnError and Catch to categorise errors.  No information is lost because File/Line
	// can already be used locate the function/sub that was running.
	// So only return a name when a BIF is raising an error:
	if (mStack.mTop < mStack.mBottom || mStack.mTop->type != DbgStack::SE_BIF)
		return _T("");
	return mStack.mTop->func->mName;
}
#endif


IObject *Line::CreateRuntimeException(LPCTSTR aErrorText, LPCTSTR aExtraInfo, Object *aPrototype)
{
	// Build the parameters for Object::Create()
	ExprTokenType aParams[3]; int aParamCount = 2;
	ExprTokenType* aParam[3] { aParams + 0, aParams + 1, aParams + 2 };
	aParams[0].SetValue(const_cast<LPTSTR>(aErrorText));
#ifdef CONFIG_DEBUGGER
	aParams[1].SetValue(const_cast<LPTSTR>(g_Debugger.WhatThrew()));
#else
	// Without the debugger stack, there's no good way to determine what's throwing. It could be:
	//g_act[mActionType].Name; // A command implemented as an Action (g_act).
	//g->CurrentFunc->mName; // A user-defined function.
	//???; // A built-in function implemented as a Func (g_BIF).
	aParams[1].SetValue(_T(""), 0);
#endif
	if (aExtraInfo && *aExtraInfo)
		aParams[aParamCount++].SetValue(const_cast<LPTSTR>(aExtraInfo));

	auto obj = Object::Create();
	if (!obj)
		return nullptr;
	if (!aPrototype)
		aPrototype = ErrorPrototype::Error;
	obj->SetBase(aPrototype);
	FuncResult rt;
	g_script.mCurrLine = this;
	g_script.mNewRuntimeException = obj;
	if (!obj->CallInitNew(rt, aParam, aParamCount))
		obj = nullptr; // CallInitNew released it.
	g_script.mNewRuntimeException = nullptr;
	return obj;
}


ResultType Line::ThrowRuntimeException(LPCTSTR aErrorText, LPCTSTR aExtraInfo)
{
	return g_script.ThrowRuntimeException(aErrorText, aExtraInfo, this, FAIL);
}

ResultType Script::ThrowRuntimeException(LPCTSTR aErrorText, LPCTSTR aExtraInfo
	, Line *aLine, ResultType aErrorType, Object *aPrototype)
{
	// ThrownToken should only be non-NULL while control is being passed up the
	// stack, which implies no script code can be executing.
	ASSERT(!g->ThrownToken);

	if (!aLine)
		aLine = mCurrLine;

	ResultToken *token;
	if (   !(token = new ResultToken)
		|| !(token->object = aLine->CreateRuntimeException(aErrorText, aExtraInfo, aPrototype))   )
	{
		// Out of memory. It's likely that we were called for this very reason.
		// Since we don't even have enough memory to allocate an exception object,
		// just show an error message and exit the thread. Don't call LineError(),
		// since that would recurse into this function.
		if (token)
			delete token;
		if (!g->ThrownToken)
		{
			MsgBox(ERR_OUTOFMEM ERR_ABORT);
			return FAIL;
		}
		//else: Thrown by Error constructor?
	}
	else
	{
		token->symbol = SYM_OBJECT;
		token->mem_to_free = NULL;

		return aLine->SetThrownToken(*g, token, aErrorType);
	}

	// Returning FAIL causes each caller to also return FAIL, until either the
	// thread has fully exited or the recursion layer handling ACT_TRY is reached:
	return FAIL;
}

ResultType Script::ThrowRuntimeException(LPCTSTR aErrorText, LPCTSTR aExtraInfo)
{
	return ThrowRuntimeException(aErrorText, aExtraInfo, mCurrLine, FAIL);
}


ResultType Line::SetThrownToken(global_struct &g, ResultToken *aToken, ResultType aErrorType)
{
#ifdef CONFIG_DEBUGGER
	if (g_Debugger.IsConnected())
		if (g_Debugger.PreThrow(aToken) && !(g.ExcptMode & EXCPTMODE_CATCH))
		{
			// The debugger has entered (and left) a break state, so the client has had a
			// chance to inspect the exception and report it.  There's nothing in the DBGp
			// spec about what to do next, probably since PHP would just log the error.
			// In our case, it seems more useful to suppress the dialog than to show it.
			g_script.FreeExceptionToken(aToken);
			return FAIL;
		}
#endif
	g.ThrownToken = aToken;
	if (!(g.ExcptMode & EXCPTMODE_CATCH))
		return g_script.UnhandledException(this, aErrorType); // Usually returns FAIL; may return OK if aErrorType == FAIL_OR_OK.
	return FAIL;
}


BIF_DECL(BIF_Throw)
{
	if (!aParamCount || aParam[aParamCount - 1]->symbol == SYM_MISSING)
	{
		if (g->ExcptMode & EXCPTMODE_CAUGHT) // Re-throw.
			_f_return_FAIL;
		_f_throw(ERR_EXCEPTION);
	}
	auto &param = *aParam[aParamCount - 1];
	ResultToken* token = new ResultToken;
	token->mem_to_free = nullptr;
	switch (param.symbol)
	{
	case SYM_OBJECT:
		token->SetValue(param.object);
		param.object->AddRef();
		break;
	case SYM_VAR:
		param.var->ToToken(*token);
		break;
	default:
		token->CopyValueFrom(param);
	}
	if (token->symbol == SYM_STRING && !token->Malloc(token->marker, token->marker_length))
	{
		delete token;
		_f_throw_oom;
	}
	// Throw() isn't made continuable in v2.1 because existing v2.0 code isn't
	// expected to deal with the possibility that the thread doesn't exit.
	g_script.mCurrLine->SetThrownToken(*g, token, FAIL);
	aResultToken.SetExitResult(FAIL);
}


ResultType Script::Win32Error(DWORD aError, ResultType aErrorType)
{
	TCHAR number_string[12];
	// Convert aError to string to pass it through RuntimeError, but it will ultimately
	// be converted to the error number and proper message by OSError.Prototype.__New.
	_ultot(aError, number_string, 10);
	return RuntimeError(number_string, _T(""), aErrorType, nullptr, ErrorPrototype::OS);
}


static bool ResolveErrorColor(int aRequest); // defined below, near the formatters

void Script::SetErrorStdOut(LPTSTR aParam, bool aColorMode)
{
	// Determine the color request.  The `:` form carries an explicit token
	// (/ErrorStdOut:color or :nocolor); the plain and `=encoding` forms request
	// auto-detection (color when stderr is a real console, unless NO_COLOR is set).
	int color_request = 0; // 0 = auto
	if (aColorMode)
	{
		if (aParam && (!_tcsicmp(aParam, _T("nocolor")) || !_tcsicmp(aParam, _T("none")) || !_tcsicmp(aParam, _T("off"))))
			color_request = -1; // explicit off
		else
			color_request = 1;  // explicit on (back-compat: any other ':' token meant "color")
		aParam = NULL; // the ':' form carries no encoding
	}
	mErrorStdOutColor = ResolveErrorColor(color_request);

	mErrorStdOutCP = Line::ConvertFileEncoding(aParam);
	// Seems best not to print errors to stderr if the encoding was invalid.  Current behaviour
	// for an encoding of -1 would be to print only the ASCII characters and drop the rest, but
	// if our caller is expecting UTF-16, it won't be readable.
	mErrorStdOut = mErrorStdOutCP != -1;
	// If invalid, no error is shown here because this function might be called early, before
	// Line::sSourceFile[0] is given its value.  Instead, errors appearing as dialogs should
	// be a sufficient clue that the /ErrorStdOut= value was invalid.
}

static LPCTSTR DiagSeverity(ResultType aErrorType)
{
	switch (aErrorType)
	{
	case WARN: return _T("warning");
	case CRITICAL_ERROR: return _T("critical");
	default: return _T("error");
	}
}

static int EscapeJsonText(LPTSTR aDest, int aDestSize, LPCTSTR aSrc)
{
	if (!aDest || aDestSize < 1)
		return 0;
	if (!aSrc)
		aSrc = _T("");
	int n = 0;
	for (; *aSrc && n < aDestSize - 1; ++aSrc)
	{
		LPCTSTR repl = NULL;
		switch (*aSrc)
		{
		case _T('\\'): repl = _T("\\\\"); break;
		case _T('"'):  repl = _T("\\\""); break;
		case _T('\r'): repl = _T("\\r"); break;
		case _T('\n'): repl = _T("\\n"); break;
		case _T('\t'): repl = _T("\\t"); break;
		}
		if (repl)
		{
			int wrote = sntprintf(aDest + n, aDestSize - n, _T("%s"), repl);
			if (wrote <= 0 || wrote >= aDestSize - n)
				break;
			n += wrote;
			continue;
		}
		if ((UINT)*aSrc < 0x20)
		{
			int wrote = sntprintf(aDest + n, aDestSize - n, _T("\\u%04X"), (UINT)*aSrc);
			if (wrote <= 0 || wrote >= aDestSize - n)
				break;
			n += wrote;
			continue;
		}
		aDest[n++] = *aSrc;
	}
	aDest[n] = '\0';
	return n;
}

// ---- ANSI color codes (shared by the plain-text formatter and source-context rendering) ----
#define ANSI_RED     _T("\x1b[31m")
#define ANSI_YELLOW  _T("\x1b[33m")
#define ANSI_CYAN    _T("\x1b[36m")
#define ANSI_DIM     _T("\x1b[2m")
#define ANSI_RESET   _T("\x1b[0m")

// Source-context display tuning.  ERR_CONTEXT_RADIUS lines are shown either side of
// the error line in plain-text output; lines longer than ERR_CONTEXT_MAXLEN are
// truncated for display (the structured JSON "source" field keeps the longer line).
#define ERR_CONTEXT_RADIUS 2
#define ERR_CONTEXT_MAXLEN 1024

// Assembly buffer size for a single JSON diagnostic record.  Sized to hold every
// escaped component (each independently capped by EscapeJsonText) plus the template,
// so the final sntprintf can never truncate mid-record and emit invalid JSON.
#define DIAG_JSON_BUF_SIZE (LINE_SIZE * 3 + T_MAX_PATH + SCRIPT_STACK_BUF_SIZE * 2 + 1280)

// Read line aLineNumber (1-based) verbatim from the file behind aFileIndex into aBuf
// (null-terminated, trailing EOL stripped).  Returns false for stdin/embedded sources
// or unreadable files so the caller can fall back to a decompiled reconstruction.
static bool GetVerbatimSourceLine(FileIndexType aFileIndex, LineNumberType aLineNumber, LPTSTR aBuf, int aBufSize)
{
	if (aBufSize > 0)
		aBuf[0] = '\0';
	if (aLineNumber == 0 || aFileIndex >= Line::sSourceFileCount)
		return false;
	LPCTSTR path = Line::sSourceFile[aFileIndex];
	if (!path || !*path || *path == '*') // no real file on disk (stdin / embedded script)
		return false;
	TextFile tf;
	if (!tf.Open(path, DEFAULT_READ_FLAGS, g_DefaultScriptCodepage))
		return false;
	TCHAR line_buf[LINE_SIZE + 2];
	int line_length;
	LineNumberType current = 0;
	bool found = false;
	while (-1 != (line_length = tf.ReadLine(line_buf, LINE_SIZE)))
	{
		if (++current != aLineNumber)
			continue;
		while (line_length > 0 && (line_buf[line_length - 1] == '\n' || line_buf[line_length - 1] == '\r'))
			--line_length;
		line_buf[line_length] = '\0';
		tcslcpy(aBuf, line_buf, aBufSize);
		found = true;
		break;
	}
	tf.Close();
	return found;
}

// Source text of aLine for display: verbatim file text when available, else the
// decompiled ToText() reconstruction (which normalizes syntax, e.g. `throw Error(...)`
// renders as `throw(Error(...))`).
static void GetErrorSourceText(Line *aLine, LPTSTR aBuf, int aBufSize)
{
	if (aBufSize > 0)
		aBuf[0] = '\0';
	if (!aLine)
		return;
	if (GetVerbatimSourceLine(aLine->mFileIndex, aLine->mLineNumber, aBuf, aBufSize))
		return;
	aLine->ToText(aBuf, aBufSize, false, 0, false, false);
}

// Append a verbatim source-context block (ERR_CONTEXT_RADIUS lines either side of the
// error line) to aBuf, marking the error line with '>' (and cyan when aUseColor).
// Returns characters written, or -1 if the file couldn't be read or the error line
// wasn't found, in which case the caller falls back to a single decompiled line.
static int AppendSourceContext(LPTSTR aBuf, int aBufSize, FileIndexType aFileIndex,
	LineNumberType aErrLineNo, bool aUseColor)
{
	if (aErrLineNo == 0 || aFileIndex >= Line::sSourceFileCount)
		return -1;
	LPCTSTR path = Line::sSourceFile[aFileIndex];
	if (!path || !*path || *path == '*')
		return -1;
	TextFile tf;
	if (!tf.Open(path, DEFAULT_READ_FLAGS, g_DefaultScriptCodepage))
		return -1;
	LineNumberType from = aErrLineNo > (LineNumberType)ERR_CONTEXT_RADIUS ? aErrLineNo - ERR_CONTEXT_RADIUS : 1u;
	LineNumberType to = aErrLineNo + ERR_CONTEXT_RADIUS;
	TCHAR line_buf[LINE_SIZE + 2];
	int line_length, n = 0;
	LineNumberType current = 0;
	bool found_err = false;
	while (-1 != (line_length = tf.ReadLine(line_buf, LINE_SIZE)))
	{
		if (++current > to)
			break;
		if (current < from)
			continue;
		if (aBufSize - n < ERR_CONTEXT_MAXLEN + 64) // out of room; stop cleanly
			break;
		while (line_length > 0 && (line_buf[line_length - 1] == '\n' || line_buf[line_length - 1] == '\r'))
			--line_length;
		bool truncated = line_length > ERR_CONTEXT_MAXLEN;
		if (truncated)
			line_length = ERR_CONTEXT_MAXLEN;
		line_buf[line_length] = '\0';
		bool is_err = (current == aErrLineNo);
		found_err |= is_err;
		LPCTSTR marker = is_err ? _T(">") : _T(" ");
		LPCTSTR tail = truncated ? _T(" ...") : _T("");
		if (aUseColor && is_err)
			n += sntprintf(aBuf + n, aBufSize - n, _T("        %s ") ANSI_CYAN _T("%d| %s%s") ANSI_RESET _T("\n"),
				marker, (int)current, line_buf, tail);
		else
			n += sntprintf(aBuf + n, aBufSize - n, _T("        %s %d| %s%s\n"),
				marker, (int)current, line_buf, tail);
	}
	tf.Close();
	return found_err ? n : -1;
}

// Resolve whether ANSI color should be used on stderr.  aRequest: 1=explicit on,
// -1=explicit off, 0=auto.  Honors NO_COLOR (disable) and CLICOLOR_FORCE (force),
// auto-enables when stderr is a real console, and enables VT processing when used.
static bool ResolveErrorColor(int aRequest)
{
	if (aRequest < 0)
		return false;
	TCHAR env[2];
	bool no_color = GetEnvironmentVariable(_T("NO_COLOR"), env, _countof(env)) > 0;       // present & non-empty
	bool force = GetEnvironmentVariable(_T("CLICOLOR_FORCE"), env, _countof(env)) > 0;
	HANDLE hErr = GetStdHandle(STD_ERROR_HANDLE);
	DWORD mode;
	bool is_console = GetConsoleMode(hErr, &mode) != 0;
	// Precedence: CLICOLOR_FORCE forces color on; else NO_COLOR forces it off; else an
	// explicit :color enables it, and auto mode enables it only when stderr is a console.
	bool want = (aRequest == 1) ? (force || !no_color)
	                            : (force || (is_console && !no_color));
	if (!want)
		return false;
	if (is_console)
		SetConsoleMode(hErr, mode | 0x0004); // ENABLE_VIRTUAL_TERMINAL_PROCESSING
	else if (!force)
		return false; // colors are meaningless on a non-console unless explicitly forced
	return true;
}

// Retrieve the current script call stack into aBuf (empty string if unavailable or not
// requested).  Shared by both formatters so their stack-gathering can't drift apart.
static void RetrieveErrorStack(LPTSTR aBuf, int aBufSize, bool aIncludeStack)
{
	if (aBufSize > 0)
		aBuf[0] = '\0';
#ifdef CONFIG_DEBUGGER
	if (aIncludeStack && g_Debugger.mStack.Depth() > 0)
		GetScriptStack(aBuf, aBufSize);
#endif
}

static int FormatDiagJson(LPTSTR aBuf, int aBufSize, LPCTSTR aErrorText, LPCTSTR aExtraInfo
	, FileIndexType aFileIndex, LineNumberType aLineNumber, ResultType aErrorType, Line *aLine, bool aIncludeStack
	, Object *aException = nullptr)
{
	if (!aBuf || aBufSize < 1)
		return 0;

	TCHAR msg[LINE_SIZE];
	TCHAR extra[LINE_SIZE];
	TCHAR what[256];
	TCHAR type[128];
	TCHAR file[T_MAX_PATH];
	TCHAR source[LINE_SIZE];
	TCHAR stack[SCRIPT_STACK_BUF_SIZE * 2];

	LPCTSTR file_name = (aFileIndex < Line::sSourceFileCount && Line::sSourceFile[aFileIndex])
		? Line::sSourceFile[aFileIndex] : _T("");

	EscapeJsonText(msg, _countof(msg), aErrorText ? aErrorText : _T(""));
	EscapeJsonText(extra, _countof(extra), aExtraInfo ? aExtraInfo : _T(""));
	EscapeJsonText(file, _countof(file), file_name);

	// Error class name (e.g. TypeError, OSError, SyntaxError) and the throwing context,
	// taken from the exception object when one is available (runtime throws).
	LPCTSTR type_src = aException ? aException->Type() : (aErrorType == WARN ? _T("Warning") : nullptr);
	LPCTSTR what_src = aException ? aException->GetOwnPropString(_T("What")) : nullptr;
	EscapeJsonText(type, _countof(type), type_src ? type_src : _T("Error"));
	EscapeJsonText(what, _countof(what), what_src ? what_src : _T(""));

	// Column within the line, when the exception carries one (e.g. SyntaxError from Eval).
	int column = aException ? (int)aException->GetOwnPropInt64(_T("Column")) : 0;

	if (aLine)
	{
		TCHAR line_buf[LINE_SIZE];
		GetErrorSourceText(aLine, line_buf, _countof(line_buf));
		EscapeJsonText(source, _countof(source), line_buf);
	}
	else
		*source = '\0';

	TCHAR stack_buf[SCRIPT_STACK_BUF_SIZE];
	RetrieveErrorStack(stack_buf, _countof(stack_buf), aIncludeStack);
	EscapeJsonText(stack, _countof(stack), stack_buf);

	// Match the actual process exit code (see AutoHotkey.cpp): load-time failures use
	// the PARSE/VALIDATE codes, runtime failures use RUNTIME/CRITICAL.  mIsReadyToExecute
	// distinguishes load-time from runtime; mCheckMode distinguishes /check (validate).
	int code;
	if (aErrorType == WARN)
		code = 0;
	else if (aErrorType == CRITICAL_ERROR)
		code = AHK_EXIT_CRITICAL_ERROR;
	else if (!g_script.mIsReadyToExecute)
		code = g_script.mCheckMode ? AHK_EXIT_VALIDATE_ERROR : AHK_EXIT_PARSE_ERROR;
	else
		code = AHK_EXIT_RUNTIME_ERROR;

	int n = sntprintf(aBuf, aBufSize
		, _T("{\"kind\":\"diagnostic\",\"format\":\"json\",\"schema\":2,\"severity\":\"%s\",\"type\":\"%s\",\"code\":%d,\"message\":\"%s\",\"extra\":\"%s\",\"what\":\"%s\",\"file\":\"%s\",\"line\":%d,\"column\":%d,\"source\":\"%s\",\"stack\":\"%s\"}\n")
		, DiagSeverity(aErrorType), type, code, msg, extra, what, file, (int)aLineNumber, column, source, stack);
	if (n < 0 || n >= aBufSize)
		return (int)_tcslen(aBuf);
	return n;
}

void Script::PrintErrorStdOut(LPCTSTR aErrorText, int aLength, LPCTSTR aFile)
{
	bool is_stderr = aFile && !_tcscmp(aFile, _T("**"));
#ifdef CONFIG_DEBUGGER
	if (is_stderr)
	{
		if (g_Debugger.OutputStdErr(aErrorText))
			return;
	}
	else if (aFile && !_tcscmp(aFile, _T("*")))
	{
		if (g_Debugger.OutputStdOut(aErrorText))
			return;
	}
#endif
	// Structured JSON diagnostics must be UTF-8 (RFC 8259) regardless of the text
	// codepage chosen for /ErrorStdOut; plain-text output keeps the configured codepage.
	// (For pure-ASCII content the two are byte-identical, so this only matters for
	// non-ASCII messages, paths, or source lines.)
	UINT out_cp = mDiagJson ? CP_UTF8 : mErrorStdOutCP;

	TextFile tf;
	tf.Open(aFile, TextStream::APPEND, out_cp);
	tf.Write(aErrorText, aLength);
	tf.Close();

	// Tee stderr output to /StdErrFile= path if configured.
	if (is_stderr && CrashLog::IsStdErrFileEnabled() && aLength > 0)
	{
		if (out_cp == CP_UTF16)
		{
			// Write raw UTF-16LE bytes (same as what went to stderr).
			CrashLog::MirrorStderr(aErrorText, (size_t)aLength * sizeof(TCHAR));
		}
		else
		{
			// Convert wide chars to the target codepage, same as TextStream::Write does.
			UINT cp = (out_cp == 0) ? CP_ACP : (UINT)out_cp;
			int byte_count = WideCharToMultiByte(cp, 0, aErrorText, aLength, nullptr, 0, nullptr, nullptr);
			if (byte_count > 0)
			{
				char *buf = (char *)_alloca((size_t)byte_count);
				byte_count = WideCharToMultiByte(cp, 0, aErrorText, aLength, buf, byte_count, nullptr, nullptr);
				if (byte_count > 0)
					CrashLog::MirrorStderr(buf, (size_t)byte_count);
			}
		}
	}
}

int FormatStdErr(LPTSTR aBuf, int aBufSize, LPCTSTR aErrorText, LPCTSTR aExtraInfo,
	FileIndexType aFileIndex, LineNumberType aLineNumber, bool aWarn = false,
	Line *aLine = nullptr, bool aIncludeStack = false, bool aUseColor = false)
{
	// ANSI color codes are defined at file scope (shared with AppendSourceContext).

	int n = 0;

	// Error header line (with optional color)
	if (aUseColor)
		n += sntprintf(aBuf + n, aBufSize - n, aWarn ? ANSI_YELLOW : ANSI_RED);

	#define STD_ERROR_FORMAT _T("%s (%d) : ==> %s%s\n")
	n += sntprintf(aBuf + n, aBufSize - n, STD_ERROR_FORMAT, Line::sSourceFile[aFileIndex], aLineNumber
		, aWarn ? _T("Warning: ") : _T(""), aErrorText);

	if (aUseColor)
		n += sntprintf(aBuf + n, aBufSize - n, ANSI_RESET);

	// Extra info (Specifically: ...) — the label is dimmed so the value stands out.
	if (*aExtraInfo)
	{
		if (aUseColor)
			n += sntprintf(aBuf + n, aBufSize - n, _T("     ") ANSI_DIM _T("Specifically:") ANSI_RESET _T(" %s\n"), aExtraInfo);
		else
			n += sntprintf(aBuf + n, aBufSize - n, _T("     Specifically: %s\n"), aExtraInfo);
	}

	// Source line display: prefer a verbatim context block read from the file; fall
	// back to the decompiled single line if the file can't be read (stdin, embedded,
	// deleted, or a line beyond EOF).
	if (aLine)
	{
		int ctx = AppendSourceContext(aBuf + n, aBufSize - n, aFileIndex, aLineNumber, aUseColor);
		if (ctx >= 0)
			n += ctx;
		else
		{
			TCHAR line_buf[LINE_SIZE];
			aLine->ToText(line_buf, _countof(line_buf), false, 0, false, false);
			if (aUseColor)
				n += sntprintf(aBuf + n, aBufSize - n, _T("          ") ANSI_CYAN _T("%d| %s") ANSI_RESET _T("\n"),
					(int)aLineNumber, line_buf);
			else
				n += sntprintf(aBuf + n, aBufSize - n, _T("          %d| %s\n"),
					(int)aLineNumber, line_buf);
		}
	}

	// Stack trace (for runtime errors)
	{
		TCHAR stack_buf[SCRIPT_STACK_BUF_SIZE];
		RetrieveErrorStack(stack_buf, _countof(stack_buf), aIncludeStack);
		if (*stack_buf)
		{
			if (aUseColor)
				n += sntprintf(aBuf + n, aBufSize - n, _T("     ") ANSI_DIM _T("Call stack:") ANSI_RESET _T("\n"));
			else
				n += sntprintf(aBuf + n, aBufSize - n, _T("     Call stack:\n"));
			// Indent each line of the stack trace
			LPTSTR line_start = stack_buf;
			for (LPTSTR p = stack_buf; ; ++p)
			{
				if (*p == '\r' || *p == '\n' || *p == '\0')
				{
					bool is_end = (*p == '\0');
					TCHAR saved = *p;
					if (*p == '\r' && *(p+1) == '\n')
					{
						*p = '\0';
						++p;
					}
					else
						*p = '\0';
					if (*line_start)
						n += sntprintf(aBuf + n, aBufSize - n, _T("          %s\n"), line_start);
					if (is_end)
						break;
					*p = saved;
					line_start = p + 1;
				}
			}
		}
	}

	return n;
}

// For backward compatibility, this actually prints to stderr, not stdout.
void Script::PrintErrorStdOut(LPCTSTR aErrorText, LPCTSTR aExtraInfo, FileIndexType aFileIndex, LineNumberType aLineNumber, Line *aLine)
{
	TCHAR buf[DIAG_JSON_BUF_SIZE];
	// This is the load-time path (mIsReadyToExecute is false here); FormatDiagJson derives
	// the correct code (PARSE/VALIDATE) from that state rather than from aErrorType.
	auto n = mDiagJson
		? FormatDiagJson(buf, _countof(buf), aErrorText, aExtraInfo, aFileIndex, aLineNumber, FAIL, aLine, false)
		: FormatStdErr(buf, _countof(buf), aErrorText, aExtraInfo, aFileIndex, aLineNumber, false, aLine, false, mErrorStdOutColor);
	PrintErrorStdOut(buf, n, _T("**"));
}

ResultType Line::LineError(LPCTSTR aErrorText, ResultType aErrorType, LPCTSTR aExtraInfo)
{
	ASSERT(aErrorText);
	if (!aExtraInfo)
		aExtraInfo = _T("");

	if (g_script.mIsReadyToExecute)
	{
		return g_script.RuntimeError(aErrorText, aExtraInfo, aErrorType, this);
	}

	// Emit [PARSE] crash-log record for load-time syntax errors.
	if (aErrorType != WARN && CrashLog::IsCrashLogEnabled())
	{
		LPCTSTR err_file = (mFileIndex >= 0 && mFileIndex < Line::sSourceFileCount)
		                   ? Line::sSourceFile[mFileIndex]
		                   : _T("");
		CrashLog::LogParse(err_file, mLineNumber, aErrorText);
	}

#ifdef CONFIG_DLL
	if (LibNotifyProblem(aErrorText, aExtraInfo, this))
		return aErrorType;
#endif

	if (g_script.mErrorStdOut && aErrorType != WARN)
	{
		// JdeB said:
		// Just tested it in Textpad, Crimson and Scite. they all recognise the output and jump
		// to the Line containing the error when you double click the error line in the output
		// window (like it works in C++).  Had to change the format of the line to:
		// printf("%s (%d) : ==> %s: \n%s \n%s\n",szInclude, nAutScriptLine, szText, szScriptLine, szOutput2 );
		// MY: Full filename is required, even if it's the main file, because some editors (EditPlus)
		// seem to rely on that to determine which file and line number to jump to when the user double-clicks
		// the error message in the output window.
		// v1.0.47: Added a space before the colon as originally intended.  Toralf said, "With this minor
		// change the error lexer of Scite recognizes this line as a Microsoft error message and it can be
		// used to jump to that line."
		g_script.PrintErrorStdOut(aErrorText, aExtraInfo, mFileIndex, mLineNumber, this);
		return FAIL;
	}

	return g_script.ShowError(aErrorText, aErrorType, aExtraInfo, this);
}

ResultType Script::RuntimeError(LPCTSTR aErrorText, LPCTSTR aExtraInfo, ResultType aErrorType, Line *aLine, Object *aPrototype)
{
	ASSERT(aErrorText);
	if (!aExtraInfo)
		aExtraInfo = _T("");

	if ((g->ExcptMode || mOnError.Count()
#ifdef CONFIG_DEBUGGER
		|| g_Debugger.BreakOnExceptionIsEnabled()
#endif
		|| aPrototype) && aErrorType != WARN)
		return ThrowRuntimeException(aErrorText, aExtraInfo, aLine, aErrorType, aPrototype);
	
#ifdef CONFIG_DLL
	if (LibNotifyProblem(aErrorText, aExtraInfo, aLine))
		return aErrorType;
#endif
	
	return ShowError(aErrorText, aErrorType, aExtraInfo, aLine);
}

FResult FError(LPCTSTR aErrorText, LPCTSTR aExtraInfo, Object *aPrototype)
{
	return g_script.RuntimeError(aErrorText, aExtraInfo, FAIL_OR_OK, nullptr, aPrototype) ? FR_ABORTED : FR_FAIL;
}


struct ErrorBoxParam
{
	LPCTSTR text;
	ResultType type;
	LPCTSTR info;
	Line *line;
	Object *obj;
#ifdef CONFIG_DEBUGGER
	int stack_index;
#endif
};


#ifdef CONFIG_DEBUGGER
void InsertCallStack(HWND re, ErrorBoxParam &error)
{
	TCHAR buf[SCRIPT_STACK_BUF_SIZE], *stack = _T("");
	if (error.obj && error.obj->IsOfType(Object::sPrototype))
	{
		auto obj = static_cast<Object*>(error.obj);
		if (auto temp = obj->GetOwnPropString(_T("Stack")))
			stack = temp;
	}
	else if (error.stack_index >= 0)
	{
		GetScriptStack(stack = buf, _countof(buf), g_Debugger.mStack.mBottom + error.stack_index);
	}

	CHARFORMAT cfBold;
	cfBold.cbSize = sizeof(cfBold);
	cfBold.dwMask = CFM_BOLD | CFM_LINK;
	cfBold.dwEffects = CFE_BOLD;
	SendMessage(re, EM_SETCHARFORMAT, SCF_SELECTION, (LPARAM)&cfBold);
	SendMessage(re, EM_REPLACESEL, FALSE, (LPARAM)_T("Call stack:\n"));
	cfBold.dwEffects = 0;
	SendMessage(re, EM_SETCHARFORMAT, SCF_SELECTION, (LPARAM)&cfBold);

	if (!*stack)
		return;

	// Prevent insertion of a blank line at the end (a bit pedantic, I know):
	auto stack_end = _tcschr(stack, '\0');
	if (stack_end[-1] == '\n')
		*--stack_end = '\0';
	if (stack_end > stack && stack_end[-1] == '\r')
		*--stack_end = '\0';
	
	CHARFORMAT cfLink;
	cfLink.cbSize = sizeof(cfLink);
	cfLink.dwMask = CFM_LINK | CFM_BOLD;
	cfLink.dwEffects = CFE_LINK;
	//cfLink.crTextColor = 0xbb4d00; // Has no effect on Windows 7 or 11 (even with CFM_COLOR).

	CHARRANGE cr;
	SendMessage(re, EM_EXGETSEL, 0, (LPARAM)&cr); // This will become the start position of the stack text.
	auto start_pos = cr.cpMin;
	SendMessage(re, EM_REPLACESEL, FALSE, (LPARAM)stack);
		
	for (auto cp = stack; ; )
	{
		if (auto ext = _tcsstr(cp, _T(".ahk (")))
		{
			// Apply CFE_LINK effect (and possibly colour) to the full path.
			cr.cpMax = cr.cpMin + int(ext - cp) + 4;
			SendMessage(re, EM_EXSETSEL, 0, (LPARAM)&cr);
			SendMessage(re, EM_SETCHARFORMAT, SCF_SELECTION, (LPARAM)&cfLink);
		}
		auto cpn = _tcschr(cp, '\n');
		if (!cpn)
			break;
		cr.cpMin += int(cpn - cp);
		if (cpn == cp || cpn[-1] != '\r') // Count the \n only if \r wasn't already counted, since it seems RichEdit uses just \r internally.
			++cr.cpMin;
		cp = cpn + 1;
	}

	cr.cpMin = cr.cpMax = start_pos - 1; // Remove selection.
	SendMessage(re, EM_EXSETSEL, 0, (LPARAM)&cr);
}
#endif


void InitErrorBox(HWND hwnd, ErrorBoxParam &error)
{
	TCHAR buf[1024];

	SetWindowText(hwnd, g_script.DefaultDialogTitle());

	SetWindowLongPtr(hwnd, DWLP_USER, (LONG_PTR)&error);

	HWND re = GetDlgItem(hwnd, IDC_ERR_EDIT);

	RECT rc, rcOffset {0,0,7,7};
	SendMessage(re, EM_GETRECT, 0, (LPARAM)&rc);
	MapDialogRect(hwnd, &rcOffset);
	rc.left += rcOffset.right;
	rc.top += rcOffset.bottom;
	rc.right -= rcOffset.right;
	rc.bottom -= rcOffset.bottom;
	SendMessage(re, EM_SETRECTNP, 0, (LPARAM)&rc);

	PARAFORMAT pf;
	pf.cbSize = sizeof(pf);
	pf.dwMask = PFM_TABSTOPS;
	pf.cTabCount = 1;
	pf.rgxTabs[0] = 300;
	SendMessage(re, EM_SETPARAFORMAT, 0, (LPARAM)&pf);

	SETTEXTEX t { ST_SELECTION | ST_UNICODE, CP_UTF16 };
	SETTEXTEX t_rtf { ST_SELECTION | ST_DEFAULT, CP_UTF8 };

	CHARFORMAT2 cf;
	cf.cbSize = sizeof(cf);

	cf.dwMask = CFM_SIZE;
	cf.yHeight = 9*20;
	SendMessage(re, EM_SETCHARFORMAT, SCF_DEFAULT, (LPARAM)&cf);
	
	cf.dwMask = CFM_SIZE | CFM_COLOR;
	cf.yHeight = 10*20;
	cf.crTextColor = 0x3399;
	cf.dwEffects = 0;
	SendMessage(re, EM_SETCHARFORMAT, SCF_SELECTION, (LPARAM)&cf);
	
	sntprintf(buf, _countof(buf), _T("%s: %.500s\n")
		, error.type == CRITICAL_ERROR ? _T("Critical Error")
			: error.type == WARN ? _T("Warning") : _T("Error")
		, error.text);
	auto cp = _tcschr(buf, '\n');
	if (auto c = *++cp) // Multiple lines in error.text.
	{
		// Insert a break *after* the \n so that formatting will revert to default afterward.
		*cp = '\0';
		SendMessage(re, EM_REPLACESEL, FALSE, (LPARAM)buf);
		*cp = c;
	}
	else
		cp = buf;
	SendMessage(re, EM_REPLACESEL, FALSE, (LPARAM)cp);
	
	bool file_needs_break = true;
	if (error.info && *error.info)
	{
		UINT suffix = _tcslen(error.info) > 80 ? 8230 : 0;
		if (file_needs_break = error.line || error.obj)
			sntprintf(buf, _countof(buf), _T("\nSpecifically: %.80s%s\n"), error.info, &suffix);
		else
			sntprintf(buf, _countof(buf), _T("\nText:\t%.80s%s\n"), error.info, &suffix);
		SendMessage(re, EM_REPLACESEL, FALSE, (LPARAM)buf);
	}

	if (error.line)
	{
		SendMessage(re, EM_REPLACESEL, FALSE, (LPARAM)_T("\n"));

		#define LINES_ABOVE_AND_BELOW 2

		// Determine the range of lines to be shown:
		Line *line_start = error.line, *line_end = error.line;
		if (g_AllowMainWindow)
		{
			for (int i = 0
				; i < LINES_ABOVE_AND_BELOW && line_start->mPrevLine != NULL
				; ++i, line_start = line_start->mPrevLine);
			for (int i = 0
				; i < LINES_ABOVE_AND_BELOW && line_end->mNextLine != NULL
				; ++i, line_end = line_end->mNextLine);
		}
		//else show only a single line, to conceal the script's source code.

		int last_file = 0; // Init to zero so path is omitted if it is the main file.
		for (auto line = line_start; ; line = line->mNextLine)
		{
			if (last_file != line->mFileIndex)
			{
				last_file = line->mFileIndex;
				sntprintf(buf, _countof(buf), _T("\t---- %s\n"), Line::sSourceFile[line->mFileIndex]);
				SendMessage(re, EM_REPLACESEL, FALSE, (LPARAM)buf);
			}
			int lead = 0;
			if (line == error.line)
			{
				cf.dwMask = CFM_COLOR | CFM_BACKCOLOR;
				cf.crTextColor = 0; // Use explicit black to ensure visibility if a high contrast theme is enabled.
				cf.crBackColor = 0x60ffff;
				SendMessage(re, EM_SETCHARFORMAT, SCF_SELECTION, (LPARAM)&cf);
				buf[lead++] = 9654; // ▶
			}
			buf[lead++] = '\t';
			buf[lead] = '\0';
			SendMessage(re, EM_REPLACESEL, FALSE, (LPARAM)buf);

			line->ToText(buf, _countof(buf), true);
			SendMessage(re, EM_REPLACESEL, FALSE, (LPARAM)buf);
			if (line == line_end)
				break;
		}
	}
	else
	{
		LPCTSTR file = nullptr;
		LineNumberType line = 0;
		if (error.obj)
		{
			file = error.obj->GetOwnPropString(_T("File"));
			line = (LineNumberType)error.obj->GetOwnPropInt64(_T("Line"));
		}
		else
		{
			file = g_script.CurrentFile();
			line = g_script.CurrentLine();
		}
		if (file && *file)
		{
			sntprintf(buf, _countof(buf), line ? _T("\nLine:\t%d\nFile:\t") : _T("\nFile: "), line);
			SendMessage(re, EM_REPLACESEL, FALSE, (LPARAM)(buf + !file_needs_break));
			cf.dwMask = CFM_LINK;
			cf.dwEffects = CFE_LINK; // Mark it as a link.
			SendMessage(re, EM_SETCHARFORMAT, SCF_SELECTION, (LPARAM)&cf);
			SendMessage(re, EM_REPLACESEL, FALSE, (LPARAM)file);
			SendMessage(re, EM_REPLACESEL, FALSE, (LPARAM)_T("\n"));
		}
	}

	LPCTSTR footer = error.obj ? error.obj->GetOwnPropString(_T("Hint")) : nullptr;
	if (footer) // Footer was specified.
	{
		if (!*footer) // Explicitly blank: omit default footer.
			footer = nullptr;
	}
	else // Use default footer for this error type, if any.
	{
		switch (error.type)
		{
		case WARN: footer = ERR_WARNING_FOOTER; break;
		case FAIL_OR_OK: break;
		case CRITICAL_ERROR: footer = UNSTABLE_WILL_EXIT; break;
		default: footer = (g->ExcptMode & EXCPTMODE_DELETE) ? ERR_ABORT_DELETE
			: g_script.mIsReadyToExecute ? ERR_ABORT_NO_SPACES
			: g_script.mIsRestart ? OLD_STILL_IN_EFFECT
			: WILL_EXIT;
		}
	}
	if (footer)
	{
		SendMessage(re, EM_REPLACESEL, FALSE, (LPARAM)_T("\n"));
		SendMessage(re, EM_REPLACESEL, FALSE, (LPARAM)footer);
	}

#ifdef CONFIG_DEBUGGER
	LPCTSTR stack;
	if (   error.stack_index >= 0
		|| error.obj && error.obj->IsOfType(Object::sPrototype)
			&& (stack = error.obj->GetOwnPropString(_T("Stack"))) && *stack   )
	{
		// Stack trace appears to be available, so add a link to show it.
		CHARRANGE cr;
		for (int i = footer ? 2 : 1; i; --i)
			SendMessage(re, EM_REPLACESEL, FALSE, (LPARAM)_T("\n"));
		SendMessage(re, EM_EXGETSEL, 0, (LPARAM)&cr);
#define SHOW_CALL_STACK_TEXT _T("Show call stack »")
		SendMessage(re, EM_REPLACESEL, FALSE, (LPARAM)SHOW_CALL_STACK_TEXT);
		cr.cpMax = -1; // Select to end.
		SendMessage(re, EM_EXSETSEL, 0, (LPARAM)&cr);
		cf.dwMask = CFM_LINK;
		cf.dwEffects = CFE_LINK; // Mark it as a link.
		SendMessage(re, EM_SETCHARFORMAT, SCF_SELECTION, (LPARAM)&cf);
		cr.cpMin = -1; // Deselect (move selection anchor to insertion point).
		SendMessage(re, EM_EXSETSEL, 0, (LPARAM)&cr);
	}
#endif

	SendMessage(re, EM_SETEVENTMASK, 0, ENM_REQUESTRESIZE | ENM_LINK | ENM_KEYEVENTS);
	SendMessage(re, EM_REQUESTRESIZE, 0, 0);

#ifndef AUTOHOTKEYSC
	if (error.line && error.line->mFileIndex ? *Line::sSourceFile[error.line->mFileIndex] == '*'
		: g_script.mKind != Script::ScriptKindFile)
		// Source "file" is an embedded resource or stdin, so can't be edited.
		EnableWindow(GetDlgItem(hwnd, ID_FILE_EDITSCRIPT), FALSE);
#endif

	if (error.type != FAIL_OR_OK)
	{
		HWND hide = GetDlgItem(hwnd, error.type == WARN ? IDCANCEL : IDCONTINUE);
		if (error.type == WARN)
		{
			// Hide "Abort" since it it's not applicable to warnings except as an alias of ExitApp,
			// shift "Continue" to the right for aesthetic purposes and make it the default button
			// (otherwise the left-most button would become the default).
			RECT rc;
			GetClientRect(hide, &rc);
			MapWindowPoints(hide, hwnd, (LPPOINT)&rc, 1);
			HWND keep = GetDlgItem(hwnd, IDCONTINUE);
			MoveWindow(keep, rc.left, rc.top, rc.right, rc.bottom, FALSE);
			DefDlgProc(hwnd, DM_SETDEFID, IDCONTINUE, 0);
			SetFocus(keep);
		}
		ShowWindow(hide, SW_HIDE);
	}
}


INT_PTR CALLBACK ErrorBoxProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
	switch (msg)
	{
	case WM_COMMAND:
		switch (LOWORD(wParam))
		{
		case IDCONTINUE:
		case IDCANCEL:
			EndDialog(hwnd, wParam);
			return TRUE;
		case ID_FILE_EDITSCRIPT:
		{
			auto &error = *(ErrorBoxParam*)GetWindowLongPtr(hwnd, DWLP_USER);
			if (error.line)
			{
				g_script.Edit(Line::sSourceFile[error.line->mFileIndex]);
				return TRUE;
			}
		}
		default:
			if (LOWORD(wParam) >= ID_FILE_RELOADSCRIPT)
			{
				// Call the handler directly since g_hWnd might be NULL if this is a warning dialog.
				HandleMenuItem(NULL, LOWORD(wParam), NULL);
				if (LOWORD(wParam) == ID_FILE_RELOADSCRIPT)
					EndDialog(hwnd, IDCANCEL);
				return TRUE;
			}
		}
		break;
	case WM_NOTIFY:
		if (wParam == IDC_ERR_EDIT)
		{
			HWND re = ((NMHDR*)lParam)->hwndFrom;
			switch (((NMHDR*)lParam)->code)
			{
			case EN_MSGFILTER:
			{
				auto mf = (MSGFILTER*)lParam;
				if (mf->msg == WM_CHAR)
					// Forward it to any of the buttons so the dialog will process it as a mnemonic.
					PostMessage(GetDlgItem(hwnd, IDCANCEL), mf->msg, mf->wParam, mf->lParam);
				break;
			}
			case EN_REQUESTRESIZE: // Received when the RichEdit's content grows beyond its capacity to display all at once.
			{
				RECT &rcNew = ((REQRESIZE*)lParam)->rc;
				RECT rcOld, rcInner;
				GetWindowRect(re, &rcOld);
				SendMessage(re, EM_GETRECT, 0, (LPARAM)&rcInner);
				// Stack traces can get quite "tall" if the paths/lines are mostly short,
				// so impose a rough limit to ensure the dialog remains usable.
				int rough_limit = GetSystemMetrics(SM_CYSCREEN) * 3 / 4;
				if (rcNew.bottom > rough_limit)
					rcNew.bottom = rough_limit;
				int delta = rcNew.bottom - (rcInner.bottom - rcInner.top);
				if (rcNew.bottom == rough_limit)
					SendMessage(re, EM_SHOWSCROLLBAR, SB_VERT, TRUE);
				// Enable horizontal scroll bars if necessary.
				if (rcNew.right > (rcInner.right - rcInner.left)
					&& !(GetWindowLong(re, GWL_STYLE) & WS_HSCROLL))
				{
					SendMessage(re, EM_SHOWSCROLLBAR, SB_HORZ, TRUE);
					delta += GetSystemMetrics(SM_CYHSCROLL);
				}
				// Move the buttons (and the RichEdit, temporarily).
				ScrollWindow(hwnd, 0, delta, NULL, NULL);
				// Resize the RichEdit, while also moving it back to the origin.
				MoveWindow(re, 0, 0, rcOld.right - rcOld.left, rcOld.bottom - rcOld.top + delta, TRUE);
				// Adjust the dialog's height and vertical position.
				GetWindowRect(hwnd, &rcOld);
				MoveWindow(hwnd, rcOld.left, rcOld.top - (delta / 2), rcOld.right - rcOld.left, rcOld.bottom - rcOld.top + delta, TRUE);
				break;
			}
			case EN_LINK: // Received when the user clicks or moves the mouse over text with the CFE_LINK effect.
				if (((ENLINK*)lParam)->msg == WM_LBUTTONUP)
				{
					TEXTRANGE tr { ((ENLINK*)lParam)->chrg };
					SendMessage(re, EM_EXSETSEL, 0, (LPARAM)&tr.chrg);
					tr.lpstrText = (LPTSTR)talloca(tr.chrg.cpMax - tr.chrg.cpMin + 1);
					*tr.lpstrText = '\0';
					SendMessage(re, EM_GETTEXTRANGE, 0, (LPARAM)&tr);
					PostMessage(hwnd, WM_NEXTDLGCTL, TRUE, FALSE); // Make it less edit-like by shifting focus away.
#ifdef CONFIG_DEBUGGER
					if (!_tcscmp(tr.lpstrText, SHOW_CALL_STACK_TEXT))
					{
						auto &error = *(ErrorBoxParam*)GetWindowLongPtr(hwnd, DWLP_USER);
						InsertCallStack(re, error);
						return TRUE;
					}
#endif
					g_script.Edit(tr.lpstrText);
					return TRUE;
				}
				break;
			}
		}
		break;
	case WM_INITDIALOG:
		InitErrorBox(hwnd, *(ErrorBoxParam *)lParam);
		return FALSE; // "return FALSE to prevent the system from setting the default keyboard focus"
	}
	return FALSE;
}


__declspec(noinline)
ResultType Script::ShowError(LPCTSTR aErrorText, ResultType aErrorType, LPCTSTR aExtraInfo, Line *aLine)
{
	// This overload reduces code size vs. using optional parameters since the the latter
	// works by the compiler implicitly inserting the default values in the compiled code.
	return ShowError(aErrorText, aErrorType, aExtraInfo, aLine, nullptr);
}


ResultType Script::ShowError(LPCTSTR aErrorText, ResultType aErrorType, LPCTSTR aExtraInfo, Line *aLine, Object *aException)
{
	if (!aErrorText)
		aErrorText = _T("");
	if (!aExtraInfo)
		aExtraInfo = _T("");

#ifdef CONFIG_DEBUGGER
	// Feed the debugger's stderr stream only when the console/headless path below won't:
	// that path writes via PrintErrorStdOut("**"), which already routes to OutputStdErr
	// when a hook is active.  Without this guard the debugger client receives each error
	// twice (once here, once from the stderr path).
	if (g_Debugger.HasStdErrHook() && !(mErrorStdOut || mHeadless))
	{
		TCHAR buf[LINE_SIZE * 4];
		Line *line = aLine ? aLine : mCurrLine;
		FormatStdErr(buf, _countof(buf), aErrorText, aExtraInfo
			, line ? line->mFileIndex : mCurrFileIndex
			, line ? line->mLineNumber : mCombinedLineNumber
			, aErrorType == WARN, line, mIsReadyToExecute, false);
		g_Debugger.OutputStdErr(buf);
	}
#endif

	// If /ErrorStdOut or headless mode is enabled, output runtime errors to stderr instead of showing a dialog.
	// This enables headless/console operation where all errors go to the shell.
	if (mErrorStdOut || mHeadless)
	{
		TCHAR buf[DIAG_JSON_BUF_SIZE];
		Line *line = aLine ? aLine : mCurrLine;
		if (mDiagJson)
			FormatDiagJson(buf, _countof(buf), aErrorText, aExtraInfo
				, line ? line->mFileIndex : mCurrFileIndex
				, line ? line->mLineNumber : mCombinedLineNumber
				, aErrorType, line, mIsReadyToExecute, aException);
		else
			FormatStdErr(buf, _countof(buf), aErrorText, aExtraInfo
				, line ? line->mFileIndex : mCurrFileIndex
				, line ? line->mLineNumber : mCombinedLineNumber
				, aErrorType == WARN, line, mIsReadyToExecute, mErrorStdOutColor);
		PrintErrorStdOut(buf, (int)_tcslen(buf), _T("**")); // ** means stderr

		// Handle exit behavior based on error type
		if (aErrorType == WARN)
			return OK; // Warnings don't abort execution
		// Set exit code before calling ExitApp
		mPendingExitCode = (aErrorType == CRITICAL_ERROR) ? AHK_EXIT_CRITICAL_ERROR : AHK_EXIT_RUNTIME_ERROR;
		mHasPendingExitCode = true;
		ExitApp((aErrorType == CRITICAL_ERROR) ? EXIT_CRITICAL : EXIT_ERROR);
		return FAIL; // Not reached, but keeps compiler happy
	}

	static auto sMod = LoadLibrary(_T("msftedit.dll"));
	ErrorBoxParam error;
	error.text = aErrorText;
	error.type = aErrorType;
	error.info = aExtraInfo;
	error.line = aLine;
	error.obj = aException;
#ifdef CONFIG_DEBUGGER
	error.stack_index = (aException || !g_script.mIsReadyToExecute) ? -1 : int(g_Debugger.mStack.mTop - g_Debugger.mStack.mBottom);
#endif
	INT_PTR result = DialogBoxParam(NULL, MAKEINTRESOURCE(IDD_ERRORBOX), NULL, ErrorBoxProc, (LPARAM)&error);
	if (result == IDCONTINUE && aErrorType == FAIL_OR_OK)
		return OK;
	if (result == -1) // May have failed to show the custom dialog box.
		MsgBox(aErrorText, MB_TOPMOST); // Keep it simple since it will hopefully never be needed.

	if (aErrorType == CRITICAL_ERROR && mIsReadyToExecute)
		ExitApp(EXIT_CRITICAL); // Pass EXIT_CRITICAL to ensure the program always exits, regardless of OnExit.
	if (aErrorType == WARN && result == IDCANCEL && !mIsReadyToExecute) // Let Escape cancel loading the script.
		ExitApp(EXIT_EXIT);

	return FAIL; // Some callers rely on a FAIL result to propagate failure.
}



ResultType Script::ScriptError(LPCTSTR aErrorText, LPCTSTR aExtraInfo)
// Even though this is a Script method, including it here since it shares
// a common theme with the other error-displaying functions:
{
	if (mCurrLine && g_script.mIsReadyToExecute)
		// If a line is available, do RuntimeError instead for exceptions and line context.
		return RuntimeError(aErrorText, aExtraInfo, FAIL, mCurrLine);
	// Otherwise: The fact that mCurrLine is NULL means that the line currently being loaded
	// has not yet been successfully added to the linked list.  Such errors will always result
	// in the program exiting.
	if (!aErrorText)
		aErrorText = _T("Unk"); // Placeholder since it shouldn't be NULL.
	if (!aExtraInfo) // In case the caller explicitly called it with NULL.
		aExtraInfo = _T("");

	// Emit [PARSE] crash-log record for load-time syntax errors.
	if (!mIsReadyToExecute && CrashLog::IsCrashLogEnabled())
	{
		LPCTSTR err_file = (mCurrFileIndex >= 0 && mCurrFileIndex < Line::sSourceFileCount)
		                   ? Line::sSourceFile[mCurrFileIndex]
		                   : _T("");
		CrashLog::LogParse(err_file, mCombinedLineNumber, aErrorText);
	}

#ifdef CONFIG_DLL
	if (LibNotifyProblem(aErrorText, aExtraInfo, nullptr))
		return FAIL;
#endif
	
	if (g_script.mErrorStdOut && !g_script.mIsReadyToExecute) // i.e. runtime errors are always displayed via dialog.
	{
		// See LineError() for details.
		PrintErrorStdOut(aErrorText, aExtraInfo, mCurrLine ? mCurrLine->mFileIndex : mCurrFileIndex, CurrentLine(), mCurrLine);
	}
	else
	{
		ShowError(aErrorText, FAIL, aExtraInfo, nullptr);
	}
	return FAIL; // See above for why it's better to return FAIL than CRITICAL_ERROR.
}



LPCTSTR VarKindForErrorMessage(Var *aVar)
{
	switch (aVar->Type())
	{
	case VAR_VIRTUAL: return _T("built-in variable");
	case VAR_CONSTANT: return aVar->Object()->Type();
	default: return Var::DeclarationType(aVar->Scope());
	}
}

ResultType Script::ConflictingDeclarationError(LPCTSTR aDeclType, Var *aExisting)
{
	TCHAR buf[127];
	sntprintf(buf, _countof(buf), _T("This %s declaration conflicts with an existing %s.")
		, aDeclType, VarKindForErrorMessage(aExisting));
	return ScriptError(buf, aExisting->mName);
}


ResultType Line::ValidateVarUsage(Var *aVar, int aUsage)
{
	if (VARREF_IS_WRITE(aUsage) && aVar->IsReadOnly() && aUsage != VARREF_LVALUE_MAYBE)
		return VarIsReadOnlyError(aVar, aUsage);
	return OK;
}

__declspec(noinline)
ResultType Script::VarIsReadOnlyError(Var *aVar, int aErrorType)
{
	TCHAR buf[127];
	sntprintf(buf, _countof(buf), _T("This %s cannot %s.")
		, VarKindForErrorMessage(aVar)
		, aErrorType == VARREF_OUTPUT_VAR ? _T("be used as an output variable")
		: aErrorType == VARREF_REF ? _T("have its reference taken")
		: _T("be assigned a value"));
	return ScriptError(buf, aVar->mName);
}

ResultType Line::VarIsReadOnlyError(Var *aVar, int aErrorType)
{
	g_script.mCurrLine = this;
	return g_script.VarIsReadOnlyError(aVar, aErrorType);
}


ResultType Line::LineUnexpectedError()
{
	TCHAR buf[127];
	sntprintf(buf, _countof(buf), _T("Unexpected \"%s\""), g_act[mActionType].Name);
	return LineError(buf);
}



ResultType Script::CriticalError(LPCTSTR aErrorText, LPCTSTR aExtraInfo)
{
	g->ExcptMode = EXCPTMODE_NONE; // Do not throw an exception.
	if (mCurrLine)
		mCurrLine->LineError(aErrorText, CRITICAL_ERROR, aExtraInfo);
	// mCurrLine should always be non-NULL during runtime, and CRITICAL_ERROR should
	// cause LineError() to exit even if an OnExit routine is present, so this is here
	// mainly for maintainability.
	TerminateApp(EXIT_CRITICAL, 0);
	return FAIL; // Never executed.
}



__declspec(noinline)
ResultType ResultToken::Error(LPCTSTR aErrorText)
{
	// Defining this overload separately rather than making aErrorInfo optional reduces code size
	// by not requiring the compiler to 'push' the second parameter's default value at each call site.
	return Error(aErrorText, _T(""));
}

__declspec(noinline)
ResultType ResultToken::Error(LPCTSTR aErrorText, LPCTSTR aExtraInfo)
{
	return Error(aErrorText, aExtraInfo, nullptr);
}

__declspec(noinline)
ResultType ResultToken::Error(LPCTSTR aErrorText, Object *aPrototype)
{
	return Error(aErrorText, nullptr, aPrototype);
}

__declspec(noinline)
ResultType ResultToken::Error(LPCTSTR aErrorText, LPCTSTR aExtraInfo, Object *aPrototype)
{
	// These two assertions should always pass, since anything else would imply returning a value,
	// not throwing an error.  If they don't, the memory/object might not be freed since the caller
	// isn't expecting a value, or they might be freed twice (if the callee already freed it).
	//ASSERT(!mem_to_free); // At least one caller frees it after calling this function.
	ASSERT(symbol != SYM_OBJECT);
	return Fail(g_script.RuntimeError(aErrorText, aExtraInfo, FAIL_OR_OK, g_script.mCurrLine, aPrototype));
}

__declspec(noinline)
ResultType ResultToken::Error(LPCTSTR aErrorText, ExprTokenType &aExtraInfo, Object *aPrototype)
{
	TCHAR buf[MAX_NUMBER_SIZE];
	return Error(aErrorText, TokenToString(aExtraInfo, buf), aPrototype);
}

__declspec(noinline)
ResultType ResultToken::MemoryError()
{
	return Error(ERR_OUTOFMEM, nullptr, ErrorPrototype::Memory);
}

ResultType MemoryError()
{
	return g_script.RuntimeError(ERR_OUTOFMEM, nullptr, FAIL, nullptr, ErrorPrototype::Memory);
}

void SimpleHeap::CriticalFail()
{
	g_script.CriticalError(ERR_OUTOFMEM);
}

__declspec(noinline)
ResultType ResultToken::ValueError(LPCTSTR aErrorText)
{
	return Error(aErrorText, nullptr, ErrorPrototype::Value);
}

__declspec(noinline)
ResultType ResultToken::ValueError(LPCTSTR aErrorText, LPCTSTR aExtraInfo)
{
	return Error(aErrorText, aExtraInfo, ErrorPrototype::Value);
}

__declspec(noinline)
ResultType ValueError(LPCTSTR aErrorText, LPCTSTR aExtraInfo, ResultType aErrorType)
{
	if (!g_script.mIsReadyToExecute)
		return g_script.ScriptError(aErrorText, aExtraInfo);
	return g_script.RuntimeError(aErrorText, aExtraInfo, aErrorType, nullptr, ErrorPrototype::Value);
}

__declspec(noinline)
FResult FValueError(LPCTSTR aErrorText, LPCTSTR aExtraInfo)
{
	return FError(aErrorText, aExtraInfo, ErrorPrototype::Value);
}

__declspec(noinline)
ResultType ResultToken::UnknownMemberError(ExprTokenType &aObject, int aFlags, LPCTSTR aMember)
{
	TCHAR msg[512];
	if (!aMember)
		aMember = (aFlags & IT_CALL) ? _T("Call") : _T("__Item");
	sntprintf(msg, _countof(msg), _T("This value of type \"%s\" has no %s named \"%s\".")
		, TokenTypeString(aObject), (aFlags & IT_CALL) ? _T("method") : _T("property"), aMember);
	return Error(msg, nullptr, (aFlags & IT_CALL) ? ErrorPrototype::Method : ErrorPrototype::Property);
}

__declspec(noinline)
ResultType ResultToken::Win32Error(DWORD aError)
{
	if (g_script.Win32Error(aError) == FAIL)
		return SetExitResult(FAIL);
	SetValue(_T(""), 0);
	return FAIL;
}


void TokenTypeAndValue(ExprTokenType &aToken, LPCTSTR &aType, LPCTSTR &aValue, TCHAR *aNBuf)
{
	if (aToken.symbol == SYM_VAR && aToken.var->IsUninitializedNormalVar())
		aType = _T("unset variable"), aValue = aToken.var->mName;
	else if (aToken.symbol == SYM_MISSING) // Must be checked before TokenIsBlank() if SYM_MISSING is ever passed here.
		aType = _T("unset"), aValue = _T("");
	else if (TokenIsBlank(aToken))
		aType = _T("empty string"), aValue = _T("");
	else
		aType = TokenTypeString(aToken), aValue = TokenToString(aToken, aNBuf);
}


__declspec(noinline)
ResultType TypeError(LPCTSTR aExpectedType, ExprTokenType &aActualValue)
{
	TCHAR number_buf[MAX_NUMBER_SIZE];
	LPCTSTR actual_type, value_as_string;
	if (aActualValue.symbol == SYM_VAR && aActualValue.var->IsUninitializedNormalVar())
		return g_script.VarUnsetError(aActualValue.var);
	TokenTypeAndValue(aActualValue, actual_type, value_as_string, number_buf);
	return TypeError(aExpectedType, actual_type, value_as_string);
}

ResultType TypeError(LPCTSTR aExpectedType, LPCTSTR aActualType, LPCTSTR aExtraInfo)
{
	auto an = [](LPCTSTR thing) {
		return *thing ? _tcschr(_T("aeiou"), ctolower(*thing)) ? _T("an ") : _T("a ") : _T("nothing");
	};
	TCHAR msg[512];
	sntprintf(msg, _countof(msg), _T("Expected %s%s but got %s%s.")
		, an(aExpectedType), aExpectedType, an(aActualType), aActualType);
	return g_script.RuntimeError(msg, aExtraInfo, FAIL_OR_OK, nullptr, ErrorPrototype::Type);
}

ResultType ResultToken::TypeError(LPCTSTR aExpectedType, ExprTokenType &aActualValue)
{
	return Fail(::TypeError(aExpectedType, aActualValue));
}

FResult FTypeError(LPCTSTR aExpectedType, ExprTokenType &aActualValue)
{
	return TypeError(aExpectedType, aActualValue) == OK ? FR_ABORTED : FR_FAIL;
}


__declspec(noinline)
ResultType ParamError(int aIndex, ExprTokenType *aParam, LPCTSTR aExpectedType, LPCTSTR aFunction)
{
	auto an = [](LPCTSTR thing) {
		return _tcschr(_T("aeiou"), ctolower(*thing)) ? _T("n") : _T("");
	};
	TCHAR msg[512];
	TCHAR number_buf[MAX_NUMBER_SIZE];
	LPCTSTR actual_type, value_as_string;
#ifdef CONFIG_DEBUGGER
	if (!aFunction)
		aFunction = g_Debugger.WhatThrew();
#endif
	if (!aParam || aParam->symbol == SYM_MISSING)
	{
#ifdef CONFIG_DEBUGGER
		sntprintf(msg, _countof(msg), _T("Parameter #%i of %s must not be omitted in this case.")
			, aIndex + 1, aFunction);
#else
		sntprintf(msg, _countof(msg), _T("Parameter #%i must not be omitted in this case.")
			, aIndex + 1);
#endif
		return g_script.RuntimeError(msg, nullptr, FAIL_OR_OK, nullptr, ErrorPrototype::Value);
	}
	TokenTypeAndValue(*aParam, actual_type, value_as_string, number_buf);
	if (!*value_as_string && !aExpectedType)
		value_as_string = actual_type;
#ifdef CONFIG_DEBUGGER
	if (aExpectedType)
		sntprintf(msg, _countof(msg), _T("Parameter #%i of %s requires a%s %s, but received a%s %s.")
			, aIndex + 1, aFunction, an(aExpectedType), aExpectedType, an(actual_type), actual_type);
	else
		sntprintf(msg, _countof(msg), _T("Parameter #%i of %s is invalid."), aIndex + 1, g_Debugger.WhatThrew());
#else
	if (aExpectedType)
		sntprintf(msg, _countof(msg), _T("Parameter #%i requires a%s %s, but received a%s %s.")
			, aIndex + 1, an(aExpectedType), aExpectedType, an(actual_type), actual_type);
	else
		sntprintf(msg, _countof(msg), _T("Parameter #%i invalid."), aIndex + 1);
#endif
	return g_script.RuntimeError(msg, value_as_string, FAIL_OR_OK, nullptr
		, aExpectedType ? ErrorPrototype::Type : ErrorPrototype::Value);
}

__declspec(noinline)
ResultType ResultToken::ParamError(int aIndex, ExprTokenType *aParam)
{
	return Fail(::ParamError(aIndex, aParam, nullptr, nullptr));
}

__declspec(noinline)
ResultType ResultToken::ParamError(int aIndex, ExprTokenType *aParam, LPCTSTR aExpectedType)
{
	return Fail(::ParamError(aIndex, aParam, aExpectedType, nullptr));
}

__declspec(noinline)
ResultType ResultToken::ParamError(int aIndex, ExprTokenType *aParam, LPCTSTR aExpectedType, LPCTSTR aFunction)
{
	return Fail(::ParamError(aIndex, aParam, aExpectedType, aFunction));
}

FResult FParamError(int aIndex, ExprTokenType *aParam, LPCTSTR aExpectedType)
{
	return ::ParamError(aIndex, aParam, aExpectedType, nullptr) == OK ? FR_ABORTED : FR_FAIL;
}



ResultType FResultToError(ResultToken &aResultToken, ExprTokenType *aParam[], int aParamCount, FResult aResult, int aFirstParam)
{
	if (aResult & FR_OUR_FLAG)
	{
		if (aResult & FR_INT_FLAG)
		{
			// This is a bit of a hack and should probably be revised.
			TCHAR buf[12];
			return aResultToken.Error(ERR_FAILED, _itot(FR_GET_THROWN_INT(aResult), buf, 10));
		}
		auto code = HRESULT_CODE(aResult);
		switch (HRESULT_FACILITY(aResult))
		{
		case FR_FACILITY_CONTROL:
			ASSERT(!code);
			return aResultToken.SetExitResult(FAIL);
		case FR_FACILITY_ARG:
			if (aResult == FR_E_ARGS)
				return aResultToken.Error(ERR_PARAM_INVALID);
			return aResultToken.ParamError(code, code + aFirstParam < aParamCount ? aParam[code + aFirstParam] : nullptr);
		case FACILITY_WIN32:
			if (!code)
				code = GetLastError();
			return aResultToken.Win32Error(code);
#ifndef _DEBUG
		default: // Using a default case may slightly reduce code size.
#endif
		case FR_FACILITY_ERR:
			switch (code)
			{
			case HRESULT_CODE(FR_E_OUTOFMEM):
				return aResultToken.MemoryError();
			}
		}
		ASSERT(aResult == FR_E_FAILED); // Alert for any unhandled error codes in debug mode.
		return aResultToken.Error(ERR_FAILED);
	}
	else // Presumably a HRESULT error value.
	{
		return aResultToken.Win32Error(aResult);
	}
}



Line *Script::GetLine(LPCTSTR aFile, int aNumber, Line *aCandidate)
{
	int file_index;
	for (file_index = 0; file_index < Line::sSourceFileCount; ++file_index)
		if (!_tcsicmp(aFile, Line::sSourceFile[file_index]))
			break;
	if (!aCandidate || aCandidate->mFileIndex != file_index || aCandidate->mLineNumber != aNumber) // Keep aLine if it matches, in case of multiple Lines with the same number.
	{
		for (auto mod = mLastModule; mod; mod = mod->mPrev)
		{
			for (Line *line = mod->mFirstLine; line; line = line->mNextLine)
			{
				if (line->mLineNumber == aNumber && line->mFileIndex == file_index
					&& (line->mArgc || !line->mNextLine || line->mNextLine->mLineNumber != aNumber))
					return line;
				if (line == mod->mLastLine)
					break;
			}
		}
	}
	return aCandidate;
}



bif_impl FResult _ScriptGetLines(StrArg aFilename, int aLineNumber, optl<int> aRange, IObject *&aRetVal)
{
	int range = aRange.value_or(0);
	Line *line = g_script.GetLine(aFilename, aLineNumber);
	if (!line)
		return OK; // Empty
	// Determine the range of lines to be shown:
	Line *line_start = line, *line_end = line;
	for (int i = range
		; i > 0 && line_start->mPrevLine != NULL
		; --i, line_start = line_start->mPrevLine);
	for (int i = range
		; i > 0 && line_end->mNextLine != NULL
		; --i, line_end = line_end->mNextLine);
	// Output
	auto lines = Array::Create();
	TCHAR buf[32768]; // Arbitrary maximum
	for (auto line = line_start; ; line = line->mNextLine)
	{
		auto obj = Object::Create();
		if (!obj)
		{
			lines->Release();
			return FR_E_OUTOFMEM;
		}
		line->ToText(buf, _countof(buf), false, 0, false, false);
		obj->SetOwnProp(_T("File"), Line::sSourceFile[line->mFileIndex]);
		obj->SetOwnProp(_T("Number"), line->mLineNumber);
		obj->SetOwnProp(_T("Text"), buf);
		ExprTokenType _et(obj);
		if (!lines->Append(_et))
		{
			obj->Release();
			lines->Release();
			return FR_E_OUTOFMEM;
		}
		if (line == line_end)
			break;
	}
	aRetVal = lines;
	return OK;
}


// ============================================================================
// tree-sitter integration — TSParse(Source) -> parsed-tree snapshot
//
// Loads tree-sitter-ahk.dll (the self-contained AHK grammar + bundled
// tree-sitter runtime; see docs/TREE_SITTER.md) on first use. TSParse walks the
// whole tree in C++ and returns plain AHK objects, then frees the native tree
// immediately — no native handle outlives the call, so the script has nothing
// to release. The DLL is optional: if it is missing, TSParse throws.
// ============================================================================

namespace {

// Minimal slice of the tree-sitter C API. TSNode is a 32-byte by-value struct;
// on the x64 ABI the compiler returns it via a hidden pointer and passes it as a
// pointer to a copy — matching how the DLL was built (and the Buffer(32) dance
// the AHK-side smoke test uses). TSPoint (8 bytes) is returned in a register.
struct TSPoint { UINT32 row, column; };
struct TSNode  { UINT32 context[4]; const void *id; const void *tree; };

struct TSApi
{
	HMODULE mod = nullptr;
	bool ok = false;

	const void *(*lang)(void);
	void *(*parser_new)(void);
	void  (*parser_delete)(void *);
	bool  (*set_language)(void *, const void *);
	void *(*parse_string)(void *, const void *, const char *, UINT32);
	void  (*tree_delete)(void *);
	TSNode (*root_node)(const void *);
	const char *(*node_type)(TSNode);
	UINT32 (*start_byte)(TSNode);
	UINT32 (*end_byte)(TSNode);
	TSPoint (*start_point)(TSNode);
	TSPoint (*end_point)(TSNode);
	UINT32 (*child_count)(TSNode);
	TSNode (*child)(TSNode, UINT32);
	bool (*is_named)(TSNode);
	bool (*is_missing)(TSNode);
	bool (*is_error)(TSNode);
	bool (*has_error)(TSNode);
	bool (*is_extra)(TSNode);
	const char *(*field_name_for_child)(TSNode, UINT32);
};

// Resolve the DLL + exports once. Mirrors the static-LoadLibrary pattern used
// elsewhere in this file (e.g. msftedit.dll). AHK runs BIFs on the main thread,
// so a plain function-local static is sufficient.
TSApi &GetTSApi()
{
	static TSApi api;
	static bool tried = false;
	if (tried)
		return api;
	tried = true;

	// Prefer the DLL sitting next to the running executable; fall back to the
	// normal search path so a copy on PATH / in the CWD still works.
	TCHAR path[MAX_PATH];
	DWORD n = GetModuleFileName(NULL, path, MAX_PATH);
	if (n > 0 && n < (DWORD)MAX_PATH)
	{
		LPTSTR slash = _tcsrchr(path, '\\');
		if (slash && (size_t)(slash - path) + 20 < (size_t)MAX_PATH)
		{
			_tcscpy(slash + 1, _T("tree-sitter-ahk.dll"));
			api.mod = LoadLibrary(path);
		}
	}
	if (!api.mod)
		api.mod = LoadLibrary(_T("tree-sitter-ahk.dll"));
	if (!api.mod)
		return api;

	#define TS_LOAD(field, name) \
		api.field = (decltype(api.field))GetProcAddress(api.mod, name); \
		if (!api.field) return api;
	TS_LOAD(lang,                 "tree_sitter_autohotkey")
	TS_LOAD(parser_new,           "ts_parser_new")
	TS_LOAD(parser_delete,        "ts_parser_delete")
	TS_LOAD(set_language,         "ts_parser_set_language")
	TS_LOAD(parse_string,         "ts_parser_parse_string")
	TS_LOAD(tree_delete,          "ts_tree_delete")
	TS_LOAD(root_node,            "ts_tree_root_node")
	TS_LOAD(node_type,            "ts_node_type")
	TS_LOAD(start_byte,           "ts_node_start_byte")
	TS_LOAD(end_byte,             "ts_node_end_byte")
	TS_LOAD(start_point,          "ts_node_start_point")
	TS_LOAD(end_point,            "ts_node_end_point")
	TS_LOAD(child_count,          "ts_node_child_count")
	TS_LOAD(child,                "ts_node_child")
	TS_LOAD(is_named,             "ts_node_is_named")
	TS_LOAD(is_missing,           "ts_node_is_missing")
	TS_LOAD(is_error,             "ts_node_is_error")
	TS_LOAD(has_error,            "ts_node_has_error")
	TS_LOAD(is_extra,             "ts_node_is_extra")
	TS_LOAD(field_name_for_child, "ts_node_field_name_for_child")
	#undef TS_LOAD

	api.ok = true;
	return api;
}

// Set a property from a UTF-8 string (tree-sitter returns UTF-8). Returns false
// only on allocation failure; null/empty input yields an empty string.
bool SetU8Prop(Object *obj, LPCTSTR name, const char *s, int u8len)
{
	if (!s || u8len <= 0)
		return obj->SetOwnProp(name, _T(""));
	int wlen = MultiByteToWideChar(CP_UTF8, 0, s, u8len, nullptr, 0);
	if (wlen <= 0)
		return obj->SetOwnProp(name, _T(""));
	LPWSTR wbuf = (LPWSTR)malloc((size_t)(wlen + 1) * sizeof(WCHAR));
	if (!wbuf)
		return false;
	MultiByteToWideChar(CP_UTF8, 0, s, u8len, wbuf, wlen);
	wbuf[wlen] = L'\0';
	bool ret = obj->SetOwnProp(name, wbuf);
	free(wbuf);
	return ret;
}

const int TS_MAX_DEPTH = 1000; // Guard the C stack against pathological nesting.

// Recursively snapshot a node into a fresh AHK object. Returns nullptr on OOM,
// having released anything it had already built. The native tree must stay alive
// for the whole walk (it does — TSParse deletes it only after this returns).
Object *TSBuildNode(TSApi &ts, TSNode node, const char *src, UINT32 srcLen,
	const char *fieldName, int depth)
{
	Object *obj = Object::Create();
	if (!obj)
		return nullptr;

	const char *type = ts.node_type(node);
	UINT32 sb = ts.start_byte(node), eb = ts.end_byte(node);
	TSPoint sp = ts.start_point(node), ep = ts.end_point(node);

	bool ok = SetU8Prop(obj, _T("Type"), type, type ? (int)strlen(type) : 0);
	obj->SetOwnProp(_T("StartByte"), (__int64)sb);
	obj->SetOwnProp(_T("EndByte"),   (__int64)eb);
	obj->SetOwnProp(_T("StartRow"),  (__int64)sp.row);
	obj->SetOwnProp(_T("StartCol"),  (__int64)sp.column);
	obj->SetOwnProp(_T("EndRow"),    (__int64)ep.row);
	obj->SetOwnProp(_T("EndCol"),    (__int64)ep.column);
	obj->SetOwnProp(_T("IsNamed"),   (__int64)(ts.is_named(node)   ? 1 : 0));
	obj->SetOwnProp(_T("IsMissing"), (__int64)(ts.is_missing(node) ? 1 : 0));
	obj->SetOwnProp(_T("IsError"),   (__int64)(ts.is_error(node)   ? 1 : 0));
	obj->SetOwnProp(_T("HasError"),  (__int64)(ts.has_error(node)  ? 1 : 0));
	obj->SetOwnProp(_T("IsExtra"),   (__int64)(ts.is_extra(node)   ? 1 : 0));
	if (fieldName)
		ok = SetU8Prop(obj, _T("FieldName"), fieldName, (int)strlen(fieldName)) && ok;
	else
		obj->SetOwnProp(_T("FieldName"), _T(""));
	// Node text: the UTF-8 slice [sb, eb) re-decoded to UTF-16.
	if (eb >= sb && eb <= srcLen)
		ok = SetU8Prop(obj, _T("Text"), src + sb, (int)(eb - sb)) && ok;
	else
		obj->SetOwnProp(_T("Text"), _T(""));
	if (!ok)
	{
		obj->Release();
		return nullptr;
	}

	Array *children = Array::Create();
	Array *named = Array::Create();
	if (!children || !named)
	{
		if (children) children->Release();
		if (named) named->Release();
		obj->Release();
		return nullptr;
	}

	if (depth < TS_MAX_DEPTH)
	{
		UINT32 cc = ts.child_count(node);
		for (UINT32 i = 0; i < cc; ++i)
		{
			TSNode ch = ts.child(node, i);
			const char *fn = ts.field_name_for_child(node, i); // may be null
			Object *childObj = TSBuildNode(ts, ch, src, srcLen, fn, depth + 1);
			if (!childObj)
			{
				children->Release();
				named->Release();
				obj->Release();
				return nullptr;
			}
			// Append/SetOwnProp AddRef the value, so drop our creation ref after.
			ExprTokenType ct(childObj);
			bool ac = children->Append(ct);
			bool an = true;
			if (ac && ts.is_named(ch))
				an = named->Append(ct);
			childObj->Release();
			if (!ac || !an)
			{
				children->Release();
				named->Release();
				obj->Release();
				return nullptr;
			}
		}
		obj->SetOwnProp(_T("Truncated"), (__int64)0);
	}
	else
	{
		obj->SetOwnProp(_T("Truncated"), (__int64)1);
	}

	obj->SetOwnProp(_T("Children"), children);
	obj->SetOwnProp(_T("NamedChildren"), named);
	children->Release();
	named->Release();
	return obj;
}

} // anonymous namespace

// TSParse(Source) -> Object {Root, Source, HasError}. Each node carries Type,
// byte/point span, IsNamed/IsMissing/IsError/HasError/IsExtra, FieldName, Text,
// Children and NamedChildren. See docs/TREE_SITTER.md.
bif_impl FResult TSParse(StrArg aSource, IObject *&aRetVal)
{
	TSApi &ts = GetTSApi();
	if (!ts.ok)
		return FError(_T("tree-sitter-ahk.dll could not be loaded or is missing required exports."));

	// AHK source is UTF-16; tree-sitter parses UTF-8 bytes. Keep the UTF-8 copy
	// alive for the whole walk so node byte offsets can be sliced back into Text.
	int u8size = WideCharToMultiByte(CP_UTF8, 0, aSource, -1, nullptr, 0, nullptr, nullptr);
	if (u8size <= 0)
		return FR_E_FAILED;
	char *u8 = (char *)malloc((size_t)u8size);
	if (!u8)
		return FR_E_OUTOFMEM;
	WideCharToMultiByte(CP_UTF8, 0, aSource, -1, u8, u8size, nullptr, nullptr);
	UINT32 u8len = (UINT32)(u8size - 1); // exclude the trailing NUL

	void *parser = ts.parser_new();
	if (!parser)
	{
		free(u8);
		return FR_E_OUTOFMEM;
	}
	if (!ts.set_language(parser, ts.lang()))
	{
		ts.parser_delete(parser);
		free(u8);
		return FError(_T("tree-sitter language/runtime ABI mismatch."));
	}
	void *tree = ts.parse_string(parser, nullptr, u8, u8len);
	if (!tree)
	{
		ts.parser_delete(parser);
		free(u8);
		return FR_E_OUTOFMEM;
	}

	TSNode root = ts.root_node(tree);
	bool rootHasError = ts.has_error(root);
	Object *rootObj = TSBuildNode(ts, root, u8, u8len, nullptr, 0); // walk while tree is alive

	ts.tree_delete(tree);
	ts.parser_delete(parser);
	free(u8);

	if (!rootObj)
		return FR_E_OUTOFMEM;

	Object *treeObj = Object::Create();
	if (!treeObj)
	{
		rootObj->Release();
		return FR_E_OUTOFMEM;
	}
	treeObj->SetOwnProp(_T("Root"), rootObj);
	treeObj->SetOwnProp(_T("Source"), aSource);
	treeObj->SetOwnProp(_T("HasError"), (__int64)(rootHasError ? 1 : 0));
	rootObj->Release();

	aRetVal = treeObj;
	return OK;
}



// Shared by the Eval BIF and the REPL (Script::ReplDrainInput).  Evaluates aExpression
// against aScope (nullptr = global scope) and stores the value in aRetVal.  On failure
// an AHK exception is left in g->ThrownToken and a failed FResult is returned.
static FResult EvalCore(LPCTSTR aExpression, UserFunc *aScope, ResultToken &aRetVal)
{
	UserFunc *caller = aScope;

	// ParseExprToPostfix writes into the buffer (e.g. normalises whitespace),
	// so we pass a modifiable copy. The function also makes its own internal
	// copy onto SimpleHeap, so this stack buffer is only needed for the call.
	size_t len = _tcslen(aExpression);
	LPTSTR buf = (LPTSTR)_alloca((len + 1) * sizeof(TCHAR));
	_tcscpy(buf, aExpression);

	Line *scratch = nullptr;
	if (g_script.ParseExprToPostfix(buf, caller, scratch) != OK)
	{
		// Convert any parser exception into a SyntaxError so `catch SyntaxError` works.
		// The parser raises a generic Error via ScriptError/LineError; we replace it with
		// a SyntaxError that preserves the Message and adds a Column property.

		// 1) Extract message from any pre-existing thrown exception.
		LPCTSTR msg_src = _T("Invalid expression");
		LPTSTR msg_copy = nullptr;
		if (g->ThrownToken && g->ThrownToken->symbol == SYM_OBJECT)
		{
			auto *prev = dynamic_cast<Object*>(g->ThrownToken->object);
			if (prev)
			{
				LPTSTR prev_msg = prev->GetOwnPropString(_T("Message"));
				if (prev_msg && *prev_msg)
				{
					// Copy into a local stack buffer before freeing the exception.
					size_t mlen = _tcslen(prev_msg);
					msg_copy = (LPTSTR)_alloca((mlen + 1) * sizeof(TCHAR));
					_tcscpy(msg_copy, prev_msg);
					msg_src = msg_copy;
				}
			}
		}

		// 2) Free the old exception (clears g->ThrownToken).
		if (g->ThrownToken)
			g_script.FreeExceptionToken(g->ThrownToken);

		// 3) Build a new SyntaxError object with Message, File, Line, Column.
		auto *err = Object::Create();
		err->SetBase(ErrorPrototype::Syntax);
		err->SetOwnProp(_T("Message"), const_cast<LPTSTR>(msg_src));
		err->SetOwnProp(_T("File"),    _T("_Eval"));
		err->SetOwnProp(_T("Line"),    (__int64)0);
		err->SetOwnProp(_T("Column"),  (__int64)0);

		// 4) Throw it (mirrors BIF_Throw pattern).
		ResultToken *token = new ResultToken;
		token->symbol = SYM_OBJECT;
		token->object = err; // Object::Create() returns refcount=1; token owns it.
		token->mem_to_free = nullptr;
		g_script.mCurrLine->SetThrownToken(*g, token, FAIL);
		return FR_FAIL;
	}

	// ACT_EXPRESSION causes ExpandExpression to discard the final result (it's designed
	// for stand-alone side-effect expressions). Use ACT_SWITCH instead: it has no special
	// handling in ExpandExpression, so the result flows through into aResultToken.
	scratch->mActionType = ACT_SWITCH;

	// Privatize Line::sDerefBuf so that any function calls made during evaluation
	// (e.g. StrLen(), user-defined functions) can safely allocate their own deref
	// buffers without corrupting the outer evaluation layer's buffer.  This mirrors
	// what ExecUntil's ACT_SWITCH handler does before calling ExpandSingleArg().
	PRIVATIZE_S_DEREF_BUF;

	// Evaluate the scratch Line's mArg[0] postfix using ExpandSingleArg,
	// which is the same thin wrapper used by the Switch/For machinery.
	ResultToken eval_result;
	eval_result.mem_to_free = nullptr;

	ResultType eval_status = scratch->ExpandSingleArg(0, eval_result, our_deref_buf, our_deref_buf_size);

	if (eval_status != OK)
	{
		DEPRIVATIZE_S_DEREF_BUF;
		if (eval_result.mem_to_free)
			free(eval_result.mem_to_free);
		return FR_FAIL; // AHK exception already propagated (e.g. thrown object).
	}

	// Transfer the result into aRetVal BEFORE calling DEPRIVATIZE, because a
	// string result with mem_to_free==nullptr may point into our_deref_buf, which
	// DEPRIVATIZE may free or return to the outer layer (making the pointer stale).
	FResult fret = OK;
	if (eval_result.symbol == SYM_OBJECT)
	{
		// ExpandSingleArg already AddRef'd the object for eval_result.
		// Transfer ownership to aRetVal (no extra AddRef, no Release).
		aRetVal.symbol = SYM_OBJECT;
		aRetVal.object = eval_result.object;
		// eval_result.mem_to_free is always nullptr for objects.
	}
	else if (eval_result.symbol == SYM_STRING)
	{
		if (eval_result.mem_to_free)
		{
			// The string is already in heap memory. Transfer ownership to aRetVal
			// so it will be freed by the caller via the normal ResultToken::Free path.
			aRetVal.AcceptMem(eval_result.mem_to_free, eval_result.marker_length);
			eval_result.mem_to_free = nullptr; // ownership transferred
		}
		else
		{
			// The string may be in our_deref_buf (not yet freed) or in persistent
			// storage (variable contents, literal). Copy it into aRetVal now,
			// while our_deref_buf is still valid.
			size_t slen = (eval_result.marker_length != (size_t)-1)
				? eval_result.marker_length
				: _tcslen(eval_result.marker);
			if (!aRetVal.Malloc(eval_result.marker, slen))
				fret = FR_FAIL; // MemoryError already set; free buffer below.
		}
	}
	else
	{
		// Integer, float, unset, etc. — a plain value copy is sufficient.
		aRetVal.CopyValueFrom(eval_result);
	}

	// Restore the outer deref buffer now that we've copied everything we need
	// out of our_deref_buf. DEPRIVATIZE frees any inner buffer and restores the
	// saved outer one (or keeps a new buffer if the original was NULL).
	DEPRIVATIZE_S_DEREF_BUF;

	return fret;
}



bif_impl FResult Eval(StrArg aExpression, ResultToken &aRetVal)
{
	if (!g_AllowEval)
		return FError(_T("Eval is disabled (add #EnableEval to your script or pass /Eval)"));

	// Resolve scope from the caller's UserFunc (if any) so that local variables
	// referenced in the expression are resolved correctly.
	return EvalCore(aExpression, g->CurrentFunc, aRetVal);
}



// Write a wide string + trailing newline to stdout as UTF-8.
// Shared by BIF_Print and ShowMainWindow's console mirror.
void PrintWideLine(LPCTSTR text, int wlen)
{
	HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
	if (hOut == INVALID_HANDLE_VALUE || hOut == NULL)
		return; // No stdout attached (e.g. GUI app without a console); silently do nothing.

	int u8len = wlen > 0 ? WideCharToMultiByte(CP_UTF8, 0, text, wlen, nullptr, 0, nullptr, nullptr) : 0;

	// ShowMainWindow can pass up to 64K TCHARs (~192 KB as UTF-8), too much for _alloca,
	// so fall back to the heap for big payloads.
	char *heap_buf = nullptr;
	char *buf;
	if (u8len + 1 > 16384)
	{
		if (  !(heap_buf = (char *)malloc(u8len + 1))  )
			return;
		buf = heap_buf;
	}
	else
		buf = (char *)_alloca(u8len + 1);
	if (u8len > 0)
		WideCharToMultiByte(CP_UTF8, 0, text, wlen, buf, u8len, nullptr, nullptr);
	buf[u8len] = '\n';

	DWORD written;
	WriteFile(hOut, buf, (DWORD)(u8len + 1), &written, nullptr);
	free(heap_buf);
}

BIF_DECL(BIF_Print)
{
	// Print()                  -> blank line
	// Print(text)              -> write text + "\n" as-is (no Format pass)
	// Print(fmt, args...)      -> Format(fmt, args...) then write + "\n"
	if (aParamCount == 0)
	{
		PrintWideLine(_T(""), 0);
		aResultToken.SetValue(_T(""), 0);
		return;
	}

	if (aParamCount == 1)
	{
		TCHAR num_buf[MAX_NUMBER_SIZE];
		LPTSTR text = TokenToString(*aParam[0], num_buf);
		PrintWideLine(text, (int)_tcslen(text));
		aResultToken.SetValue(_T(""), 0);
		return;
	}

	// 2+ args: delegate to Format, then write the result.
	BIF_Format(aResultToken, aParam, aParamCount);
	if (aResultToken.Exited()) // Format raised; bubble up.
		return;

	LPCTSTR text = TokenToString(aResultToken, nullptr);
	PrintWideLine(text, text ? (int)_tcslen(text) : 0);

	// Reset aResultToken to blank (Print returns nothing), releasing any mem Format allocated.
	if (aResultToken.mem_to_free)
	{
		free(aResultToken.mem_to_free);
		aResultToken.mem_to_free = nullptr;
	}
	aResultToken.SetValue(_T(""), 0);
}



// REPL mode (`AutoHotkey64.exe repl [script.ahk]`).
// A dedicated thread reads stdin; each line travels through an interlocked single-slot
// mailbox to the main thread (AHK_REPL_INPUT -> Script::ReplDrainInput), which evaluates
// it in global scope via EvalCore and prints the result.  Lockstep: the reader waits for
// g_ReplLineDone before reading the next line, so results pair 1:1 with inputs.

static HANDLE g_ReplLineDone = NULL; // Auto-reset; signaled after each line is fully processed.
static PVOID volatile g_ReplPendingLine = NULL; // Mailbox slot: heap line awaiting the main thread.
static LONG volatile g_ReplEofPending = 0; // Set when stdin reaches EOF (or the reader gives up).
static bool g_ReplInteractive = false; // Stdin is a console (banner + prompt) vs a pipe.

static void ReplWritePrompt()
{
	HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
	if (hOut == INVALID_HANDLE_VALUE || hOut == NULL)
		return;
	DWORD written;
	WriteFile(hOut, ">>> ", 4, &written, nullptr);
}

// Convert a UTF-8 byte range (trailing CR stripped) to a heap TCHAR string; caller frees.
static LPTSTR ReplUtf8ToHeapLine(const char *aBytes, size_t aLen)
{
	while (aLen && aBytes[aLen - 1] == '\r')
		--aLen;
	int wlen = aLen ? MultiByteToWideChar(CP_UTF8, 0, aBytes, (int)aLen, nullptr, 0) : 0;
	LPTSTR line = (LPTSTR)malloc((wlen + 1) * sizeof(TCHAR));
	if (!line)
		return nullptr;
	if (wlen)
		MultiByteToWideChar(CP_UTF8, 0, aBytes, (int)aLen, line, wlen);
	line[wlen] = '\0';
	return line;
}

// Hand one line (or EOF when aLine is NULL) to the main thread; wait until processed.
static void ReplPostAndWait(LPTSTR aLine)
{
	if (aLine)
		InterlockedExchangePointer(&g_ReplPendingLine, aLine);
	else
		InterlockedExchange(&g_ReplEofPending, 1);
	PostMessage(g_hWnd, AHK_REPL_INPUT, 0, 0);
	WaitForSingleObject(g_ReplLineDone, INFINITE);
}

static DWORD WINAPI ReplReaderThread(LPVOID)
{
	HANDLE hIn = GetStdHandle(STD_INPUT_HANDLE);
	if (g_ReplInteractive)
	{
		for (;;)
		{
			ReplWritePrompt();
			WCHAR wbuf[16384];
			DWORD rd = 0;
			if (!ReadConsoleW(hIn, wbuf, _countof(wbuf) - 1, &rd, nullptr) || rd == 0)
				break; // Console gone or hard EOF.
			while (rd && (wbuf[rd - 1] == L'\n' || wbuf[rd - 1] == L'\r'))
				--rd;
			if (rd == 1 && wbuf[0] == 0x1A) // Lone Ctrl+Z line.
				break;
			wbuf[rd] = L'\0';
			LPTSTR line = _tcsdup(wbuf);
			if (!line)
				break;
			ReplPostAndWait(line);
		}
	}
	else
	{
		// Pipe/file stdin: accumulate UTF-8 bytes, split on '\n'.
		size_t cap = 8192, len = 0;
		char *acc = (char *)malloc(cap);
		bool eof = !acc;
		while (!eof)
		{
			char *nl;
			while (!(nl = (char *)memchr(acc, '\n', len)))
			{
				if (len + 4096 > cap)
				{
					char *bigger = (char *)realloc(acc, cap *= 2);
					if (!bigger)
					{
						eof = true;
						break;
					}
					acc = bigger;
				}
				DWORD rd = 0;
				if (!ReadFile(hIn, acc + len, 4096, &rd, nullptr) || rd == 0)
				{
					eof = true;
					break;
				}
				len += rd;
			}
			size_t line_len = nl ? (size_t)(nl - acc) : len;
			if (line_len || nl) // Post blank mid-stream lines; skip a zero-length tail at EOF.
			{
				LPTSTR line = ReplUtf8ToHeapLine(acc, line_len);
				if (!line)
					break;
				ReplPostAndWait(line);
			}
			if (!nl)
				break; // EOF after the final (possibly unterminated) line.
			size_t consumed = line_len + 1;
			memmove(acc, acc + consumed, len - consumed);
			len -= consumed;
		}
		free(acc);
	}
	ReplPostAndWait(nullptr); // EOF: the main thread exits the app.
	return 0;
}

// Print one REPL outcome.  JSON mode emits exactly one stdout line per input line so a
// consumer never desynchronizes; text mode prints values to stdout, errors to stderr.
static void ReplPrintOutcome(bool aOk, LPCTSTR aType, LPCTSTR aValue)
{
	if (g_script.mDiagJson)
	{
		TCHAR esc_type[128], esc_val[4096], out[4400];
		EscapeJsonText(esc_type, _countof(esc_type), aType);
		EscapeJsonText(esc_val, _countof(esc_val), aValue);
		sntprintf(out, _countof(out), _T("{\"kind\":\"result\",\"ok\":%s,\"type\":\"%s\",\"value\":\"%s\"}")
			, aOk ? _T("true") : _T("false"), esc_type, esc_val);
		PrintWideLine(out, (int)_tcslen(out));
		return;
	}
	if (aOk)
	{
		PrintWideLine(aValue, (int)_tcslen(aValue));
		return;
	}
	TCHAR out[4400];
	sntprintf(out, _countof(out), _T("%s: %s\n"), aType, aValue);
	g_script.PrintErrorStdOut(out, (int)_tcslen(out), _T("**")); // ** means stderr.
}

void Script::ReplStart()
{
	g_ReplLineDone = CreateEvent(nullptr, FALSE, FALSE, nullptr); // Auto-reset.
	if (!g_ReplLineDone)
		return;
	g_ReplInteractive = (GetFileType(GetStdHandle(STD_INPUT_HANDLE)) == FILE_TYPE_CHAR);

	// REPL errors belong on stderr, never in a dialog.
	if (!mErrorStdOut)
		SetErrorStdOut(nullptr);

	if (g_ReplInteractive && !mDiagJson)
	{
		TCHAR banner[160];
		sntprintf(banner, _countof(banner), _T("AutoHotkey v%hs REPL - one expression per line; .help for commands"), AHK_VERSION);
		PrintWideLine(banner, (int)_tcslen(banner));
	}

	HANDLE thread = CreateThread(nullptr, 0, ReplReaderThread, nullptr, 0, nullptr);
	if (thread)
		CloseHandle(thread);
}

void Script::ReplDrainInput()
{
	LPTSTR line = (LPTSTR)InterlockedExchangePointer(&g_ReplPendingLine, NULL);
	if (!line)
	{
		if (InterlockedExchange(&g_ReplEofPending, 0))
		{
			SetEvent(g_ReplLineDone); // Unblock the reader in case an OnExit callback cancels the exit.
			ExitApp(EXIT_EXIT);
		}
		return; // Forged or duplicate posting: nothing to do.
	}

	LPTSTR expr = line;
	while (*expr == ' ' || *expr == '\t')
		++expr;

	if (!*expr) // Blank line: no-op.
	{
		free(line);
		SetEvent(g_ReplLineDone);
		return;
	}
	if (!_tcsicmp(expr, _T(".exit")))
	{
		free(line);
		SetEvent(g_ReplLineDone);
		ExitApp(EXIT_EXIT);
		return; // Only reached if an OnExit callback canceled the exit.
	}
	if (!_tcsicmp(expr, _T(".help")))
	{
		static const TCHAR help_text[] = _T("REPL: one expression per line (commas allowed: x := 1, y := 2).  .exit or EOF quits.  Errors do not end the session.");
		PrintWideLine(help_text, (int)_tcslen(help_text));
		free(line);
		SetEvent(g_ReplLineDone);
		return;
	}

	if (g_nThreads >= g_MaxThreadsTotal || g->Priority > 0)
	{
		ReplPrintOutcome(false, _T("Error"), _T("REPL busy: thread limit reached or a higher-priority thread is running"));
		free(line);
		SetEvent(g_ReplLineDone);
		return;
	}

	// Launch a pseudo-thread (same pattern as MsgMonitor) so hotkeys, timers and GUI
	// events interleave normally and a thrown error aborts only this line.
	InitNewThread(0, false, true);

	// The REPL is an implicit try/catch: without EXCPTMODE_CATCH, SetThrownToken and
	// RuntimeError report-and-exit immediately in console mode (mErrorStdOut), which
	// would end the session on the first bad expression.
	g->ExcptMode = EXCPTMODE_CATCH;

	TCHAR result_buf[MAX_NUMBER_SIZE];
	ResultToken result;
	result.InitResult(result_buf);

	FResult fr = EvalCore(expr, nullptr, result);
	g->ExcptMode = EXCPTMODE_NONE;

	if (fr == OK)
	{
		if (result.symbol == SYM_OBJECT)
		{
			TCHAR disp[256];
			sntprintf(disp, _countof(disp), _T("<%s object>"), result.object->Type());
			ReplPrintOutcome(true, result.object->Type(), disp);
		}
		else if (result.symbol == SYM_MISSING) // Void/unset result (e.g. a void function call).
		{
			if (mDiagJson)
				ReplPrintOutcome(true, _T("Unset"), _T(""));
			// Text mode: print nothing, like a statement.
		}
		else
		{
			TCHAR num_buf[MAX_NUMBER_SIZE];
			LPCTSTR value = TokenToString(result, num_buf);
			ReplPrintOutcome(true, TokenTypeString(result), value);
		}
	}
	else
	{
		// EvalCore leaves the exception in g->ThrownToken (SyntaxError or runtime error).
		LPCTSTR err_type = _T("Error");
		LPCTSTR err_msg = (fr == FR_E_OUTOFMEM) ? _T("Out of memory") : _T("Evaluation failed");
		TCHAR msg_buf[MAX_NUMBER_SIZE];
		if (g->ThrownToken)
		{
			if (Object *ex = dynamic_cast<Object *>(TokenToObject(*g->ThrownToken)))
			{
				err_type = ex->Type();
				ExprTokenType t;
				if (ex->GetOwnProp(t, _T("Message")))
					err_msg = TokenToString(t, msg_buf);
			}
			else
				err_msg = TokenToString(*g->ThrownToken, msg_buf); // A thrown string/number.
		}
		ReplPrintOutcome(false, err_type, err_msg); // Print before freeing: err_msg may point into the exception object.
		if (g->ThrownToken)
			FreeExceptionToken(g->ThrownToken);
	}
	result.Free();

	ResumeUnderlyingThread();
	free(line);
	SetEvent(g_ReplLineDone);
}



ResultType Script::UnhandledException(Line* aLine, ResultType aErrorType)
{
	global_struct &g = *::g;
	
	ResultToken *token = g.ThrownToken;
	// Clear ThrownToken to allow any applicable callbacks to execute correctly.
	// This includes OnError callbacks explicitly called below, but also COM events
	// and CallbackCreate callbacks that execute while MsgBox() is waiting.
	g.ThrownToken = NULL;
	
#ifdef CONFIG_DEBUGGER
	if (g.ExcptMode & EXCPTMODE_DEBUGGER)
	{
		FreeExceptionToken(token);
		return FAIL;
	}
#endif
	
	// OnError: Allow the script to handle it via a global callback.
	static bool sOnErrorRunning = false;
	if (mOnError.Count() && !sOnErrorRunning)
	{
		__int64 retval;
		sOnErrorRunning = true;
		ExprTokenType param[2];
		param[0].CopyValueFrom(*token);
		param[1].SetValue(aErrorType == CRITICAL_ERROR ? _T("ExitApp")
			: aErrorType == FAIL_OR_OK ? _T("Return") : _T("Exit"));
		mOnError.Call(param, 2, INT_MAX, &retval);
		sOnErrorRunning = false;
		if (g.ThrownToken) // An exception was thrown by the callback.
		{
			// UnhandledException() has already been called recursively for g.ThrownToken,
			// so don't show a second error message.  This allows `throw param1` to mean
			// "abort all OnError callbacks and show default message now".
			FreeExceptionToken(token);
			return FAIL;
		}
		if (retval < 0 && aErrorType == FAIL_OR_OK)
		{
			FreeExceptionToken(token);
			return OK; // Ignore error and continue.
		}
		// Some callers rely on g.ThrownToken!=NULL to unwind the stack, so it is restored
		// rather than freeing it immediately.  If the exception object has __Delete, it
		// will be called after the stack unwinds.
		if (retval)
		{
			g.ThrownToken = token;
			return FAIL; // Exit thread.
		}
	}
	
#ifdef CONFIG_DLL
	if (LibNotifyProblem(*token))
	{
		g.ThrownToken = token; // See comments above.
		return FAIL;
	}
#endif

	// The error was not consumed by OnError — log it before showing the dialog.
	if (CrashLog::IsCrashLogEnabled())
	{
		Object *ex = dynamic_cast<Object *>(TokenToObject(*token));
		// Type() walks the base chain for __Class (instance doesn't own it; prototype does).
		LPCTSTR cl_type  = ex ? ex->Type()                          : nullptr;
		LPCTSTR cl_file  = ex ? ex->GetOwnPropString(_T("File"))    : nullptr;
		LPCTSTR cl_what  = ex ? ex->GetOwnPropString(_T("What"))    : nullptr;
		LPCTSTR cl_stack = ex ? ex->GetOwnPropString(_T("Stack"))   : nullptr;
		int     cl_line  = ex ? (int)ex->GetOwnPropInt64(_T("Line")): 0;

		// Message and Extra require a conversion buffer (may be a number).
		TCHAR cl_msg_buf[MAX_NUMBER_SIZE], cl_extra_buf[MAX_NUMBER_SIZE];
		LPCTSTR cl_msg   = _T(""), cl_extra = _T("");
		if (ex)
		{
			ExprTokenType cl_t;
			if (ex->GetOwnProp(cl_t, _T("Message")))
				cl_msg   = TokenToString(cl_t, cl_msg_buf);
			if (ex->GetOwnProp(cl_t, _T("Extra")))
				cl_extra = TokenToString(cl_t, cl_extra_buf);
		}

		LPCTSTR cl_mode = aErrorType == CRITICAL_ERROR ? _T("ExitApp")
		                : aErrorType == FAIL_OR_OK     ? _T("Return")
		                :                                _T("Exit");

		CrashLog::LogError(
			cl_type  ? cl_type  : _T("Error"),
			cl_mode,
			cl_msg,
			cl_file  ? cl_file  : _T(""),
			cl_line,
			cl_what  ? cl_what  : _T(""),
			cl_extra,
			cl_stack ? cl_stack : _T("")
		);
	}

	if (ShowError(aLine, aErrorType, token) == OK)
	{
		FreeExceptionToken(token);
		return OK;
	}
	g.ThrownToken = token;
	return FAIL;
}



ResultType Script::ShowError(Line* aLine, ResultType aErrorType, ExprTokenType *token)
{
	LPCTSTR message = _T(""), extra = _T("");
	TCHAR extra_buf[MAX_NUMBER_SIZE], message_buf[MAX_NUMBER_SIZE];
	
	Object *ex = dynamic_cast<Object *>(TokenToObject(*token));
	if (ex)
	{
		// For simplicity and safety, we call into the Object directly rather than via Invoke().
		ExprTokenType t;
		if (ex->GetOwnProp(t, _T("Message")))
			message = TokenToString(t, message_buf);
		if (ex->GetOwnProp(t, _T("Extra")))
			extra = TokenToString(t, extra_buf);
		LPCTSTR file = ex->GetOwnPropString(_T("File"));
		LineNumberType line_no = (LineNumberType)ex->GetOwnPropInt64(_T("Line"));
		if (file && *file && line_no)
		{
			// Locate the line by number and file index, then display that line instead
			// of the caller supplied one since it's probably more relevant.
			int file_index;
			for (file_index = 0; file_index < Line::sSourceFileCount; ++file_index)
				if (!_tcsicmp(file, Line::sSourceFile[file_index]))
					break;
			if (!aLine || aLine->mFileIndex != file_index || aLine->mLineNumber != line_no) // Keep aLine if it matches, in case of multiple Lines with the same number.
			{
				// Locate the line by number and file index, then display that line instead
				// of the caller supplied one since it's probably more relevant.
				aLine = GetLine(TokenToString(t), line_no, aLine);
			}
		}
	}
	else
	{
		// Assume it's a string or number.
		extra = TokenToString(*token, message_buf);
	}

	// If message is empty (or a string or number was thrown), display a default message for clarity.
	if (!*message)
		message = _T("Unhandled exception.");

	return ShowError(message, aErrorType, extra, aLine, ex);
}



void Object::Error_Show(ResultToken &aResultToken, int aID, int aFlags, ExprTokenType *aParam[], int aParamCount)
{
	ResultType type = FAIL_OR_OK;
	if (aParamCount && aParam[0]->symbol != SYM_MISSING)
	{
		static LPCTSTR sKindName[] { _T("Return"), _T("Exit"), _T("ExitApp"), _T("Warn") };
		static ResultType sKindType[] { FAIL_OR_OK, FAIL, CRITICAL_ERROR, WARN };
		auto kind = TokenToString(*aParam[0]);
		for (int i = 0;; ++i)
		{
			if (i == _countof(sKindName))
				_f_throw_param(0);
			if (!_tcsicmp(kind, sKindName[i]))
			{
				type = sKindType[i];
				break;
			}
		}
	}

	ExprTokenType t_this(this);
	_o_return(g_script.ShowError(nullptr, type, &t_this) == OK ? -1 : 1);
}



void Script::FreeExceptionToken(ResultToken*& aToken)
{
	// Release any potential content the token may hold
	aToken->Free();
	// Free the token itself.
	delete aToken;
	// Clear caller's variable.
	aToken = NULL;
}



bool Line::CatchThis(ExprTokenType &aThrown) // ACT_CATCH
{
	auto args = (CatchStatementArgs *)mAttribute;
	if (!args || !args->prototype_count)
		return Object::HasBase(aThrown, ErrorPrototype::Error);
	for (int i = 0; i < args->prototype_count; ++i)
		if (Object::HasBase(aThrown, args->prototype[i]))
			return true;
	return false;
}



void Script::ScriptWarning(WarnMode warnMode, LPCTSTR aWarningText, LPCTSTR aExtraInfo, Line *line)
{
	if (!line) line = mCurrLine;
	int fileIndex = line ? line->mFileIndex : mCurrFileIndex;
	FileIndexType lineNumber = line ? line->mLineNumber : mCombinedLineNumber;
	
#ifdef CONFIG_DLL
	if (LibNotifyProblem(aWarningText, aExtraInfo, line, true))
		return;
#endif
	
	if (warnMode == WARNMODE_ON)
		warnMode = g_WarnMode;
	if (warnMode == WARNMODE_OFF)
		return;

	// In /Diag=json mode, emit the warning as a JSON record too, so it doesn't corrupt
	// the structured stream with plain text.  Buffer sized for the JSON path (the
	// plain-text path needs far less).
	TCHAR buf[DIAG_JSON_BUF_SIZE];
	auto n = mDiagJson
		? FormatDiagJson(buf, _countof(buf), aWarningText, aExtraInfo, fileIndex, lineNumber, WARN, line, false)
		: FormatStdErr(buf, _countof(buf), aWarningText, aExtraInfo, fileIndex, lineNumber, true, line, false, mErrorStdOutColor);

	if (warnMode == WARNMODE_STDOUT)
		PrintErrorStdOut(buf, n);
	else
#ifdef CONFIG_DEBUGGER
	if (!g_Debugger.OutputStdErr(buf))
#endif
		OutputDebugString(buf);

	// In MsgBox mode, MsgBox is in addition to OutputDebug
	if (warnMode == WARNMODE_MSGBOX)
	{
		g_script.ShowError(aWarningText, WARN, aExtraInfo, line);
	}
}



void Script::WarnUnassignedVar(Var *var, Line *aLine)
{
	auto warnMode = mCurrentModule->Warn_VarUnset;
	if (!warnMode)
		return;

	// Currently only the first reference to each var generates a warning even when using
	// StdOut/OutputDebug. MarkAlreadyWarned() is also used to suppress warnings for any
	// var which is checked with IsSet().
	//if (warnMode == WARNMODE_MSGBOX)
	{
		// The following check uses a flag separate to IsAssignedSomewhere() because setting
		// that one for the purpose of preventing multiple MsgBoxes would cause other callers
		// of IsAssignedSomewhere() to get the wrong result if a MsgBox has been shown.
		if (var->HasAlreadyWarned())
			return;
		var->MarkAlreadyWarned();
	}

	// No check for a global variable is done because var is unassigned and therefore should
	// have resolved to a global if there was one, unless it was declared local.
	TCHAR buf[1024];
	sntprintf(buf, _countof(buf), _T("This %s appears to never be assigned a value."), Var::DeclarationType(var->Scope()));
	ScriptWarning(warnMode, buf, var->mName, aLine);
}



ResultType Script::VarUnsetError(Var *var)
{
	TCHAR buf[1024];
	bool isUndeclaredLocal = (var->Scope() & (VAR_LOCAL | VAR_DECLARED)) == VAR_LOCAL;
	bool sameNameAsGlobal = isUndeclaredLocal && FindGlobalVar(var->mName);
	sntprintf(buf, _countof(buf), _T("This %s has not been assigned a value.%s"), Var::DeclarationType(var->Scope())
		, sameNameAsGlobal ? _T("\nA global declaration inside the function may be required.") : _T(""));
	return RuntimeError(buf, var->mName, FAIL_OR_OK, nullptr, ErrorPrototype::Unset);
}



void Script::WarnLocalSameAsGlobal(LPCTSTR aVarName)
// Relies on the following pre-conditions:
//  1) It is an implicit (not declared) variable.
//  2) Caller has verified that a global variable exists with the same name.
//  3) g->CurrentFunc->mModule->Warn_LocalSameAsGlobal is on (true).
//  4) g->CurrentFunc is the function which contains this variable.
{
	TCHAR buf[DIALOG_TITLE_SIZE];
	sntprintf(buf, _countof(buf), _T("%s  (in function %s)"), aVarName, g->CurrentFunc->mName);
	ScriptWarning(g->CurrentFunc->mModule->Warn_LocalSameAsGlobal, WARNING_LOCAL_SAME_AS_GLOBAL, buf);
}
