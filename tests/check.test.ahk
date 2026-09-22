; Check(Source): the engine's own parser as an oracle for "does this parse?".

Test.Case("Check accepts valid source", () => (
    Assert.Eq(Check('x := 1`nMsgBox(x)').Ok, 1)
))

Test.Case("Check reports a diagnostic with a line for invalid source", CheckReportsLine)
CheckReportsLine() {
    result := Check('x := 1`ny := (`n')
    Assert.Eq(result.Ok, 0, "Ok")
    Assert.True(result.Diagnostics.Length >= 1, "Diagnostics")
    Assert.Eq(result.Diagnostics[1].Severity, "error")
    Assert.True(result.Diagnostics[1].Line >= 1, "Line")
}
