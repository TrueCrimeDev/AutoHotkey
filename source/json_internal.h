#pragma once

// Internal formatting shared by JSON serialization and script-free Inspect.
// Include after the engine's types and utility declarations.
#include <math.h>

namespace ahk_json_internal {
constexpr int JSON_DEFAULT_DEPTH = 256;
constexpr int JSON_MAX_DEPTH = 1000;

struct JsonBuf
{
	LPTSTR data = nullptr;
	size_t len = 0, cap = 0;
	bool failed = false;

	~JsonBuf() { free(data); }

	bool Reserve(size_t need)
	{
		if (len + need <= cap)
			return true;
		size_t want = cap ? cap * 2 : 256;
		while (want < len + need)
			want *= 2;
		LPTSTR bigger = (LPTSTR)realloc(data, (want + 1) * sizeof(TCHAR));
		if (!bigger)
			return !(failed = true);
		data = bigger;
		cap = want;
		return true;
	}
	void Put(TCHAR c)
	{
		if (Reserve(1))
			data[len++] = c;
	}
	void Put(LPCTSTR s, size_t n)
	{
		if (n && Reserve(n))
		{
			tmemcpy(data + len, s, n);
			len += n;
		}
	}
	void Put(LPCTSTR s) { Put(s, _tcslen(s)); }
	void Terminate() { if (Reserve(1)) data[len] = '\0'; }
};

struct JsonWriteOpts
{
	LPTSTR space = nullptr;   // indent unit; nullptr = compact
	int maxDepth = JSON_DEFAULT_DEPTH;
	bool ensureAscii = false;
	bool escapeSlash = false;
	bool sortKeys = false;
};

inline void FormatDouble(JsonBuf &aBuf, double d)
{
	if (!(d == d) || d == HUGE_VAL || d == -HUGE_VAL)
	{
		// NaN and Infinity have no JSON representation; null keeps output valid.
		aBuf.Put(_T("null"));
		return;
	}
	TCHAR tmp[64];
	for (int prec = 15; prec <= 17; ++prec)
	{
		sntprintf(tmp, _countof(tmp), _T("%.*g"), prec, d);
		if (_tcstod(tmp, nullptr) == d)
			break;
	}
	aBuf.Put(tmp);
	// A whole-valued float must keep a marker or it reads back as an integer.
	for (LPCTSTR p = tmp; *p; ++p)
		if (*p == '.' || *p == 'e' || *p == 'E' || *p == 'n' || *p == 'i')
			return;
	aBuf.Put(_T(".0"));
}

inline void WriteQuoted(JsonBuf &aBuf, LPCTSTR s, size_t len, const JsonWriteOpts &opt)
{
	aBuf.Put('"');
	size_t runStart = 0;
	for (size_t k = 0; k < len; ++k)
	{
		TCHAR c = s[k];
		LPCTSTR rep = nullptr;
		TCHAR esc[8];
		switch (c)
		{
		case '"':  rep = _T("\\\""); break;
		case '\\': rep = _T("\\\\"); break;
		case '\n': rep = _T("\\n"); break;
		case '\r': rep = _T("\\r"); break;
		case '\t': rep = _T("\\t"); break;
		case (TCHAR)8:  rep = _T("\\b"); break;
		case (TCHAR)12: rep = _T("\\f"); break;
		case '/':
			if (opt.escapeSlash) rep = _T("\\/");
			break;
		default:
			// Every C0 control is escaped unconditionally: output that cannot be
			// re-parsed is never acceptable, so this is not an option.
			if ((unsigned)c < 0x20 || (opt.ensureAscii && (unsigned)c > 0x7E))
			{
				sntprintf(esc, _countof(esc), _T("\\u%04x"), (unsigned)c);
				rep = esc;
			}
			break;
		}
		if (rep)
		{
			aBuf.Put(s + runStart, k - runStart);
			aBuf.Put(rep);
			runStart = k + 1;
		}
	}
	aBuf.Put(s + runStart, len - runStart);
	aBuf.Put('"');
}

} // namespace ahk_json_internal
