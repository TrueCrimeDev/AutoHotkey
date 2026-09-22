#include "stdafx.h"
#include "defines.h"
#include "globaldata.h"
#include "script.h"
#include "script_object.h"
#include "script_func_impl.h"
#include "abi.h"
#include "json.h"
#include "inspect.h"
#include "json_internal.h"
#include <vector>

using namespace ahk_json_internal;

// ---------------------------------------------------------------------------
// Inspect(Value, Depth := 2, MaxItems := 100)
//
// A structured view of a live value for tools, agents and the REPL. It never
// invokes script: own value properties are serialized, while getters, typed
// fields and methods (own and inherited up to Object.Prototype) are listed by
// name. Nested objects are described to Depth levels, containers are cut at
// MaxItems, and cycles are reported instead of followed.
// ---------------------------------------------------------------------------

namespace
{
	struct Inspector
	{
		JsonBuf &buf;
		JsonWriteOpts opt;
		int maxDepth, maxItems;
		IObject *stack[JSON_MAX_DEPTH + 1];
		int depth = 0;

		Inspector(JsonBuf &aBuf, int aDepth, int aMaxItems) : buf(aBuf), maxDepth(aDepth), maxItems(aMaxItems) {}

		void Key(LPCTSTR aKey) { WriteQuoted(buf, aKey, _tcslen(aKey), opt); buf.Put(':'); }
		void Str(LPCTSTR aStr, size_t aLen = (size_t)-1) { WriteQuoted(buf, aStr, aLen == (size_t)-1 ? _tcslen(aStr) : aLen, opt); }
		void Int(__int64 aNum) { TCHAR num[32]; ITOA64(aNum, num); buf.Put(num); }

		bool IsCircular(IObject *aObj)
		{
			for (int k = 0; k < depth; ++k)
				if (stack[k] == aObj)
					return true;
			return false;
		}

		// Top-level entry: primitives get a descriptor too, so the output shape
		// is always an object with a "type".
		void Top(ExprTokenType &aTokIn)
		{
			ExprTokenType deref;
			if (aTokIn.symbol == SYM_VAR)
				aTokIn.var->ToToken(deref);
			ExprTokenType &t = aTokIn.symbol == SYM_VAR ? deref : aTokIn;
			if (t.symbol == SYM_OBJECT)
			{
				Describe(t.object);
				return;
			}
			buf.Put(_T("{\"type\":"));
			switch (t.symbol)
			{
			case SYM_INTEGER: buf.Put(_T("\"Integer\",\"value\":")); Int(t.value_int64); break;
			case SYM_FLOAT: buf.Put(_T("\"Float\",\"value\":")); FormatDouble(buf, t.value_double); break;
			case SYM_STRING:
			{
				size_t len = t.marker_length == -1 ? _tcslen(t.marker) : t.marker_length;
				buf.Put(_T("\"String\",\"length\":")); Int((__int64)len);
				buf.Put(_T(",\"value\":")); Str(t.marker, len);
				break;
			}
			default: buf.Put(_T("\"Unset\""));
			}
			buf.Put('}');
		}

		// Primitive -> JSON value; object -> descriptor.
		void Value(ExprTokenType &aTokIn)
		{
			ExprTokenType deref;
			if (aTokIn.symbol == SYM_VAR)
				aTokIn.var->ToToken(deref);
			ExprTokenType &t = aTokIn.symbol == SYM_VAR ? deref : aTokIn;
			switch (t.symbol)
			{
			case SYM_INTEGER: Int(t.value_int64); return;
			case SYM_FLOAT: FormatDouble(buf, t.value_double); return;
			case SYM_STRING: Str(t.marker, t.marker_length == -1 ? _tcslen(t.marker) : t.marker_length); return;
			case SYM_OBJECT: Describe(t.object); return;
			default: buf.Put(_T("null")); return;
			}
		}

		void Describe(IObject *aObj)
		{
			buf.Put(_T("{\"type\":"));
			Str(aObj->Type());
			if (IsCircular(aObj))
			{
				buf.Put(_T(",\"circular\":true}"));
				return;
			}
			if (depth >= maxDepth)
			{
				buf.Put(_T(",\"truncated\":true}"));
				return;
			}
			stack[depth++] = aObj;
			bool truncated = false;
			if (auto func = dynamic_cast<Func *>(aObj))
				DescribeFunc(func);
			else if (auto jo = dynamic_cast<JsonObject *>(aObj))
				truncated |= DescribeJsonObject(jo);
			else if (auto arr = dynamic_cast<Array *>(aObj))
				truncated |= DescribeArray(arr);
			else if (auto map = dynamic_cast<Map *>(aObj))
				truncated |= DescribeMap(map);
			if (auto obj = dynamic_cast<Object *>(aObj))
				truncated |= DescribeObject(obj);
			if (truncated)
				buf.Put(_T(",\"truncated\":true"));
			--depth;
			buf.Put('}');
		}

		void DescribeFunc(Func *aFunc)
		{
			buf.Put(_T(",\"name\":"));
			Str(aFunc->mName ? aFunc->mName : _T(""));
			buf.Put(_T(",\"minParams\":")); Int(aFunc->mMinParams);
			buf.Put(_T(",\"maxParams\":")); Int(aFunc->mParamCount);
			buf.Put(aFunc->mIsVariadic ? _T(",\"variadic\":true") : _T(",\"variadic\":false"));
		}

		// JSON.Object keeps its keys in document order outside the field table.
		bool DescribeJsonObject(JsonObject *aObj)
		{
			Object::index_t count = aObj->Count();
			buf.Put(_T(",\"count\":")); Int(count);
			buf.Put(_T(",\"entries\":["));
			Object::index_t shown = count < (Object::index_t)maxItems ? count : (Object::index_t)maxItems;
			for (Object::index_t k = 0; k < shown; ++k)
			{
				if (k)
					buf.Put(',');
				buf.Put('[');
				Str(aObj->KeyAt(k));
				buf.Put(',');
				ExprTokenType t;
				aObj->ValueAt(k, t);
				Value(t);
				buf.Put(']');
			}
			buf.Put(']');
			return shown < count;
		}

		bool DescribeArray(Array *aArr)
		{
			Object::index_t count = aArr->Length();
			buf.Put(_T(",\"length\":")); Int(count);
			buf.Put(_T(",\"items\":["));
			Object::index_t shown = count < (Object::index_t)maxItems ? count : (Object::index_t)maxItems;
			for (Object::index_t k = 0; k < shown; ++k)
			{
				if (k)
					buf.Put(',');
				ExprTokenType t;
				if (aArr->ItemToToken(k, t))
					Value(t);
				else
					buf.Put(_T("null"));
			}
			buf.Put(']');
			return shown < count;
		}

		bool DescribeMap(Map *aMap)
		{
			Object::index_t count = aMap->ItemCount();
			buf.Put(_T(",\"count\":")); Int(count);
			buf.Put(_T(",\"entries\":["));
			Object::index_t written = 0;
			bool truncated = false;
			for (Object::index_t k = 0; k < count; ++k)
			{
				ExprTokenType key, val;
				if (!aMap->ItemAt(k, key, val))
					continue;
				if (written >= (Object::index_t)maxItems)
				{
					truncated = true;
					break;
				}
				if (written++)
					buf.Put(',');
				buf.Put('[');
				Value(key);
				buf.Put(',');
				Value(val);
				buf.Put(']');
			}
			buf.Put(']');
			return truncated;
		}

		struct NameList
		{
			std::vector<LPCTSTR> names;
			bool Add(LPCTSTR aName)
			{
				for (auto n : names)
					if (!_tcsicmp(n, aName))
						return false;
				names.push_back(aName);
				return true;
			}
		};

		void WriteNames(LPCTSTR aKey, NameList &aList)
		{
			if (aList.names.empty())
				return;
			buf.Put(',');
			Key(aKey);
			buf.Put('[');
			for (size_t k = 0; k < aList.names.size(); ++k)
			{
				if (k)
					buf.Put(',');
				Str(aList.names[k]);
			}
			buf.Put(']');
		}

		// Walk the prototype chain, stopping at the engine's root prototypes so
		// the universal Object/Any members do not swamp the listing.
		static bool IsRootPrototype(Object *aObj)
		{
			return !aObj || aObj == Object::sPrototype || aObj == Object::sClass
				|| aObj == Object::sClassPrototype || aObj == Object::sAnyPrototype;
		}

		bool DescribeObject(Object *aObj)
		{
			bool truncated = false;
			if (Object *proto = aObj->ClassGetPrototype())
			{
				buf.Put(_T(",\"class\":"));
				LPTSTR name = proto->GetOwnPropString(_T("__Class"));
				Str(name ? name : _T(""));
			}
			NameList getters, setters, methods, typed;
			buf.Put(_T(",\"properties\":{"));
			Object::index_t written = 0;
			for (Object::index_t k = 0; k < aObj->OwnPropCount(); ++k)
			{
				LPCTSTR name; SymbolType symbol; ExprTokenType value; Property *prop;
				if (!aObj->OwnFieldAt(k, name, symbol, value, prop))
					break;
				if (symbol == SYM_DYNAMIC)
				{
					if (prop->Method()) methods.Add(name);
					if (prop->Getter()) getters.Add(name);
					if (prop->Setter()) setters.Add(name);
					continue;
				}
				if (symbol == SYM_TYPED_FIELD)
				{
					typed.Add(name);
					continue;
				}
				if (written >= (Object::index_t)maxItems)
				{
					truncated = true;
					break;
				}
				if (written++)
					buf.Put(',');
				Key(name);
				Value(value);
			}
			buf.Put('}');
			for (Object *base = aObj->Base(); !IsRootPrototype(base); base = base->Base())
			{
				for (Object::index_t k = 0; k < base->OwnPropCount(); ++k)
				{
					LPCTSTR name; SymbolType symbol; ExprTokenType value; Property *prop;
					if (!base->OwnFieldAt(k, name, symbol, value, prop))
						break;
					if (symbol != SYM_DYNAMIC)
						continue;
					if (prop->Method()) methods.Add(name);
					if (prop->Getter()) getters.Add(name);
					if (prop->Setter()) setters.Add(name);
				}
			}
			for (NameList *list : { &getters, &setters, &methods, &typed })
				if (list->names.size() > (size_t)maxItems)
				{
					list->names.resize(maxItems);
					truncated = true;
				}
			WriteNames(_T("getters"), getters);
			WriteNames(_T("setters"), setters);
			WriteNames(_T("methods"), methods);
			WriteNames(_T("typed"), typed);
			return truncated;
		}
	};

	void ClampInspectArgs(int &aDepth, int &aMaxItems)
	{
		if (aDepth < 0) aDepth = 0;
		if (aDepth > JSON_MAX_DEPTH) aDepth = JSON_MAX_DEPTH;
		if (aMaxItems < 1) aMaxItems = 1;
	}
}

LPTSTR InspectValue(ExprTokenType &aValue, int aDepth, int aMaxItems)
{
	ClampInspectArgs(aDepth, aMaxItems);
	JsonBuf buf;
	Inspector inspector(buf, aDepth, aMaxItems);
	inspector.Top(aValue);
	buf.Terminate();
	if (buf.failed || !buf.data)
		return nullptr;
	LPTSTR result = buf.data;
	buf.data = nullptr; // Ownership moves to the caller.
	return result;
}

bif_impl FResult Inspect(ExprTokenType &aValue, optl<int> aDepth, optl<int> aMaxItems, StrRet &aRetVal)
{
	LPTSTR text = InspectValue(aValue, aDepth.value_or(2), aMaxItems.value_or(100));
	if (!text)
		return FR_E_OUTOFMEM;
	bool copied = aRetVal.Copy(text);
	free(text);
	return copied ? OK : FR_E_OUTOFMEM;
}
