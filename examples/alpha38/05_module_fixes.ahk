; alpha.38: three module fixes
;
; Modules run at startup in reverse order of creation, so the body of a
; module written later runs first, and its first reference to an earlier
; module runs that module early. Alpha.38 fixes three cases:
;
;   v := imported            now runs the imported module first
;                            (was: "This global variable has not been
;                            assigned a value.")
;   a module run early from  runs with no function context
;   inside a function        (was: A_ThisFunc was the calling function)
;   #Import M {*} inside a   wins over a global wildcard import, whatever
;   function                 order the #Import lines are in
;                            (was: a later global #Import shadowed it)
;
; Run: bin\AutoHotkey64Console.exe examples\alpha38\05_module_fixes.ahk
#Requires AutoHotkey v2.1-alpha.38

; --- Config: a setting another module reads at load time ----------------------
#Module Config
global Level := "debug"

; --- Theme: read only from inside a function -----------------------------------
#Module Theme
Print("[Theme runs; A_ThisFunc = '" A_ThisFunc "']")
global Accent := "teal"

; --- Plain and Fancy: two formatters exporting the same name ------------------
#Module Plain
Banner(text) => "-- " text " --"

#Module Fancy
Banner(text) => "== " StrUpper(text) " =="

; --- Log: runs before Config, because it was created after it -----------------
#Module Log
#Import Config {Level}
#Import Theme {Accent}

; 1. A direct assignment from an imported variable. Config has not run yet,
;    so this line runs it first. Alpha.38 handles this form like any other
;    read; alpha.37 threw because the module had not run.
startLevel := Level
Print("Log: level captured at load = " startLevel)

; 2. Theme's first reference is inside a function, so Theme runs early from
;    there, but in its own context: the line it prints shows an empty
;    A_ThisFunc. Alpha.37 printed 'AccentName'.
AccentName() => Accent
Print("Log: accent = " AccentName())

; --- The main script --------------------------------------------------------
#Module __Main

; 3. Scoped wildcard imports. Report() imports Fancy for itself; the global
;    #Import of Plain comes later in the file. Inside Report, Fancy's Banner
;    wins; everywhere else Plain's does.
Report(title) {
    #Import Fancy {*}
    return Banner(title)
}
#Import Plain {*}

Print(Report("report"))
Print(Banner("everywhere else"))
