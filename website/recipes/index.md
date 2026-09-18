# Build something small and observable

Each recipe connects an AHK behavior to a result you can verify. Run examples with a compatible local Windows engine; this static site does not execute them.

| Recipe | You will build | You will verify |
| --- | --- | --- |
| [JSON command-line tool](/recipes/json-cli) | Parse a JSON argument and return JSON | Structured stdout and invalid-input behavior |
| [Validated Claude edit](/recipes/validated-edit) | A harmless script changed through the plugin | Actual hook output and an assertion |
| [Tests & Windows CI](/recipes/testing-ci) | An assertion script and repeatable CI job | Process exit and saved diagnostics |
| [Process worker](/recipes/process-worker) | An AHK parent that reads a child | Pipe output, child exit, stderr |

For a broader combined example, download the [six-feature fixture](/showcase). Check [build compatibility](/guide/compatibility) before choosing recipes that use preview APIs.
