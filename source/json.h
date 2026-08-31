#pragma once

// ============================================================================
// Native JSON support.
//
//   JSON.Parse(Text, Reviver?, Options?)              alias: JSON.Load
//   JSON.Stringify(Value, Replacer?, Space?, Options?) alias: JSON.Dump
//   JSON.True / JSON.False / JSON.Null                 singletons
//   JSON.Object                                        ordered container
//
// Failures raise JSONError (a ValueError subclass, so existing `catch ValueError`
// still works) whose Message carries the line, column, 1-based position and a
// machine-readable [Code]. Structured position fields belong on the planned
// JSON.Validate result object rather than on the exception.
//
// Parameter slots follow the JS/community consensus so existing call sites work
// unchanged: thqby's `JSON.stringify(obj, expandlevel, space)` lands its space
// argument in the same slot this uses.
//
// Parsing and writing are recursive with a hard depth cap (default 256, clamped
// to JSON_MAX_DEPTH), so a deep document raises a catchable JSONError long
// before the native stack is at risk — where script-level libraries die by
// stack overflow, which AHK reports as an UNCATCHABLE critical error.
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
		UINT32 hash;     // of key, so lookups compare an integer before strcmp
		JsonTag tag;
		Variant value;
	};

	Slot *mSlot = nullptr;
	index_t mCount = 0, mCapacity = 0;

	// Open-addressed hash index over mSlot, built once an object is big enough
	// to make the linear scan matter. Entries hold slot+1; 0 means empty.
	UINT32 *mIndex = nullptr;
	index_t mIndexCap = 0;

	static UINT32 HashKey(LPCTSTR aKey);
	void RebuildIndex();
	void DropIndex();
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

// Arrays parsed from JSON, carrying the same provenance tags as JsonObject so
// a bare true/false/null inside an array round-trips too. Derives from Array,
// so `value is Array` and every Array method keep working unchanged.
//
// Array's own mutators know nothing about the tags, so any change to the
// array's length moves elements out from under them; TagAt() detects that and
// reports no tag rather than mislabelling a value. Untouched arrays — the case
// that matters for read-modify-write of a config file — keep full fidelity.
class JsonArray : public Array
{
	JsonTag *mTags = nullptr;
	index_t mTagCount = 0;  // Length when the tags were recorded

public:
	static Object *sPrototype;

	~JsonArray() { free(mTags); }
	static JsonArray *Create();

	bool AppendTagged(ExprTokenType &aValue, JsonTag aTag);
	JsonTag TagAt(index_t aIndex)
	{
		return (mTags && Length() == mTagCount && aIndex < mTagCount) ? mTags[aIndex] : JTAG_NONE;
	}
};

// Registered from Object::CreateRootPrototypes().
void DefineJsonClass();
