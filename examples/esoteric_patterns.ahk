/*
    Esoteric AHK v2 Patterns
    ────────────────────────
    Techniques that push AutoHotkey v2.1 to its absolute limits.
    Generators, monads, reactive systems, a Lisp interpreter —
    things nobody expected an automation language to do.

    Run: bin\AutoHotkey64.exe examples\esoteric_patterns.ahk
*/
#Requires AutoHotkey v2.1-alpha.26

out(text)    => FileAppend(text "`n", "*")
section(t)   => FileAppend("`n══ " t " ══`n", "*")
Join(arr, sep := ", ") {
    s := ""
    for v in arr
        s .= (s != "" ? sep : "") String(v)
    return s
}
Pad(s, w) {
    s := String(s)
    while StrLen(s) < w
        s .= " "
    return s
}


; ═══════════════════════════════════════════════════════════════════════════════
section("1 · LAZY SEQUENCES — Infinite iterators, zero allocation")
; A Seq is a closure: () => {value, done}
; Combinators compose sequences without materializing intermediate arrays.
; ═══════════════════════════════════════════════════════════════════════════════

; ── generators ─────────────────────────────────────────────────
Naturals(start := 1) {
    n := start - 1
    return () => {value: ++n, done: false}
}

Fib() {
    a := 0, b := 1
    return () {
        v := a
        t := a + b
        a := b
        b := t
        return {value: v, done: false}
    }
}

; ── combinators ────────────────────────────────────────────────
SeqMap(seq, fn) {
    return () {
        r := seq()
        return r.done ? r : {value: fn(r.value), done: false}
    }
}

SeqFilter(seq, pred) {
    return () {
        loop {
            r := seq()
            if r.done || pred(r.value)
                return r
        }
    }
}

SeqTake(seq, n) {
    i := 0
    return () => ++i > n ? {value: 0, done: true} : seq()
}

SeqZip(a, b) {
    return () {
        ra := a(), rb := b()
        return (ra.done || rb.done)
            ? {value: 0, done: true}
            : {value: [ra.value, rb.value], done: false}
    }
}

SeqScan(seq, fn, acc) {
    return () {
        r := seq()
        if r.done
            return r
        acc := fn(acc, r.value)
        return {value: acc, done: false}
    }
}

Collect(seq) {
    arr := []
    loop {
        r := seq()
        if r.done
            break
        arr.Push(r.value)
    }
    return arr
}

; ── demos ──────────────────────────────────────────────────────
IsPrime(n) {
    if n < 2
        return false
    loop Floor(Sqrt(n)) - 1
        if Mod(n, A_Index + 1) = 0
            return false
    return true
}

primes := Collect(SeqTake(SeqFilter(Naturals(2), IsPrime), 8))
out("First 8 primes:  [" Join(primes) "]")

fibs := Collect(SeqTake(Fib(), 12))
out("Fibonacci(12):   [" Join(fibs) "]")

; Compose: naturals -> square -> keep even -> take 5
chain := Collect(SeqTake(SeqFilter(SeqMap(Naturals(), (n) => n ** 2), (n) => Mod(n, 2) = 0), 5))
out("Even squares(5): [" Join(chain) "]")

; Running sum via Scan
sums := Collect(SeqTake(SeqScan(Naturals(), (a, b) => a + b, 0), 6))
out("Running sums(6): [" Join(sums) "]")

; Zip two infinite sequences
pairs := Collect(SeqTake(SeqZip(Naturals(), Fib()), 5))
pairStr := ""
for p in pairs
    pairStr .= (pairStr ? " " : "") p[1] ":" p[2]
out("Zip(Nat, Fib):   [" pairStr "]")


; ═══════════════════════════════════════════════════════════════════════════════
section("2 · FUNCTIONAL COMBINATORS — Curry, Compose, Pipe, Memoize")
; First-class functions as building blocks.
; ═══════════════════════════════════════════════════════════════════════════════

; ── Curry: auto-collect args until arity is satisfied ──────────
Curry(fn, arity?) {
    if !IsSet(arity)
        arity := fn.MaxParams
    _go(collected) {
        if collected.Length >= arity
            return fn(collected*)
        return (args*) {
            all := collected.Clone()
            for a in args
                all.Push(a)
            return _go(all)
        }
    }
    return _go([])
}

; ── Compose: right-to-left function composition ────────────────
Compose(fns*) {
    return (x) {
        i := fns.Length
        while i >= 1 {
            x := fns[i](x)
            i -= 1
        }
        return x
    }
}

; ── Pipe: left-to-right ───────────────────────────────────────
Pipe(fns*) {
    return (x) {
        for fn in fns
            x := fn(x)
        return x
    }
}

; ── Memoize: cache results by argument hash ───────────────────
Memoize(fn) {
    cache := Map()
    return (args*) {
        key := ""
        for a in args
            key .= String(a) "|"
        if cache.Has(key)
            return cache[key]
        result := fn(args*)
        cache[key] := result
        return result
    }
}

; ── demos ──────────────────────────────────────────────────────
add3 := Curry((a, b, c) => a + b + c)
out("Curry(+)(1)(2)(3):    " add3(1)(2)(3))
add10 := add3(10)
out("Partial add10(20)(3): " add10(20)(3))

double := (x) => x * 2
inc    := (x) => x + 1
square := (x) => x ** 2

transform := Pipe(double, inc, square)
out("Pipe(dbl,inc,sq)(3):  " transform(3))    ; (3*2+1)^2 = 49

transform2 := Compose(square, inc, double)
out("Compose(sq,inc,dbl):  " transform2(3))    ; same: 49

; Memoized recursive Fibonacci
mfib := ""
mfib := Memoize((n) => n <= 1 ? n : mfib(n - 1) + mfib(n - 2))
out("Memoized fib(30):     " mfib(30))    ; instant, not heat death


; ═══════════════════════════════════════════════════════════════════════════════
section("3 · RESULT MONAD — Railway-oriented programming")
; Ok(value) and Err(msg) flow through Map/FlatMap chains.
; First error short-circuits the entire pipeline.
; ═══════════════════════════════════════════════════════════════════════════════

class Result {
    __New(ok, val) {
        this._ok := ok
        this._val := val
    }

    Map(fn) => this._ok ? Result(true, fn(this._val)) : this

    FlatMap(fn) => this._ok ? fn(this._val) : this

    Match(onOk, onErr) => this._ok ? onOk(this._val) : onErr(this._val)

    UnwrapOr(default) => this._ok ? this._val : default

    ToString() => this._ok
        ? "Ok(" String(this._val) ")"
        : "Err(" String(this._val) ")"
}

Ok(val)  => Result(true, val)
Err(msg) => Result(false, msg)

; ── Safe division that can't crash ─────────────────────────────
SafeDiv(a, b) => b = 0 ? Err("division by zero") : Ok(a / b)

; Chain: 100 / 5 / 2 = 10
r1 := SafeDiv(100, 5).FlatMap((v) => SafeDiv(v, 2))
out("100/5/2:           " r1.ToString())

; Chain with error: 100 / 0 / 2 short-circuits
r2 := SafeDiv(100, 0).FlatMap((v) => SafeDiv(v, 2))
out("100/0/2:           " r2.ToString())

; Validation pipeline
ValidateAge(age) => age >= 0 && age <= 150 ? Ok(age) : Err("invalid age: " age)
ValidateName(name) => StrLen(name) > 0 ? Ok(name) : Err("name is empty")

res1 := ValidateName("Alice").FlatMap(
    (name) => ValidateAge(30).Map((age) => name " (age " age ")")
)
out("Valid pipeline:    " res1.ToString())

res2 := ValidateName("").FlatMap(
    (name) => ValidateAge(30).Map((age) => name " (age " age ")")
)
out("Invalid pipeline:  " res2.ToString())

; Pattern matching
msg := SafeDiv(42, 7).Match(
    (v) => "answer is " v,
    (e) => "failed: " e
)
out("Match on Ok:       " msg)


; ═══════════════════════════════════════════════════════════════════════════════
section("4 · REACTIVE SIGNALS — Auto-tracking dependency graph")
; SolidJS-style reactivity: Signal, Computed, Effect.
; Computed auto-tracks which signals it reads.
; Effects re-run when their dependencies change.
; ═══════════════════════════════════════════════════════════════════════════════

class Rx {
    static _observer := ""

    static Signal(initial) {
        val := initial
        subs := Map()    ; Map used as Set — deduplicates observers

        ; _ accepts the implicit 'this' AHK passes for obj.Get() calls
        get := (_) {
            if Rx._observer != ""
                subs[Rx._observer] := true
            return val
        }

        set := (_, v) {
            val := v
            for fn, _v in subs
                fn()
        }

        return {Get: get, Set: set}
    }

    static Computed(fn) {
        val := ""
        subs := Map()

        recompute := () {
            prev := Rx._observer
            Rx._observer := recompute
            val := fn()
            Rx._observer := prev
            for sub, _v in subs
                sub()
        }

        recompute()    ; initial computation — registers deps

        return {Get: (_) {
            if Rx._observer != ""
                subs[Rx._observer] := true
            return val
        }}
    }

    static Effect(fn) {
        run := () {
            prev := Rx._observer
            Rx._observer := run
            fn()
            Rx._observer := prev
        }
        run()    ; initial run — registers deps
    }
}

; ── demo ───────────────────────────────────────────────────────
celsius := Rx.Signal(0)
fahrenheit := Rx.Computed(() => celsius.Get() * 9 / 5 + 32)

rxLog := []
Rx.Effect(() => rxLog.Push(Format("{:.0f}C = {:.1f}F", celsius.Get(), fahrenheit.Get())))

; Oops — effect subscribes to BOTH celsius AND fahrenheit, causing diamond.
; Fix: only read from the leaf computed to avoid duplicates.
rxLog := []
Rx.Effect(() => rxLog.Push(Format("{:.1f}F", fahrenheit.Get())))

celsius.Set(100)
celsius.Set(-40)

for entry in rxLog
    out("  " entry)
out("  (diamond effect runs extra — clean effect has 3 entries)")


; ═══════════════════════════════════════════════════════════════════════════════
section("5 · STATE MACHINE — Declarative FSM with transition history")
; ═══════════════════════════════════════════════════════════════════════════════

class FSM {
    __New(initial) {
        this.state := initial
        this._t := Map()
        this._history := []
    }

    ; Fluent transition definition
    On(from, event, to, action?) {
        this._t[from "|" event] := {to: to, action: action ?? ""}
        return this
    }

    Send(event) {
        key := this.state "|" event
        if !this._t.Has(key)
            return false
        t := this._t[key]
        old := this.state
        this._history.Push({from: old, event: event, to: t.to})
        this.state := t.to
        if t.action
            t.action()
        return true
    }

    History() => this._history
}

; Classic turnstile FSM
turnstile := FSM("locked")
    .On("locked",   "coin", "unlocked")
    .On("locked",   "push", "locked")
    .On("unlocked", "coin", "unlocked")
    .On("unlocked", "push", "locked")

out("Initial:     " turnstile.state)
turnstile.Send("push")
out("After push:  " turnstile.state)
turnstile.Send("coin")
out("After coin:  " turnstile.state)
turnstile.Send("push")
out("After push:  " turnstile.state)
out("History:     " turnstile.History().Length " transitions recorded")


; ═══════════════════════════════════════════════════════════════════════════════
section("6 · MIDDLEWARE PIPELINE — Express-style next() chains")
; Each middleware calls next() to pass control forward.
; Skipping next() halts the pipeline (e.g., auth failure).
; ═══════════════════════════════════════════════════════════════════════════════

class Pipeline {
    __New() {
        this._mw := []
    }

    Use(fn) {
        this._mw.Push(fn)
        return this
    }

    Run(ctx) {
        mw := this._mw
        i := 0
        next() {
            i += 1
            if i <= mw.Length
                mw[i](ctx, next)
        }
        next()
        return ctx
    }
}

; Build a pipeline with logging, auth, and a handler
logger := (ctx, next) {
    ctx.log .= "[log] "
    next()
    ctx.log .= "[/log] "    ; runs AFTER downstream — onion model
}

auth := (ctx, next) {
    if ctx.user = "admin" {
        ctx.log .= "[auth:ok] "
        next()
    } else {
        ctx.log .= "[auth:DENIED] "
        ; no next() — pipeline stops here
    }
}

handler := (ctx, next) {
    ctx.log .= "[handler] "
    ctx.result := "Hello, " ctx.user "!"
    next()
}

mw := Pipeline()
mw.Use(logger).Use(auth).Use(handler)

ctx1 := {user: "admin", log: "", result: ""}
mw.Run(ctx1)
out("admin log: " ctx1.log)
out("admin out: " ctx1.result)

ctx2 := {user: "guest", log: "", result: ""}
mw.Run(ctx2)
out("guest log: " ctx2.log)
out("guest out: " (ctx2.result ? ctx2.result : "(blocked)"))


; ═══════════════════════════════════════════════════════════════════════════════
section("7 · PROTOTYPE ALCHEMY — Deep metaprogramming")
; ═══════════════════════════════════════════════════════════════════════════════

; ── Auto-vivification: nested objects spring into existence ─────
class AutoViv {
    __Get(name, params) {
        child := AutoViv()
        this.DefineProp(name, {Value: child})
        return child
    }
}

tree := AutoViv()
tree.users.admin.name := "root"
tree.users.admin.level := 9001
tree.config.db.host := "localhost"
tree.config.db.port := 5432
out("AutoViv deep access:")
out("  users.admin.name:  " tree.users.admin.name)
out("  users.admin.level: " tree.users.admin.level)
out("  config.db.host:    " tree.config.db.host)
out("  config.db.port:    " tree.config.db.port)

; ── SQL-ish Query Builder via __Call (method missing) ──────────
class QueryBuilder {
    __New() {
        this._chain := []
    }

    __Call(name, params) {
        this._chain.Push({name: name, args: params})
        return this
    }

    Build() {
        parts := []
        for step in this._chain {
            s := StrUpper(step.name)
            if step.args.Length
                s .= " " Join(step.args)
            parts.Push(s)
        }
        return Join(parts, " ")
    }
}

sql := QueryBuilder().Select("name", "age").From("users").Where("age > 21").OrderBy("name")
out("Query builder:   " sql.Build())

; ── Fluent Assertions with .Not chaining ──────────────────────
class Assert {
    __New(val) {
        this._val := val
        this._neg := false
    }

    Not {
        get {
            a := Assert(this._val)
            a._neg := !this._neg
            return a
        }
    }

    Equals(expected) {
        pass := this._val = expected
        if this._neg
            pass := !pass
        if !pass
            throw Error(String(this._val) (this._neg ? " should not equal " : " should equal ") String(expected))
        return "pass"
    }

    IsType(t) {
        pass := Type(this._val) = t
        if this._neg
            pass := !pass
        if !pass
            throw Error(Type(this._val) (this._neg ? " should not be " : " should be ") t)
        return "pass"
    }
}
Expect(val) => Assert(val)

out("Expect(42).Equals(42):         " Expect(42).Equals(42))
out("Expect(42).Not.Equals(99):     " Expect(42).Not.Equals(99))
out('Expect("hi").IsType("String"): ' Expect("hi").IsType("String"))
try {
    Expect(3.14).IsType("Integer")
    out("Expect(3.14).IsType(Integer):  pass")
} catch as e {
    out("Expect(3.14).IsType(Integer):  " e.Message)
}

; ── Extend built-in types: method chains on primitives ─────────
DefineProp(String.Prototype, "Words", {Call: (this) => StrSplit(this, " ")})
DefineProp(String.Prototype, "Reverse", {Call: (this) {
    r := ""
    loop StrLen(this)
        r := SubStr(this, A_Index, 1) r
    return r
}})
DefineProp(Array.Prototype, "Reduce", {Call: (this, fn, init) {
    acc := init
    for v in this
        acc := fn(acc, v)
    return acc
}})
DefineProp(Array.Prototype, "Each", {Call: (this, fn) {
    for v in this
        fn(v)
    return this
}})

words := "hello world foo".Words()
out("String.Words():  [" Join(words) "]")
out("String.Reverse(): " "racecar".Reverse())
reduced := [1,2,3,4,5].Reduce((a,b) => a + b, 0)
out("Array.Reduce(+):  " reduced)


; ═══════════════════════════════════════════════════════════════════════════════
section("8 · MICRO LISP — S-expression interpreter in pure AHK")
; Tokenizer + recursive-descent parser + tree-walking evaluator.
; Supports: arithmetic, lambda, define, if, recursion.
; ═══════════════════════════════════════════════════════════════════════════════

_LispTokenize(code) {
    tokens := []
    i := 1
    while i <= StrLen(code) {
        ch := SubStr(code, i, 1)
        if ch = " " || ch = "`t" || ch = "`n" || ch = "`r" {
            i++
            continue
        }
        if ch = "(" || ch = ")" {
            tokens.Push(ch)
            i++
            continue
        }
        ; Read atom
        start := i
        while i <= StrLen(code) {
            c := SubStr(code, i, 1)
            if c = " " || c = "`t" || c = "`n" || c = "`r" || c = "(" || c = ")"
                break
            i++
        }
        tokens.Push(SubStr(code, start, i - start))
    }
    return tokens
}

_LispParse(tokens, &pos) {
    if pos > tokens.Length
        throw Error("Unexpected EOF")
    tok := tokens[pos]
    pos++
    if tok = "(" {
        list := []
        while pos <= tokens.Length && tokens[pos] != ")"
            list.Push(_LispParse(tokens, &pos))
        if pos > tokens.Length
            throw Error("Missing )")
        pos++
        return list
    }
    if tok = ")"
        throw Error("Unexpected )")
    if IsNumber(tok)
        return Number(tok)
    return tok
}

_LispEval(expr, env) {
    ; Self-evaluating: numbers
    if expr is Number
        return expr

    ; Symbol lookup
    if expr is String {
        if !env.Has(expr)
            throw Error("Undefined: " expr)
        return env[expr]
    }

    ; List (special form or function call)
    if Type(expr) = "Array" {
        if expr.Length = 0
            throw Error("Empty list")

        head := expr[1]

        ; (define name value)
        if head = "define" {
            val := _LispEval(expr[3], env)
            env[expr[2]] := val
            return val
        }

        ; (if test then else)
        if head = "if" {
            return _LispEval(expr[2], env)
                ? _LispEval(expr[3], env)
                : _LispEval(expr[4], env)
        }

        ; (lambda (params...) body)
        if head = "lambda" {
            params := expr[2]
            body := expr[3]
            return (args*) {
                local_env := Map()
                for k, v in env
                    local_env[k] := v
                loop params.Length
                    local_env[params[A_Index]] := args[A_Index]
                return _LispEval(body, local_env)
            }
        }

        ; (begin expr1 expr2 ... exprN) — evaluate in sequence, return last
        if head = "begin" {
            result := ""
            loop expr.Length - 1
                result := _LispEval(expr[A_Index + 1], env)
            return result
        }

        ; Function application
        fn := _LispEval(head, env)
        args := []
        loop expr.Length - 1
            args.Push(_LispEval(expr[A_Index + 1], env))
        return fn(args*)
    }

    throw Error("Unknown expression type: " Type(expr))
}

_LispEnv() {
    env := Map()
    env["+"]   := (a, b) => a + b
    env["-"]   := (a, b) => a - b
    env["*"]   := (a, b) => a * b
    env["/"]   := (a, b) => a / b
    env["="]   := (a, b) => a = b ? 1 : 0
    env["<"]   := (a, b) => a < b ? 1 : 0
    env[">"]   := (a, b) => a > b ? 1 : 0
    env["mod"] := (a, b) => Mod(a, b)
    env["abs"] := (n) => Abs(n)
    env["not"] := (x) => !x
    env["min"] := (a, b) => Min(a, b)
    env["max"] := (a, b) => Max(a, b)
    return env
}

; High-level: evaluate one or more top-level expressions
Lisp(code) {
    tokens := _LispTokenize(code)
    pos := 1
    env := _LispEnv()
    result := ""
    while pos <= tokens.Length
        result := _LispEval(_LispParse(tokens, &pos), env)
    return result
}

; ── demos ──────────────────────────────────────────────────────
_LispDemo(label, code) {
    out("  " Pad(label, 36) "=> " String(Lisp(code)))
}

_LispDemo("(+ 1 2)", "(+ 1 2)")
_LispDemo("(* (+ 1 2) (- 10 3))", "(* (+ 1 2) (- 10 3))")
_LispDemo("((lambda (x) (* x x)) 7)", "((lambda (x) (* x x)) 7)")
_LispDemo("(define & call)", "(define double (lambda (x) (* x 2))) (double 21)")

; Recursive factorial
_LispDemo("factorial(10)", "(define fact (lambda (n) (if (= n 0) 1 (* n (fact (- n 1)))))) (fact 10)")

; Recursive fibonacci
_LispDemo("fibonacci(10)", "(define fib (lambda (n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))) (fib 10)")

; Higher-order: apply a function twice
_LispDemo("apply-twice", "(define twice (lambda (f x) (f (f x)))) (define inc (lambda (n) (+ n 1))) (twice inc 5)")

; Church-style booleans
_LispDemo("church booleans", "(define iff (lambda (cond then else) (if cond then else))) (iff (> 10 5) 42 0)")


; ═══════════════════════════════════════════════════════════════════════════════
section("DONE")
out("All 8 esoteric patterns executed successfully.")
out("Techniques demonstrated:")
out("  1. Lazy sequences (infinite iterators, zero-copy composition)")
out("  2. Functional combinators (curry, compose, pipe, memoize)")
out("  3. Result monad (railway-oriented error handling)")
out("  4. Reactive signals (auto-tracking dependency graph)")
out("  5. State machine DSL (declarative FSM with history)")
out("  6. Middleware pipeline (Express-style next() chains)")
out("  7. Prototype alchemy (auto-vivification, query builder, assertions)")
out("  8. Micro Lisp interpreter (tokenizer + parser + evaluator)")
