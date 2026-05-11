
#define AHK_NAME "AutoHotkey"
#define T_AHK_NAME _T(AHK_NAME)

#ifndef RAW_AHK_VERSION
	// Fallback version string for when `git describe` fails during build.
	// Custom build with /ErrorStdOut runtime error support
	// Use + instead of - so version comparison treats this as >= base version
	// (- marks pre-release which sorts lower, + marks metadata which is ignored)
	#define RAW_AHK_VERSION "2.1-alpha.28+Console"
#endif
#ifdef RC_INVOKED
	#define AHK_VERSION RAW_AHK_VERSION
	#ifndef AHK_VERSION_N
	#define AHK_VERSION_N 2,0,0,0
	#endif
#else
	// Use global variables rather than macros so only ahkversion.cpp needs to be recompiled
	// whenever GITDESC changes.
	extern LPSTR AHK_VERSION;
	extern LPTSTR T_AHK_VERSION;
	extern LPTSTR T_AHK_NAME_VERSION;
#endif
