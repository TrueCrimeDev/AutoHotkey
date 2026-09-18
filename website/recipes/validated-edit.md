# A validated Claude edit

This recipe uses a disposable demo folder and avoids GUI or external-application effects.

## Configure the workspace

Follow [plugin setup](/clautohotkey/setup). Put the exact engine path in `harness.env`, enable JSON diagnostics for the fork, and ensure Bash can find `jq`.

## Give Claude a concrete outcome

```text
Create Demo/double.test.ahk using Write so the ClautoHotkey hooks run.
Add a Double(value) function and assert that Double(21) equals 42.
Use the configured Console engine to check and test the file.
Report hook output, stdout, stderr, and exit codes.
Only work in this disposable demo directory.
```

## What an assertion can look like

```ahk
#Requires AutoHotkey v2.1-alpha.31
Double(value) => value * 2
if Double(21) != 42
    throw Error("Double(21) must equal 42")
Print("PASS: Double(21) = 42")
```

## Observe the boundaries

The post-edit hook should show that it actually checked this path. Then run `check` and `test` deliberately. A hook's short runtime probe and a full assertion test serve different purposes.

For a controlled negative test, change the expected value in the assertion and rerun. Observe failure, restore the expectation, and rerun successfully. Preserve the actual evidence instead of announcing success from code inspection.

The [gallery](/showcase) shows a real edit and hook invocation from this workflow. [Download the test](/examples/double.test.ahk).
