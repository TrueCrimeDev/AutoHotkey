/*
AutoHotkey

Copyright 2003-2009 Chris Mallett (support@autohotkey.com)

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
*/

#include "stdafx.h" // pre-compiled headers
#include "globaldata.h" // for access to many global vars
#include "application.h" // for MsgSleep()
#include "window.h" // For MsgBox()
#include "TextIO.h"
#include "crashlog.h"
#include "mcp_server.h" // McpServerMain() for the `mcp` subcommand.
#include "ahkversion.h"
#include <string>

// General note:
// The use of Sleep() should be avoided *anywhere* in the code.  Instead, call MsgSleep().
// The reason for this is that if the keyboard or mouse hook is installed, a straight call
// to Sleep() will cause user keystrokes & mouse events to lag because the message pump
// (GetMessage() or PeekMessage()) is the only means by which events are ever sent to the
// hook functions.


ResultType InitForExecution();
ResultType ParseCmdLineArgs(LPTSTR &script_filespec);
ResultType CheckPriorInstance();
int MainExecuteScript(bool aMsgSleep = true);

#ifndef AUTOHOTKEYSC
enum CliInfoMode { CLI_INFO_NONE, CLI_INFO_HELP, CLI_INFO_VERSION, CLI_INFO_CAPABILITIES, CLI_INFO_SUMMARY };
static CliInfoMode sCliInfoMode = CLI_INFO_NONE;

static std::wstring CliJsonString(LPCTSTR text)
{
	std::wstring out = L"\"";
	for (; *text; ++text)
	{
		if (*text == L'"' || *text == L'\\')
			out += L'\\';
		if (*text < 0x20)
		{
			TCHAR escaped[7];
			sntprintf(escaped, _countof(escaped), _T("\\u%04x"), (unsigned)*text);
			out += escaped;
		}
		else
			out += *text;
	}
	return out + L'"';
}

static ResultType CliUsageError(LPCTSTR message, LPCTSTR detail = nullptr)
{
	std::wstring text = message;
	if (detail)
		text += std::wstring(L" ") + detail;
	text += L" Run AutoHotkey --help for usage.";
	if (g_script.mDiagJson)
		text = L"{\"kind\":\"diagnostic\",\"format\":\"json\",\"schema\":2,\"severity\":\"error\","
			L"\"type\":\"UsageError\",\"code\":64,\"message\":" + CliJsonString(text.c_str())
			+ L",\"extra\":\"\",\"what\":\"\",\"file\":\"\",\"line\":0,\"column\":0,\"source\":\"\",\"stack\":\"\"}";
	text += L'\n';
	// An invalid encoding option must never route this error into a dialog.
	g_script.mErrorStdOutCP = CP_UTF8;
	g_script.PrintErrorStdOut(text.c_str(), (int)text.size(), _T("**"));
	return FAIL;
}

static void PrintCliInfo()
{
	std::wstring out;
	if (sCliInfoMode == CLI_INFO_HELP)
	{
		out = L"Usage: AutoHotkey [options] [run|check|test|repl|mcp] [script.ahk] [script arguments]\n"
			L"       AutoHotkey --help | --version | --capabilities\n\n"
			L"Commands:\n"
			L"  run script.ahk    Run a script (the run keyword is optional).\n"
			L"  check script.ahk  Validate syntax without executing (exit 0 or 13).\n"
			L"  test script.ahk   Run a non-persistent test script (exit 0 or 14).\n"
			L"  repl [script.ahk] Evaluate expressions from stdin; .help describes the session.\n"
			L"  mcp              Serve MCP over stdin/stdout; no script is loaded.\n\n"
			L"Options (before the script; may precede or follow the command):\n"
			L"  /Headless         Report errors without interactive error or instance prompts.\n"
			L"  /Diag=text|json   Diagnostic output format (stderr).\n"
			L"  /ErrorStdOut[=encoding]  Diagnostic text encoding; :color or :nocolor.\n"
			L"  /Eval             Enable Eval() in a script.\n"
			L"  /Trace            Show executing statements on stderr (no raw key events).\n"
			L"  /force            Replace an existing script instance.\n"
			L"  /include file     Include one file before the script.\n"
			L"  /CPnnn            Script source code page.\n"
			L"  /CrashLog=path    Append crash and process lifecycle events.\n"
			L"  /StdErrFile=path  Mirror diagnostics to a file.\n"
			L"  --                Treat the next argument as the script filename.\n\n"
			L"All arguments after the script filename are passed unchanged in A_Args.\n"
			L"--version reports engine and build identity; --capabilities emits JSON.\n"
			L"Help aliases: help, -h, --h, -help, --help, /help, /?.\n"
			L"Exit codes: 0 success, 10 runtime, 11 critical, 12 parse, 13 check,\n"
			L"            14 test, 64 command-line usage, 130 interrupted.";
	}
	else if (sCliInfoMode == CLI_INFO_VERSION || sCliInfoMode == CLI_INFO_SUMMARY)
	{
		out = T_AHK_NAME_VERSION;
		out += std::wstring(L"\nrevision=") + T_AHK_BUILD_REVISION
			+ L" compiler=" + T_AHK_BUILD_COMPILER + L" architecture=" + T_AHK_BUILD_ARCH;
		if (sCliInfoMode == CLI_INFO_SUMMARY)
			out += L"\n\n  ahk script.ahk        Run a script\n"
				L"  ahk run script.ahk    Run a script (same as above)\n"
				L"  ahk check script.ahk  Check syntax without running\n"
				L"  ahk test script.ahk   Execute a test script\n"
				L"  ahk repl              Open the interactive console; .exit to leave\n"
				L"  ahk help              Show all commands and options (also -h or --help)";
	}
	else
	{
		out = L"{\"kind\":\"capabilities\",\"schema\":1,\"name\":\"AutoHotkey\",\"version\":"
			+ CliJsonString(T_AHK_VERSION) + L",\"build\":{\"revision\":" + CliJsonString(T_AHK_BUILD_REVISION)
			+ L",\"compiler\":" + CliJsonString(T_AHK_BUILD_COMPILER)
			+ L",\"architecture\":" + CliJsonString(T_AHK_BUILD_ARCH)
			+ L"},\"commands\":[\"run\",\"check\",\"test\",\"repl\",\"mcp\"],"
			L"\"diagnostics\":{\"formats\":[\"text\",\"json\"],\"jsonSchema\":2},"
			L"\"mcp\":{\"transport\":\"stdio\",\"protocolVersions\":[\"2025-06-18\",\"2024-11-05\"]},"
			L"\"features\":{\"eval\":\"opt-in\",\"json\":true,\"check\":true,\"repl\":true},"
			L"\"exitCodes\":{\"success\":0,\"runtime\":10,\"critical\":11,\"parse\":12,\"check\":13,\"test\":14,\"usage\":64,\"interrupted\":130}}";
	}
	PrintWideLine(out.c_str(), (int)out.size());
}
#endif


// Performs any initialization that should be done before LoadFromFile().
void EarlyAppInit()
{
	// v1.1.22+: This is done unconditionally, on startup, so that any attempts to read a drive
	// that has no media (and possibly other errors) won't cause the system to display an error
	// dialog that the script can't suppress.  This is known to affect floppy drives and some
	// but not all CD/DVD drives.  MSDN says: "Best practice is that all applications call the
	// process-wide SetErrorMode function with a parameter of SEM_FAILCRITICALERRORS at startup."
	// Note that in previous versions, this was done by the Drive/DriveGet commands and not
	// reverted afterward, so it affected all subsequent commands.
	SetErrorMode(SEM_FAILCRITICALERRORS);

	// Without the following, the Start menu on Windows 11 can't be opened with the mouse
	// if we have a modeless menu active and we're running as admin or with UI access.
	// It's necessary to allow it at least for the owner of the menu while the menu is
	// visible, but this is simpler and probably helps to make the windows of our process
	// behave as the user expects.  Doing it early also means that the script can easily
	// override it at startup.
	ChangeWindowMessageFilter(WM_CANCELMODE, MSGFLT_ALLOW);

	// g_WorkingDir is used by various functions but might currently only be used at runtime.
	// g_WorkingDirOrig needs to be initialized before Script::Init() is called.
	UpdateWorkingDir();
	g_WorkingDirOrig = SimpleHeap::Alloc(g_WorkingDir.GetString());

	// Initialize early since g is used in many places, including some at load-time.
	global_init(*g);
	
	// Initialize the object model here, prior to any use of Objects (or Array below).
	// Doing this here rather than in a static initializer in script_object.cpp avoids
	// issues of static initialization order.  At this point all static members such as
	// sMembers arrays have been initialized (normally they are constant initialized
	// anyway, but in debug mode the arrays using cast_into_voidp() are not).
	Object::CreateRootPrototypes();
}


int WINAPI _tWinMain (HINSTANCE hInstance, HINSTANCE hPrevInstance, LPTSTR lpCmdLine, int nCmdShow)
{
	g_hInstance = hInstance;

	// Install the SEH filter as early as possible so it catches crashes during init.
	// The filter writes [FATAL] + [EXIT] to the crash log before returning
	// EXCEPTION_CONTINUE_SEARCH (letting Windows perform its normal crash handling).
	CrashLog::InstallExceptionFilter();

	// Install console handler so Ctrl+C / close / shutdown writes [EXIT] code=130.
	CrashLog::InstallConsoleHandler();

	EarlyAppInit();
	#ifdef AHK_CONSOLE_ENTRYPOINT
	// A console launch reports load/runtime errors in the terminal too.
	g_script.SetErrorStdOut(nullptr);
	#endif

	LPTSTR script_filespec; // Script path as originally specified, or NULL if omitted/defaulted.
	if (!ParseCmdLineArgs(script_filespec))
		return AHK_EXIT_CLI_ERROR;

#ifndef AUTOHOTKEYSC
	if (sCliInfoMode != CLI_INFO_NONE)
	{
		PrintCliInfo();
		return AHK_EXIT_OK;
	}
	if (g_script.mMcpMode)
		return McpServerMain(); // Stdio JSON-RPC loop; never loads a script, opens no windows.
#endif

	g_script.ReplPrepare();
	UINT load_result = g_script.LoadFromFile(script_filespec);
	if (load_result == LOADING_FAILED) // Error during load (was already displayed by the function call).
	{
		int exit_code = g_script.mCheckMode ? AHK_EXIT_VALIDATE_ERROR : AHK_EXIT_PARSE_ERROR;
		CrashLog::LogExitWithCode(exit_code);
		return exit_code;
	}
	if (!load_result) // LoadFromFile() relies upon us to do this check.  No script was loaded or we're in /iLib mode, so nothing more to do.
	{
#ifndef AUTOHOTKEYSC
		if (g_script.mCheckMode)
		{
			if (g_script.mDiagJson)
				g_script.PrintErrorStdOut(_T("{\"kind\":\"check\",\"status\":\"pass\"}\n"), 0, _T("*"));
			else
				g_script.PrintErrorStdOut(_T("CHECK PASS\n"), 0, _T("*"));
		}
#endif
		return AHK_EXIT_OK;
	}

	switch (CheckPriorInstance())
	{
	case EARLY_EXIT: return 0;
	case FAIL: return AHK_EXIT_CLI_ERROR;
	}

	if (!InitForExecution())
		return AHK_EXIT_CRITICAL_ERROR;

	if (CrashLog::IsCrashLogEnabled())
		CrashLog::LogStart(g_script.mFileSpec, GetCommandLineW());

	return MainExecuteScript();
}


ResultType ParseCmdLineArgs(LPTSTR &script_filespec)
{
	script_filespec = NULL; // Set default as "unspecified/omitted".
#ifndef AUTOHOTKEYSC
	// Is this a compiled script?
	if (FindResource(NULL, SCRIPT_RESOURCE_NAME, RT_RCDATA))
		script_filespec = SCRIPT_RESOURCE_SPEC;
#endif

	// The number of switches recognized by compiled scripts (without /script) is kept to a minimum
	// since all such switches must be effectively reserved, as there's nothing to separate them from
	// the switches defined by the script itself.  The abbreviated /R and /F switches present in v1
	// were also removed for this reason.
	// 
	// Examine command line args.  Rules:
	// Any special flags (e.g. /force and /restart) must appear prior to the script filespec.
	// The script filespec (if present) must be the first non-backslash arg.
	// All args that appear after the filespec are considered to be parameters for the script
	// and will be stored in A_Args.
	int i;
	bool command_seen = false;
	bool run_command = false;
	for (i = 1; i < __argc; ++i) // Start at 1 because 0 contains the program name.
	{
		LPTSTR param = __targv[i]; // For performance and convenience.
#ifndef AUTOHOTKEYSC
		if (!script_filespec && !command_seen && !_tcsicmp(param, _T("run")))
		{
			command_seen = run_command = true;
			continue;
		}
		if (!script_filespec && !command_seen && !_tcsicmp(param, _T("help")))
		{
			sCliInfoMode = CLI_INFO_HELP;
			continue;
		}
		// Support subcommand style: AutoHotkey.exe check script.ahk / AutoHotkey.exe test script.ahk
		if (!script_filespec && !command_seen && !_tcsicmp(param, _T("check")))
		{
			command_seen = true;
			g_script.mCheckMode = true;
			g_script.mValidateThenExit = true;
			g_script.SetHeadless();
			continue;
		}
		if (!script_filespec && !command_seen && !_tcsicmp(param, _T("test")))
		{
			command_seen = true;
			g_script.mTestMode = true;
			g_script.SetHeadless();
			continue;
		}
		if (!script_filespec && !command_seen && !_tcsicmp(param, _T("repl")))
		{
			command_seen = true;
			g_script.mReplMode = true;
			g_AllowEval = true; // The REPL is an Eval driver; the BIF gate is implied.
			g_AllowOnlyOneInstance = SINGLE_INSTANCE_OFF; // Parallel sessions are expected.
			continue;
		}
		// !script_filespec: a resource-compiled script (detected above) must get
		// "mcp" as its own A_Args[1], not be hijacked into server mode.
		if (!script_filespec && !command_seen && !_tcsicmp(param, _T("mcp")))
		{
			command_seen = true;
			g_script.mMcpMode = true;
			g_script.SetHeadless();
			g_AllowOnlyOneInstance = SINGLE_INSTANCE_OFF; // Stdio MCP servers spawn one process per client.
			continue;
		}
#endif
		// Insist that switches be an exact match for the allowed values to cut down on ambiguity.
		// For example, if the user runs "CompiledScript.exe /find", we want /find to be considered
		// an input parameter for the script rather than a switch:
		if (!_tcsicmp(param, _T("/restart")))
			g_script.mIsRestart = true;
		else if (!_tcsicmp(param, _T("/force")))
			g_ForceLaunch = true;
#ifndef AUTOHOTKEYSC // i.e. the following switch is recognized only by AutoHotkey.exe (especially since recognizing new switches in compiled scripts can break them, unlike AutoHotkey.exe).
		else if (!_tcsicmp(param, _T("/script")))
			script_filespec = NULL; // Override compiled script mode, otherwise no effect.
		else if (script_filespec) // Compiled script mode.
			break;
		else if (!_tcsicmp(param, _T("--help")) || !_tcsicmp(param, _T("/help")) || !_tcsicmp(param, _T("/?"))
			|| !_tcsicmp(param, _T("-h")) || !_tcsicmp(param, _T("--h")) || !_tcsicmp(param, _T("-help")))
			sCliInfoMode = CLI_INFO_HELP;
		else if (!_tcsicmp(param, _T("--version")) || !_tcsicmp(param, _T("/version")))
			sCliInfoMode = CLI_INFO_VERSION;
		else if (!_tcsicmp(param, _T("--capabilities")))
			sCliInfoMode = CLI_INFO_CAPABILITIES;
		else if (!_tcscmp(param, _T("--")))
		{
			if (++i >= __argc)
				return CliUsageError(_T("Expected a script filename after --."));
			script_filespec = __targv[i++];
			break;
		}
		else if (!_tcsnicmp(param, _T("/ErrorStdOut"), 12) && (param[12] == '\0' || param[12] == '=' || param[12] == ':'))
		{
			g_script.SetErrorStdOut(param[12] ? param + 13 : NULL, param[12] == ':');
			if (!g_script.mErrorStdOut)
				return CliUsageError(_T("Invalid /ErrorStdOut encoding."));
		}
		else if (!_tcsicmp(param, _T("/Headless")) || !_tcsicmp(param, _T("--headless")))
			g_script.SetHeadless();
		else if (!_tcsicmp(param, _T("/Trace")) || !_tcsicmp(param, _T("--trace")))
		{
			g_script.mTrace = true;
			g_script.SetHeadless();
			// An inherited pipe/file is already a usable destination. Attaching a
			// console here would replace it and hide trace output from test runners.
			HANDLE trace_stderr = GetStdHandle(STD_ERROR_HANDLE);
			if ((!trace_stderr || trace_stderr == INVALID_HANDLE_VALUE || GetFileType(trace_stderr) == FILE_TYPE_UNKNOWN)
				&& AttachConsole(ATTACH_PARENT_PROCESS))
			{
				// Reopen stderr so WriteFile(GetStdHandle(STD_ERROR_HANDLE)) works
				freopen("CONOUT$", "w", stderr);
			}
		}
		else if ((!_tcsnicmp(param, _T("/Diag"), 5) && (param[5] == '\0' || param[5] == '='))
			|| (!_tcsnicmp(param, _T("--diag"), 6) && (param[6] == '\0' || param[6] == '=')))
		{
			LPTSTR value = NULL;
			if (!_tcsnicmp(param, _T("/Diag"), 5))
				value = (param[5] == '=') ? param + 6 : NULL;
			else
				value = (param[6] == '=') ? param + 7 : NULL;

			if (!value || !*value || !_tcsicmp(value, _T("text")))
				g_script.SetDiagJson(false);
			else if (!_tcsicmp(value, _T("json")))
				g_script.SetDiagJson(true);
			else
				return CliUsageError(_T("Invalid /Diag format; expected text or json."));
		}
		else if (!_tcsicmp(param, _T("/Check")) || !_tcsicmp(param, _T("--check")))
		{
			g_script.mCheckMode = true;
			g_script.mValidateThenExit = true;
			g_script.SetHeadless();
		}
		else if (!_tcsicmp(param, _T("/Test")) || !_tcsicmp(param, _T("--test")))
		{
			g_script.mTestMode = true;
			g_script.SetHeadless();
		}
		else if (!_tcsicmp(param, _T("/Eval")) || !_tcsicmp(param, _T("--eval")))
		{
			g_AllowEval = true;
		}
		else if ((!_tcsnicmp(param, _T("/CrashLog="), 10)) || (!_tcsnicmp(param, _T("--crashlog="), 11)))
		{
			LPTSTR path = param + (!_tcsnicmp(param, _T("/CrashLog="), 10) ? 10 : 11);
			if (!*path)
				return CliUsageError(_T("/CrashLog requires a non-empty path."));
			if (*path)
			{
				free(g_CrashLogPath);
				g_CrashLogPath = _tcsdup(path);
				CrashLog::SetCrashLogPath(path);
			}
		}
		else if ((!_tcsnicmp(param, _T("/StdErrFile="), 12)) || (!_tcsnicmp(param, _T("--stderrfile="), 13)))
		{
			LPTSTR path = param + (!_tcsnicmp(param, _T("/StdErrFile="), 12) ? 12 : 13);
			if (!*path)
				return CliUsageError(_T("/StdErrFile requires a non-empty path."));
			if (*path)
			{
				free(g_StdErrFilePath);
				g_StdErrFilePath = _tcsdup(path);
				CrashLog::SetStdErrFilePath(path);
			}
		}
		else if (!_tcsicmp(param, _T("/include")))
		{
			++i; // Consume the next parameter too, because it's associated with this one.
			if (i >= __argc // Missing the expected filename parameter.
				|| g_script.mCmdLineInclude) // Only one is supported, so abort if there's more.
				return CliUsageError(_T("/include requires one filename and may appear only once."));
			g_script.mCmdLineInclude = __targv[i];
		}
		else if (!_tcsicmp(param, _T("/validate")))
			g_script.mValidateThenExit = true;
		// DEPRECATED: /iLib
		else if (!_tcsicmp(param, _T("/iLib"))) // v1.0.47: Build an include-file so that ahk2exe can include library functions called by the script.
		{
			++i; // Consume the next parameter too, because it's associated with this one.
			if (i >= __argc) // Missing the expected filename parameter.
				return CliUsageError(_T("/iLib requires a filename argument."));
			// The original purpose of /iLib has gone away with the removal of auto-includes,
			// but some scripts (like Ahk2Exe) use it to validate the syntax of script files.
			g_script.mValidateThenExit = true;
		}
		else if (!_tcsnicmp(param, _T("/CP"), 3)) // /CPnnn
		{
			// Default codepage for the script file, NOT the default for commands used by it.
			g_DefaultScriptCodepage = ATOU(param + 3);
		}
#endif
#ifdef CONFIG_DEBUGGER
		// Allow a debug session to be initiated by command-line.
		else if (!_tcsnicmp(param, _T("/Debug"), 6) && (param[6] == '\0' || param[6] == '='))
		{
			if (param[6] == '=')
			{
				param += 7;

				if (!_tcsicmp(param, _T("stdio")))
				{
					// Stdio transport: debugger protocol over stdin/stdout.
					g_DebugStdio = true;
					g_DebuggerHost = "stdio";
					g_DebuggerPort = "0";
				}
				else
				{
					LPTSTR c = _tcsrchr(param, ':');

					if (c)
					{
						StringTCharToChar(param, g_DebuggerHost, (int)(c-param));
						StringTCharToChar(c + 1, g_DebuggerPort);
					}
					else
					{
						StringTCharToChar(param, g_DebuggerHost);
						g_DebuggerPort = "9000";
					}
				}
			}
			else
			{
				g_DebuggerHost = "localhost";
				g_DebuggerPort = "9000";
			}
			// The actual debug session is initiated after the script is successfully parsed.
		}
#endif
		else // since this is not a recognized switch, the end of the [Switches] section has been reached (by design).
		{
#ifndef AUTOHOTKEYSC
			if (param[0] == '-' || (param[0] == '/' && !_tcschr(param + 1, '/') && !_tcschr(param + 1, '\\')))
				return CliUsageError(_T("Unknown option:"), param);
			script_filespec = param;  // The first unrecognized switch must be the script filespec, by design.
			++i; // Omit this from the "args" array.
#endif
			break; // No more switches allowed after this point.
		}
	}
	
#ifndef AUTOHOTKEYSC
	#ifdef AHK_CONSOLE_ENTRYPOINT
	if (__argc == 1 && !script_filespec)
		sCliInfoMode = CLI_INFO_SUMMARY;
	#endif
	if (sCliInfoMode != CLI_INFO_NONE)
		return OK;
	if (script_filespec && !*script_filespec)
		return CliUsageError(_T("The script filename must not be empty."));
	if ((int)run_command + (int)g_script.mCheckMode + (int)g_script.mTestMode + (int)g_script.mReplMode + (int)g_script.mMcpMode > 1)
		return CliUsageError(_T("Choose only one command: run, check, test, repl or mcp."));
	if ((run_command || g_script.mCheckMode || g_script.mTestMode) && !script_filespec)
		return CliUsageError(_T("The run, check and test commands require a script filename. Use repl for an interactive console."));
	if (g_script.mMcpMode && script_filespec)
		return CliUsageError(_T("The mcp command does not accept a script filename."));
	if (g_script.mReplMode && !script_filespec)
		script_filespec = _T("*REPL"); // Synthetic in-memory script; see LoadIncludedFile().
	#ifdef AHK_CONSOLE_ENTRYPOINT
	if (!script_filespec && !g_script.mMcpMode)
		return CliUsageError(_T("Expected a script filename or command."));
	#endif
#endif

	// Pass any remaining args to the script via the A_Args array.
	auto args = Array::FromArgV(__targv + i, __argc - i);

	// Set up the basics of the script:
	return g_script.Init(script_filespec, args);
}


ResultType CheckPriorInstance()
{
	HWND w_existing = NULL;
	UserMessages reason_to_close_prior = (UserMessages)0;
	if (g_AllowOnlyOneInstance && !g_script.mIsRestart && !g_ForceLaunch)
	{
		if (w_existing = FindWindow(WINDOW_CLASS_MAIN, g_script.mMainWindowTitle))
		{
			if (g_AllowOnlyOneInstance == SINGLE_INSTANCE_IGNORE)
				return EARLY_EXIT;
			if (g_AllowOnlyOneInstance != SINGLE_INSTANCE_REPLACE)
			{
				if (g_script.mHeadless)
				{
					g_script.PrintErrorStdOut(_T("Another instance is already running. Use #SingleInstance Force or /force.\n"), 0, _T("**"));
					return FAIL;
				}
				if (MsgBox(_T("An older instance of this script is already running.  Replace it with this")
					_T(" instance?\nNote: To avoid this message, see #SingleInstance in the help file.")
					, MB_YESNO, g_script.mFileName) == IDNO)
					return EARLY_EXIT;
			}
			// Otherwise:
			reason_to_close_prior = AHK_EXIT_BY_SINGLEINSTANCE;
		}
	}
	if (!reason_to_close_prior && g_script.mIsRestart)
		if (w_existing = FindWindow(WINDOW_CLASS_MAIN, g_script.mMainWindowTitle))
			reason_to_close_prior = AHK_EXIT_BY_RELOAD;
	if (reason_to_close_prior)
	{
		// Now that the script has been validated and is ready to run, close the prior instance.
		// We wait until now to do this so that the prior instance's "restart" hotkey will still
		// be available to use again after the user has fixed the script.  UPDATE: We now inform
		// the prior instance of why it is being asked to close so that it can make that reason
		// available to the OnExit function via a built-in variable:
		ASK_INSTANCE_TO_CLOSE(w_existing, reason_to_close_prior);
		//PostMessage(w_existing, WM_CLOSE, 0, 0);

		// Wait for it to close before we continue, so that it will deinstall any
		// hooks and unregister any hotkeys it has:
		int interval_count;
		for (interval_count = 0; ; ++interval_count)
		{
			Sleep(20);  // No need to use MsgSleep() in this case.
			if (!IsWindow(w_existing))
				break;  // done waiting.
			if (interval_count == 100)
			{
				// This can happen if the previous instance has an OnExit function that takes a long
				// time to finish, or if it's waiting for a network drive to timeout or some other
				// operation in which it's thread is occupied.
				if (g_script.mHeadless)
				{
					g_script.PrintErrorStdOut(_T("Timed out waiting for a prior instance to close.\n"), 0, _T("**"));
					return FAIL;
				}
				if (MsgBox(_T("Could not close the previous instance of this script.  Keep waiting?"), 4) == IDNO)
					return FAIL;
				interval_count = 0;
			}
		}
		// Give it a small amount of additional time to completely terminate, even though
		// its main window has already been destroyed:
		Sleep(100);
	}
	return OK;
}


ResultType InitForExecution()
{
	// Create all our windows and the tray icon.  This is done after all other chances
	// to return early due to an error have passed, above.
	if (!g_script.CreateWindows())
		return FAIL;

	if (g_MaxHistoryKeys && (g_KeyHistory = (KeyHistoryItem *)malloc(g_MaxHistoryKeys * sizeof(KeyHistoryItem))))
		ZeroMemory(g_KeyHistory, g_MaxHistoryKeys * sizeof(KeyHistoryItem)); // Must be zeroed.
	//else leave it NULL as it was initialized in globaldata.

	// From this point on, any errors that are reported should not indicate that they will exit the program.
	// Various functions also use this to detect that they are being called by the script at runtime.
	g_script.mIsReadyToExecute = true;

	return OK;
}


int MainExecuteScript(bool aMsgSleep)
{
#ifdef CONFIG_DEBUGGER
	// Initiate debug session now if applicable.
	if (!g_DebuggerHost.IsEmpty() && g_Debugger.Connect(g_DebuggerHost, g_DebuggerPort) == DEBUGGER_E_OK)
	{
		g_Debugger.Break();
	}
#endif

	// Activate the hotkeys, hotstrings, and any hooks that are required prior to executing the
	// top part (the auto-execute part) of the script so that they will be in effect even if the
	// top part is something that's very involved and requires user interaction:
	Hotkey::ManifestAllHotkeysHotstringsHooks(); // We want these active now in case auto-execute never returns (e.g. loop)

#if !defined(_DEBUG) && defined(_MSC_VER)
	__try
#endif
	{
		// Run the auto-execute part at the top of the script:
		auto exec_result = g_script.AutoExecSection();
		// REMEMBER: The call above will never return if one of the following happens:
		// 1) The AutoExec section never finishes (e.g. infinite loop).
		// 2) The AutoExec function uses the Exit or ExitApp command to terminate the script.
		// 3) The script isn't persistent and its last line is reached (in which case an Exit is implicit).
		// However, #ifdef CONFIG_DLL, the call will return after Exit is used (but not explicit ExitApp).

#ifdef CONFIG_DLL
		if (!aMsgSleep)
			return exec_result ? AHK_EXIT_OK : AHK_EXIT_CRITICAL_ERROR;
#endif
		if (g_script.mTestMode)
		{
			if (g_script.IsPersistent())
			{
				if (g_script.mDiagJson)
					g_script.PrintErrorStdOut(_T("{\"kind\":\"test\",\"status\":\"fail\",\"reason\":\"persistent_script\"}\n"), 0, _T("**"));
				else
					g_script.PrintErrorStdOut(_T("TEST FAIL: test mode requires a non-persistent script.\n"), 0, _T("**"));
				g_script.mPendingExitCode = AHK_EXIT_TEST_FAILURE;
				g_script.mHasPendingExitCode = true;
				g_script.ExitApp(EXIT_ERROR);
			}
			else
			{
				if (g_script.mDiagJson)
					g_script.PrintErrorStdOut(exec_result == FAIL
						? _T("{\"kind\":\"test\",\"status\":\"fail\"}\n")
						: _T("{\"kind\":\"test\",\"status\":\"pass\"}\n"), 0, _T("*"));
				else
					g_script.PrintErrorStdOut(exec_result == FAIL
						? _T("TEST FAIL\n")
						: _T("TEST PASS\n"), 0, _T("*"));
				g_script.mPendingExitCode = exec_result == FAIL ? AHK_EXIT_TEST_FAILURE : AHK_EXIT_OK;
				g_script.mHasPendingExitCode = true;
				g_script.ExitApp(exec_result == FAIL ? EXIT_ERROR : EXIT_EXIT);
			}
		}
		if (g_script.mReplMode)
			g_script.ReplStart(); // Auto-execute has finished; begin the read-eval-print session.
		if (g_script.IsPersistent())
		{
			// Call it in this special mode to kick off the main event loop.
			// Be sure to pass something >0 for the first param or it will
			// return (and we never want this to return):
			MsgSleep(SLEEP_INTERVAL, WAIT_FOR_MESSAGES);
		}
		else
		{
			// The script isn't persistent, so call OnExit handlers and terminate.
			g_script.ExitApp(exec_result == FAIL ? EXIT_ERROR : EXIT_EXIT);
		}
	}
#if !defined(_DEBUG) && defined(_MSC_VER)
	__except (EXCEPTION_EXECUTE_HANDLER)
	{
		LPCTSTR msg;
		auto ecode = GetExceptionCode();
		switch (ecode)
		{
		// Having specific messages for the most common exceptions seems worth the added code size.
		// The term "stack overflow" is not used because it is probably less easily understood by
		// the average user, and is not useful as a search term due to stackoverflow.com.
		case EXCEPTION_STACK_OVERFLOW: msg = _T("Function recursion limit exceeded."); break;
		case EXCEPTION_ACCESS_VIOLATION: msg = _T("Invalid memory read/write."); break;
		default: msg = _T("System exception 0x%X."); break;
		}
		TCHAR buf[127];
		sntprintf(buf, _countof(buf), msg, ecode);
		g_script.CriticalError(buf);
		return AHK_EXIT_CRITICAL_ERROR;
	}
#endif 
	return AHK_EXIT_OK;
}
