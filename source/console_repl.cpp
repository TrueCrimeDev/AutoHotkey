#include "stdafx.h"
#include "script.h"
#include "globaldata.h"
#include "abi.h"
#include "console_eval.h"
#include "console_output.h"
#include "application.h"
#include "hook.h"
#include "ahkversion.h"
#include "inspect.h"
#include <string>
#include <stdexcept>

// REPL mode (`AutoHotkey64.exe repl [script.ahk]`).
// A dedicated thread reads stdin; each line travels through an interlocked single-slot
// mailbox to the main thread (AHK_REPL_INPUT -> Script::ReplDrainInput), which evaluates
// it in global scope via ConsoleEval::Evaluate and prints the result. The reader waits for
// g_ReplLineDone before reading the next line, so results pair 1:1 with inputs.

static HANDLE g_ReplLineDone = NULL; // Auto-reset; signaled after each line is fully processed.
static PVOID volatile g_ReplPendingLine = NULL; // Mailbox slot: heap line awaiting the main thread.
static LONG volatile g_ReplEofPending = 0; // Set when stdin reaches EOF (or the reader gives up).
static bool g_ReplInteractive = false; // Stdin is a console (banner + prompt) vs a pipe.
static HANDLE g_ReplProtocolOut = NULL;
static LONG volatile g_ReplInputError = 0;

void Script::ReplPrepare()
{
	if (mReplMode && mDiagJson)
	{
		// Reserve stdout before host-script initialization. All normal AHK
		// output paths (Print/FileAppend/FileOpen) now see stderr; only the
		// result writer uses the original stdout handle.
		g_ReplProtocolOut = GetStdHandle(STD_OUTPUT_HANDLE);
		SetStdHandle(STD_OUTPUT_HANDLE, GetStdHandle(STD_ERROR_HANDLE));
	}
}

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
	int wlen = aLen ? MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, aBytes, (int)aLen, nullptr, 0) : 0;
	if (aLen && (!wlen || memchr(aBytes, '\0', aLen)))
	{
		InterlockedExchange(&g_ReplInputError, 1);
		return _tcsdup(_T(""));
	}
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
			if (!g_script.mDiagJson)
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
		bool first_line = true;
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
				size_t bom = first_line && line_len >= 3
					&& (unsigned char)acc[0] == 0xEF && (unsigned char)acc[1] == 0xBB
					&& (unsigned char)acc[2] == 0xBF ? 3 : 0;
				first_line = false;
				LPTSTR line = ReplUtf8ToHeapLine(acc + bom, line_len - bom);
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
static void ReplAppendJsonString(std::wstring &out, LPCTSTR value, size_t length)
{
	out += L'"';
	for (size_t i = 0; i < length; ++i)
	{
		WCHAR c = value[i];
		if (c == L'"' || c == L'\\')
			out += L'\\', out += c;
		else if (c < 0x20 || (c >= 0xD800 && c <= 0xDFFF))
		{
			// Escaping UTF-16 code units preserves pairs and lone surrogates,
			// and length-based iteration preserves embedded NUL characters.
			TCHAR escaped[7];
			sntprintf(escaped, _countof(escaped), _T("\\u%04x"), (unsigned)c);
			out += escaped;
		}
		else
			out += c;
	}
	out += L'"';
}

static void ReplPrintOutcome(bool aOk, LPCTSTR aType, LPCTSTR aValue, size_t aLength = (size_t)-1)
{
	if (aLength == (size_t)-1)
		aLength = _tcslen(aValue);
	if (g_script.mDiagJson)
	{
		try
		{
			std::wstring out = aOk ? L"{\"kind\":\"result\",\"ok\":true,\"type\":" : L"{\"kind\":\"result\",\"ok\":false,\"type\":";
			ReplAppendJsonString(out, aType, _tcslen(aType));
			out += L",\"value\":";
			ReplAppendJsonString(out, aValue, aLength);
			out += L'}';
			if (out.size() > INT_MAX)
				throw std::length_error("REPL result too large");
			ConsoleOutput::WriteProtocolLine(g_ReplProtocolOut, out.c_str(), (int)out.size());
		}
		catch (const std::exception &)
		{
			static const TCHAR error[] = _T("{\"kind\":\"result\",\"ok\":false,\"type\":\"MemoryError\",\"value\":\"Unable to serialize the complete result.\"}");
			ConsoleOutput::WriteProtocolLine(g_ReplProtocolOut, error, _countof(error) - 1);
		}
		return;
	}
	if (aOk)
	{
		PrintWideLine(aValue, (int)aLength);
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

	if (InterlockedExchange(&g_ReplInputError, 0))
	{
		ReplPrintOutcome(false, _T("SyntaxError"), _T("Input must be valid UTF-8 without NUL bytes."));
		free(line);
		SetEvent(g_ReplLineDone);
		return;
	}
	if (!*expr) // Blank line: no-op.
	{
		if (mDiagJson)
			ReplPrintOutcome(true, _T("Unset"), _T(""));
		free(line);
		SetEvent(g_ReplLineDone);
		return;
	}
	if (!_tcsicmp(expr, _T(".exit")))
	{
		if (mDiagJson)
			ReplPrintOutcome(true, _T("Unset"), _T(""));
		free(line);
		SetEvent(g_ReplLineDone);
		ExitApp(EXIT_EXIT);
		return; // Only reached if an OnExit callback canceled the exit.
	}
	if (!_tcsicmp(expr, _T(".help")))
	{
		static const TCHAR help_text[] = _T("REPL: one expression per line (commas allowed: x := 1, y := 2).  .exit or EOF quits.  Errors do not end the session.");
		if (mDiagJson)
			ReplPrintOutcome(true, _T("String"), help_text);
		else
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

	FResult fr = ConsoleEval::Evaluate(expr, nullptr, result);
	g->ExcptMode = EXCPTMODE_NONE;

	if (fr == OK)
	{
		if (result.symbol == SYM_OBJECT)
		{
			// Describe the object (own values, getter/method names, one level of
			// nesting) instead of an opaque "<Type object>" placeholder.
			if (LPTSTR described = InspectValue(result, 1, 50))
			{
				ReplPrintOutcome(true, result.object->Type(), described);
				free(described);
			}
			else
			{
				TCHAR disp[256];
				sntprintf(disp, _countof(disp), _T("<%s object>"), result.object->Type());
				ReplPrintOutcome(true, result.object->Type(), disp);
			}
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
			ReplPrintOutcome(true, TokenTypeString(result), value,
				result.symbol == SYM_STRING ? result.marker_length : (size_t)-1);
		}
	}
	else
	{
		// Evaluation leaves the exception in g->ThrownToken (SyntaxError or runtime error).
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
