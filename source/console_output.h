#pragma once

#include <windows.h>
#include <tchar.h>

namespace ConsoleOutput
{
// Raw UTF-8 protocol output. Ordinary script output must use PrintWideLine
// so an attached debugger can frame or redirect it. Appends one newline.
void WriteProtocolLine(HANDLE aHandle, LPCTSTR aText, int aLength);
}
