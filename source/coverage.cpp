#include "stdafx.h"
#include "coverage.h"
#include "script.h"
#include "script_module.h"
#include "globaldata.h"
#include <map>
#include <string>
#include <vector>

bool g_CoverageEnabled = false;

namespace
{
	LPTSTR s_path = nullptr;
	// s_hits[file_index][line_number] = execution count.  Grown on demand, so an
	// unexecuted file costs nothing and a file costs 4 bytes per line at most.
	std::vector<std::vector<UINT>> s_hits;
	SRWLOCK s_lock = SRWLOCK_INIT;
	bool s_prepared = false;
	std::vector<std::map<UINT, UINT>> s_lines;
	std::vector<std::wstring> s_files;

	struct CoverageLock
	{
		bool held;
		CoverageLock(bool aTryOnly = false)
		{
			if (aTryOnly)
				held = TryAcquireSRWLockExclusive(&s_lock) != FALSE;
			else
				AcquireSRWLockExclusive(&s_lock), held = true;
		}
		~CoverageLock() { if (held) ReleaseSRWLockExclusive(&s_lock); }
	};

	// Lines that never reach the per-line hook.  ELSE/CATCH/FINALLY/CASE are
	// dispatched from within their parent statement, and block braces are
	// structural.  Mirrors the rules the debugger uses to slide breakpoints.
	bool IsStructuralLine(Line *aLine)
	{
		switch (aLine->mActionType)
		{
		case ACT_BLOCK_BEGIN:
		case ACT_BLOCK_END:
		case ACT_ELSE:
		case ACT_CATCH:
		case ACT_FINALLY:
		case ACT_CASE:
		case ACT_END_MODULE: // Appended by the loader past the last source line.
			return true;
		default:
			return false;
		}
	}

	// Called only by the script thread, after loading and before the first hit.
	// Shutdown handlers must not traverse parser structures which Eval can mutate.
	void PrepareSourceLines()
	{
		if (s_prepared)
			return;
		s_lines.resize(Line::sSourceFileCount);
		for (int f = 0; f < Line::sSourceFileCount; ++f)
			s_files.emplace_back(Line::sSourceFile[f]);
		for (auto mod = g_script.LastModule(); mod; mod = mod->mPrev)
			for (Line *line = mod->mFirstLine; line; line = line->mNextLine)
				if (line->mLineNumber && !IsStructuralLine(line) && line->mFileIndex < s_lines.size())
					s_lines[line->mFileIndex][line->mLineNumber] = 0;
		s_prepared = true;
	}

	void AppendUtf8(std::string &aOut, LPCTSTR aText)
	{
		if (!aText || !*aText)
			return;
		// Convert without the terminator so the written length equals the resize.
		int len = (int)_tcslen(aText);
		int n = WideCharToMultiByte(CP_UTF8, 0, aText, len, nullptr, 0, nullptr, nullptr);
		if (n <= 0)
			return;
		size_t start = aOut.size();
		aOut.resize(start + n);
		WideCharToMultiByte(CP_UTF8, 0, aText, len, &aOut[start], n, nullptr, nullptr);
	}

	void AppendJsonString(std::wstring &aOut, LPCTSTR aText)
	{
		static const wchar_t hex[] = L"0123456789ABCDEF";
		aOut += L'"';
		for (; *aText; ++aText)
		{
			if (*aText == '"' || *aText == '\\')
				aOut += L'\\', aOut += *aText;
			else if ((UINT)*aText < 0x20)
				aOut += L"\\u00", aOut += hex[(*aText >> 4) & 0xF], aOut += hex[*aText & 0xF];
			else
				aOut += *aText;
		}
		aOut += L'"';
	}

	// Open-write-flush-close, like the crash log, so the bytes reach the disk
	// even if the process dies immediately afterwards.  A missing directory is
	// created first, so /Coverage=out\cov.lcov needs no separate mkdir step.
	// Returns NO_ERROR or the Win32 error which stopped the write; aInDir is
	// set when that error came from creating the directory.
	DWORD WriteWholeFile(LPCTSTR aPath, const std::string &aBytes, bool &aInDir)
	{
		aInDir = false;
		HANDLE h = CreateFile(aPath, GENERIC_WRITE, FILE_SHARE_READ, nullptr,
			CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
		DWORD error = h == INVALID_HANDLE_VALUE ? GetLastError() : NO_ERROR;
		if (error == ERROR_PATH_NOT_FOUND)
		{
			// FileCreateDir is DirCreate's helper: it creates every missing level
			// and normalizes either separator and relative components.
			std::wstring dir = aPath;
			size_t sep = dir.find_last_of(L"\\/");
			if (sep != std::wstring::npos && sep > 0)
			{
				dir.resize(sep);
				if (!FileCreateDir(dir.c_str()))
					error = GetLastError(), aInDir = true;
				else
				{
					h = CreateFile(aPath, GENERIC_WRITE, FILE_SHARE_READ, nullptr,
						CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
					error = h == INVALID_HANDLE_VALUE ? GetLastError() : NO_ERROR;
				}
			}
		}
		if (h == INVALID_HANDLE_VALUE)
			return error;
		DWORD written = 0;
		if (!aBytes.empty() && !WriteFile(h, aBytes.data(), (DWORD)aBytes.size(), &written, nullptr))
			error = GetLastError();
		FlushFileBuffers(h);
		CloseHandle(h);
		return error;
	}

	// One stderr line (a JSON diagnostic under /Diag=json) naming the report and
	// the Win32 error, so a run which loses its coverage says so.  The exit code
	// is left alone: coverage only observes the run, and every caller flushes
	// after the script's own exit code has been decided.
	void ReportWriteFailure(LPCTSTR aPath, DWORD aError, bool aInDir, bool aBestEffort)
	{
		TCHAR reason[256] = _T("");
		GetWin32ErrorText(reason, _countof(reason), aError);
		size_t len = _tcslen(reason);
		while (len && (reason[len - 1] == '\r' || reason[len - 1] == '\n' || reason[len - 1] == ' '))
			reason[--len] = '\0'; // FormatMessage ends the text with CRLF.
		for (LPTSTR cp = reason; *cp; ++cp)
			if (*cp == '\r' || *cp == '\n')
				*cp = ' '; // Keep the diagnostic on one line.
		std::wstring message = L"Coverage report \"";
		message += aPath;
		message += aInDir ? L"\" not written: could not create its directory (Win32 error " : L"\" not written (Win32 error ";
		message += std::to_wstring(aError);
		if (*reason)
			message += L": ", message += reason;
		message += L')';
		std::wstring text;
		if (g_script.mDiagJson)
		{
			text = L"{\"kind\":\"diagnostic\",\"format\":\"json\",\"schema\":2,\"severity\":\"warning\","
				L"\"type\":\"OSError\",\"code\":0,\"message\":";
			AppendJsonString(text, message.c_str());
			text += L",\"extra\":";
			AppendJsonString(text, aPath);
			text += L",\"what\":\"\",\"file\":\"\",\"line\":0,\"column\":0,\"source\":\"\",\"stack\":\"\"}";
		}
		else
			text = message;
		text += L'\n';
		if (aBestEffort)
		{
			// Fault and console-signal handlers run on a faulting or console-control
			// thread, where TextFile and the debugger's stream hooks are not safe to
			// enter, so write UTF-8 straight to the handle.
			std::string bytes;
			AppendUtf8(bytes, text.c_str());
			HANDLE err = GetStdHandle(STD_ERROR_HANDLE);
			DWORD written;
			if (err && err != INVALID_HANDLE_VALUE)
				WriteFile(err, bytes.data(), (DWORD)bytes.size(), &written, nullptr);
		}
		else
			g_script.PrintErrorStdOut(text.c_str(), (int)text.size(), _T("**")); // Honors /ErrorStdOut and /StdErrFile.
	}
}

void Coverage::SetPath(LPCTSTR aPath)
{
	CoverageLock lock;
	free(s_path);
	s_path = nullptr;
	g_CoverageEnabled = false;
	if (!aPath || !*aPath)
		return;
	TCHAR full[MAX_PATH * 2];
	DWORD n = GetFullPathName(aPath, _countof(full), full, nullptr);
	s_path = _tcsdup(n && n < _countof(full) ? full : aPath);
	g_CoverageEnabled = true;
}

bool Coverage::IsEnabled()
{
	return g_CoverageEnabled;
}

void Coverage::Hit(WORD aFileIndex, UINT aLineNumber)
{
	if (!aLineNumber)
		return;
	CoverageLock lock;
	PrepareSourceLines();
	if (aFileIndex >= s_hits.size())
		s_hits.resize((size_t)aFileIndex + 1);
	auto &file = s_hits[aFileIndex];
	if (aLineNumber >= file.size())
	{
		size_t grown = file.size() * 2;
		file.resize(grown > aLineNumber ? grown : (size_t)aLineNumber + 1, 0);
	}
	++file[aLineNumber];
}

void Coverage::HitLine(Line *aLine)
{
	if (IsStructuralLine(aLine) || aLine->mActionType == ACT_WHILE)
		return;
	Hit(aLine->mFileIndex, aLine->mLineNumber);
}

void Coverage::Flush(bool aBestEffort)
{
	CoverageLock lock(aBestEffort);
	if (!lock.held)
		return;
	if (!g_CoverageEnabled || !s_path)
		return;
	if (!s_prepared)
	{
		if (aBestEffort)
			return; // Loading may still be in progress on the script thread.
		PrepareSourceLines();
	}

	std::string out;
	char num[64];
	for (size_t f = 0; f < s_lines.size(); ++f)
	{
		auto &lines = s_lines[f];
		if (lines.empty())
			continue;
		UINT hit_lines = 0;
		out += "SF:";
		AppendUtf8(out, s_files[f].c_str());
		out += '\n';
		for (auto &entry : lines)
		{
			UINT hits = 0;
			if (f < s_hits.size() && entry.first < s_hits[f].size())
				hits = s_hits[f][entry.first];
			if (hits)
				++hit_lines;
			_snprintf_s(num, sizeof(num), _TRUNCATE, "DA:%u,%u\n", entry.first, hits);
			out += num;
		}
		_snprintf_s(num, sizeof(num), _TRUNCATE, "LF:%u\nLH:%u\nend_of_record\n",
			(UINT)lines.size(), hit_lines);
		out += num;
	}
	bool in_dir;
	if (DWORD error = WriteWholeFile(s_path, out, in_dir))
		ReportWriteFailure(s_path, error, in_dir, aBestEffort);
}
