#pragma once

// Shared slice of the tree-sitter C API loaded from tree-sitter-ahk.dll.
// Definitions live in error.cpp (beside TSParse); this header exists so other
// translation units (the `mcp` verb's ast_outline) can walk raw TSNodes without
// going through TSParse's AHK-object snapshot.
//
// TSNode is a 32-byte by-value struct; on the x64 ABI the compiler returns it
// via a hidden pointer and passes it as a pointer to a copy — matching how the
// DLL was built. TSPoint (8 bytes) is returned in a register. Declare the
// function pointers with these exact by-value signatures; do not substitute
// pointer parameters.
struct TSPoint { UINT32 row, column; };
struct TSNode  { UINT32 context[4]; const void *id; const void *tree; };

struct TSApi
{
	HMODULE mod = nullptr;
	bool ok = false;

	const void *(*lang)(void);
	void *(*parser_new)(void);
	void  (*parser_delete)(void *);
	bool  (*set_language)(void *, const void *);
	void *(*parse_string)(void *, const void *, const char *, UINT32);
	void  (*tree_delete)(void *);
	TSNode (*root_node)(const void *);
	const char *(*node_type)(TSNode);
	UINT32 (*start_byte)(TSNode);
	UINT32 (*end_byte)(TSNode);
	TSPoint (*start_point)(TSNode);
	TSPoint (*end_point)(TSNode);
	UINT32 (*child_count)(TSNode);
	TSNode (*child)(TSNode, UINT32);
	bool (*is_named)(TSNode);
	bool (*is_missing)(TSNode);
	bool (*is_error)(TSNode);
	bool (*has_error)(TSNode);
	bool (*is_extra)(TSNode);
	const char *(*field_name_for_child)(TSNode, UINT32);
};

// Lazy-loads the DLL on first call (exe's own directory first, then the normal
// search path). Main-thread only: the internal statics are unsynchronized.
TSApi &GetTSApi();
