
#include "stdafx.h"
#ifndef _MSC_VER
#include <windows.h>
#include <tchar.h>
#endif
#include "ahkversion.h"

LPSTR AHK_VERSION = RAW_AHK_VERSION;
LPTSTR T_AHK_VERSION = _T(RAW_AHK_VERSION);
LPTSTR T_AHK_NAME_VERSION = T_AHK_NAME _T(" v") _T(RAW_AHK_VERSION);

#ifndef AHK_BUILD_REVISION
#define AHK_BUILD_REVISION "unknown"
#endif
#define AHK_STRINGIFY_INNER(value) #value
#define AHK_STRINGIFY(value) AHK_STRINGIFY_INNER(value)

LPCTSTR T_AHK_BUILD_REVISION = _T(AHK_BUILD_REVISION);
#if defined(__clang__)
LPCTSTR T_AHK_BUILD_COMPILER = _T("Clang ") _T(__clang_version__);
#elif defined(_MSC_VER)
LPCTSTR T_AHK_BUILD_COMPILER = _T("MSVC ") _T(AHK_STRINGIFY(_MSC_FULL_VER));
#elif defined(__GNUC__)
LPCTSTR T_AHK_BUILD_COMPILER = _T("GCC ") _T(__VERSION__);
#else
LPCTSTR T_AHK_BUILD_COMPILER = _T("unknown");
#endif

#if defined(_M_ARM64) || defined(__aarch64__)
LPCTSTR T_AHK_BUILD_ARCH = _T("arm64");
#elif defined(_WIN64)
LPCTSTR T_AHK_BUILD_ARCH = _T("x64");
#else
LPCTSTR T_AHK_BUILD_ARCH = _T("x86");
#endif
