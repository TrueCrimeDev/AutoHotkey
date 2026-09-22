#include "stdafx.h"
#include "script.h"
#include "globaldata.h"
#include "abi.h"
#include "child_process.h"
#include "native_object_util.h"
#include <string>
#include <new>

// Check(Source) -> Object { Ok, Diagnostics, Raw }
// Parse in a child so the host's variables and parser state remain untouched.
// The shared runner owns the process tree and bounds execution/captured output.
// Check mode never executes the script body. Raw combines stderr then stdout;
// records within each stream retain their order.
namespace { // Check() file-static helpers

static const int kCheckFieldCap = 4096;

static bool CheckWriteTempSource(StrArg aSource, LPTSTR aOutPath /*[MAX_PATH+1]*/)
{
	TCHAR tmpDir[MAX_PATH + 1];
	aOutPath[0] = '\0';
	if (!GetTempPath(_countof(tmpDir), tmpDir))
		return false;
	if (!GetTempFileName(tmpDir, _T("ahk"), 0, aOutPath))
		return false;
	int u8size = WideCharToMultiByte(CP_UTF8, 0, aSource, -1, nullptr, 0, nullptr, nullptr);
	if (u8size <= 0)
	{
		DeleteFile(aOutPath); aOutPath[0] = '\0'; return false;
	}
	char *u8 = (char *)malloc((size_t)u8size);
	if (!u8)
	{
		DeleteFile(aOutPath); aOutPath[0] = '\0'; return false;
	}
	WideCharToMultiByte(CP_UTF8, 0, aSource, -1, u8, u8size, nullptr, nullptr);
	HANDLE hf = CreateFile(aOutPath, GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
		FILE_ATTRIBUTE_TEMPORARY, nullptr);
	if (hf == INVALID_HANDLE_VALUE)
	{
		free(u8); DeleteFile(aOutPath); aOutPath[0] = '\0'; return false;
	}
	DWORD wrote = 0;
	BOOL wok = WriteFile(hf, u8, (DWORD)(u8size - 1), &wrote, nullptr); // drop trailing NUL
	CloseHandle(hf);
	free(u8);
	if (!wok || wrote != (DWORD)(u8size - 1))
	{
		DeleteFile(aOutPath); aOutPath[0] = '\0'; return false;
	}
	return true;
}

static void CheckRunSelf(LPCTSTR aSelfExe, LPCTSTR aScriptPath, ChildResult &aResult)
{
	std::wstring command;
	AppendQuotedArg(command, aSelfExe);
	// /script also selects the interpreter when the host has an embedded script.
	command += L" /script /Headless /Diag=json /Check --";
	AppendQuotedArg(command, aScriptPath);
	RunChildCapture(command.c_str(), nullptr, 30000, aResult, 8 * 1024 * 1024);
}

struct CheckTempSource
{
	TCHAR path[MAX_PATH + 1] = {};
	~CheckTempSource() { if (*path) DeleteFile(path); }
};

// Inverse of the diagnostic JSON string escaping. Emitter only produces \\ \" \/
// \r \n \t and \uXXXX (only for ASCII controls < 0x20), so fold \u to one byte.
static void CheckJsonUnescape(const char *s, int len, char *out, int aOutCap)
{
	int o = 0;
	for (int i = 0; i < len && o < aOutCap - 1; ++i)
	{
		char c = s[i];
		if (c == '\\' && i + 1 < len)
		{
			char e = s[++i];
			switch (e)
			{
			case 'r': out[o++] = '\r'; break;
			case 'n': out[o++] = '\n'; break;
			case 't': out[o++] = '\t'; break;
			case 'u':
				if (i + 4 < len)
				{
					char hex[5];
					hex[0] = s[i + 1]; hex[1] = s[i + 2]; hex[2] = s[i + 3]; hex[3] = s[i + 4];
					hex[4] = '\0';
					unsigned cp = (unsigned)strtoul(hex, nullptr, 16);
					i += 4;
					out[o++] = (char)(cp & 0xFF);
				}
				break;
			default: out[o++] = e; break; // \\  \"  \/  and any other: literal
			}
		}
		else
			out[o++] = c;
	}
	out[o] = '\0';
}

// Find "key":" then copy the value to the first UNescaped quote, then unescape.
// _snprintf_s returns the number written
// or -1 on truncation (both caught by the guard).
static bool CheckExtractJsonStr(const char *aJson, const char *aKey, char *aOut, int aOutCap)
{
	aOut[0] = '\0';
	if (!aJson)
		return false;
	char needle[64];
	int nn = _snprintf_s(needle, _countof(needle), _TRUNCATE, "\"%s\":\"", aKey);
	if (nn <= 0 || nn >= (int)_countof(needle))
		return false;
	const char *p = strstr(aJson, needle);
	if (!p)
		return false;
	p += nn;
	const char *start = p, *q = p;
	while (*q)
	{
		if (*q == '\\') { if (q[1] == '\0') break; q += 2; continue; }
		if (*q == '"') break;
		++q;
	}
	if (*q != '"')
		return false;
	CheckJsonUnescape(start, (int)(q - start), aOut, aOutCap);
	return true;
}

// Find "key": then read an unquoted integer; aDefault if absent/non-numeric.
static __int64 CheckExtractJsonInt(const char *aJson, const char *aKey, __int64 aDefault)
{
	if (!aJson)
		return aDefault;
	char needle[64];
	int nn = _snprintf_s(needle, _countof(needle), _TRUNCATE, "\"%s\":", aKey);
	if (nn <= 0 || nn >= (int)_countof(needle))
		return aDefault;
	const char *p = strstr(aJson, needle);
	if (!p)
		return aDefault;
	p += nn;
	while (*p == ' ' || *p == '\t')
		++p;
	if (*p == '"')
		return aDefault;
	char *end = nullptr;
	long long v = strtoll(p, &end, 10);
	if (end == p)
		return aDefault;
	return (__int64)v;
}

static void CheckSetStrOr(Object *d, LPTSTR name, const char *aJson, const char *key, LPCTSTR aDef)
{
	char val[kCheckFieldCap];
	if (CheckExtractJsonStr(aJson, key, val, _countof(val)))
		ConsoleNative::SetUtf8Property(d, name, val, (int)strlen(val));
	else
		d->SetOwnProp(name, aDef);
}

static Object *CheckBuildDiag(const char *aJson, DWORD aExitCode)
{
	Object *d = Object::Create();
	if (!d)
		return nullptr;
	CheckSetStrOr(d, _T("Severity"), aJson, "severity", _T("error"));
	CheckSetStrOr(d, _T("Type"), aJson, "type", _T("Error"));
	d->SetOwnProp(_T("Code"), CheckExtractJsonInt(aJson, "code", (__int64)aExitCode));
	CheckSetStrOr(d, _T("Message"), aJson, "message", _T(""));
	CheckSetStrOr(d, _T("Extra"), aJson, "extra", _T(""));
	CheckSetStrOr(d, _T("File"), aJson, "file", _T(""));
	d->SetOwnProp(_T("Line"), CheckExtractJsonInt(aJson, "line", (__int64)0));
	d->SetOwnProp(_T("Column"), CheckExtractJsonInt(aJson, "column", (__int64)0));
	return d;
}

static Object *CheckSyntheticDiag(LPCTSTR aMessage)
{
	Object *d = Object::Create();
	if (!d)
		return nullptr;
	d->SetOwnProp(_T("Severity"), _T("error"));
	d->SetOwnProp(_T("Type"), _T("Error"));
	d->SetOwnProp(_T("Code"), (__int64)0);
	d->SetOwnProp(_T("Message"), aMessage);
	d->SetOwnProp(_T("Extra"), _T(""));
	d->SetOwnProp(_T("File"), _T(""));
	d->SetOwnProp(_T("Line"), (__int64)0);
	d->SetOwnProp(_T("Column"), (__int64)0);
	return d;
}

static bool CheckAppendDiag(Array *aDiags, Object *d)
{
	if (!d)
		return false;
	ExprTokenType t(d);
	bool ok = aDiags->Append(t);
	d->Release();
	return ok;
}

} // namespace (Check helpers)

bif_impl FResult Check(StrArg aSource, IObject *&aRetVal)
{
	TCHAR self[MAX_PATH];
	DWORD sn = GetModuleFileName(NULL, self, MAX_PATH);
	if (sn == 0 || sn >= (DWORD)MAX_PATH)
		return FR_E_WIN32(GetLastError());
	CheckTempSource source;
	if (!CheckWriteTempSource(aSource, source.path))
		return FError(_T("Check: could not create or write the temporary script file."));
	ChildResult child;
	std::wstring raw;
	std::string captured;
	try
	{
		CheckRunSelf(self, source.path, child);
		raw = child.err + child.out;
		int bytes = WideCharToMultiByte(CP_UTF8, 0, raw.data(), (int)raw.size(), nullptr, 0, nullptr, nullptr);
		if (bytes)
		{
			captured.resize(bytes);
			WideCharToMultiByte(CP_UTF8, 0, raw.data(), (int)raw.size(), &captured[0], bytes, nullptr, nullptr);
		}
	}
	catch (const std::bad_alloc &)
	{
		return FR_E_OUTOFMEM;
	}
	Object *result = Object::Create();
	if (!result)
		return FR_E_OUTOFMEM;
	Array *diags = Array::Create();
	if (!diags)
	{
		result->Release();
		return FR_E_OUTOFMEM;
	}
	bool isOk = child.started && !child.timed_out && !child.output_limit_exceeded
		&& child.exit_code == AHK_EXIT_OK;
	result->SetOwnProp(_T("Ok"), (__int64)(isOk ? 1 : 0));
	result->SetOwnProp(_T("Raw"), raw.c_str());
	if (!isOk)
	{
		Object *diagnostic = nullptr;
		if (!child.started)
			diagnostic = CheckSyntheticDiag(_T("Check: failed to spawn the validator child process."));
		else if (child.timed_out)
			diagnostic = CheckSyntheticDiag(_T("Check: validator exceeded the 30-second timeout."));
		else if (child.output_limit_exceeded)
			diagnostic = CheckSyntheticDiag(_T("Check: validator exceeded the 8 MiB output limit."));
		else if (const char *record = strstr(captured.c_str(), "\"kind\":\"diagnostic\""))
			diagnostic = CheckBuildDiag(record, child.exit_code);
		else
		{
			TCHAR message[128];
			sntprintf(message, _countof(message),
				_T("Check: validator exited with code %u and no diagnostic output."),
				(unsigned)child.exit_code);
			diagnostic = CheckSyntheticDiag(message);
		}
		if (diagnostic)
			CheckAppendDiag(diags, diagnostic);
	}
	result->SetOwnProp(_T("Diagnostics"), diags);
	diags->Release();
	aRetVal = result;
	return OK;
}
