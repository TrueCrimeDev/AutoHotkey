#Requires AutoHotkey v2.1-alpha.30
; test_jsonsuite.ahk -- nst/JSONTestSuite conformance for the native JSON parser.
;
; Corpus vendored at qa/fixtures/jsonsuite/ (MIT, (c) 2016 Nicolas Seriot; see
; the LICENSE beside it). Vendored rather than submoduled so the suite runs
; offline; upstream has been effectively frozen since 2017.
;
; Naming convention: y_ MUST parse, n_ MUST be rejected, i_ is implementation-
; defined and only pinned so a change is visible rather than silent.
;
; CAVEAT worth knowing before trusting a number here: fixtures are read with
; FileRead(..., "UTF-8"), so byte-level-invalid encoding is repaired to U+FFFD
; before the parser ever sees it. For the files listed in ENCODING_DEPENDENT the
; verdict is therefore partly the transcoder's, not the parser's -- they are
; still asserted (they currently give the right answer), but a future FileRead
; change upstream could flip them with no change to json.cpp. Rendering true
; verdicts on those needs the planned raw-bytes/Buffer parse path.
#Include ..\Assert.ahk

; i_ cases this build deliberately rejects. Everything else in i_ is accepted.
;   500-deep       -> our MaxDepth default of 256 (configurable, catchable)
;   utf16*_no_BOM  -> UTF-16 with no BOM, read as UTF-8; an encoding-layer verdict
global I_REJECTED := Map(
    "i_structure_500_nested_arrays.json", "MaxDepth 256",
    "i_string_utf16BE_no_BOM.json",       "encoding layer",
    "i_string_utf16LE_no_BOM.json",       "encoding layer")

; n_ cases whose raw bytes are invalid UTF-8; FileRead repairs them first.
global ENCODING_DEPENDENT := Map(
    "n_array_a_invalid_utf8.json", 1, "n_array_invalid_utf8.json", 1,
    "n_number_invalid-utf-8-in-bigger-int.json", 1, "n_number_invalid-utf-8-in-exponent.json", 1,
    "n_number_invalid-utf-8-in-int.json", 1, "n_number_real_with_invalid_utf8_after_e.json", 1,
    "n_object_lone_continuation_byte_in_key_and_trailing_comma.json", 1,
    "n_string_invalid-utf-8-in-escape.json", 1, "n_string_invalid_utf8_after_escape.json", 1,
    "n_structure_incomplete_UTF8_BOM.json", 1, "n_structure_lone-invalid-utf-8.json", 1,
    "n_structure_single_eacute.json", 1)

Parses(text) {
    try {
        JSON.Parse(text)
        return true
    } catch
        return false
}

counts := Map("y", 0, "n", 0, "i", 0), encDependent := 0
Loop Files, A_ScriptDir "\..\fixtures\jsonsuite\*.json" {
    name := A_LoopFileName
    ; FileRead on a zero-byte file returns no value on this alpha (see
    ; qa/run.ahk and the WORKLOG); n_structure_no_data.json is exactly that.
    text := ""
    try text := FileRead(A_LoopFileFullPath, "UTF-8")
    kind := SubStr(name, 1, 1)
    counts[kind] := counts.Get(kind, 0) + 1
    ok := Parses(text)

    if (kind = "y")
        Assert.truthy(ok, "jsonsuite.must-parse." name)
    else if (kind = "n") {
        Assert.falsy(ok, "jsonsuite.must-reject." name)
        if ENCODING_DEPENDENT.Has(name)
            encDependent++
    } else
        Assert.eq(ok ? 0 : 1, I_REJECTED.Has(name) ? 1 : 0, "jsonsuite.pinned." name)
}

; Guard the corpus itself: a partial checkout would silently shrink coverage.
Assert.eq(counts["y"], 95, "jsonsuite.corpus.y_count")
Assert.eq(counts["n"], 188, "jsonsuite.corpus.n_count")
Assert.eq(counts["i"], 35, "jsonsuite.corpus.i_count")
Assert.eq(encDependent, 12, "jsonsuite.corpus.encoding_dependent_count")

Assert.Summary()
