#pragma once

// ============================================================================
// Native JSON support.
//
//   JSON.Parse(Text, Reviver?, Options?)              alias: JSON.Load
//   JSON.Stringify(Value, Replacer?, Space?, Options?) alias: JSON.Dump
//   JSON.True / JSON.False / JSON.Null                 typed singletons
//   JSON.Object(Pairs*)                                ordered container
//   class JSONError extends Error                      Code/Char/Line/Col/Path
//
// Parameter slots follow the JS/community consensus so existing call sites work
// unchanged: thqby's `JSON.stringify(obj, expandlevel, space)` lands its space
// argument in the same slot this uses.
//
// Scanning is iterative with an explicit heap stack on BOTH sides, so a deep
// document raises a catchable JSONError instead of the uncatchable native stack
// overflow every script-level library dies from.
// ============================================================================

// Records the JSON provenance of a stored value. Script sees true/false/null as
// 1/0/"" so `if cfg["enabled"]` reads naturally and Type() is unsurprising; the
// tag rides along in the container so Stringify emits the original keyword back.
// This is why a config file survives parse -> modify -> stringify intact.
enum JsonTag : UCHAR
{
	JTAG_NONE = 0,
	JTAG_TRUE,
	JTAG_FALSE,
	JTAG_NULL,
};

// Ordered, case-sensitive, string-keyed container; the default parse target.
// AHK's Map keeps its pairs sorted and Object sorts fields case-insensitively,
// so neither can preserve document order or distinguish "a" from "A" — which is
// why every script-level JSON library silently reorders a file it rewrites.
class JsonObject : public Object
{
	struct Slot
	{
		LPTSTR key;      // malloc'd, compared case-sensitively
		TCHAR key_c;     // first char, for fast rejection during lookup
		JsonTag tag;
		Variant value;
	};

	Slot *mSlot = nullptr;
	index_t mCount = 0, mCapacity = 0;

	Slot *Find(LPCTSTR aKey) const;
	bool Grow(index_t aNeeded);

public:
	static Object *sPrototype;
	static ObjectMemberMd sMembers[];

	JsonObject() {}
	~JsonObject();

	static JsonObject *Create();

	index_t Count() const { return mCount; }
	LPCTSTR KeyAt(index_t aIndex) const { return mSlot[aIndex].key; }
	JsonTag TagAt(index_t aIndex) const { return mSlot[aIndex].tag; }
	void ValueAt(index_t aIndex, ExprTokenType &aToken) { mSlot[aIndex].value.ToToken(aToken); }

	// Appends without checking for an existing key — for the parser's fast path
	// when duplicates are impossible or already resolved.
	bool Append(LPCTSTR aKey, ExprTokenType &aValue, JsonTag aTag);
	bool SetItem(LPCTSTR aKey, ExprTokenType &aValue, JsonTag aTag);
	bool GetItem(LPCTSTR aKey, ExprTokenType &aToken) const;
	bool HasItem(LPCTSTR aKey) const { return Find(aKey) != nullptr; }
	bool DeleteItem(LPCTSTR aKey, ResultToken *aRetVal);
	void ClearItems();

	// Script-visible members.
	FResult get___Item(StrArg aKey, ResultToken &aRetVal);
	FResult set___Item(ExprTokenType &aValue, StrArg aKey);
	FResult Has(StrArg aKey, BOOL &aRetVal);
	FResult Get(StrArg aKey, ExprTokenType *aDefault, ResultToken &aRetVal);
	FResult Set(StrArg aKey, ExprTokenType &aValue);
	FResult Delete(StrArg aKey, ResultToken &aRetVal);
	FResult Clear();
	FResult Clone(IObject *&aRetVal);
	FResult get_Count(UINT &aRetVal);
	FResult get_Keys(IObject *&aRetVal);
	FResult get_Values(IObject *&aRetVal);
	FResult __Enum(optl<int> aVarCount, IObject *&aRetVal);
};

// Registered from Object::CreateRootPrototypes().
void DefineJsonClass();
