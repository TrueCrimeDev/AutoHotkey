#include "stdafx.h"
#include "defines.h"
#include "globaldata.h"
#include "script.h"
#include "ahkversion.h"
#include "ts_api.h"
#include "mcp_server.h"
#include <string>
#include <vector>
#include <utility>
#include <wchar.h>  // wcstoll/wcstoull/wcstod
#include <wctype.h> // towlower

// ============================================================================
// `AutoHotkey64.exe mcp` — native stdio MCP server (newline-delimited JSON-RPC
// 2.0). The behavioral contract is debugger-tool/mcp-ahk/mcp.ahk, the AHK
// reference implementation: same five tools, same payload fields, same error
// codes and stats semantics, so the same conformance tests drive both.
//
// Runs from _tWinMain before any script is loaded: single-threaded, no windows,
// no hooks, no message pump — it blocks on stdin (REPL pipe-reader pattern) and
// answers one UTF-8 JSON line per request via PrintWideLine.
// ============================================================================

namespace {

using std::wstring;

// ---------------------------------------------------------------------------
// JSON value + parser (the engine has JSON emission only; this is its first
// parser). Semantics mirror mcp.ahk's script-side Json class: strict single
// top-level value, no trailing commas, \uXXXX as one UTF-16 code unit.
// ---------------------------------------------------------------------------

struct JVal
{
	enum Kind { J_NULL, J_BOOL, J_NUM, J_STR, J_ARR, J_OBJ };
	Kind kind = J_NULL;
	bool b = false;
	wstring num; // number lexeme kept verbatim so ids round-trip exactly
	wstring str;
	std::vector<JVal> arr;
	std::vector<std::pair<wstring, JVal>> obj;

	// Last occurrence wins, matching Map assignment overwrite semantics.
	const JVal *Get(LPCWSTR key) const
	{
		const JVal *found = nullptr;
		for (auto &kv : obj)
			if (kv.first == key)
				found = &kv.second;
		return found;
	}
};

struct JParser
{
	LPCWSTR s = nullptr;
	size_t n = 0, i = 0;
	int depth = 0;
	wstring err;

	bool Parse(const wstring &text, JVal &out)
	{
		s = text.c_str(); n = text.size(); i = 0; depth = 0; err.clear();
		SkipWs();
		if (!Value(out))
			return false;
		SkipWs();
		if (i < n)
			return Fail(L"JSON: trailing characters at position " + Pos());
		return true;
	}

	wstring Pos() const { return std::to_wstring((long long)i + 1); }
	bool Fail(const wstring &m) { err = m; return false; }
	void SkipWs() { while (i < n && (s[i] == L' ' || s[i] == L'\t' || s[i] == L'\n' || s[i] == L'\r')) ++i; }
	static bool IsDig(wchar_t c) { return c >= L'0' && c <= L'9'; }

	bool Value(JVal &out)
	{
		SkipWs();
		if (i >= n)
			return Fail(L"JSON: unexpected end of input");
		if (depth >= 256)
			return Fail(L"JSON: nesting too deep");
		++depth;
		bool ok;
		wchar_t c = s[i];
		if (c == L'{')
			ok = ObjectVal(out);
		else if (c == L'[')
			ok = ArrayVal(out);
		else if (c == L'"')
		{
			out.kind = JVal::J_STR;
			ok = StringVal(out.str);
		}
		else if (c == L't' || c == L'f' || c == L'n')
			ok = KeywordVal(out);
		else if (c == L'-' || IsDig(c))
			ok = NumberVal(out);
		else
			ok = Fail(L"JSON: unexpected character '" + wstring(1, c) + L"' at position " + Pos());
		--depth;
		return ok;
	}

	bool ObjectVal(JVal &out)
	{
		out.kind = JVal::J_OBJ;
		++i;
		SkipWs();
		if (i < n && s[i] == L'}')
		{
			++i;
			return true;
		}
		for (;;)
		{
			SkipWs();
			if (i >= n || s[i] != L'"')
				return Fail(L"JSON: expected string key at position " + Pos());
			wstring key;
			if (!StringVal(key))
				return false;
			SkipWs();
			if (i >= n || s[i] != L':')
				return Fail(L"JSON: expected ':' at position " + Pos());
			++i;
			JVal v;
			if (!Value(v))
				return false;
			out.obj.emplace_back(std::move(key), std::move(v));
			SkipWs();
			if (i < n && s[i] == L',')
			{
				++i;
				continue;
			}
			if (i < n && s[i] == L'}')
			{
				++i;
				return true;
			}
			return Fail(L"JSON: expected ',' or '}' at position " + Pos());
		}
	}

	bool ArrayVal(JVal &out)
	{
		out.kind = JVal::J_ARR;
		++i;
		SkipWs();
		if (i < n && s[i] == L']')
		{
			++i;
			return true;
		}
		for (;;)
		{
			JVal v;
			if (!Value(v))
				return false;
			out.arr.push_back(std::move(v));
			SkipWs();
			if (i < n && s[i] == L',')
			{
				++i;
				continue;
			}
			if (i < n && s[i] == L']')
			{
				++i;
				return true;
			}
			return Fail(L"JSON: expected ',' or ']' at position " + Pos());
		}
	}

	bool StringVal(wstring &out)
	{
		++i; // opening quote
		out.clear();
		for (;;)
		{
			if (i >= n)
				return Fail(L"JSON: unterminated string");
			wchar_t c = s[i];
			if (c == L'"')
			{
				++i;
				return true;
			}
			if (c == L'\\')
			{
				++i;
				if (i >= n)
					return Fail(L"JSON: unterminated string");
				wchar_t e = s[i];
				switch (e)
				{
				case L'"':  out += L'"'; break;
				case L'\\': out += L'\\'; break;
				case L'/':  out += L'/'; break;
				case L'b':  out += (wchar_t)8; break;
				case L'f':  out += (wchar_t)12; break;
				case L'n':  out += L'\n'; break;
				case L'r':  out += L'\r'; break;
				case L't':  out += L'\t'; break;
				case L'u':
				{
					if (i + 4 >= n)
						return Fail(L"JSON: invalid \\u escape at position " + Pos());
					unsigned v = 0;
					for (int k = 1; k <= 4; ++k)
					{
						wchar_t h = s[i + k];
						unsigned d;
						if (h >= L'0' && h <= L'9') d = h - L'0';
						else if (h >= L'a' && h <= L'f') d = 10 + h - L'a';
						else if (h >= L'A' && h <= L'F') d = 10 + h - L'A';
						else return Fail(L"JSON: invalid \\u escape at position " + Pos());
						v = v * 16 + d;
					}
					out += (wchar_t)v; // one UTF-16 code unit; surrogate pairs concatenate naturally
					i += 4;
					break;
				}
				default:
					return Fail(L"JSON: invalid escape '\\" + wstring(1, e) + L"' at position " + Pos());
				}
				++i;
				continue;
			}
			if (c < 0x20)
				return Fail(L"JSON: unescaped control character at position " + Pos());
			out += c;
			++i;
		}
	}

	bool NumberVal(JVal &out)
	{
		size_t start = i;
		if (s[i] == L'-')
			++i;
		if (i >= n || !IsDig(s[i]))
			return Fail(L"JSON: expected digit at position " + Pos());
		if (s[i] == L'0')
		{
			++i;
			if (i < n && IsDig(s[i]))
				return Fail(L"JSON: leading zero at position " + Pos());
		}
		else
			while (i < n && IsDig(s[i])) ++i;
		if (i < n && s[i] == L'.')
		{
			++i;
			if (i >= n || !IsDig(s[i]))
				return Fail(L"JSON: expected fractional digit at position " + Pos());
			while (i < n && IsDig(s[i])) ++i;
		}
		if (i < n && (s[i] == L'e' || s[i] == L'E'))
		{
			++i;
			if (i < n && (s[i] == L'+' || s[i] == L'-'))
				++i;
			if (i >= n || !IsDig(s[i]))
				return Fail(L"JSON: expected exponent digit at position " + Pos());
			while (i < n && IsDig(s[i])) ++i;
		}
		out.kind = JVal::J_NUM;
		out.num.assign(s + start, i - start); // no numeric conversion or precision loss
		return true;
	}

	bool KeywordVal(JVal &out)
	{
		if (n - i >= 4 && !wcsncmp(s + i, L"true", 4))
		{
			i += 4;
			out.kind = JVal::J_BOOL;
			out.b = true;
			return true;
		}
		if (n - i >= 5 && !wcsncmp(s + i, L"false", 5))
		{
			i += 5;
			out.kind = JVal::J_BOOL;
			out.b = false;
			return true;
		}
		if (n - i >= 4 && !wcsncmp(s + i, L"null", 4))
		{
			i += 4;
			out.kind = JVal::J_NULL;
			return true;
		}
		return Fail(L"JSON: invalid keyword at position " + Pos());
	}
};

// ---------------------------------------------------------------------------
// JSON emission. Escape set matches mcp.ahk's Json._Quote: \" \\ \n \r \t \b
// \f, and lowercase \u%04x for the remaining control chars < 0x20. Non-ASCII
// passes through and becomes UTF-8 at the write boundary.
// ---------------------------------------------------------------------------

void JsonQuote(wstring &out, LPCWSTR text, size_t len)
{
	out += L'"';
	for (size_t k = 0; k < len; ++k)
	{
		wchar_t c = text[k];
		switch (c)
		{
		case L'"':        out += L"\\\""; break;
		case L'\\':       out += L"\\\\"; break;
		case L'\n':       out += L"\\n"; break;
		case L'\r':       out += L"\\r"; break;
		case L'\t':       out += L"\\t"; break;
		case (wchar_t)8:  out += L"\\b"; break;
		case (wchar_t)12: out += L"\\f"; break;
		default:
			if ((unsigned)c < 0x20)
			{
				wchar_t buf[8];
				sntprintf(buf, _countof(buf), L"\\u%04x", (unsigned)c);
				out += buf;
			}
			else
				out += c;
		}
	}
	out += L'"';
}

void JsonQuote(wstring &out, const wstring &text) { JsonQuote(out, text.c_str(), text.size()); }

void JsonAppend(wstring &out, const JVal &v)
{
	switch (v.kind)
	{
	case JVal::J_NULL: out += L"null"; break;
	case JVal::J_BOOL: out += v.b ? L"true" : L"false"; break;
	case JVal::J_NUM:  out += v.num; break;
	case JVal::J_STR:  JsonQuote(out, v.str); break;
	case JVal::J_ARR:
	{
		out += L'[';
		bool first = true;
		for (auto &e : v.arr)
		{
			if (!first) out += L',';
			first = false;
			JsonAppend(out, e);
		}
		out += L']';
		break;
	}
	case JVal::J_OBJ:
	{
		out += L'{';
		bool first = true;
		for (auto &kv : v.obj)
		{
			if (!first) out += L',';
			first = false;
			JsonQuote(out, kv.first);
			out += L':';
			JsonAppend(out, kv.second);
		}
		out += L'}';
		break;
	}
	}
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

wstring U8ToW(const char *bytes, size_t len)
{
	if (!len)
		return wstring();
	int wlen = MultiByteToWideChar(CP_UTF8, 0, bytes, (int)len, nullptr, 0);
	if (wlen <= 0)
		return wstring();
	wstring w((size_t)wlen, L'\0');
	MultiByteToWideChar(CP_UTF8, 0, bytes, (int)len, &w[0], wlen);
	return w;
}

// AHK Trim() default: spaces and tabs only.
wstring TrimSpTab(const wstring &in)
{
	size_t a = 0, b = in.size();
	while (a < b && (in[a] == L' ' || in[a] == L'\t')) ++a;
	while (b > a && (in[b - 1] == L' ' || in[b - 1] == L'\t')) --b;
	return in.substr(a, b - a);
}

bool IsJsonWsOrEol(wchar_t c) { return c == L' ' || c == L'\t' || c == L'\r' || c == L'\n'; }

// \s of the bundled PCRE 8.30: space, \t, \r, \n, \f — deliberately NOT \v
// (Perl-5.004 semantics; VT joined \s only in PCRE 8.34+). The regex-scan
// matchers must track this exactly or they diverge from the reference.
bool IsPcreWs(wchar_t c) { return c == L' ' || c == L'\t' || c == L'\r' || c == L'\n' || c == L'\f'; }
bool IsIdentStart(wchar_t c) { return (c >= L'A' && c <= L'Z') || (c >= L'a' && c <= L'z') || c == L'_'; }
bool IsIdentCont(wchar_t c) { return IsIdentStart(c) || (c >= L'0' && c <= L'9'); }

wstring AsciiLower(const wstring &in)
{
	wstring out = in;
	for (auto &c : out)
		if (c >= L'A' && c <= L'Z')
			c = c - L'A' + L'a';
	return out;
}

// The 15-word statement-keyword filter shared by the regex-scan tools (verbatim
// from mcp.ahk's _IsKeyword).
bool IsStmtKeyword(const wstring &name)
{
	static LPCWSTR kw[] = { L"if", L"while", L"for", L"loop", L"switch", L"catch", L"else", L"return",
		L"until", L"case", L"throw", L"try", L"finally", L"break", L"continue" };
	wstring low = AsciiLower(name);
	for (auto k : kw)
		if (low == k)
			return true;
	return false;
}

// Case-insensitive substring (InStr default), ASCII fold plus towlower for the rest.
bool ContainsCi(const wstring &haystack, const wstring &needle)
{
	if (needle.empty())
		return true;
	wstring h = haystack, nd = needle;
	for (auto &c : h) c = (wchar_t)towlower(c);
	for (auto &c : nd) c = (wchar_t)towlower(c);
	return h.find(nd) != wstring::npos;
}

wstring SysErrorText(DWORD err)
{
	LPWSTR msg = nullptr;
	DWORD len = FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
		nullptr, err, 0, (LPWSTR)&msg, 0, nullptr);
	wstring out = len && msg ? wstring(msg, len) : L"unknown error";
	if (msg)
		LocalFree(msg);
	while (!out.empty() && (out.back() == L'\r' || out.back() == L'\n' || out.back() == L' '))
		out.pop_back();
	return out;
}

// Re-encode UTF-16 to UTF-8 with explicit length (embedded NULs preserved).
std::string WToU8(const wstring &w)
{
	if (w.empty())
		return std::string();
	int len = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), nullptr, 0, nullptr, nullptr);
	if (len <= 0)
		return std::string();
	std::string s((size_t)len, '\0');
	WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), &s[0], len, nullptr, nullptr);
	return s;
}

// Backstop against allocation-death: the tool pipeline multiplies the file size
// several times over (UTF-16 copy, JSON escaping, response re-quote), so cap
// what a single tool call will ingest. The reference has no cap, but a file
// this size would produce a response no MCP client accepts anyway.
const __int64 MCP_MAX_FILE_BYTES = 100 * 1024 * 1024;

// Read a whole file as UTF-8 bytes (BOM stripped). An empty file yields an
// empty string — the `?? ""` semantics of the reference implementation (v2.1
// FileRead returns unset on a zero-byte file; here it is simply no bytes).
// A UTF-16 LE BOM is honored the way FileRead honors it regardless of the
// requested codepage: the content is re-encoded to UTF-8.
bool ReadFileUtf8(const wstring &path, std::string &out, wstring &err_msg)
{
	out.clear();
	HANDLE h = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
		nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
	if (h == INVALID_HANDLE_VALUE)
	{
		DWORD e = GetLastError();
		err_msg = L"(" + std::to_wstring((long long)e) + L") " + SysErrorText(e);
		return false;
	}
	LARGE_INTEGER size;
	if (!GetFileSizeEx(h, &size) || size.QuadPart < 0 || size.QuadPart > MCP_MAX_FILE_BYTES)
	{
		CloseHandle(h);
		err_msg = L"file is too large to read (limit 100 MB)";
		return false;
	}
	out.resize((size_t)size.QuadPart);
	size_t off = 0;
	while (off < out.size())
	{
		DWORD want = (DWORD)((out.size() - off > 0x1000000) ? 0x1000000 : out.size() - off);
		DWORD got = 0;
		if (!ReadFile(h, &out[off], want, &got, nullptr) || got == 0)
		{
			CloseHandle(h);
			err_msg = L"read failed mid-file";
			return false;
		}
		off += got;
	}
	CloseHandle(h);
	if (out.size() >= 2 && (unsigned char)out[0] == 0xFF && (unsigned char)out[1] == 0xFE)
	{
		// UTF-16 LE BOM (std::string data is suitably aligned; +2 keeps 2-byte alignment).
		wstring w((const wchar_t *)(out.data() + 2), (out.size() - 2) / 2);
		out = WToU8(w);
	}
	else if (out.size() >= 3 && (unsigned char)out[0] == 0xEF && (unsigned char)out[1] == 0xBB && (unsigned char)out[2] == 0xBF)
		out.erase(0, 3);
	return true;
}

// Split UTF-8 content the way StrSplit(content, "`n", "`r") does: split on every
// LF (N delimiters -> N+1 parts, trailing empty part included), strip CRs from
// both ends of each part; empty content -> zero lines.
void SplitLines(const std::string &u8, std::vector<wstring> &lines)
{
	lines.clear();
	if (u8.empty())
		return;
	size_t start = 0;
	for (;;)
	{
		size_t nl = u8.find('\n', start);
		size_t end = (nl == std::string::npos) ? u8.size() : nl;
		size_t a = start, b = end;
		while (a < b && u8[a] == '\r') ++a;
		while (b > a && u8[b - 1] == '\r') --b;
		lines.push_back(U8ToW(u8.data() + a, b - a));
		if (nl == std::string::npos)
			break;
		start = nl + 1;
	}
}

// Coerce a JSON argument the way the reference passes it to FileRead: strings
// as-is, numbers via their lexeme.
bool JArgToString(const JVal *v, wstring &out)
{
	if (!v)
		return false;
	if (v->kind == JVal::J_STR)
	{
		out = v->str;
		return true;
	}
	if (v->kind == JVal::J_NUM)
	{
		out = v->num;
		return true;
	}
	return false;
}

// Coerce like AHK Integer(): numbers (floats truncate) and numeric strings
// (decimal, 0x hex, float forms); anything else fails.
bool JArgToInt(const JVal *v, __int64 &out)
{
	if (!v)
		return false;
	wstring lex;
	if (v->kind == JVal::J_NUM)
		lex = v->num;
	else if (v->kind == JVal::J_STR)
		lex = v->str;
	else
		return false;
	// AHK numeric strings tolerate only space/tab padding, not CR/LF.
	lex = TrimSpTab(lex);
	if (lex.empty())
		return false;
	wchar_t *endp = nullptr;
	bool neg = lex[0] == L'-';
	size_t digs = (lex[0] == L'-' || lex[0] == L'+') ? 1 : 0;
	if (lex.size() > digs + 1 && lex[digs] == L'0' && (lex[digs + 1] == L'x' || lex[digs + 1] == L'X'))
	{
		unsigned __int64 uv = wcstoull(lex.c_str() + digs + 2, &endp, 16);
		if (!endp || *endp || endp == lex.c_str() + digs + 2)
			return false;
		out = neg ? -(__int64)uv : (__int64)uv;
		return true;
	}
	if (lex.find_first_of(L".eE") != wstring::npos)
	{
		double d = wcstod(lex.c_str(), &endp);
		if (!endp || *endp || endp == lex.c_str())
			return false;
		out = (__int64)d;
		return true;
	}
	out = wcstoll(lex.c_str(), &endp, 10);
	return endp && !*endp && endp != lex.c_str();
}

// ---------------------------------------------------------------------------
// Server stats (mirrors _McpStats/_McpStatsRecord/_McpStatsTool: requests and
// byMethod count every method-bearing message before dispatch; errors counts
// every error response of any code; toolCalls increments before the handler
// runs so server_status counts its own invocation).
// ---------------------------------------------------------------------------

typedef std::vector<std::pair<wstring, __int64>> CountList;

struct McpStats
{
	ULONGLONG started = 0;
	ULONGLONG last_tick = 0;
	__int64 requests = 0;
	__int64 errors = 0;
	CountList by_method;
	CountList tool_calls;
};

McpStats g_McpStats;

void BumpCount(CountList &list, const wstring &key)
{
	for (auto &p : list)
	{
		if (p.first == key)
		{
			++p.second;
			return;
		}
	}
	list.emplace_back(key, 1);
}

void AppendCounts(wstring &out, const CountList &list)
{
	out += L'{';
	bool first = true;
	for (auto &p : list)
	{
		if (!first) out += L',';
		first = false;
		JsonQuote(out, p.first);
		out += L':';
		out += std::to_wstring(p.second);
	}
	out += L'}';
}

// Milliseconds -> seconds with one decimal, e.g. "0.3" (Round(ms/1000, 1)).
wstring Fmt1Dec(ULONGLONG ms)
{
	wchar_t buf[32];
	sntprintf(buf, _countof(buf), L"%.1f", (double)ms / 1000.0);
	return buf;
}

// ---------------------------------------------------------------------------
// Tools. Each returns true and its JSON payload text, or false and an error
// message (surfaced as JSON-RPC error -32603, exactly like a handler throw in
// the reference implementation).
// ---------------------------------------------------------------------------

const wchar_t MCP_SERVER_NAME[] = L"ahk-mcp";
const wchar_t MCP_SERVER_VERSION[] = L"0.1.0";

// Fetches the "file" argument; returns its JVal (for echoing) or nullptr + err.
const JVal *GetFileArg(const JVal &args, wstring &path, wstring &err_msg)
{
	const JVal *v = args.Get(L"file");
	if (!JArgToString(v, path))
	{
		err_msg = L"missing or invalid required argument \"file\"";
		return nullptr;
	}
	return v;
}

// Echo an argument the way the reference does — the original JSON value, so a
// number stays a number; defaulted/derived values are quoted strings.
void EchoArg(wstring &out, const JVal *orig, const wstring &derived)
{
	if (orig && orig->kind == JVal::J_NUM)
		out += orig->num;
	else
		JsonQuote(out, derived);
}

// --- ast_outline -----------------------------------------------------------

wstring AstIdentName(TSApi &ts, TSNode node, const char *src, UINT32 src_len)
{
	UINT32 cc = ts.child_count(node);
	for (UINT32 k = 0; k < cc; ++k)
	{
		TSNode ch = ts.child(node, k);
		if (!ts.is_named(ch))
			continue;
		const char *type = ts.node_type(ch);
		if (type && !strcmp(type, "identifier"))
		{
			UINT32 sb = ts.start_byte(ch), eb = ts.end_byte(ch);
			if (eb >= sb && eb <= src_len)
				return TrimSpTab(U8ToW(src + sb, eb - sb));
			return wstring();
		}
	}
	return wstring();
}

void AstCollect(TSApi &ts, TSNode node, const char *src, UINT32 src_len, int depth, wstring &out, __int64 &count)
{
	if (depth >= 1000) // guard the C stack against pathological nesting
		return;
	UINT32 cc = ts.child_count(node);
	for (UINT32 k = 0; k < cc; ++k)
	{
		TSNode ch = ts.child(node, k);
		if (!ts.is_named(ch))
			continue;
		const char *type = ts.node_type(ch);
		LPCWSTR kind = nullptr;
		if (type)
		{
			if (!strcmp(type, "function_declaration"))      kind = L"function";
			else if (!strcmp(type, "class_declaration"))    kind = L"class";
			else if (!strcmp(type, "method_declaration"))   kind = L"method";
			else if (!strcmp(type, "property_declaration")) kind = L"property";
		}
		if (kind)
		{
			TSPoint sp = ts.start_point(ch), ep = ts.end_point(ch);
			if (count)
				out += L',';
			out += L"{\"kind\":\"";
			out += kind;
			out += L"\",\"name\":";
			JsonQuote(out, AstIdentName(ts, ch, src, src_len));
			out += L",\"line\":" + std::to_wstring((long long)sp.row + 1);
			out += L",\"endLine\":" + std::to_wstring((long long)ep.row + 1);
			out += L",\"startByte\":" + std::to_wstring((long long)ts.start_byte(ch));
			out += L",\"endByte\":" + std::to_wstring((long long)ts.end_byte(ch));
			out += L'}';
			++count;
		}
		AstCollect(ts, ch, src, src_len, depth + 1, out, count);
	}
}

bool Tool_AstOutline(const JVal &args, wstring &out, wstring &err_msg)
{
	wstring file;
	const JVal *file_arg = GetFileArg(args, file, err_msg);
	if (!file_arg)
		return false;
	std::string u8;
	if (!ReadFileUtf8(file, u8, err_msg))
		return false;

	// Parity with the reference pipeline (FileRead -> TSParse): decode to UTF-16
	// (each invalid byte becomes U+FFFD) and re-encode NUL-terminated (content
	// truncates at the first embedded NUL) so byte offsets match exactly.
	{
		wstring w = U8ToW(u8.data(), u8.size());
		std::string t;
		int len8 = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, nullptr, 0, nullptr, nullptr);
		if (len8 > 1)
		{
			t.resize((size_t)len8);
			WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, &t[0], len8, nullptr, nullptr);
			t.resize((size_t)len8 - 1); // drop the terminating NUL
		}
		u8 = std::move(t);
	}

	TSApi &ts = GetTSApi();
	if (!ts.ok)
	{
		err_msg = L"tree-sitter-ahk.dll could not be loaded or is missing required exports.";
		return false;
	}
	void *parser = ts.parser_new();
	if (!parser)
	{
		err_msg = L"out of memory";
		return false;
	}
	if (!ts.set_language(parser, ts.lang()))
	{
		ts.parser_delete(parser);
		err_msg = L"tree-sitter language/runtime ABI mismatch.";
		return false;
	}
	void *tree = ts.parse_string(parser, nullptr, u8.data(), (UINT32)u8.size());
	if (!tree)
	{
		ts.parser_delete(parser);
		err_msg = L"tree-sitter parse failed";
		return false;
	}
	TSNode root = ts.root_node(tree);
	bool has_error = ts.has_error(root);

	wstring symbols;
	__int64 count = 0;
	AstCollect(ts, root, u8.data(), (UINT32)u8.size(), 0, symbols, count);

	ts.tree_delete(tree);
	ts.parser_delete(parser);

	out = L"{\"file\":";
	EchoArg(out, file_arg, file);
	out += has_error ? L",\"hasError\":true" : L",\"hasError\":false";
	out += L",\"count\":" + std::to_wstring(count);
	out += L",\"symbols\":[" + symbols + L"]}";
	return true;
}

// --- get_source_context ----------------------------------------------------

bool Tool_GetSourceContext(const JVal &args, wstring &out, wstring &err_msg)
{
	wstring file;
	const JVal *file_arg = GetFileArg(args, file, err_msg);
	if (!file_arg)
		return false;
	__int64 line = 1, radius = 5;
	if (const JVal *v = args.Get(L"line"))
		if (!JArgToInt(v, line))
		{
			err_msg = L"argument \"line\" is not an integer";
			return false;
		}
	if (const JVal *v = args.Get(L"radius"))
		if (!JArgToInt(v, radius))
		{
			err_msg = L"argument \"radius\" is not an integer";
			return false;
		}
	std::string u8;
	if (!ReadFileUtf8(file, u8, err_msg))
		return false;
	std::vector<wstring> lines;
	SplitLines(u8, lines);

	__int64 total = (__int64)lines.size();
	__int64 start_l = line - radius < 1 ? 1 : line - radius;
	__int64 end_l = line + radius > total ? total : line + radius;

	out = L"{\"file\":";
	EchoArg(out, file_arg, file);
	out += L",\"line\":" + std::to_wstring(line);
	out += L",\"radius\":" + std::to_wstring(radius);
	out += L",\"total\":" + std::to_wstring(total);
	out += L",\"context\":[";
	bool first = true;
	for (__int64 k = start_l; k <= end_l; ++k)
	{
		if (!first) out += L',';
		first = false;
		out += L"{\"line\":" + std::to_wstring(k) + L",\"text\":";
		JsonQuote(out, lines[(size_t)(k - 1)]);
		out += (k == line) ? L",\"isTarget\":true}" : L",\"isTarget\":false}";
	}
	out += L"]}";
	return true;
}

// --- source_outline / workspace_symbols (regex-equivalent line scans) -------

// i)^class\s+([A-Za-z_]\w*)
bool MatchClassDecl(const wstring &t, wstring &name)
{
	if (t.size() < 6)
		return false;
	static const wchar_t word[] = L"class";
	for (int k = 0; k < 5; ++k)
	{
		wchar_t c = t[(size_t)k];
		if (c >= L'A' && c <= L'Z')
			c = c - L'A' + L'a';
		if (c != word[k])
			return false;
	}
	size_t p = 5;
	if (!IsPcreWs(t[p]))
		return false;
	while (p < t.size() && IsPcreWs(t[p]))
		++p;
	if (p >= t.size() || !IsIdentStart(t[p]))
		return false;
	size_t s0 = p;
	while (p < t.size() && IsIdentCont(t[p]))
		++p;
	name = t.substr(s0, p - s0);
	return true;
}

// ^([A-Za-z_]\w*)\s*\([^)]*\)\s*\{\s*$
bool MatchFuncDecl(const wstring &t, wstring &name)
{
	size_t p = 0;
	if (t.empty() || !IsIdentStart(t[0]))
		return false;
	while (p < t.size() && IsIdentCont(t[p]))
		++p;
	size_t name_end = p;
	while (p < t.size() && IsPcreWs(t[p]))
		++p;
	if (p >= t.size() || t[p] != L'(')
		return false;
	++p;
	while (p < t.size() && t[p] != L')')
		++p;
	if (p >= t.size())
		return false;
	++p; // past ')'
	while (p < t.size() && IsPcreWs(t[p]))
		++p;
	if (p >= t.size() || t[p] != L'{')
		return false;
	++p;
	while (p < t.size() && IsPcreWs(t[p]))
		++p;
	if (p != t.size())
		return false;
	name = t.substr(0, name_end);
	return true;
}

// ^(\S.*?)::  — earliest "::" at index >= 1, first char not \s.
bool MatchHotkeyDecl(const wstring &t, wstring &name)
{
	if (t.size() < 3 || IsPcreWs(t[0]))
		return false;
	for (size_t p = 1; p + 1 < t.size(); ++p)
	{
		if (t[p] == L':' && t[p + 1] == L':')
		{
			name = t.substr(0, p);
			return true;
		}
	}
	return false;
}

// ^([A-Za-z_]\w*):\s*$
bool MatchLabelDecl(const wstring &t, wstring &name)
{
	size_t p = 0;
	if (t.empty() || !IsIdentStart(t[0]))
		return false;
	while (p < t.size() && IsIdentCont(t[p]))
		++p;
	size_t name_end = p;
	if (p >= t.size() || t[p] != L':')
		return false;
	++p;
	while (p < t.size() && IsPcreWs(t[p]))
		++p;
	if (p != t.size())
		return false;
	name = t.substr(0, name_end);
	return true;
}

bool Tool_SourceOutline(const JVal &args, wstring &out, wstring &err_msg)
{
	wstring file;
	const JVal *file_arg = GetFileArg(args, file, err_msg);
	if (!file_arg)
		return false;
	std::string u8;
	if (!ReadFileUtf8(file, u8, err_msg))
		return false;
	std::vector<wstring> lines;
	SplitLines(u8, lines);

	wstring symbols;
	__int64 count = 0;
	for (size_t idx = 0; idx < lines.size(); ++idx)
	{
		wstring t = TrimSpTab(lines[idx]);
		LPCWSTR kind = nullptr;
		wstring nm;
		if (MatchClassDecl(t, nm))
			kind = L"class";
		else if (MatchFuncDecl(t, nm) && !IsStmtKeyword(nm))
			kind = L"function";
		else if (MatchHotkeyDecl(t, nm))
			kind = L"hotkey";
		else if (MatchLabelDecl(t, nm) && !IsStmtKeyword(nm))
			kind = L"label";
		if (!kind)
			continue;
		if (count)
			symbols += L',';
		symbols += L"{\"kind\":\"";
		symbols += kind;
		symbols += L"\",\"name\":";
		JsonQuote(symbols, nm);
		symbols += L",\"line\":" + std::to_wstring((long long)idx + 1) + L"}";
		++count;
	}
	out = L"{\"file\":";
	EchoArg(out, file_arg, file);
	out += L",\"count\":" + std::to_wstring(count);
	out += L",\"symbols\":[" + symbols + L"]}";
	return true;
}

struct WsScan
{
	wstring query;
	__int64 max_n = 200;
	__int64 count = 0;
	bool truncated = false;
	wstring symbols; // accumulated JSON entries
};

void WsScanFile(WsScan &scan, const wstring &path)
{
	std::string u8;
	wstring ignored;
	if (!ReadFileUtf8(path, u8, ignored)) // unreadable files are silently skipped
		return;
	std::vector<wstring> lines;
	SplitLines(u8, lines);
	for (size_t idx = 0; idx < lines.size(); ++idx)
	{
		if (scan.count >= scan.max_n)
		{
			scan.truncated = true;
			return;
		}
		wstring t = TrimSpTab(lines[idx]);
		LPCWSTR kind = nullptr;
		wstring nm;
		if (MatchClassDecl(t, nm))
			kind = L"class";
		else if (MatchFuncDecl(t, nm) && !IsStmtKeyword(nm))
			kind = L"function";
		if (!kind)
			continue;
		if (!scan.query.empty() && !ContainsCi(nm, scan.query))
			continue;
		if (scan.count)
			scan.symbols += L',';
		scan.symbols += L"{\"kind\":\"";
		scan.symbols += kind;
		scan.symbols += L"\",\"name\":";
		JsonQuote(scan.symbols, nm);
		scan.symbols += L",\"file\":";
		JsonQuote(scan.symbols, path);
		scan.symbols += L",\"line\":" + std::to_wstring((long long)idx + 1) + L"}";
		++scan.count;
	}
}

wstring JoinPath(const wstring &dir, LPCWSTR name)
{
	wstring p = dir;
	if (p.empty() || p.back() != L'\\')
		p += L'\\';
	p += name;
	return p;
}

// Loop Files "R" order: matching files in a folder first, then its subfolders.
void WsScanDir(WsScan &scan, const wstring &dir, int depth)
{
	if (depth > 64 || scan.truncated)
		return;
	WIN32_FIND_DATAW fd;
	HANDLE h = FindFirstFileW(JoinPath(dir, L"*.ahk").c_str(), &fd);
	if (h != INVALID_HANDLE_VALUE)
	{
		do
		{
			if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
				continue;
			if (scan.count >= scan.max_n)
			{
				scan.truncated = true;
				break;
			}
			WsScanFile(scan, JoinPath(dir, fd.cFileName));
		} while (!scan.truncated && FindNextFileW(h, &fd));
		FindClose(h);
	}
	if (scan.truncated)
		return;
	h = FindFirstFileW(JoinPath(dir, L"*").c_str(), &fd);
	if (h != INVALID_HANDLE_VALUE)
	{
		do
		{
			if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY))
				continue;
			// Junctions/symlinks can form cycles a depth guard cannot bound
			// (branching cycles explode combinatorially) — never follow them.
			if (fd.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)
				continue;
			if (!wcscmp(fd.cFileName, L".") || !wcscmp(fd.cFileName, L".."))
				continue;
			WsScanDir(scan, JoinPath(dir, fd.cFileName), depth + 1);
		} while (!scan.truncated && FindNextFileW(h, &fd));
		FindClose(h);
	}
}

bool Tool_WorkspaceSymbols(const JVal &args, wstring &out, wstring &err_msg)
{
	wstring root;
	const JVal *root_arg = args.Get(L"root");
	if (root_arg)
	{
		if (!JArgToString(root_arg, root))
		{
			err_msg = L"argument \"root\" is not a string";
			return false;
		}
	}
	else
	{
		wchar_t cwd[MAX_PATH];
		DWORD n = GetCurrentDirectoryW(MAX_PATH, cwd);
		root = (n && n < MAX_PATH) ? cwd : L".";
	}
	WsScan scan;
	const JVal *query_arg = args.Get(L"query");
	if (query_arg)
		if (!JArgToString(query_arg, scan.query))
		{
			err_msg = L"argument \"query\" is not a string";
			return false;
		}
	if (const JVal *v = args.Get(L"max_results"))
		if (!JArgToInt(v, scan.max_n))
		{
			err_msg = L"argument \"max_results\" is not an integer";
			return false;
		}

	// Canonicalize the scan base the way the engine's file loop does
	// (GetFullPathName), so emitted symbol paths are absolute and
	// separator-normalized for roots like "." or C:/fwd/slashes. The raw root
	// string is still echoed back in the payload's "root" field.
	wstring dir = root;
	while (dir.size() > 1 && (dir.back() == L'\\' || dir.back() == L'/'))
		dir.pop_back();
	wchar_t full[MAX_PATH * 4];
	DWORD fl = GetFullPathNameW(dir.c_str(), _countof(full), full, nullptr);
	if (fl && fl < _countof(full))
		dir = full;
	WsScanDir(scan, dir, 0);

	out = L"{\"root\":";
	EchoArg(out, root_arg, root);
	out += L",\"query\":";
	EchoArg(out, query_arg, scan.query);
	out += L",\"count\":" + std::to_wstring(scan.count);
	out += scan.truncated ? L",\"truncated\":true" : L",\"truncated\":false";
	out += L",\"symbols\":[" + scan.symbols + L"]}";
	return true;
}

// --- server_status ----------------------------------------------------------

bool Tool_ServerStatus(const JVal &, wstring &out, wstring &)
{
	ULONGLONG now = GetTickCount64();
	out = L"{\"name\":\"";
	out += MCP_SERVER_NAME;
	out += L"\",\"version\":\"";
	out += MCP_SERVER_VERSION;
	out += L"\",\"ahkVersion\":";
	JsonQuote(out, T_AHK_VERSION, _tcslen(T_AHK_VERSION));
	out += L",\"pid\":" + std::to_wstring((long long)GetCurrentProcessId());
	out += L",\"uptimeSeconds\":" + Fmt1Dec(now - g_McpStats.started);
	out += L",\"requests\":" + std::to_wstring(g_McpStats.requests);
	out += L",\"errors\":" + std::to_wstring(g_McpStats.errors);
	out += L",\"lastActivitySecondsAgo\":";
	out += g_McpStats.last_tick ? Fmt1Dec(now - g_McpStats.last_tick) : wstring(L"null");
	out += L",\"byMethod\":";
	AppendCounts(out, g_McpStats.by_method);
	out += L",\"toolCalls\":";
	AppendCounts(out, g_McpStats.tool_calls);
	out += L",\"toolsRegistered\":5}";
	return true;
}

// ---------------------------------------------------------------------------
// Tool registry (alphabetical, matching the reference's Map enumeration order;
// descriptions and inputSchemas verbatim from mcp.ahk's BuildToolRegistry).
// ---------------------------------------------------------------------------

struct ToolDef
{
	LPCWSTR name;
	LPCWSTR description;
	LPCWSTR schema; // inputSchema as literal JSON
	bool (*handler)(const JVal &args, wstring &out, wstring &err_msg);
};

const ToolDef g_McpTools[] =
{
	{ L"ast_outline",
	  L"Tree-sitter symbol outline (classes/functions/methods/properties with line ranges and byte spans) for one AHK file. Real parse, not regex.",
	  L"{\"type\":\"object\",\"properties\":{\"file\":{\"type\":\"string\",\"description\":\"Absolute path to the .ahk file\"}},\"required\":[\"file\"]}",
	  Tool_AstOutline },
	{ L"get_source_context",
	  L"Return source lines around file:line, with the target line flagged.",
	  L"{\"type\":\"object\",\"properties\":{\"file\":{\"type\":\"string\",\"description\":\"Absolute path to the file\"},\"line\":{\"type\":\"integer\",\"description\":\"1-based line number to center on\"},\"radius\":{\"type\":\"integer\",\"description\":\"Lines of context before/after (default 5)\"}},\"required\":[\"file\",\"line\"]}",
	  Tool_GetSourceContext },
	{ L"server_status",
	  L"Live status/health of this MCP server: uptime, total requests, request counts by method, per-tool call counts, error count, PID and engine version.",
	  L"{\"type\":\"object\",\"properties\":{},\"required\":[]}",
	  Tool_ServerStatus },
	{ L"source_outline",
	  L"List functions, classes, hotkeys and labels in one AHK file (fast regex scan).",
	  L"{\"type\":\"object\",\"properties\":{\"file\":{\"type\":\"string\",\"description\":\"Absolute path to the .ahk file\"}},\"required\":[\"file\"]}",
	  Tool_SourceOutline },
	{ L"workspace_symbols",
	  L"Scan all *.ahk files under a root for function and class definitions.",
	  L"{\"type\":\"object\",\"properties\":{\"root\":{\"type\":\"string\",\"description\":\"Root directory to scan (default: working dir)\"},\"query\":{\"type\":\"string\",\"description\":\"Only return symbols whose name contains this substring\"},\"max_results\":{\"type\":\"integer\",\"description\":\"Cap on returned symbols (default 200)\"}},\"required\":[]}",
	  Tool_WorkspaceSymbols },
};

const ToolDef *FindTool(const wstring &name)
{
	for (auto &t : g_McpTools)
		if (name == t.name)
			return &t;
	return nullptr;
}

// ---------------------------------------------------------------------------
// JSON-RPC dispatch (mirrors _McpHandle)
// ---------------------------------------------------------------------------

wstring EmitId(const JVal *id)
{
	if (!id)
		return L"null";
	wstring out;
	JsonAppend(out, *id);
	return out;
}

wstring MakeResult(const JVal *id, const wstring &result_json)
{
	return L"{\"jsonrpc\":\"2.0\",\"id\":" + EmitId(id) + L",\"result\":" + result_json + L"}";
}

wstring MakeError(const JVal *id, int code, const wstring &message)
{
	++g_McpStats.errors;
	wstring msg;
	JsonQuote(msg, message);
	return L"{\"jsonrpc\":\"2.0\",\"id\":" + EmitId(id) + L",\"error\":{\"code\":"
		+ std::to_wstring(code) + L",\"message\":" + msg + L"}}";
}

wstring InitializeResult(const wstring &requested_version)
{
	wstring ver;
	// MCP version negotiation: echo a supported version, otherwise offer our latest.
	// https://modelcontextprotocol.io/specification/2025-06-18/basic/lifecycle
	JsonQuote(ver, requested_version == L"2024-11-05" ? L"2024-11-05" : L"2025-06-18");
	wstring out = L"{\"protocolVersion\":" + ver
		+ L",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"";
	out += MCP_SERVER_NAME;
	out += L"\",\"version\":\"";
	out += MCP_SERVER_VERSION;
	out += L"\"}}";
	return out;
}

wstring ToolsListResult()
{
	static wstring cached;
	if (cached.empty())
	{
		cached = L"{\"tools\":[";
		bool first = true;
		for (auto &t : g_McpTools)
		{
			if (!first) cached += L',';
			first = false;
			cached += L"{\"name\":\"";
			cached += t.name;
			cached += L"\",\"description\":";
			JsonQuote(cached, t.description, wcslen(t.description));
			cached += L",\"inputSchema\":";
			cached += t.schema;
			cached += L'}';
		}
		cached += L"]}";
	}
	return cached;
}

wstring ToolsCall(const JVal *id, const JVal &req)
{
	static const JVal empty_obj = [] { JVal v; v.kind = JVal::J_OBJ; return v; }();
	const JVal *params_v = req.Get(L"params");
	const JVal *params = (params_v && params_v->kind == JVal::J_OBJ) ? params_v : &empty_obj;
	const JVal *name_v = params->Get(L"name");
	if (!name_v || name_v->kind != JVal::J_STR) // name must be a string
		return MakeError(id, -32602, L"Invalid params: missing tool name");
	const wstring &name = name_v->str;
	const ToolDef *tool = FindTool(name);
	if (!tool)
		return MakeError(id, -32602, L"Unknown tool: " + name);
	BumpCount(g_McpStats.tool_calls, name); // before the handler, so server_status counts itself
	const JVal *args_v = params->Get(L"arguments");
	if (args_v && args_v->kind != JVal::J_OBJ)
		return MakeError(id, -32602, L"Invalid params: tool arguments must be an object");
	const JVal *args = (args_v && args_v->kind == JVal::J_OBJ) ? args_v : &empty_obj;
	wstring tool_json, err_msg;
	bool ok;
	try
	{
		ok = tool->handler(*args, tool_json, err_msg);
	}
	catch (...) // most plausibly std::bad_alloc from an oversized intermediate
	{
		ok = false;
		tool_json.clear();
		err_msg = L"out of memory or internal error";
	}
	if (!ok)
		return MakeError(id, -32603, L"Tool '" + name + L"' failed: " + err_msg);
	wstring result = L"{\"content\":[{\"type\":\"text\",\"text\":";
	JsonQuote(result, tool_json);
	result += L"}],\"isError\":false}";
	return MakeResult(id, result);
}

// MCP requires integer or string IDs, preserving the original numeric lexeme.
// Test integrality without floating-point rounding (e.g. 1.0000000000000001).
bool IsRequestId(const JVal *id)
{
	if (!id)
		return false;
	if (id->kind == JVal::J_STR)
		return true;
	if (id->kind != JVal::J_NUM)
		return false;
	const wstring &num = id->num;
	size_t exponent_at = num.find_first_of(L"eE");
	size_t end = exponent_at == wstring::npos ? num.size() : exponent_at;
	size_t point = num.find(L'.');
	__int64 fraction_digits = point == wstring::npos ? 0 : (__int64)(end - point - 1);
	__int64 trailing_zeros = 0;
	bool all_zero = true;
	for (size_t i = 0; i < end; ++i)
	{
		if (num[i] == L'-' || num[i] == L'.') continue;
		if (num[i] == L'0') ++trailing_zeros;
		else { trailing_zeros = 0; all_zero = false; }
	}
	__int64 exponent = 0;
	if (exponent_at != wstring::npos)
	{
		size_t i = exponent_at + 1;
		bool negative = num[i] == L'-';
		if (num[i] == L'-' || num[i] == L'+') ++i;
		// Once the exponent exceeds the entire input length its exact value cannot
		// affect integrality. Saturate there instead of overflowing an integer.
		__int64 limit = (__int64)num.size() + 1;
		for (; i < num.size(); ++i)
		{
			exponent = exponent * 10 + (num[i] - L'0');
			if (exponent > limit) { exponent = limit; break; }
		}
		if (negative) exponent = -exponent;
	}
	return all_zero || exponent + trailing_zeros >= fraction_digits;
}

bool ValidateInitialize(const JVal *params)
{
	if (!params || params->kind != JVal::J_OBJ)
		return false;
	const JVal *version = params->Get(L"protocolVersion"), *caps = params->Get(L"capabilities"),
		*client = params->Get(L"clientInfo");
	if (!version || version->kind != JVal::J_STR || version->str.empty()
		|| !caps || caps->kind != JVal::J_OBJ || !client || client->kind != JVal::J_OBJ)
		return false;
	const JVal *name = client->Get(L"name"), *client_version = client->Get(L"version");
	return name && name->kind == JVal::J_STR && client_version && client_version->kind == JVal::J_STR;
}

// One request line in -> one response line out ("" = no response, e.g. for
// notifications).
wstring McpHandle(const wstring &line)
{
	JVal req;
	JParser parser;
	if (!parser.Parse(line, req))
		return MakeError(nullptr, -32700, L"Parse error: " + parser.err);
	if (req.kind != JVal::J_OBJ)
		return MakeError(nullptr, -32600, L"Invalid Request: expected an object");
	const JVal *id = req.Get(L"id");
	bool has_id = id != nullptr;
	if (has_id && !IsRequestId(id))
		return MakeError(nullptr, -32600, L"Invalid Request: id must be a string or integer");
	const JVal *rpc = req.Get(L"jsonrpc");
	if (!rpc || rpc->kind != JVal::J_STR || rpc->str != L"2.0")
		return MakeError(id, -32600, L"Invalid Request: jsonrpc must be 2.0");
	const JVal *method_v = req.kind == JVal::J_OBJ ? req.Get(L"method") : nullptr;
	if (!method_v || method_v->kind != JVal::J_STR) // JSON-RPC 2.0: method MUST be a string
		return MakeError(id, -32600, L"Invalid Request: method must be a string");
	const wstring &method = method_v->str;

	++g_McpStats.requests; // recorded before dispatch, notifications included
	g_McpStats.last_tick = GetTickCount64();
	BumpCount(g_McpStats.by_method, method);

	// Notifications never produce responses, including known request-only methods.
	// They must not accidentally execute tools with no caller awaiting a result.
	if (!has_id)
		return wstring();
	const JVal *params = req.Get(L"params");
	if (params && params->kind != JVal::J_OBJ)
		return MakeError(id, -32602, L"Invalid params: expected an object");
	if (method == L"initialize")
	{
		if (!ValidateInitialize(params))
			return MakeError(id, -32602, L"Invalid initialize params: protocolVersion, capabilities, and clientInfo.name/version are required");
		return MakeResult(id, InitializeResult(params->Get(L"protocolVersion")->str));
	}
	if (method == L"ping")
		return MakeResult(id, L"{}");
	if (method == L"tools/list")
		return MakeResult(id, ToolsListResult());
	if (method == L"tools/call")
		return ToolsCall(id, req);
	return has_id ? MakeError(id, -32601, L"Method not found: " + method) : wstring();
}

void HandleLine(const wstring &raw)
{
	size_t a = 0, b = raw.size();
	while (a < b && IsJsonWsOrEol(raw[a])) ++a;
	while (b > a && IsJsonWsOrEol(raw[b - 1])) --b;
	if (a == b)
		return; // blank lines are ignored
	// Last-resort backstop: an allocation failure anywhere in handling must
	// produce an error line, never abort the process mid-session. (The id is
	// unknown at this point; ToolsCall catches tool-level failures with the id.)
	static const wchar_t oom_resp[] = L"{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"internal error: out of memory\"}}";
	wstring resp;
	try
	{
		resp = McpHandle(raw.substr(a, b - a));
	}
	catch (...)
	{
		++g_McpStats.errors;
		PrintWideLine(oom_resp, (int)(_countof(oom_resp) - 1));
		return;
	}
	if (resp.empty())
		return;
	if (resp.size() > (size_t)INT_MAX) // PrintWideLine takes int; never let the cast wrap
	{
		++g_McpStats.errors;
		static const wchar_t big_resp[] = L"{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"internal error: response too large\"}}";
		PrintWideLine(big_resp, (int)(_countof(big_resp) - 1));
		return;
	}
	PrintWideLine(resp.c_str(), (int)resp.size()); // one UTF-8 line + '\n' per response
}

} // anonymous namespace

int McpServerMain()
{
	HANDLE h_in = GetStdHandle(STD_INPUT_HANDLE);
	HANDLE h_out = GetStdHandle(STD_OUTPUT_HANDLE);
	if (!h_in || h_in == INVALID_HANDLE_VALUE || !h_out || h_out == INVALID_HANDLE_VALUE)
	{
		// GUI-subsystem process launched without redirected pipes has no stdio
		// to serve on; MCP clients always spawn with pipes.
		HANDLE h_err = GetStdHandle(STD_ERROR_HANDLE);
		if (h_err && h_err != INVALID_HANDLE_VALUE)
		{
			static const char msg[] = "mcp: stdin/stdout not available; launch with redirected pipes.\n";
			DWORD written;
			WriteFile(h_err, msg, sizeof(msg) - 1, &written, nullptr);
		}
		return AHK_EXIT_CLI_ERROR;
	}
	g_McpStats.started = GetTickCount64();

	if (GetFileType(h_in) == FILE_TYPE_CHAR)
	{
		// Interactive console (manual testing): ReadConsoleW per line, since
		// ReadFile on a console handle yields ANSI-codepage bytes. A line longer
		// than the buffer arrives as multiple chunks with no newline until the
		// last one — accumulate so a long pasted request stays one request.
		wstring pending;
		for (;;)
		{
			WCHAR wbuf[16384];
			DWORD rd = 0;
			if (!ReadConsoleW(h_in, wbuf, _countof(wbuf) - 1, &rd, nullptr) || rd == 0)
				break;
			bool line_complete = wbuf[rd - 1] == L'\n' || wbuf[rd - 1] == L'\r';
			while (rd && (wbuf[rd - 1] == L'\n' || wbuf[rd - 1] == L'\r'))
				--rd;
			if (pending.empty() && rd == 1 && wbuf[0] == 0x1A) // lone Ctrl+Z line
				break;
			pending.append(wbuf, rd);
			if (line_complete)
			{
				HandleLine(pending);
				pending.clear();
			}
		}
		if (!pending.empty())
			HandleLine(pending);
		return AHK_EXIT_OK;
	}

	// Pipe/file stdin (the normal MCP transport): accumulate UTF-8 bytes,
	// split on '\n' — the REPL reader's pipe branch, synchronous on this thread.
	size_t cap = 8192, len = 0;
	char *acc = (char *)malloc(cap);
	if (!acc)
		return AHK_EXIT_CRITICAL_ERROR;
	bool eof = false;
	bool first_line = true;
	while (!eof)
	{
		char *nl;
		size_t scanned = 0; // memchr only the not-yet-scanned tail, else a huge
		                    // single line costs O(n^2) rescans across 4KB reads
		while (!(nl = (char *)memchr(acc + scanned, '\n', len - scanned)))
		{
			scanned = len;
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
			if (!ReadFile(h_in, acc + len, 4096, &rd, nullptr) || rd == 0)
			{
				eof = true; // clean shutdown: client closed stdin
				break;
			}
			len += rd;
		}
		size_t line_len = nl ? (size_t)(nl - acc) : len;
		if (line_len || nl) // handle blank mid-stream lines; skip a zero-length tail at EOF
		{
			size_t l = line_len;
			while (l && acc[l - 1] == '\r')
				--l;
			// Windows PowerShell can prefix a UTF-8 native pipe with a BOM.
			// Accept it only at the start of the stream, as the REPL does.
			size_t start = first_line && l >= 3
				&& (unsigned char)acc[0] == 0xEF && (unsigned char)acc[1] == 0xBB
				&& (unsigned char)acc[2] == 0xBF ? 3 : 0;
			first_line = false;
			HandleLine(U8ToW(acc + start, l - start));
		}
		if (!nl)
			break; // EOF after the final (possibly unterminated) line
		size_t consumed = line_len + 1;
		memmove(acc, acc + consumed, len - consumed);
		len -= consumed;
	}
	free(acc);
	return AHK_EXIT_OK;
}
