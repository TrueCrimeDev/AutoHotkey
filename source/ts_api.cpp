#include "stdafx.h"
#include "script.h"
#include "globaldata.h"
#include "abi.h"
#include "ts_api.h"
#include "native_object_util.h"

// ============================================================================
// tree-sitter integration — TSParse(Source) -> parsed-tree snapshot
//
// Loads tree-sitter-ahk.dll (the self-contained AHK grammar + bundled
// tree-sitter runtime; see docs/TREE_SITTER.md) on first use. TSParse walks the
// whole tree in C++ and returns plain AHK objects, then frees the native tree
// immediately — no native handle outlives the call, so the script has nothing
// to release. The DLL is optional: if it is missing, TSParse throws.
// ============================================================================

// TSPoint/TSNode/TSApi are declared in ts_api.h so the `mcp` verb's native
// ast_outline can walk raw TSNodes from its own translation unit.

// Resolve the DLL + exports once. AHK runs BIFs on the main thread,
// so a plain function-local static is sufficient.
TSApi &GetTSApi()
{
	static TSApi api;
	static bool tried = false;
	if (tried)
		return api;
	tried = true;

	// Prefer the DLL sitting next to the running executable; fall back to the
	// normal search path so a copy on PATH / in the CWD still works.
	TCHAR path[MAX_PATH];
	DWORD n = GetModuleFileName(NULL, path, MAX_PATH);
	if (n > 0 && n < (DWORD)MAX_PATH)
	{
		LPTSTR slash = _tcsrchr(path, '\\');
		if (slash && (size_t)(slash - path) + 20 < (size_t)MAX_PATH)
		{
			_tcscpy(slash + 1, _T("tree-sitter-ahk.dll"));
			api.mod = LoadLibrary(path);
		}
	}
	if (!api.mod)
		api.mod = LoadLibrary(_T("tree-sitter-ahk.dll"));
	if (!api.mod)
		return api;

	#define TS_LOAD(field, name) \
		api.field = (decltype(api.field))GetProcAddress(api.mod, name); \
		if (!api.field) return api;
	TS_LOAD(lang,                 "tree_sitter_autohotkey")
	TS_LOAD(parser_new,           "ts_parser_new")
	TS_LOAD(parser_delete,        "ts_parser_delete")
	TS_LOAD(set_language,         "ts_parser_set_language")
	TS_LOAD(parse_string,         "ts_parser_parse_string")
	TS_LOAD(tree_delete,          "ts_tree_delete")
	TS_LOAD(root_node,            "ts_tree_root_node")
	TS_LOAD(node_type,            "ts_node_type")
	TS_LOAD(start_byte,           "ts_node_start_byte")
	TS_LOAD(end_byte,             "ts_node_end_byte")
	TS_LOAD(start_point,          "ts_node_start_point")
	TS_LOAD(end_point,            "ts_node_end_point")
	TS_LOAD(child_count,          "ts_node_child_count")
	TS_LOAD(child,                "ts_node_child")
	TS_LOAD(is_named,             "ts_node_is_named")
	TS_LOAD(is_missing,           "ts_node_is_missing")
	TS_LOAD(is_error,             "ts_node_is_error")
	TS_LOAD(has_error,            "ts_node_has_error")
	TS_LOAD(is_extra,             "ts_node_is_extra")
	TS_LOAD(field_name_for_child, "ts_node_field_name_for_child")
	#undef TS_LOAD

	api.ok = true;
	return api;
}

namespace {

const int TS_MAX_DEPTH = 1000; // Guard the C stack against pathological nesting.

// Recursively snapshot a node into a fresh AHK object. Returns nullptr on OOM,
// having released anything it had already built. The native tree must stay alive
// for the whole walk (it does — TSParse deletes it only after this returns).
Object *TSBuildNode(TSApi &ts, TSNode node, const char *src, UINT32 srcLen,
	const char *fieldName, int depth)
{
	Object *obj = Object::Create();
	if (!obj)
		return nullptr;

	const char *type = ts.node_type(node);
	UINT32 sb = ts.start_byte(node), eb = ts.end_byte(node);
	TSPoint sp = ts.start_point(node), ep = ts.end_point(node);

	bool ok = ConsoleNative::SetUtf8Property(obj, _T("Type"), type, type ? (int)strlen(type) : 0);
	obj->SetOwnProp(_T("StartByte"), (__int64)sb);
	obj->SetOwnProp(_T("EndByte"),   (__int64)eb);
	obj->SetOwnProp(_T("StartRow"),  (__int64)sp.row);
	obj->SetOwnProp(_T("StartCol"),  (__int64)sp.column);
	obj->SetOwnProp(_T("EndRow"),    (__int64)ep.row);
	obj->SetOwnProp(_T("EndCol"),    (__int64)ep.column);
	obj->SetOwnProp(_T("IsNamed"),   (__int64)(ts.is_named(node)   ? 1 : 0));
	obj->SetOwnProp(_T("IsMissing"), (__int64)(ts.is_missing(node) ? 1 : 0));
	obj->SetOwnProp(_T("IsError"),   (__int64)(ts.is_error(node)   ? 1 : 0));
	obj->SetOwnProp(_T("HasError"),  (__int64)(ts.has_error(node)  ? 1 : 0));
	obj->SetOwnProp(_T("IsExtra"),   (__int64)(ts.is_extra(node)   ? 1 : 0));
	if (fieldName)
		ok = ConsoleNative::SetUtf8Property(obj, _T("FieldName"), fieldName, (int)strlen(fieldName)) && ok;
	else
		obj->SetOwnProp(_T("FieldName"), _T(""));
	// Node text: the UTF-8 slice [sb, eb) re-decoded to UTF-16.
	if (eb >= sb && eb <= srcLen)
		ok = ConsoleNative::SetUtf8Property(obj, _T("Text"), src + sb, (int)(eb - sb)) && ok;
	else
		obj->SetOwnProp(_T("Text"), _T(""));
	if (!ok)
	{
		obj->Release();
		return nullptr;
	}

	Array *children = Array::Create();
	Array *named = Array::Create();
	if (!children || !named)
	{
		if (children) children->Release();
		if (named) named->Release();
		obj->Release();
		return nullptr;
	}

	if (depth < TS_MAX_DEPTH)
	{
		UINT32 cc = ts.child_count(node);
		for (UINT32 i = 0; i < cc; ++i)
		{
			TSNode ch = ts.child(node, i);
			const char *fn = ts.field_name_for_child(node, i); // may be null
			Object *childObj = TSBuildNode(ts, ch, src, srcLen, fn, depth + 1);
			if (!childObj)
			{
				children->Release();
				named->Release();
				obj->Release();
				return nullptr;
			}
			// Append/SetOwnProp AddRef the value, so drop our creation ref after.
			ExprTokenType ct(childObj);
			bool ac = children->Append(ct);
			bool an = true;
			if (ac && ts.is_named(ch))
				an = named->Append(ct);
			childObj->Release();
			if (!ac || !an)
			{
				children->Release();
				named->Release();
				obj->Release();
				return nullptr;
			}
		}
		obj->SetOwnProp(_T("Truncated"), (__int64)0);
	}
	else
	{
		obj->SetOwnProp(_T("Truncated"), (__int64)1);
	}

	obj->SetOwnProp(_T("Children"), children);
	obj->SetOwnProp(_T("NamedChildren"), named);
	children->Release();
	named->Release();
	return obj;
}

} // anonymous namespace

// TSParse(Source) -> Object {Root, Source, HasError}. Each node carries Type,
// byte/point span, IsNamed/IsMissing/IsError/HasError/IsExtra, FieldName, Text,
// Children and NamedChildren. See docs/TREE_SITTER.md.
bif_impl FResult TSParse(StrArg aSource, IObject *&aRetVal)
{
	TSApi &ts = GetTSApi();
	if (!ts.ok)
		return FError(_T("tree-sitter-ahk.dll could not be loaded or is missing required exports."));

	// AHK source is UTF-16; tree-sitter parses UTF-8 bytes. Keep the UTF-8 copy
	// alive for the whole walk so node byte offsets can be sliced back into Text.
	int u8size = WideCharToMultiByte(CP_UTF8, 0, aSource, -1, nullptr, 0, nullptr, nullptr);
	if (u8size <= 0)
		return FR_E_FAILED;
	char *u8 = (char *)malloc((size_t)u8size);
	if (!u8)
		return FR_E_OUTOFMEM;
	WideCharToMultiByte(CP_UTF8, 0, aSource, -1, u8, u8size, nullptr, nullptr);
	UINT32 u8len = (UINT32)(u8size - 1); // exclude the trailing NUL

	void *parser = ts.parser_new();
	if (!parser)
	{
		free(u8);
		return FR_E_OUTOFMEM;
	}
	if (!ts.set_language(parser, ts.lang()))
	{
		ts.parser_delete(parser);
		free(u8);
		return FError(_T("tree-sitter language/runtime ABI mismatch."));
	}
	void *tree = ts.parse_string(parser, nullptr, u8, u8len);
	if (!tree)
	{
		ts.parser_delete(parser);
		free(u8);
		return FR_E_OUTOFMEM;
	}

	TSNode root = ts.root_node(tree);
	bool rootHasError = ts.has_error(root);
	Object *rootObj = TSBuildNode(ts, root, u8, u8len, nullptr, 0); // walk while tree is alive

	ts.tree_delete(tree);
	ts.parser_delete(parser);
	free(u8);

	if (!rootObj)
		return FR_E_OUTOFMEM;

	Object *treeObj = Object::Create();
	if (!treeObj)
	{
		rootObj->Release();
		return FR_E_OUTOFMEM;
	}
	treeObj->SetOwnProp(_T("Root"), rootObj);
	treeObj->SetOwnProp(_T("Source"), aSource);
	treeObj->SetOwnProp(_T("HasError"), (__int64)(rootHasError ? 1 : 0));
	rootObj->Release();

	aRetVal = treeObj;
	return OK;
}
