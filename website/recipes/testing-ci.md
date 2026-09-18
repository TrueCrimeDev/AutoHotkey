# Tests & Windows CI

An AHK assertion can be as small as a condition that throws on failure. The `test` command turns a failure into a test-specific exit code.

## Start with a standalone test

```ahk
#Requires AutoHotkey v2.1-alpha.31
data := JSON.Parse('{"count":21}')
if data["count"] * 2 != 42
    throw Error("Expected doubled count to equal 42")
Print("PASS: JSON count")
```

```powershell
ahk check .\tests.ahk
ahk /Headless /Diag=json test .\tests.ahk 1>tests.stdout.txt 2>tests.stderr.jsonl
$LASTEXITCODE
```

A successful test exits `0`; test failure exits `14`. A script can still choose other explicit exit codes, so inspect the actual result.

## Add coverage when available

```powershell
ahk /Headless /Coverage=coverage.lcov /Diag=json test .\tests.ahk
```

Coverage does not prove correctness, but it helps locate untested behavior. Add explicit failing-input and error-recovery cases, not just more happy-path hits.

## CI pattern with a verified engine

This example assumes your repository supplies a pinned, verified compatible executable at `tools/AutoHotkey64Console.exe`. It does not download an unpublished release.

```yaml
name: AHK tests
on: [push, pull_request]
jobs:
  test:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Identify and test
        shell: pwsh
        run: |
          & tools/AutoHotkey64Console.exe --version
          & tools/AutoHotkey64Console.exe /Headless /Diag=json test tests.ahk 1>tests.stdout.txt 2>tests.stderr.jsonl
          exit $LASTEXITCODE
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: ahk-test-output
          path: |
            tests.stdout.txt
            tests.stderr.jsonl
```

For source builds, use the engine repository's [build instructions](https://github.com/TrueCrimeDev/AutoHotkey/blob/alpha/BUILD.md) and [workflow](https://github.com/TrueCrimeDev/AutoHotkey/blob/alpha/.github/workflows/build.yml). A Windows runner does not by itself prove reliable interactive desktop behavior. Keep unattended test fixtures bounded and free of unexpected prompts.
