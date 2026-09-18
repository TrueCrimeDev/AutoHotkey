# Explore the Console toolkit

Choose a capability by the job you want to do. Each guide explains its interface, an example, how it fits into ClautoHotkey, and the limits of the result.

<FeatureExplorer />

## Start with the process contract

Results belong on **stdout**. Diagnostics belong on **stderr**. The **exit code** tells the caller whether the process succeeded. These three channels make a script usable by a shell, a test runner, or an MCP client.

Newer features build on that foundation: inspection turns live values into structured data, ProcessPipe connects another process, and trace/coverage explain execution. Check [your build](/guide/compatibility) before using the development APIs.
