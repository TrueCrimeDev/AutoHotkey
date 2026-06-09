#!/bin/sh
# Test wrapper: behaves like AutoHotkey64.exe /Debug=stdio <script> but runs the
# Node fake. Drops the /Debug=stdio flag and ignores the script argument.
exec node "$(dirname "$0")/fake-ahk.js"
