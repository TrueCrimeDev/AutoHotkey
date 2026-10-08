;
; fork.d.ahk: declarations for thqby's vscode-autohotkey2-lsp covering this
; fork's additions on top of AutoHotkey v2.1-alpha.33. The engine reports
; A_AhkVersion = "2.1-alpha.33+Console".
;
; This file holds declarations only, not code. Do not #Include it: the engine
; would load each entry as a script definition that shadows the built-in, and
; the script then fails at startup.
;
; LOADING (verified against vscode-autohotkey2-lsp 3.0.10, server/dist/server.js)
;
; The server does not load this file just because it sits in the workspace. Its
; workspace scan skips *.d.ahk files, and no AutoHotkey2.Files.ScanInclude
; setting exists. Use one of these in each file that uses the fork's names. A
; file reached through #Include does not inherit them.
;
;   1. A ;@include comment directive. Any number are allowed.
;        ;@include C:\path\to\fork.d.ahk   absolute path
;        ;@include ..\fork.d.ahk           relative to the script's own folder
;        ;@include <fork>                  fork.d.ahk from a Lib folder (below)
;      The server appends ".d.ahk" when the path lacks it, and the engine reads
;      the line as a comment.
;   2. ;@reference <path>: at most one per script, and it may use %A_Locale%.
;      When the path resolves, it replaces the script's sibling declaration
;      file (option 3). When it does not, the sibling file is used, with no
;      diagnostic.
;   3. A sibling file: Foo.ahk automatically uses Foo.d.ahk from its folder.
;
; <fork> searches <workspace folder>\Lib\ (or <script folder>\Lib\ outside a
; workspace). Once an interpreter is selected, it also searches
; Documents\AutoHotkey\Lib\ and <interpreter folder>\Lib\.
; AutoHotkey2.Syntaxes replaces the bundled ahk2.d.ahk wholesale, so it cannot
; add this file alongside the bundled one.
;
; Each @since tag gives the engine version at the commit that added the member
; (its "+Console" version string where the fork set one). The server enforces
; @since only in its bundled syntax files, so here the tags are documentation.
;
; RETURN TYPES THAT CAN BE UNSET
;
; This file must also pass the engine's own `check` (the post-edit hook runs it
; on each edited .ahk file, and tools/check_all.py on every .ahk file in the
; repo), so every declaration has to parse as AutoHotkey. The bundled
; ahk2.d.ahk spells an unset result `T | unset` or `T?`. The engine rejects
; `| unset` ("This operator's right operand must not be unset.") and a `?` on
; a middle member of a union, and it reads a `?` at the end of a line as an
; operator and joins the next line onto it. So the `?` goes on the first
; member: `Array? | String` means Array, String or unset, and `Any? | Any`
; means Any or unset. The server shows them as `Array | unset? | String` and
; `Any | unset?`.
;

;@region Functions

/**
 * Evaluates one AutoHotkey expression in the caller's scope and returns its
 * value, which may be unset.
 *
 * Disabled by default. Enable it with the `#EnableEval` directive or the
 * `/Eval` switch (`--eval` from Git Bash). Otherwise every call throws an
 * `Error`: "Eval is disabled (add #EnableEval to your script or pass /Eval)".
 *
 * Names resolve to the calling function's locals and parameters, then its
 * static and closure variables, then globals. Assignments change the caller's
 * existing locals, statics, captured closure variables and declared globals.
 * Assigning to any other name creates it: a new global at the top level or in
 * an assume-global function, otherwise a new local, even when a global of
 * that name exists (declare it `global` to assign the global). That local
 * stays in the function, so on each later call it starts unset and hides the
 * global from Eval. Reading a name that does not exist raises the VarUnset
 * warning (when enabled) and then throws UnsetError.
 *
 * Eval can return unset in either compatibility mode, as with `Eval("x?")`
 * when x is unset, or `Eval("unset")`. Assigning or passing that result
 * throws UnsetError ("No value was returned."), so write
 * `Eval(...) ?? Default`. A built-in function inside the expression that
 * returns no value gives "" in the default v2.0 mode, as it would in the
 * script itself, and unset under `#Requires AutoHotkey v2.1-...`.
 * @param {String} Expression A single expression of at most 16,384 characters.
 * Statements and control flow are not accepted.
 * @returns {Any|unset} The expression's value, or unset.
 * @throws {SyntaxError} The expression does not parse. The error's `File` is
 * "_Eval", and its `Line` and `Column` are 0.
 * @throws {ValueError} The expression is longer than 16,384 characters.
 * @example
 * #EnableEval
 * x := 10, y := 20
 * Print(Eval("x + y"))   ; 30
 * Eval("x := 99")        ; assigns the caller's x
 * @since 2.1-alpha.29+Console
 */
Eval(Expression) => Any? | Any

/**
 * Writes a line to stdout as UTF-8 and returns an empty string.
 *
 * - `Print()` writes an empty line.
 * - `Print(Text)` writes Text unchanged. A single argument never goes
 *   through `Format`, so literal `{` and `}` survive.
 * - `Print(Fmt, Values*)` writes `Format(Fmt, Values*)`.
 *
 * Writes nothing when the process has no stdout, such as a GUI build started
 * from Explorer. While a DBGp debugger has stdout copy (`stdout -c 1`) or
 * redirect (`stdout -c 2`) enabled, the line goes to the debugger's stdout
 * stream; copy mode also writes it to stdout. `/Debug=stdio` always
 * redirects. `Format` dispatch for two or more arguments arrived in
 * 2.1-alpha.30+Console.
 * @param {String} Fmt The text to write, or a `Format` pattern when Values
 * are supplied.
 * @param Values Values for the pattern's placeholders.
 * @overload Print() => void
 * @overload Print(Text) => void
 * @overload Print(Fmt, Values*) => void
 * @example
 * Print("hello")              ; hello
 * Print()                     ; empty line
 * Print("x={}, y={}", 1, 2)   ; x=1, y=2
 * Print("{ok: true}")         ; {ok: true}
 * @since 2.1-alpha.29+Console
 */
Print(Fmt?, Values*) => void

/**
 * Checks whether AutoHotkey source parses, using the engine itself. The source
 * goes to a temporary file, and a child copy of this executable runs
 * `/script /Headless /Diag=json /Check` on it. The host script's state is not
 * touched.
 *
 * Returns `{Ok, Diagnostics, Raw}`:
 * - `Ok`: 1 when the child exits 0 (warnings allowed), otherwise 0.
 * - `Diagnostics`: an Array that is empty when `Ok` is 1, even if the child
 *   printed warnings. Otherwise it holds one
 *   `{Severity, Type, Code, Message, Extra, File, Line, Column}` object built
 *   from the first diagnostic record in `Raw`, whatever its severity. A
 *   load-time warning on stderr that comes before the error (VarUnset
 *   warnings are on by default) therefore takes the place of the error, so
 *   check `Severity`. `#Warn ..., StdOut` sends warnings to stdout, which
 *   follows every stderr record in `Raw`, so then the error is picked even
 *   when the child printed a warning first. `File` names the temporary file.
 * - `Raw`: all of the child's stderr followed by all of its stdout, normally
 *   one JSON object per line: the diagnostic records, then
 *   `{"kind":"check","status":"pass"}` when the source parses. It does not
 *   keep the order in which the child wrote to the two streams.
 *
 * The child has a 30-second timeout and an 8 MiB output limit. A spawn
 * failure, a timeout, an exceeded limit, or a nonzero exit with no diagnostic
 * record in `Raw` returns `Ok` = 0 with one synthetic diagnostic: Severity
 * "error", Code 0, Line 0, an empty File, and a Message that starts with
 * "Check:".
 *
 * Load-time directives such as `#DllLoad` still take effect in the child, so
 * this is not a sandbox. Use `Check`, not `TSParse(...).HasError`, to decide
 * whether code parses.
 * @param {String} Source AutoHotkey source text.
 * @example
 * r := Check("y := undefinedQ`nG() {`n    Goto Nope`n}")
 * d := r.Diagnostics[1]
 * Print("{} at line {}: {}", d.Severity, d.Line, d.Message)
 * ; warning at line 1: This global variable appears to never be assigned a value.
 * for line in StrSplit(Trim(r.Raw, "`r`n"), "`n", "`r")
 *     if (rec := JSON.Parse(line)).Get("severity", "") = "error"
 *         Print("line {}: {}", rec["line"], rec["message"])
 * ; line 3: Label not found in current scope.
 * @since 2.1-alpha.30+Console
 */
Check(Source) => Object

/**
 * Returns a JSON string that describes a value without running any script:
 * getters and methods are listed by name and never called.
 *
 * Objects produce `type` and `properties` (own value properties), plus
 * `getters`, `setters` and `methods` name lists covering own and inherited
 * members, stopping before the built-in roots such as `Object.Prototype`.
 * The `typed` list holds only the object's own typed fields. A class's typed
 * fields live on its prototype, so they appear when inspecting
 * `Cls.Prototype` (without inherited ones), not an instance. A class object
 * also gets `class`, its class name. Arrays add `length` and `items`. Maps
 * and `JSON.Object` add `count` and `entries`, given as `[key, value]` pairs.
 * Functions add `name`, `minParams`, `maxParams` and `variadic`. A primitive
 * at the top level produces `{type, value}`, and a String also gets `length`.
 * A node marked `truncated` hit Depth or MaxItems, and one marked `circular`
 * is already open higher in the tree.
 * @param Value Any value.
 * @param {Integer} Depth The levels of nested objects to describe, clamped to
 * the range 0 to 1000.
 * @param {Integer} MaxItems The most items, entries, properties or names to
 * list per node, at least 1.
 * @example
 * Print(Inspect(Map("a", [1, 2]), 3))
 * @since 2.1-alpha.33+Console
 */
Inspect(Value, Depth := 2, MaxItems := 100) => String

/**
 * Parses AutoHotkey source with the bundled tree-sitter grammar and returns a
 * snapshot of plain objects. No native handle outlives the call.
 *
 * Returns `{Root, Source, HasError}`. Each node has `Type`,
 * `StartByte`/`EndByte`, `StartRow`/`StartCol`/`EndRow`/`EndCol`, `Text`,
 * `IsNamed`, `IsMissing`, `IsError`, `IsExtra`, `HasError`, `FieldName`,
 * `Children`, `NamedChildren` and `Truncated`. Offsets and columns count UTF-8
 * bytes, and rows and columns start at 0. `Truncated` is 1 on a node deeper than
 * 1000 levels, whose children are omitted.
 *
 * Use it for structure only. The grammar is incomplete and sets `HasError` on
 * some valid code, such as typed Structs, fat-arrow methods and `^j::`
 * hotkeys. Use `Check` to decide whether code parses. See
 * docs/TREE_SITTER.md.
 *
 * The first call loads tree-sitter-ahk.dll from the executable's folder, then
 * from the normal DLL search path. An `Error` is thrown if the DLL cannot be
 * loaded.
 * @param {String} Source AutoHotkey source text.
 * @example
 * tree := TSParse(FileRead("x.ahk", "UTF-8"))
 * for node in tree.Root.NamedChildren
 *     Print("{} @ {}", node.Type, node.StartRow + 1)
 * @since 2.1-alpha.30+Console
 */
TSParse(Source) => Object

/**
 * Returns the engine's parsed lines around a line of a loaded script file, as
 * an Array of `{File, Number, Text}` objects.
 *
 * `Text` is the engine's rendering of the parsed line, not the raw source.
 * Comments and blank lines are absent, and an opening brace can come back as
 * its own entry with the same `Number`. Such entries count toward Range.
 *
 * When LineNumber holds no code (blank, comment-only, past the end or in a
 * file the script did not load), no Array is returned. In the default v2.0
 * mode the result is an empty string; under `#Requires AutoHotkey v2.1-...`
 * it is unset. Guard with `(_ScriptGetLines(...) ?? "") || []`.
 *
 * This comes from Lexikos's linecontext branch, which the fork has carried
 * since it was based on v2.1-alpha.18. It is not in upstream releases.
 * @param {String} Filename The full path of a loaded script file, such as
 * `A_LineFile`. Case-insensitive.
 * @param {Integer} LineNumber A 1-based line number.
 * @param {Integer} Range How many parsed lines to include before and after the
 * line. 0 or a negative number returns only that line.
 * @returns {Array|String|unset} The lines, or "" (v2.0 mode) or unset
 * (v2.1 mode) when LineNumber holds no code.
 * @example
 * lines := (_ScriptGetLines(A_LineFile, A_LineNumber, 2) ?? "") || []
 * for line in lines
 *     Print("{:03}: {}", line.Number, line.Text)
 * @since 2.1-alpha.18
 */
_ScriptGetLines(Filename, LineNumber, Range := 0) => Array? | String

;@endregion


;@region Classes

/**
 * A parse failure. `Eval` throws this class when its expression does not
 * parse. Scripts can also throw it, as with any Error class.
 *
 * An instance thrown by `Eval` has only the own properties `Message`, `File`
 * ("_Eval"), `Line` (0) and `Column` (0). It has no `What`, `Extra` or `Stack`.
 * An instance built with `SyntaxError(Message, What?, Extra?)` has the usual
 * Error properties and no `Column`.
 * @example
 * #EnableEval
 * try Eval("1 +* )")
 * catch SyntaxError as e
 *     Print("Eval parse error: {}", e.Message)
 * @since 2.1-alpha.29+Console
 */
class SyntaxError extends Error {
	/**
	 * The column of the parse error. `Eval` always sets 0, and an instance
	 * the script constructs does not have this property.
	 */
	Column: Integer
}

/**
 * Thrown by the `JSON` methods for invalid input, a rejected options argument,
 * excessive depth, a circular reference or a value JSON cannot represent. It
 * derives from ValueError, so `catch ValueError` also catches it.
 *
 * Errors from parsing, decoding, depth limits and serialization end `Message`
 * with a bracketed code such as `[UnexpectedChar]`, `[TrailingContent]`,
 * `[DepthExceeded]`, `[BadEncoding]` or `[CircularReference]`. A parse error
 * also carries its position, as in
 * `Expected a value but found ']' (line 1, col 4, pos 4) [UnexpectedChar]`.
 * The two errors about the options argument itself, a Map passed as options
 * or more than one options object, have no code.
 * @since 2.1-alpha.30+Console
 */
class JSONError extends ValueError {
}

/**
 * Native JSON parsing and serialization. No #Include is needed.
 *
 * With the default `Container`, JSON objects parse to `JSON.Object` (ordered,
 * case-sensitive string keys) and arrays to `JSON.Array`. By default `true`,
 * `false` and `null` reach the script as 1, 0 and "". These containers
 * remember which keyword each value came from and write it back when
 * serialized. The lowercase names used by other libraries also work
 * (`JSON.parse`, `JSON.stringify`), because member names are
 * case-insensitive.
 *
 * JSON is a namespace: create objects with Parse, not by calling `JSON()`.
 * The `static Call() => throw` below marks that, as in the bundled
 * declarations for classes such as File. As of 2.1-alpha.33+Console the
 * engine does not block the call. It returns an object that reports `Type`
 * "JSON.Object" and `is JSON` but is not a real JSON.Object. `Count` reads
 * garbage. `Keys` sometimes returns an empty Array, but `Keys` or `Set` can
 * also fail with "Invalid memory read/write." (exit 11) or corrupt the heap
 * and end the process with no diagnostic at all (exit code 0xC0000374,
 * STATUS_HEAP_CORRUPTION). The outcome varies from run to run.
 *
 * Parse options (Parse, Load, ParseAt, ParseFile and Validate) are passed as
 * an object literal. A Map, or a second options object, throws JSONError.
 * Option values are not validated: an unrecognized `Container`, `Booleans` or
 * `Null` value selects the default.
 * - `Container`: "JSON.Object" (default) or "Map". "Map" parses objects to
 *   a case-sensitive Map, whose keys enumerate in sorted order rather than
 *   document order, and arrays to a plain Array. Neither keeps true, false
 *   or null tags, so with the default `Booleans` and `Null` those values
 *   serialize back as 1, 0 and "".
 * - `Booleans`: "integer" (default, 1 and 0) or "native" (JSON.True and
 *   JSON.False).
 * - `Null`: "empty" (default, "") or "native" (JSON.Null).
 * - `MaxDepth`: the nesting limit. The default is 256, and values are
 *   clamped to the range 1 to 1000. The top-level value is at depth 0, and
 *   a value more than MaxDepth levels below it fails with `DepthExceeded`. So
 *   MaxDepth containers may enclose a scalar, and MaxDepth + 1 containers
 *   are accepted when the innermost one is empty: with the default, 256
 *   arrays around `1` and 257 empty nested arrays both parse.
 * - `AllowComments`, `AllowTrailingCommas`: off by default.
 * - `AllowTopLevelScalar`: on by default.
 * - `Encoding`: for Buffer input and ParseFile, the encoding when no BOM is
 *   present. The default is UTF-8.
 *
 * Stringify options: `MaxDepth`, `EnsureAscii` (writes non-ASCII as \uXXXX)
 * and `EscapeSlash` (writes / as \/). Stringify counts `MaxDepth`
 * differently from Parse: it allows at most MaxDepth nested containers,
 * whether or not the innermost one is empty (256 by default; 257 throw
 * `[DepthExceeded]`).
 * @example
 * cfg := JSON.Parse('{"name":"x","on":true}')
 * cfg["name"] := "y"
 * Print(JSON.Stringify(cfg))   ; {"name":"y","on":true}
 * @since 2.1-alpha.30+Console
 */
class JSON extends Object {
	/**
	 * Do not call `JSON()`. JSON is a namespace; see the class description.
	 */
	static Call() => throw

	/**
	 * The JSON `true` singleton, used for parsed values when the
	 * `Booleans` option is "native". Stringify writes it as `true`.
	 * This is a plain value property, so do not assign to it.
	 */
	static True => Object

	/**
	 * The JSON `false` singleton, used for parsed values when the
	 * `Booleans` option is "native". Stringify writes it as `false`.
	 * This is a plain value property, so do not assign to it.
	 */
	static False => Object

	/**
	 * The JSON `null` singleton, used for parsed values when the `Null`
	 * option is "native". Stringify writes it as `null`.
	 * This is a plain value property, so do not assign to it.
	 */
	static Null => Object

	/**
	 * Parses a complete JSON document. Content after the value is an error.
	 * @param {String|Buffer} Text JSON text, or a Buffer holding encoded
	 * bytes. A Buffer's encoding comes from its BOM or the `Encoding` option.
	 * @param Reviver Reserved and currently ignored. An options object passed
	 * here is read as Options.
	 * @param {Object} Options Parse options (see the JSON class).
	 * @returns {JSON.Object|JSON.Array|Map|Array|String|Integer|Float|Object}
	 * The parsed value. Containers are JSON.Object and JSON.Array, or Map and
	 * Array with `Container: "Map"`. A bare Object is one of the JSON.True,
	 * JSON.False and JSON.Null singletons, under the "native" `Booleans` or
	 * `Null` option.
	 * @throws {JSONError} The text is not valid JSON, or the options argument
	 * is rejected. With `AllowTopLevelScalar: false`, a scalar document is
	 * reported at line 1, col 1, pos 1 wherever the value starts.
	 */
	static Parse(Text, Reviver?, Options?) => JSON.Object | JSON.Array | Map | Array | String | Integer | Float | Object

	/**
	 * An alias of `JSON.Parse`.
	 * @param {String|Buffer} Text JSON text, or a Buffer holding encoded bytes.
	 * @param Reviver Reserved and currently ignored.
	 * @param {Object} Options Parse options (see the JSON class).
	 */
	static Load(Text, Reviver?, Options?) => JSON.Object | JSON.Array | Map | Array | String | Integer | Float | Object

	/**
	 * Parses the value that starts at Pos, then moves Pos past the value and
	 * any whitespace after it. Unlike Parse, it accepts trailing content,
	 * which makes it suitable for NDJSON, JSON Lines and concatenated JSON.
	 * When only whitespace remains, it returns no value (an empty string in
	 * v2.0 mode) and sets Pos past the end. Loop on the position, because a
	 * record's value can be 0 or "":
	 * `while (pos <= StrLen(text))`.
	 * @param {String} Text JSON text containing one or more values.
	 * @param {VarRef} Pos A variable holding the 1-based start position. It
	 * must be passed with &.
	 * @param {Object} Options Parse options (see the JSON class).
	 * @returns {JSON.Object|JSON.Array|Map|Array|String|Integer|Float|Object|unset}
	 * The parsed value (see Parse), or unset (an empty string in v2.0 mode)
	 * when only whitespace remains.
	 * @throws {JSONError} The value is not valid JSON. Pos then points at the
	 * error. A scalar rejected by `AllowTopLevelScalar: false` is reported at
	 * line 1, col 1, pos 1 instead, and Pos is left unchanged.
	 * @example
	 * pos := 1
	 * while (pos <= StrLen(text))
	 *     rec := JSON.ParseAt(text, &pos)
	 */
	static ParseAt(Text, &Pos, Options?) => JSON.Object? | JSON.Array | Map | Array | String | Integer | Float | Object

	/**
	 * Reads a file's raw bytes and parses them. The encoding comes from the
	 * BOM, then the `Encoding` option, then UTF-8. Invalid bytes raise a
	 * `[BadEncoding]` JSONError instead of becoming U+FFFD.
	 * @param {String} Path The file to read.
	 * @param {Object} Options Parse options (see the JSON class).
	 * @throws {OSError} The file cannot be opened or read.
	 */
	static ParseFile(Path, Options?) => JSON.Object | JSON.Array | Map | Array | String | Integer | Float | Object

	/**
	 * Reports whether text is valid JSON without building any values, and
	 * never throws for invalid input. Returns
	 * `{Valid, Pos, Line, Col, Code, Message}`. Valid is 1 or 0. On success,
	 * Pos, Line and Col are 0 and Code and Message are "". On failure, Code is
	 * the JSONError code without brackets, and Pos (1-based), Line and Col
	 * usually locate the error, with these exceptions:
	 * - They are 0 when the failure has no position, such as invalid bytes in
	 *   a Buffer (`BadEncoding`).
	 * - A scalar rejected by `AllowTopLevelScalar: false` is reported just
	 *   past the value and any whitespace after it, where Parse reports
	 *   line 1, col 1, pos 1.
	 * @param {String|Buffer} Text JSON text, or a Buffer holding encoded bytes.
	 * @param {Object} Options Parse options (see the JSON class).
	 */
	static Validate(Text, Options?) => Object

	/**
	 * Serializes a value to JSON text. Maps, Arrays, JSON containers and
	 * plain objects are written from their items or own value properties.
	 * Dynamic properties are skipped because reading one would run script
	 * code. Values tagged by Parse, and the JSON.True, JSON.False and
	 * JSON.Null singletons, are written as `true`, `false` and `null`.
	 * @param Value The value to serialize.
	 * @param Replacer Reserved and currently ignored. An options object passed
	 * here is read as Options.
	 * @param {Integer|String} Space An indent width (1 to 32 spaces) or a
	 * literal indent string. When omitted, the output is compact.
	 * @param {Object} Options Stringify options (see the JSON class).
	 * @throws {JSONError} A circular reference, excessive depth, a value JSON
	 * cannot represent, or a rejected options argument.
	 */
	static Stringify(Value, Replacer?, Space?, Options?) => String

	/**
	 * An alias of `JSON.Stringify`.
	 * @param Value The value to serialize.
	 * @param Replacer Reserved and currently ignored.
	 * @param {Integer|String} Space An indent width or a literal indent string.
	 * @param {Object} Options Stringify options (see the JSON class).
	 */
	static Dump(Value, Replacer?, Space?, Options?) => String

	/**
	 * The type of objects parsed from JSON (`Type(v)` = "JSON.Object"). It is
	 * Map-like, with case-sensitive string keys kept in document order.
	 * This is a type name only: `JSON.Object` is not a property at run time.
	 * Test values with `Type(v) = "JSON.Object"` or `v is JSON`.
	 * @since 2.1-alpha.30+Console
	 */
	class Object {
		/**
		 * Not callable: `JSON.Object()` throws MethodError at run time.
		 * Parse JSON text to get a JSON.Object.
		 */
		static Call() => throw

		/**
		 * Enumerates keys, or keys and values, in document order.
		 */
		__Enum(NumberOfVars?) => Enumerator

		/**
		 * Gets or sets the value for a key. Keys are case-sensitive strings,
		 * and other keys are converted to strings. Reading a missing key
		 * throws UnsetItemError.
		 */
		__Item[Key] {
			get => Any
			set => void
		}

		/**
		 * Removes all keys.
		 */
		Clear() => void

		/**
		 * Returns a shallow copy, which is also a JSON.Object.
		 */
		Clone() => JSON.Object

		/**
		 * Removes a key and returns its value. A missing key throws
		 * UnsetItemError.
		 */
		Delete(Key) => Any

		/**
		 * Returns the value for a key, or Default when the key is missing.
		 * Without Default, a missing key throws UnsetItemError.
		 */
		Get(Key, Default?) => Any

		/**
		 * Returns 1 if the key exists, otherwise 0.
		 */
		Has(Key) => Integer

		/**
		 * Sets the value for one key. A new key is appended at the end.
		 */
		Set(Key, Value) => void

		/**
		 * The number of keys.
		 */
		Count => Integer

		/**
		 * A new Array holding the keys in document order.
		 */
		Keys => Array

		/**
		 * A new Array holding the values in document order.
		 */
		Values => Array
	}

	/**
	 * The type of arrays parsed from JSON (`Type(v)` = "JSON.Array"). It
	 * derives from Array, so `v is Array` is true and every Array method
	 * works. Each element remembers whether it was `true`, `false` or `null`.
	 * Assigning or deleting an element clears its tag. Push, InsertAt,
	 * RemoveAt, Pop and Length changes keep the tags of the other elements,
	 * which move with them, and new slots are untagged.
	 * This is a type name only: `JSON.Array` is not a property at run time.
	 * @extends {#Array}
	 * @since 2.1-alpha.30+Console
	 */
	class Array {
		/**
		 * Not callable: `JSON.Array()` throws MethodError at run time.
		 * Parse JSON text to get a JSON.Array.
		 */
		static Call() => throw
	}
}

/**
 * A child process connected through UTF-8 stdin, stdout and stderr pipes,
 * without a console window. It runs in a job object, so `Kill()` or releasing
 * the last reference terminates the whole process tree.
 *
 * Every wait (ReadLine, Read with a timeout, Wait, and a pending Send) keeps
 * draining both output pipes and lets timers, hotkeys and GUI events run.
 * Timeouts are in seconds, and omitting one waits indefinitely, except that
 * Read() without a timeout does not wait. When a timeout expires, the call
 * throws TimeoutError.
 * @example
 * p := ProcessPipe(A_ComSpec, ["/c", "echo hello"])
 * Print(p.ReadLine(10))   ; hello
 * Print(p.Wait(10))       ; 0
 * @since 2.1-alpha.33+Console
 */
class ProcessPipe extends Object {
	/**
	 * Starts the process.
	 * @param {String} Command The program to run. When Args is omitted, it is
	 * the complete command line.
	 * @param {Array|String} Args An Array of arguments, each quoted for
	 * CommandLineToArgvW, or a string appended to Command unchanged.
	 * @param {String} WorkingDir The child's working directory.
	 * @throws {OSError} The process cannot be started.
	 * @throws {ValueError} Command is empty, or Args is an object other than
	 * an Array.
	 */
	__New(Command, Args?, WorkingDir?) => void

	/**
	 * Writes Text to the child's stdin as UTF-8.
	 * @param {Number} Timeout Seconds to wait for the write. If it expires,
	 * the child may have received part of the text.
	 */
	Send(Text, Timeout?) => void

	/**
	 * Writes Text plus a newline (`n) to the child's stdin.
	 * @param {Number} Timeout Seconds to wait for the write.
	 */
	SendLine(Text, Timeout?) => void

	/**
	 * Returns the next stdout line without its line ending. At end of output
	 * it returns "", so check AtEOF to tell that apart from an empty line.
	 * @param {Number} Timeout Seconds to wait for a complete line.
	 */
	ReadLine(Timeout?) => String

	/**
	 * Returns everything buffered on stdout. Without Timeout it returns at
	 * once, possibly with "". With Timeout it waits until data arrives or
	 * stdout reaches end of output, so after end of output it returns ""
	 * at once.
	 * @param {Number} Timeout Seconds to wait for data.
	 */
	Read(Timeout?) => String

	/**
	 * Returns everything buffered on stderr and clears the buffer.
	 */
	ReadStdErr() => String

	/**
	 * Waits for the process to exit and returns its exit code.
	 * @param {Number} Timeout Seconds to wait.
	 */
	Wait(Timeout?) => Integer

	/**
	 * Closes the child's stdin, so a child reading to end of input can finish.
	 */
	Close() => void

	/**
	 * Terminates the process and everything it started.
	 */
	Kill() => void

	/**
	 * The child's process ID.
	 */
	PID => Integer

	/**
	 * 1 while the process is running, otherwise 0.
	 */
	Running => Integer

	/**
	 * The exit code, or -1 while the process is still running.
	 */
	ExitCode => Integer

	/**
	 * 1 once stdout has closed and its buffer is empty, otherwise 0.
	 */
	AtEOF => Integer
}

;@endregion


;
; Not declarable here: the language server reads only functions, classes and
; variables from a .d.ahk file. The fork's directives (#EnableEval, #CrashLog)
; and command-line switches (/Eval, /CrashLog=, /StdErrFile=, /Coverage=,
; /Trace=json, /Diag=json, /Headless, /Check) are covered in updates.md.
; `AutoHotkey64Console.exe --help` lists the switches and commands (/Check as
; the `check` command); `--capabilities` lists only commands, features,
; diagnostic formats and exit codes.
;
