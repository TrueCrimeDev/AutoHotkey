# Upstream report: `Script::GetSearchPath` drops every entry after a missing directory (v2.1-alpha.35)

**Affects:** upstream `v2.1-alpha.35` (`3a1291c6`, "Revised search logic for
#Include <MyLib> and #Import"), `source/script_module.cpp`, `Script::GetSearchPath`.
**Found:** 2026-10-12 while merging alpha.35 into this fork.
**Status:** fixed in this fork on branch `m1/upstream-alpha35`; not yet reported upstream.

## Symptom

With `AhkLibPath` set to a directory that holds `A.ahk`, a script that is not
next to a `Lib` folder fails:

```text
C:\Users\me\AppData\Local\Temp\s.ahk (0) : ==> Script library not found.
     Specifically: #Include <A>
```

The same script works when it sits in a directory that has a `Lib` subfolder,
even an empty one. Without `AhkLibPath` the default list has the same problem:
once `Lib` (the first entry) does not exist, the user library and the standard
library are never searched either.

## Cause

`GetSearchPath` builds the list in one buffer and dedupes consecutive entries
with a `last_dir` pointer:

```cpp
		if (last_dir && !_tcsicmp(last_dir, cp))
			continue;
		last_dir = cp;
		// Ignore nonexistent directories so each Import won't do unnecessary checks.
		DWORD attr = GetFileAttributes(cp);
		if (attr == INVALID_FILE_ATTRIBUTES || !(attr & FILE_ATTRIBUTE_DIRECTORY))
			continue; // Ignore this item.
		cp += len + 1;
```

`last_dir = cp` runs before the existence check. When the entry is discarded,
`cp` does not advance, so the next entry is written over the same bytes that
`last_dir` points at. The comparison then tests the string against itself,
succeeds, and the entry is skipped. Every later entry meets the same fate.

## Fix

Assign `last_dir` only for an entry that is kept:

```cpp
		if (last_dir && !_tcsicmp(last_dir, cp))
			continue;
		DWORD attr = GetFileAttributes(cp);
		if (attr == INVALID_FILE_ATTRIBUTES || !(attr & FILE_ATTRIBUTE_DIRECTORY))
			continue; // Ignore this item.
		last_dir = cp;
		cp += len + 1;
```

## Reproduction

```text
mkdir %TEMP%\libx
echo global Loaded := "A.ahk" > %TEMP%\libx\A.ahk
echo #Requires AutoHotkey v2.1-alpha.35 > %TEMP%\s.ahk
echo #Include ^<A^> >> %TEMP%\s.ahk
echo MsgBox(Loaded) >> %TEMP%\s.ahk
set AhkLibPath=%TEMP%\libx
AutoHotkey64.exe %TEMP%\s.ahk      (fails; create %TEMP%\Lib and it works)
```

Pinned in this fork by `qa/tests/test_alpha35.ahk` section 6, whose child
snippet runs from `%TEMP%`.
