#pragma once

#include "script_object.h"

namespace ConsoleNative
{
// Set a property from a UTF-8 string. Returns false
// only on allocation failure; null/empty input yields an empty string.
// aName is Object::name_t (LPTSTR); callers pass string literals, matching the
// SetOwnProp idiom used throughout the codebase.
inline bool SetUtf8Property(Object *obj, LPTSTR name, const char *s, int u8len)
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
}
