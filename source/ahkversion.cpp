
#include "stdafx.h"
#ifndef _MSC_VER
#include <windows.h>
#include <tchar.h>
#endif
#include "ahkversion.h"

LPSTR AHK_VERSION = RAW_AHK_VERSION;
LPTSTR T_AHK_VERSION = _T(RAW_AHK_VERSION);
LPTSTR T_AHK_NAME_VERSION = T_AHK_NAME _T(" v") _T(RAW_AHK_VERSION);
