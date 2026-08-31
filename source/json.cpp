#include "stdafx.h"
#include "defines.h"
#include "globaldata.h"
#include "script.h"
#include "script_object.h"
#include "script_func_impl.h"
#include "abi.h"
#include "json.h"
#include <math.h>

// ============================================================================
// Native JSON: scanner, parser, writer, the ordered JsonObject container, and
// the script-visible JSON class. See json.h for the API contract.
//
// Both parser and writer are recursive with an explicit depth cap (default 256,
// hard-clamped to JSON_MAX_DEPTH) that raises a catchable error well before the
// native stack is at risk. Script-level libraries die here by native stack
// overflow, which AHK reports as an UNCATCHABLE critical error that takes the
// host script down with it; a cap turns that into an ordinary throw.
// ============================================================================

#define JSON_DEFAULT_DEPTH 256
#define JSON_MAX_DEPTH 1000   // 1000 frames * ~120 bytes stays far inside the 4 MB stack

namespace {

// ---------------------------------------------------------------------------
// Output buffer: a plain growable UTF-16 buffer. Reserving in one block beats
// repeated string concatenation, which is where script-level writers lose.
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Options
// ---------------------------------------------------------------------------

enum JsonBoolMode { JBOOL_INTEGER, JBOOL_NATIVE };
enum JsonNullMode { JNULL_EMPTY, JNULL_NATIVE };
enum JsonContainer { JCON_JSONOBJECT, JCON_MAP };

struct JsonParseOpts
{
	JsonContainer container = JCON_JSONOBJECT;
	JsonBoolMode booleans = JBOOL_INTEGER;
	JsonNullMode nulls = JNULL_EMPTY;
	int maxDepth = JSON_DEFAULT_DEPTH;
	bool allowComments = false;
	bool allowTrailingCommas = false;
	bool allowTopLevelScalar = true;
};

struct JsonWriteOpts
{
	LPTSTR space = nullptr;   // indent unit; nullptr = compact
	int maxDepth = JSON_DEFAULT_DEPTH;
	bool ensureAscii = false;
	bool escapeSlash = false;
	bool sortKeys = false;
};

// ---------------------------------------------------------------------------
// Singletons: JSON.True / JSON.False / JSON.Null.
//
// These are plain objects, so they are truthy like every other object — AHK has
// no way to make a value both falsy and identifiable (TokenToBOOL, script2.cpp:
// 3502, treats every SYM_OBJECT as true). That is exactly why the default parse
// modes hand back 1/0/"" and keep provenance in the container's tag instead.
// ---------------------------------------------------------------------------

Object *g_JsonTrue, *g_JsonFalse, *g_JsonNull;

JsonTag TagOfSingleton(IObject *obj)
{
	if (obj == g_JsonTrue)  return JTAG_TRUE;
	if (obj == g_JsonFalse) return JTAG_FALSE;
	if (obj == g_JsonNull)  return JTAG_NULL;
	return JTAG_NONE;
}

// ---------------------------------------------------------------------------
// Scanner
// ---------------------------------------------------------------------------

struct JsonScanner
{
	LPCTSTR s;
	size_t n, i = 0;
	int line = 1;
	size_t lineStart = 0;
	const JsonParseOpts &opt;

	// Set when a parse fails; the caller turns these into the thrown error.
	bool failed = false;
	TCHAR errMsg[256] = { 0 };
	LPCTSTR errCode = _T("");
	size_t errPos = 0;
	int errLine = 1, errCol = 1;

	JsonScanner(LPCTSTR aText, size_t aLen, const JsonParseOpts &aOpt)
		: s(aText), n(aLen), opt(aOpt) {}

	int Col() const { return (int)(i - lineStart) + 1; }

	bool Fail(LPCTSTR aCode, LPCTSTR aMsg)
	{
		if (!failed)
		{
			failed = true;
			errCode = aCode;
			errPos = i;
			errLine = line;
			errCol = Col();
			sntprintf(errMsg, _countof(errMsg), _T("%s"), aMsg);
		}
		return false;
	}
	bool FailChar(LPCTSTR aCode, LPCTSTR aWhat)
	{
		TCHAR buf[160];
		if (i < n)
			sntprintf(buf, _countof(buf), _T("%s but found '%c'"), aWhat, s[i]);
		else
		{
			// Running out of input is its own condition, whatever was expected.
			sntprintf(buf, _countof(buf), _T("%s but reached the end of the text"), aWhat);
			aCode = _T("UnexpectedEnd");
		}
		return Fail(aCode, buf);
	}

	void Newline() { ++line; lineStart = i + 1; }

	void SkipWs()
	{
		for (;;)
		{
			while (i < n)
			{
				TCHAR c = s[i];
				if (c == '\n') { Newline(); ++i; }
				else if (c == ' ' || c == '\t' || c == '\r') ++i;
				else break;
			}
			if (!opt.allowComments || i + 1 >= n || s[i] != '/')
				return;
			if (s[i + 1] == '/')
			{
				i += 2;
				while (i < n && s[i] != '\n')
					++i;
			}
			else if (s[i + 1] == '*')
			{
				i += 2;
				while (i + 1 < n && !(s[i] == '*' && s[i + 1] == '/'))
				{
					if (s[i] == '\n') Newline();
					++i;
				}
				if (i + 1 >= n)
				{
					Fail(_T("UnexpectedEnd"), _T("Unterminated /* comment"));
					return;
				}
				i += 2;
			}
			else
				return;
		}
	}

	// Decodes a JSON string literal into aOut. Assumes s[i] == '"'.
	bool ReadString(JsonBuf &aOut)
	{
		++i; // opening quote
		size_t runStart = i;
		for (;;)
		{
			if (i >= n)
				return Fail(_T("UnexpectedEnd"), _T("Unterminated string"));
			TCHAR c = s[i];
			if (c == '"')
			{
				aOut.Put(s + runStart, i - runStart); // copy the unescaped run in one go
				++i;
				return true;
			}
			if (c == '\\')
			{
				aOut.Put(s + runStart, i - runStart);
				++i;
				if (i >= n)
					return Fail(_T("UnexpectedEnd"), _T("Unterminated escape sequence"));
				TCHAR e = s[i];
				switch (e)
				{
				case '"':  aOut.Put('"');  break;
				case '\\': aOut.Put('\\'); break;
				case '/':  aOut.Put('/');  break;
				case 'b':  aOut.Put((TCHAR)8);  break;
				case 'f':  aOut.Put((TCHAR)12); break;
				case 'n':  aOut.Put('\n'); break;
				case 'r':  aOut.Put('\r'); break;
				case 't':  aOut.Put('\t'); break;
				case 'u':
				{
					if (i + 4 >= n)
						return Fail(_T("BadEscape"), _T("Truncated \\u escape sequence"));
					unsigned v = 0;
					for (int k = 1; k <= 4; ++k)
					{
						TCHAR h = s[i + k];
						unsigned d;
						if (h >= '0' && h <= '9') d = h - '0';
						else if (h >= 'a' && h <= 'f') d = 10 + h - 'a';
						else if (h >= 'A' && h <= 'F') d = 10 + h - 'A';
						else return Fail(_T("BadEscape"), _T("Invalid hex digit in \\u escape sequence"));
						v = v * 16 + d;
					}
					i += 4;
					// AHK strings are UTF-16, so a surrogate pair written as two
					// \u escapes lands as two correct code units with no work.
					aOut.Put((TCHAR)v);
					break;
				}
				default:
				{
					TCHAR buf[64];
					sntprintf(buf, _countof(buf), _T("Invalid escape sequence '\\%c'"), e);
					return Fail(_T("BadEscape"), buf);
				}
				}
				++i;
				runStart = i;
				continue;
			}
			if ((unsigned)c < 0x20)
				return Fail(_T("UnexpectedChar"), _T("Unescaped control character in string"));
			if (c == '\n')
				Newline();
			++i;
		}
	}
};

// ---------------------------------------------------------------------------
// Number formatting: shortest representation that reads back identically.
// thqby and StringifyAll both "clean up" float noise with a regex + Round,
// which is lossy by construction; the precision ladder is exact.
// ---------------------------------------------------------------------------

void FormatDouble(JsonBuf &aBuf, double d)
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

void WriteQuoted(JsonBuf &aBuf, LPCTSTR s, size_t len, const JsonWriteOpts &opt)
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

} // anonymous namespace

// ============================================================================
// JsonObject — ordered, case-sensitive container
// ============================================================================

Object *JsonObject::sPrototype;

JsonObject::~JsonObject()
{
	for (index_t k = 0; k < mCount; ++k)
	{
		free(mSlot[k].key);
		mSlot[k].value.Free();
	}
	free(mSlot);
}

JsonObject *JsonObject::Create()
{
	auto obj = new JsonObject();
	obj->SetBase(sPrototype);
	return obj;
}

JsonObject::Slot *JsonObject::Find(LPCTSTR aKey) const
{
	TCHAR first = *aKey;
	for (index_t k = 0; k < mCount; ++k)
		if (mSlot[k].key_c == first && !_tcscmp(mSlot[k].key, aKey))
			return mSlot + k;
	return nullptr;
}

bool JsonObject::Grow(index_t aNeeded)
{
	if (mCount + aNeeded <= mCapacity)
		return true;
	index_t want = mCapacity ? mCapacity * 2 : 8;
	while (want < mCount + aNeeded)
		want *= 2;
	Slot *bigger = (Slot *)realloc(mSlot, want * sizeof(Slot));
	if (!bigger)
		return false;
	mSlot = bigger;
	mCapacity = want;
	return true;
}

bool JsonObject::Append(LPCTSTR aKey, ExprTokenType &aValue, JsonTag aTag)
{
	if (!Grow(1))
		return false;
	Slot &slot = mSlot[mCount];
	if (!(slot.key = _tcsdup(aKey)))
		return false;
	slot.key_c = *aKey;
	slot.tag = aTag;
	slot.value.Minit();
	if (!slot.value.Assign(aValue))
	{
		free(slot.key);
		return false;
	}
	++mCount;
	return true;
}

bool JsonObject::SetItem(LPCTSTR aKey, ExprTokenType &aValue, JsonTag aTag)
{
	if (Slot *slot = Find(aKey))
	{
		slot->tag = aTag;
		return slot->value.Assign(aValue);
	}
	return Append(aKey, aValue, aTag);
}

bool JsonObject::GetItem(LPCTSTR aKey, ExprTokenType &aToken) const
{
	Slot *slot = Find(aKey);
	if (!slot)
		return false;
	slot->value.ToToken(aToken);
	return true;
}

bool JsonObject::DeleteItem(LPCTSTR aKey, ResultToken *aRetVal)
{
	Slot *slot = Find(aKey);
	if (!slot)
		return false;
	if (aRetVal)
		slot->value.ReturnMove(*aRetVal);
	else
		slot->value.Free();
	free(slot->key);
	index_t at = (index_t)(slot - mSlot);
	memmove(mSlot + at, mSlot + at + 1, (mCount - at - 1) * sizeof(Slot));
	--mCount;
	return true;
}

void JsonObject::ClearItems()
{
	for (index_t k = 0; k < mCount; ++k)
	{
		free(mSlot[k].key);
		mSlot[k].value.Free();
	}
	mCount = 0;
}

FResult JsonObject::get_Count(UINT &aRetVal)
{
	aRetVal = (UINT)mCount;
	return OK;
}

FResult JsonObject::Has(StrArg aKey, BOOL &aRetVal)
{
	aRetVal = HasItem(aKey);
	return OK;
}

FResult JsonObject::get___Item(StrArg aKey, ResultToken &aRetVal)
{
	ExprTokenType t;
	if (!GetItem(aKey, t))
		return FError(ERR_ITEM_UNSET, aKey, ErrorPrototype::UnsetItem);
	aRetVal.CopyValueFrom(t);
	if (aRetVal.symbol == SYM_OBJECT)
		aRetVal.object->AddRef();
	return OK;
}

FResult JsonObject::set___Item(ExprTokenType &aValue, StrArg aKey)
{
	JsonTag tag = JTAG_NONE;
	if (aValue.symbol == SYM_OBJECT)
		tag = TagOfSingleton(aValue.object);
	return SetItem(aKey, aValue, tag) ? OK : FR_E_OUTOFMEM;
}

FResult JsonObject::Get(StrArg aKey, ExprTokenType *aDefault, ResultToken &aRetVal)
{
	ExprTokenType t;
	if (GetItem(aKey, t))
	{
		aRetVal.CopyValueFrom(t);
		if (aRetVal.symbol == SYM_OBJECT)
			aRetVal.object->AddRef();
		return OK;
	}
	if (aDefault)
	{
		aRetVal.CopyValueFrom(*aDefault);
		if (aRetVal.symbol == SYM_OBJECT)
			aRetVal.object->AddRef();
		return OK;
	}
	return FError(ERR_ITEM_UNSET, aKey, ErrorPrototype::UnsetItem);
}

FResult JsonObject::Set(StrArg aKey, ExprTokenType &aValue)
{
	return set___Item(aValue, aKey);
}

FResult JsonObject::Delete(StrArg aKey, ResultToken &aRetVal)
{
	if (!DeleteItem(aKey, &aRetVal))
		return FError(ERR_ITEM_UNSET, aKey, ErrorPrototype::UnsetItem);
	return OK;
}

FResult JsonObject::Clear()
{
	ClearItems();
	return OK;
}

FResult JsonObject::Clone(IObject *&aRetVal)
{
	auto copy = JsonObject::Create();
	if (!copy)
		return FR_E_OUTOFMEM;
	if (!copy->Grow(mCount))
	{
		copy->Release();
		return FR_E_OUTOFMEM;
	}
	for (index_t k = 0; k < mCount; ++k)
	{
		ExprTokenType t;
		mSlot[k].value.ToToken(t);
		if (!copy->Append(mSlot[k].key, t, mSlot[k].tag))
		{
			copy->Release();
			return FR_E_OUTOFMEM;
		}
	}
	aRetVal = copy;
	return OK;
}

FResult JsonObject::get_Keys(IObject *&aRetVal)
{
	auto arr = Array::Create();
	if (!arr)
		return FR_E_OUTOFMEM;
	for (index_t k = 0; k < mCount; ++k)
		if (!arr->Append(mSlot[k].key))
		{
			arr->Release();
			return FR_E_OUTOFMEM;
		}
	aRetVal = arr;
	return OK;
}

FResult JsonObject::get_Values(IObject *&aRetVal)
{
	auto arr = Array::Create();
	if (!arr)
		return FR_E_OUTOFMEM;
	for (index_t k = 0; k < mCount; ++k)
	{
		ExprTokenType t;
		mSlot[k].value.ToToken(t);
		if (!arr->Append(t))
		{
			arr->Release();
			return FR_E_OUTOFMEM;
		}
	}
	aRetVal = arr;
	return OK;
}

// __Enum yields key/value pairs in document order — the whole point of the type.
class JsonObjectEnum : public EnumBase
{
	JsonObject *mObj;
	index_t mIndex = 0;

public:
	JsonObjectEnum(JsonObject *aObj) : mObj(aObj) { aObj->AddRef(); }
	~JsonObjectEnum() { mObj->Release(); }

	ResultType Next(Var *aKey, Var *aVal) override
	{
		if (mIndex >= mObj->Count())
			return CONDITION_FALSE;
		if (aKey)
			aKey->Assign(const_cast<LPTSTR>(mObj->KeyAt(mIndex)));
		if (aVal)
		{
			ExprTokenType t;
			mObj->ValueAt(mIndex, t);
			aVal->Assign(t);
		}
		++mIndex;
		return CONDITION_TRUE;
	}
};

FResult JsonObject::__Enum(optl<int> aVarCount, IObject *&aRetVal)
{
	aRetVal = new JsonObjectEnum(this);
	return aRetVal ? OK : FR_E_OUTOFMEM;
}

ObjectMemberMd JsonObject::sMembers[] =
{
	md_member(JsonObject, __Enum, CALL, (In_Opt, Int32, VarCount), (Ret, Object, RetVal)),
	md_member(JsonObject, __Item, GET, (In, String, Key), (Ret, Variant, RetVal)),
	md_member(JsonObject, __Item, SET, (In, Variant, Value), (In, String, Key)),
	md_member(JsonObject, Clear, CALL, md_arg_none),
	md_member(JsonObject, Clone, CALL, (Ret, Object, RetVal)),
	md_property_get(JsonObject, Count, UInt32),
	md_member(JsonObject, Delete, CALL, (In, String, Key), (Ret, Variant, RetVal)),
	md_member(JsonObject, Get, CALL, (In, String, Key), (In_Opt, Variant, Default), (Ret, Variant, RetVal)),
	md_member(JsonObject, Has, CALL, (In, String, Key), (Ret, Bool32, RetVal)),
	md_property_get(JsonObject, Keys, Object),
	md_member(JsonObject, Set, CALL, (In, String, Key), (In, Variant, Value)),
	md_property_get(JsonObject, Values, Object),
};

// ============================================================================
// Parser
// ============================================================================

namespace {

// A parsed value plus its provenance. `owned` is a reference the caller must
// release once the value has been stored (storing AddRefs it).
struct JsonValue
{
	ExprTokenType tok;
	JsonTag tag = JTAG_NONE;
	IObject *owned = nullptr;   // reference to release once stored
	LPTSTR ownedStr = nullptr;  // decoded string buffer to free once copied

	void Release()
	{
		if (owned)
			owned->Release();
		owned = nullptr;
		free(ownedStr);
		ownedStr = nullptr;
	}
};

bool ParseValue(JsonScanner &sc, JsonValue &aOut, int aDepth);

bool ParseNumber(JsonScanner &sc, JsonValue &aOut)
{
	size_t start = sc.i;
	if (sc.i < sc.n && sc.s[sc.i] == '-')
		++sc.i;
	if (sc.i >= sc.n || sc.s[sc.i] < '0' || sc.s[sc.i] > '9')
		return sc.FailChar(_T("BadNumber"), _T("Expected a digit"));
	// Leading zeros are invalid JSON: 0 may only be followed by . e E or a delimiter.
	if (sc.s[sc.i] == '0')
		++sc.i;
	else
		while (sc.i < sc.n && sc.s[sc.i] >= '0' && sc.s[sc.i] <= '9')
			++sc.i;
	bool isFloat = false;
	if (sc.i < sc.n && sc.s[sc.i] == '.')
	{
		isFloat = true;
		++sc.i;
		if (sc.i >= sc.n || sc.s[sc.i] < '0' || sc.s[sc.i] > '9')
			return sc.FailChar(_T("BadNumber"), _T("Expected a digit after the decimal point"));
		while (sc.i < sc.n && sc.s[sc.i] >= '0' && sc.s[sc.i] <= '9')
			++sc.i;
	}
	if (sc.i < sc.n && (sc.s[sc.i] == 'e' || sc.s[sc.i] == 'E'))
	{
		isFloat = true;
		++sc.i;
		if (sc.i < sc.n && (sc.s[sc.i] == '+' || sc.s[sc.i] == '-'))
			++sc.i;
		if (sc.i >= sc.n || sc.s[sc.i] < '0' || sc.s[sc.i] > '9')
			return sc.FailChar(_T("BadNumber"), _T("Expected a digit in the exponent"));
		while (sc.i < sc.n && sc.s[sc.i] >= '0' && sc.s[sc.i] <= '9')
			++sc.i;
	}

	TCHAR lex[400];
	size_t len = sc.i - start;
	if (len >= _countof(lex))
		return sc.Fail(_T("BadNumber"), _T("Number literal is too long"));
	tmemcpy(lex, sc.s + start, len);
	lex[len] = '\0';

	if (!isFloat)
	{
		errno = 0;
		LPTSTR endp = nullptr;
		__int64 v = _tcstoi64(lex, &endp, 10);
		if (errno != ERANGE)
		{
			aOut.tok.SetValue(v);
			return true;
		}
		// Out of Int64 range: fall back to a double rather than wrapping silently
		// the way thqby does (9223372036854775808 comes back negative there).
	}
	aOut.tok.SetValue(_tcstod(lex, nullptr));
	return true;
}

bool ParseKeyword(JsonScanner &sc, JsonValue &aOut)
{
	static const struct { LPCTSTR word; size_t len; JsonTag tag; } kw[] = {
		{ _T("true"),  4, JTAG_TRUE  },
		{ _T("false"), 5, JTAG_FALSE },
		{ _T("null"),  4, JTAG_NULL  },
	};
	for (auto &k : kw)
	{
		if (sc.n - sc.i >= k.len && !_tcsncmp(sc.s + sc.i, k.word, k.len))
		{
			sc.i += k.len;
			aOut.tag = k.tag;
			if (k.tag == JTAG_NULL)
			{
				if (sc.opt.nulls == JNULL_NATIVE)
				{
					g_JsonNull->AddRef();
					aOut.tok.SetValue(g_JsonNull);
					aOut.owned = g_JsonNull;
				}
				else
					aOut.tok.SetValue(_T(""), 0);
			}
			else if (sc.opt.booleans == JBOOL_NATIVE)
			{
				Object *v = (k.tag == JTAG_TRUE) ? g_JsonTrue : g_JsonFalse;
				v->AddRef();
				aOut.tok.SetValue(v);
				aOut.owned = v;
			}
			else
				aOut.tok.SetValue((__int64)(k.tag == JTAG_TRUE ? 1 : 0));
			return true;
		}
	}
	return sc.FailChar(_T("UnexpectedChar"), _T("Expected a value"));
}

bool ParseObject(JsonScanner &sc, JsonValue &aOut, int aDepth)
{
	++sc.i; // '{'
	// Container:"Map" trades the tag (and therefore exact true/false/null
	// round-tripping) for drop-in compatibility with code that tests `is Map`.
	bool asMap = sc.opt.container == JCON_MAP;
	JsonObject *obj = nullptr;
	Map *map = nullptr;
	if (asMap)
	{
		if (!(map = Map::Create()))
			return sc.Fail(_T("OutOfMemory"), _T("Out of memory"));
		aOut.tok.SetValue(map);
		aOut.owned = map;
	}
	else
	{
		if (!(obj = JsonObject::Create()))
			return sc.Fail(_T("OutOfMemory"), _T("Out of memory"));
		aOut.tok.SetValue(obj);
		aOut.owned = obj;
	}

	sc.SkipWs();
	if (sc.i < sc.n && sc.s[sc.i] == '}')
	{
		++sc.i;
		return true;
	}
	for (;;)
	{
		sc.SkipWs();
		if (sc.opt.allowTrailingCommas && sc.i < sc.n && sc.s[sc.i] == '}')
		{
			++sc.i;
			return true;
		}
		if (sc.i >= sc.n || sc.s[sc.i] != '"')
			return sc.FailChar(_T("UnexpectedChar"), _T("Expected a quoted property name"));
		JsonBuf key;
		if (!sc.ReadString(key))
			return false;
		key.Terminate();
		if (key.failed)
			return sc.Fail(_T("OutOfMemory"), _T("Out of memory"));
		sc.SkipWs();
		if (sc.i >= sc.n || sc.s[sc.i] != ':')
			return sc.FailChar(_T("UnexpectedChar"), _T("Expected ':' after the property name"));
		++sc.i;

		JsonValue val;
		if (!ParseValue(sc, val, aDepth + 1))
			return false;
		LPTSTR keyStr = key.data ? key.data : const_cast<LPTSTR>(_T(""));
		bool stored = asMap ? map->SetItem(keyStr, val.tok)
		                    : obj->SetItem(keyStr, val.tok, val.tag);
		val.Release();
		if (!stored)
			return sc.Fail(_T("OutOfMemory"), _T("Out of memory"));

		sc.SkipWs();
		if (sc.i < sc.n && sc.s[sc.i] == ',')
		{
			++sc.i;
			continue;
		}
		if (sc.i < sc.n && sc.s[sc.i] == '}')
		{
			++sc.i;
			return true;
		}
		return sc.FailChar(_T("UnexpectedChar"), _T("Expected ',' or '}'"));
	}
}

bool ParseArray(JsonScanner &sc, JsonValue &aOut, int aDepth)
{
	++sc.i; // '['
	auto arr = Array::Create();
	if (!arr)
		return sc.Fail(_T("OutOfMemory"), _T("Out of memory"));
	aOut.tok.SetValue(arr);
	aOut.owned = arr;

	sc.SkipWs();
	if (sc.i < sc.n && sc.s[sc.i] == ']')
	{
		++sc.i;
		return true;
	}
	for (;;)
	{
		sc.SkipWs();
		if (sc.opt.allowTrailingCommas && sc.i < sc.n && sc.s[sc.i] == ']')
		{
			++sc.i;
			return true;
		}
		JsonValue val;
		if (!ParseValue(sc, val, aDepth + 1))
			return false;
		bool stored = arr->Append(val.tok);
		val.Release();
		if (!stored)
			return sc.Fail(_T("OutOfMemory"), _T("Out of memory"));

		sc.SkipWs();
		if (sc.i < sc.n && sc.s[sc.i] == ',')
		{
			++sc.i;
			continue;
		}
		if (sc.i < sc.n && sc.s[sc.i] == ']')
		{
			++sc.i;
			return true;
		}
		return sc.FailChar(_T("UnexpectedChar"), _T("Expected ',' or ']'"));
	}
}

bool ParseValue(JsonScanner &sc, JsonValue &aOut, int aDepth)
{
	if (aDepth > sc.opt.maxDepth)
	{
		TCHAR buf[96];
		sntprintf(buf, _countof(buf), _T("Maximum nesting depth of %i exceeded"), sc.opt.maxDepth);
		return sc.Fail(_T("DepthExceeded"), buf);
	}
	sc.SkipWs();
	if (sc.failed)
		return false;
	if (sc.i >= sc.n)
		return sc.Fail(_T("UnexpectedEnd"), _T("Unexpected end of JSON input"));

	TCHAR c = sc.s[sc.i];
	if (c == '{')
		return ParseObject(sc, aOut, aDepth);
	if (c == '[')
		return ParseArray(sc, aOut, aDepth);
	if (c == '"')
	{
		JsonBuf str;
		if (!sc.ReadString(str))
			return false;
		str.Terminate();
		if (str.failed)
			return sc.Fail(_T("OutOfMemory"), _T("Out of memory"));
		// Detach the buffer into the value so it outlives this scope; storing the
		// value copies it, and Release() frees it afterwards.
		size_t slen = str.len;
		aOut.ownedStr = str.data;
		str.data = nullptr;
		str.len = str.cap = 0;
		aOut.tok.SetValue(aOut.ownedStr ? aOut.ownedStr : const_cast<LPTSTR>(_T("")), slen);
		return true;
	}
	if (c == '-' || (c >= '0' && c <= '9'))
		return ParseNumber(sc, aOut);
	return ParseKeyword(sc, aOut);
}

// ============================================================================
// Writer
// ============================================================================

struct JsonWriter
{
	JsonBuf &buf;
	const JsonWriteOpts &opt;
	IObject *stack[JSON_MAX_DEPTH + 1];  // open containers, for cycle detection
	int depth = 0;

	bool failed = false;
	TCHAR errMsg[256] = { 0 };
	LPCTSTR errCode = _T("");

	JsonWriter(JsonBuf &aBuf, const JsonWriteOpts &aOpt) : buf(aBuf), opt(aOpt) {}

	bool Fail(LPCTSTR aCode, LPCTSTR aMsg)
	{
		if (!failed)
		{
			failed = true;
			errCode = aCode;
			sntprintf(errMsg, _countof(errMsg), _T("%s"), aMsg);
		}
		return false;
	}

	void Indent(int aLevel)
	{
		if (!opt.space)
			return;
		buf.Put('\n');
		for (int k = 0; k < aLevel; ++k)
			buf.Put(opt.space);
	}

	bool Enter(IObject *aObj)
	{
		if (depth >= opt.maxDepth)
		{
			TCHAR m[96];
			sntprintf(m, _countof(m), _T("Maximum nesting depth of %i exceeded"), opt.maxDepth);
			return Fail(_T("DepthExceeded"), m);
		}
		for (int k = 0; k < depth; ++k)
			if (stack[k] == aObj)
				return Fail(_T("CircularReference"), _T("Value contains a circular reference"));
		stack[depth++] = aObj;
		return true;
	}
	void Leave() { --depth; }

	bool WriteValue(ExprTokenType &aTokIn, JsonTag aTag);
	bool WriteObject(JsonObject *aObj);
	bool WriteArray(Array *aArr);
	bool WriteMap(Map *aMap);
};

bool JsonWriter::WriteObject(JsonObject *aObj)
{
	if (!Enter(aObj))
		return false;
	buf.Put('{');
	Object::index_t count = aObj->Count();
	for (Object::index_t k = 0; k < count; ++k)
	{
		if (k)
			buf.Put(',');
		Indent(depth);
		LPCTSTR key = aObj->KeyAt(k);
		WriteQuoted(buf, key, _tcslen(key), opt);
		buf.Put(':');
		if (opt.space)
			buf.Put(' ');
		ExprTokenType t;
		aObj->ValueAt(k, t);
		if (!WriteValue(t, aObj->TagAt(k)))
			return false;
	}
	if (count)
		Indent(depth - 1);
	buf.Put('}');
	Leave();
	return true;
}

bool JsonWriter::WriteArray(Array *aArr)
{
	if (!Enter(aArr))
		return false;
	buf.Put('[');
	Object::index_t count = aArr->Length();
	for (Object::index_t k = 0; k < count; ++k)
	{
		if (k)
			buf.Put(',');
		Indent(depth);
		ExprTokenType t;
		if (!aArr->ItemToToken(k, t))
		{
			// A hole in a sparse array has no JSON equivalent; null keeps the
			// positions of the remaining elements correct.
			buf.Put(_T("null"));
			continue;
		}
		if (!WriteValue(t, JTAG_NONE))
			return false;
	}
	if (count)
		Indent(depth - 1);
	buf.Put(']');
	Leave();
	return true;
}

bool JsonWriter::WriteMap(Map *aMap)
{
	if (!Enter(aMap))
		return false;
	buf.Put('{');
	Object::index_t count = aMap->ItemCount();
	Object::index_t written = 0;
	for (Object::index_t k = 0; k < count; ++k)
	{
		ExprTokenType key, val;
		if (!aMap->ItemAt(k, key, val))
			continue;
		if (key.symbol != SYM_STRING)
			return Fail(_T("UnsupportedType"), _T("A Map with non-string keys cannot be represented as JSON"));
		if (written++)
			buf.Put(',');
		Indent(depth);
		WriteQuoted(buf, key.marker, _tcslen(key.marker), opt);
		buf.Put(':');
		if (opt.space)
			buf.Put(' ');
		if (!WriteValue(val, JTAG_NONE))
			return false;
	}
	if (written)
		Indent(depth - 1);
	buf.Put('}');
	Leave();
	return true;
}

bool JsonWriter::WriteValue(ExprTokenType &aTokIn, JsonTag aTag)
{
	// An argument passed as a variable arrives as SYM_VAR; resolve it to the
	// value it holds before dispatching on the symbol.
	ExprTokenType deref;
	if (aTokIn.symbol == SYM_VAR)
	{
		aTokIn.var->ToToken(deref);
		if (aTag == JTAG_NONE && deref.symbol == SYM_OBJECT)
			aTag = TagOfSingleton(deref.object);
	}
	ExprTokenType &aTok = (aTokIn.symbol == SYM_VAR) ? deref : aTokIn;

	// The container's tag wins: it records what the value was in the source
	// document, which is what makes parse -> modify -> stringify lossless.
	switch (aTag)
	{
	case JTAG_TRUE:  buf.Put(_T("true"));  return true;
	case JTAG_FALSE: buf.Put(_T("false")); return true;
	case JTAG_NULL:  buf.Put(_T("null"));  return true;
	default: break;
	}

	switch (aTok.symbol)
	{
	case SYM_INTEGER:
	{
		TCHAR num[32];
		ITOA64(aTok.value_int64, num);
		buf.Put(num);
		return true;
	}
	case SYM_FLOAT:
		FormatDouble(buf, aTok.value_double);
		return true;
	case SYM_STRING:
		WriteQuoted(buf, aTok.marker, aTok.marker_length == -1 ? _tcslen(aTok.marker) : aTok.marker_length, opt);
		return true;
	case SYM_OBJECT:
	{
		IObject *obj = aTok.object;
		if (JsonTag t = TagOfSingleton(obj))
			return WriteValue(aTok, t);
		if (auto jo = dynamic_cast<JsonObject *>(obj))
			return WriteObject(jo);
		if (auto arr = dynamic_cast<Array *>(obj))
			return WriteArray(arr);
		if (auto map = dynamic_cast<Map *>(obj))
			return WriteMap(map);
		TCHAR m[128];
		sntprintf(m, _countof(m), _T("Value of type '%s' cannot be represented as JSON"), TokenTypeString(aTok));
		return Fail(_T("UnsupportedType"), m);
	}
	default:
		// SYM_MISSING and friends: an unset value has no JSON form.
		buf.Put(_T("null"));
		return true;
	}
}

// ---------------------------------------------------------------------------
// Option parsing (an options object is accepted on both entry points)
// ---------------------------------------------------------------------------

bool OptBool(Object *aOpts, LPTSTR aName, bool aDefault)
{
	ExprTokenType t;
	if (!aOpts || !aOpts->GetOwnProp(t, aName))
		return aDefault;
	return TokenToBOOL(t) != 0;
}

int OptInt(Object *aOpts, LPTSTR aName, int aDefault)
{
	ExprTokenType t;
	if (!aOpts || !aOpts->GetOwnProp(t, aName))
		return aDefault;
	return (int)TokenToInt64(t);
}

bool OptStrIs(Object *aOpts, LPTSTR aName, LPCTSTR aWanted)
{
	ExprTokenType t;
	if (!aOpts || !aOpts->GetOwnProp(t, aName) || t.symbol != SYM_STRING)
		return false;
	return !_tcsicmp(t.marker, aWanted);
}

int ClampDepth(int aDepth)
{
	if (aDepth < 1) return 1;
	if (aDepth > JSON_MAX_DEPTH) return JSON_MAX_DEPTH;
	return aDepth;
}

// Raises the parse/stringify failure as a script exception carrying position.
FResult ThrowJsonError(LPCTSTR aCode, LPCTSTR aMsg, int aLine, int aCol, size_t aPos)
{
	TCHAR full[420];
	if (aLine > 0)
		sntprintf(full, _countof(full), _T("%s (line %i, col %i, pos %Iu) [%s]")
			, aMsg, aLine, aCol, (size_t)(aPos + 1), aCode);
	else
		sntprintf(full, _countof(full), _T("%s [%s]"), aMsg, aCode);
	return FError(full, nullptr, ErrorPrototype::Value);
}

} // anonymous namespace

// ============================================================================
// Script-visible entry points
// ============================================================================

// JSON.Parse(Text, Reviver?, Options?)  — Reviver is reserved; passing a Map/
// Object there is read as Options so thqby-shaped calls keep working.
BIF_DECL(JsonClass_Parse)
{
	LPTSTR text = ParamIndexToString(1, _f_number_buf);
	if (!text)
		text = _T("");

	Object *opts = nullptr;
	for (int k = 2; k < aParamCount; ++k)
		if (auto o = dynamic_cast<Object *>(ParamIndexToObject(k)))
			opts = o;

	JsonParseOpts po;
	po.container = OptStrIs(opts, _T("Container"), _T("Map")) ? JCON_MAP : JCON_JSONOBJECT;
	po.booleans = OptStrIs(opts, _T("Booleans"), _T("native")) ? JBOOL_NATIVE : JBOOL_INTEGER;
	po.nulls = OptStrIs(opts, _T("Null"), _T("native")) ? JNULL_NATIVE : JNULL_EMPTY;
	po.maxDepth = ClampDepth(OptInt(opts, _T("MaxDepth"), JSON_DEFAULT_DEPTH));
	po.allowComments = OptBool(opts, _T("AllowComments"), false);
	po.allowTrailingCommas = OptBool(opts, _T("AllowTrailingCommas"), false);
	po.allowTopLevelScalar = OptBool(opts, _T("AllowTopLevelScalar"), true);

	size_t len = _tcslen(text);
	// A UTF-8 BOM survives FileRead into U+FEFF; skipping it silently is what
	// every caller wants and what every library forgets.
	if (len && text[0] == 0xFEFF)
	{
		++text;
		--len;
	}

	JsonScanner sc(text, len, po);
	JsonValue val;
	if (!ParseValue(sc, val, 0))
	{
		val.Release();
		aResultToken.SetExitResult(ThrowJsonError(sc.errCode, sc.errMsg, sc.errLine, sc.errCol, sc.errPos) == OK ? OK : FAIL);
		return;
	}
	sc.SkipWs();
	if (sc.i < sc.n)
	{
		val.Release();
		sc.Fail(_T("TrailingContent"), _T("Unexpected content after the JSON value"));
		aResultToken.SetExitResult(ThrowJsonError(sc.errCode, sc.errMsg, sc.errLine, sc.errCol, sc.errPos) == OK ? OK : FAIL);
		return;
	}
	if (!po.allowTopLevelScalar && val.tok.symbol != SYM_OBJECT)
	{
		val.Release();
		aResultToken.SetExitResult(ThrowJsonError(_T("UnexpectedChar")
			, _T("Expected an object or array at the top level"), 1, 1, 0) == OK ? OK : FAIL);
		return;
	}

	aResultToken.CopyValueFrom(val.tok);
	if (aResultToken.symbol == SYM_OBJECT)
	{
		aResultToken.object->AddRef();
	}
	else if (aResultToken.symbol == SYM_STRING && val.ownedStr)
	{
		// Hand the decoded buffer to the caller rather than copying it again.
		aResultToken.mem_to_free = val.ownedStr;
		aResultToken.marker = val.ownedStr;
		val.ownedStr = nullptr;
	}
	val.Release();
}

// JSON.Stringify(Value, Replacer?, Space?, Options?) — Replacer is reserved, so
// thqby's `stringify(obj, expandlevel, space)` puts its space in the same slot.
BIF_DECL(JsonClass_Stringify)
{
	JsonWriteOpts wo;
	TCHAR spaceBuf[64];

	Object *opts = nullptr;
	if (aParamCount > 4)
		opts = dynamic_cast<Object *>(ParamIndexToObject(4));

	// Space: an integer width or a literal indent string.
	if (aParamCount > 3 && !ParamIndexIsOmitted(3))
	{
		if (TokenIsNumeric(*aParam[3]))
		{
			int width = (int)ParamIndexToInt64(3);
			if (width > 0)
			{
				if (width > 32) width = 32;
				for (int k = 0; k < width; ++k)
					spaceBuf[k] = ' ';
				spaceBuf[width] = '\0';
				wo.space = spaceBuf;
			}
		}
		else
		{
			LPTSTR s = ParamIndexToString(3, spaceBuf);
			if (s && *s)
				wo.space = s;
		}
	}
	wo.maxDepth = ClampDepth(OptInt(opts, _T("MaxDepth"), JSON_DEFAULT_DEPTH));
	wo.ensureAscii = OptBool(opts, _T("EnsureAscii"), false);
	wo.escapeSlash = OptBool(opts, _T("EscapeSlash"), false);

	JsonBuf buf;
	JsonWriter w(buf, wo);
	JsonTag tag = JTAG_NONE;
	if (aParamCount > 1)
		if (IObject *o = TokenToObject(*aParam[1]))
			tag = TagOfSingleton(o);

	ExprTokenType empty;
	empty.SetValue(_T(""), 0);
	ExprTokenType &val = (aParamCount > 1) ? *aParam[1] : empty;

	if (!w.WriteValue(val, tag))
	{
		aResultToken.SetExitResult(ThrowJsonError(w.errCode, w.errMsg, 0, 0, 0) == OK ? OK : FAIL);
		return;
	}
	buf.Terminate();
	if (buf.failed)
	{
		aResultToken.SetExitResult(FR_E_OUTOFMEM == OK ? OK : FAIL);
		return;
	}
	aResultToken.AcceptMem(buf.data ? buf.data : _tcsdup(_T("")), buf.len);
	buf.data = nullptr;
	buf.len = buf.cap = 0;
}

// ============================================================================
// Registration
// ============================================================================

void DefineJsonClass()
{
	JsonObject::sPrototype = Object::CreatePrototype(_T("JSON.Object"), Object::sPrototype
		, JsonObject::sMembers, _countof(JsonObject::sMembers));

	Object *jsonClass = Object::CreateClass(_T("JSON"), Object::sClass, JsonObject::sPrototype, nullptr);
	if (!jsonClass)
		return;

	jsonClass->DefineMethod(_T("Parse"), new BuiltInFunc{ _T("JSON.Parse"), JsonClass_Parse, 2, 4 });
	jsonClass->DefineMethod(_T("Stringify"), new BuiltInFunc{ _T("JSON.Stringify"), JsonClass_Stringify, 2, 5 });
	// Aliases: cJson-era code calls Load/Dump, thqby-era code calls parse/stringify
	// (property lookup is case-insensitive, so the lowercase forms already work).
	jsonClass->DefineMethod(_T("Load"), new BuiltInFunc{ _T("JSON.Load"), JsonClass_Parse, 2, 4 });
	jsonClass->DefineMethod(_T("Dump"), new BuiltInFunc{ _T("JSON.Dump"), JsonClass_Stringify, 2, 5 });

	// True / False / Null singletons. Getter-only, so they are genuinely
	// read-only rather than merely conventional.
	g_JsonTrue = Object::Create();
	g_JsonFalse = Object::Create();
	g_JsonNull = Object::Create();
	struct { LPTSTR name; Object *obj; } singletons[] = {
		{ _T("True"), g_JsonTrue }, { _T("False"), g_JsonFalse }, { _T("Null"), g_JsonNull },
	};
	for (auto &s : singletons)
	{
		if (!s.obj)
			continue;
		jsonClass->SetOwnProp(s.name, s.obj);
	}
}
