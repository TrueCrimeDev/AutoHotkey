#include "stdafx.h"
#include "script.h"
#include "globaldata.h"
#include "abi.h"
#include "console_output.h"
#include <memory>

// Write a wide string + trailing newline to stdout as UTF-8.
// Shared by BIF_Print and ShowMainWindow's console mirror.
void ConsoleOutput::WriteProtocolLine(HANDLE hOut, LPCTSTR text, int wlen)
{
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

	DWORD written, offset = 0, size = (DWORD)(u8len + 1);
	while (offset < size && WriteFile(hOut, buf + offset, size - offset, &written, nullptr) && written)
		offset += written;
	free(heap_buf);
}

void PrintWideLine(LPCTSTR text, int wlen)
{
#ifdef CONFIG_DEBUGGER
	if (g_Debugger.HasStdOutHook())
	{
		// The debugger owns stdout in stdio mode. Include Print's newline in the
		// stream packet; protocol writers call ConsoleOutput::WriteProtocolLine directly.
		std::unique_ptr<TCHAR, decltype(&free)> line((LPTSTR)malloc(((size_t)wlen + 2) * sizeof(TCHAR)), free);
		if (!line)
			return;
		tmemcpy(line.get(), text, wlen);
		line.get()[wlen] = '\n';
		line.get()[wlen + 1] = '\0';
		if (g_Debugger.OutputStdOut(line.get()))
			return;
	}
#endif
	ConsoleOutput::WriteProtocolLine(GetStdHandle(STD_OUTPUT_HANDLE), text, wlen);
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
