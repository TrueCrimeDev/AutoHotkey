; Self-checks for tests/Test.ahk: assertions must fail loudly and point at the caller.

Test.Case("Assert.Eq compares strings case-sensitively", () => (
    Assert.Eq("abc", "abc"),
    Assert.Throws(() => Assert.Eq("abc", "ABC"), AssertionError, 'expected "ABC" but got "abc"')
))

Test.Case("Assert.Eq compares numbers by value", () => (
    Assert.Eq(1, 1.0),
    Assert.Eq(0x10, 16)
))

Test.Case("Assert.Eq compares objects by identity", AssertEqObjects)
AssertEqObjects() {
    obj := {}
    Assert.Eq(obj, obj)
    Assert.Throws(() => Assert.Eq({}, {}), AssertionError)
}

Test.Case("assertion failures report the test's own line", AssertionPointsAtCaller)
AssertionPointsAtCaller() {
    err := Assert.Throws(() => Assert.True(false, "flag"), AssertionError, "flag: expected truthy")
    Assert.Eq(err.File, A_LineFile, "File")
    Assert.True(err.Line > 0, "Line")
}

Test.Case("Assert.Throws narrows by type and message", () => (
    Assert.Throws(() => Integer("x"), TypeError),
    Assert.Throws(() => Assert.Throws(() => Integer("x"), ValueError), AssertionError, "expected ValueError"),
    Assert.Throws(() => Assert.Throws(() => 1), AssertionError, "none was thrown")
))

Test.Case("Assert.Contains and Assert.Matches", () => (
    Assert.Contains("hello world", "lo w"),
    Assert.Matches("v2.1-alpha.31", "^v\d+\.\d+-alpha\.\d+$"),
    Assert.Throws(() => Assert.Matches("abc", "^\d+$"), AssertionError, "to match")
))

Test.Case("Assert.Is checks the class", () => (
    Assert.Is([], Array),
    Assert.Is(Map(), Map),
    Assert.Throws(() => Assert.Is("s", Array), AssertionError, "expected Array but got String")
))
