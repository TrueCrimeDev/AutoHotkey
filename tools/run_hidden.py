"""Run a command on a hidden Win32 desktop, so no window it opens reaches
the screen.

Usage:
    python tools/run_hidden.py [--timeout SECONDS] [--desktop NAME]
                               COMMAND [ARG...]

Every process the command starts inherits the desktop, so a MsgBox, an
error or #Warn dialog, a Gui or a new console window is created where
nobody sees it: it cannot take focus, and keystrokes a script sends do
not reach the user's windows. Each visible window that opens there is
reported on stderr with its title and text. Task View virtual desktops
cannot do this; a new window opens on whichever one the user is looking
at.

The command shares this process's stdin, stdout and stderr, and the exit
code is the command's own (124 after --timeout, 130 on Ctrl+C).
Processes it leaves running are killed when it exits. The clipboard and
the file system are shared with the user's session as usual.
"""
import argparse
import ctypes
from ctypes import wintypes as w
import os
import shutil
import subprocess
import sys
import time

if os.name != "nt":
    raise SystemExit("run_hidden.py needs Windows")

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
u32 = ctypes.WinDLL("user32", use_last_error=True)

GENERIC_ALL = 0x10000000
GENERIC_READ_WRITE = 0xC0000000
FILE_SHARE_READ_WRITE = 3
OPEN_EXISTING = 3
CREATE_SUSPENDED = 0x4
STARTF_USESTDHANDLES = 0x100
HANDLE_FLAG_INHERIT = 1
UOI_NAME = 2
WM_GETTEXT = 0x000D
SMTO_ABORTIFHUNG = 0x0002
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000
JOB_BASIC_PROCESS_ID_LIST = 3
JOB_EXTENDED_LIMIT_INFORMATION = 9
STD_HANDLES = (-10, -11, -12)  # STD_INPUT, STD_OUTPUT, STD_ERROR_HANDLE
INVALID_HANDLE = (1 << (8 * ctypes.sizeof(ctypes.c_void_p))) - 1
TIMED_OUT, INTERRUPTED = 124, 130
CONSOLE_CLASSES = {"ConsoleWindowClass", "PseudoConsoleWindow"}

# The Win32 structures keep their SDK type and field names.
# pylint: disable=invalid-name,too-few-public-methods


class STARTUPINFOW(ctypes.Structure):
    """STARTUPINFOW."""
    _fields_ = [
        ("cb", w.DWORD), ("lpReserved", w.LPWSTR),
        ("lpDesktop", w.LPWSTR), ("lpTitle", w.LPWSTR),
        ("dwX", w.DWORD), ("dwY", w.DWORD),
        ("dwXSize", w.DWORD), ("dwYSize", w.DWORD),
        ("dwXCountChars", w.DWORD), ("dwYCountChars", w.DWORD),
        ("dwFillAttribute", w.DWORD), ("dwFlags", w.DWORD),
        ("wShowWindow", w.WORD), ("cbReserved2", w.WORD),
        ("lpReserved2", ctypes.c_void_p), ("hStdInput", w.HANDLE),
        ("hStdOutput", w.HANDLE), ("hStdError", w.HANDLE),
    ]


class PROCESS_INFORMATION(ctypes.Structure):
    """PROCESS_INFORMATION."""
    _fields_ = [
        ("hProcess", w.HANDLE), ("hThread", w.HANDLE),
        ("dwProcessId", w.DWORD), ("dwThreadId", w.DWORD),
    ]


class SECURITY_ATTRIBUTES(ctypes.Structure):
    """SECURITY_ATTRIBUTES."""
    _fields_ = [
        ("nLength", w.DWORD), ("lpSecurityDescriptor", ctypes.c_void_p),
        ("bInheritHandle", w.BOOL),
    ]


class JOBOBJECT_BASIC_LIMIT_INFORMATION(ctypes.Structure):
    """JOBOBJECT_BASIC_LIMIT_INFORMATION."""
    _fields_ = [
        ("PerProcessUserTimeLimit", ctypes.c_int64),
        ("PerJobUserTimeLimit", ctypes.c_int64),
        ("LimitFlags", w.DWORD),
        ("MinimumWorkingSetSize", ctypes.c_size_t),
        ("MaximumWorkingSetSize", ctypes.c_size_t),
        ("ActiveProcessLimit", w.DWORD),
        ("Affinity", ctypes.c_size_t),
        ("PriorityClass", w.DWORD),
        ("SchedulingClass", w.DWORD),
    ]


class JOBOBJECT_EXTENDED_LIMIT_INFORMATION(ctypes.Structure):
    """JOBOBJECT_EXTENDED_LIMIT_INFORMATION; IoInfo is six counters."""
    _fields_ = [
        ("BasicLimitInformation", JOBOBJECT_BASIC_LIMIT_INFORMATION),
        ("IoInfo", ctypes.c_uint64 * 6),
        ("ProcessMemoryLimit", ctypes.c_size_t),
        ("JobMemoryLimit", ctypes.c_size_t),
        ("PeakProcessMemoryUsed", ctypes.c_size_t),
        ("PeakJobMemoryUsed", ctypes.c_size_t),
    ]


class JOBOBJECT_BASIC_PROCESS_ID_LIST(ctypes.Structure):
    """JOBOBJECT_BASIC_PROCESS_ID_LIST with room for 1024 IDs."""
    _fields_ = [
        ("NumberOfAssignedProcesses", w.DWORD),
        ("NumberOfProcessIdsInList", w.DWORD),
        ("ProcessIdList", ctypes.c_size_t * 1024),
    ]


# pylint: enable=invalid-name,too-few-public-methods


def fn(dll, name, restype, *argtypes):
    """Declare one Win32 function with its result and argument types."""
    f = getattr(dll, name)
    f.restype, f.argtypes = restype, argtypes
    return f


WNDENUMPROC = ctypes.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)
PDWORD = ctypes.POINTER(w.DWORD)

CreateDesktopW = fn(u32, "CreateDesktopW", w.HANDLE, w.LPCWSTR, w.LPCWSTR,
                    ctypes.c_void_p, w.DWORD, w.DWORD, ctypes.c_void_p)
CloseDesktop = fn(u32, "CloseDesktop", w.BOOL, w.HANDLE)
GetProcessWindowStation = fn(u32, "GetProcessWindowStation", w.HANDLE)
GetUserObjectInformationW = fn(u32, "GetUserObjectInformationW", w.BOOL,
                               w.HANDLE, ctypes.c_int, ctypes.c_void_p,
                               w.DWORD, PDWORD)
EnumDesktopWindows = fn(u32, "EnumDesktopWindows", w.BOOL, w.HANDLE,
                        WNDENUMPROC, w.LPARAM)
EnumChildWindows = fn(u32, "EnumChildWindows", w.BOOL, w.HWND,
                      WNDENUMPROC, w.LPARAM)
IsWindowVisible = fn(u32, "IsWindowVisible", w.BOOL, w.HWND)
IsIconic = fn(u32, "IsIconic", w.BOOL, w.HWND)
GetClassNameW = fn(u32, "GetClassNameW", ctypes.c_int, w.HWND, w.LPWSTR,
                   ctypes.c_int)
GetWindowThreadProcessId = fn(u32, "GetWindowThreadProcessId", w.DWORD,
                              w.HWND, PDWORD)
SendMessageTimeoutW = fn(u32, "SendMessageTimeoutW", ctypes.c_size_t,
                         w.HWND, w.UINT, ctypes.c_size_t, ctypes.c_void_p,
                         w.UINT, w.UINT, ctypes.POINTER(ctypes.c_size_t))
GetStdHandle = fn(k32, "GetStdHandle", w.HANDLE, w.DWORD)
SetHandleInformation = fn(k32, "SetHandleInformation", w.BOOL, w.HANDLE,
                          w.DWORD, w.DWORD)
CreateFileW = fn(k32, "CreateFileW", w.HANDLE, w.LPCWSTR, w.DWORD, w.DWORD,
                 ctypes.c_void_p, w.DWORD, w.DWORD, w.HANDLE)
CreateProcessW = fn(k32, "CreateProcessW", w.BOOL, w.LPCWSTR, w.LPWSTR,
                    ctypes.c_void_p, ctypes.c_void_p, w.BOOL, w.DWORD,
                    ctypes.c_void_p, w.LPCWSTR,
                    ctypes.POINTER(STARTUPINFOW),
                    ctypes.POINTER(PROCESS_INFORMATION))
CreateJobObjectW = fn(k32, "CreateJobObjectW", w.HANDLE, ctypes.c_void_p,
                      w.LPCWSTR)
SetInformationJobObject = fn(k32, "SetInformationJobObject", w.BOOL,
                             w.HANDLE, ctypes.c_int, ctypes.c_void_p,
                             w.DWORD)
QueryInformationJobObject = fn(k32, "QueryInformationJobObject", w.BOOL,
                               w.HANDLE, ctypes.c_int, ctypes.c_void_p,
                               w.DWORD, PDWORD)
AssignProcessToJobObject = fn(k32, "AssignProcessToJobObject", w.BOOL,
                              w.HANDLE, w.HANDLE)
TerminateJobObject = fn(k32, "TerminateJobObject", w.BOOL, w.HANDLE,
                        w.UINT)
ResumeThread = fn(k32, "ResumeThread", w.DWORD, w.HANDLE)
TerminateProcess = fn(k32, "TerminateProcess", w.BOOL, w.HANDLE, w.UINT)
WaitForSingleObject = fn(k32, "WaitForSingleObject", w.DWORD, w.HANDLE,
                         w.DWORD)
GetExitCodeProcess = fn(k32, "GetExitCodeProcess", w.BOOL, w.HANDLE,
                        PDWORD)
OpenProcess = fn(k32, "OpenProcess", w.HANDLE, w.DWORD, w.BOOL, w.DWORD)
QueryFullProcessImageNameW = fn(k32, "QueryFullProcessImageNameW", w.BOOL,
                                w.HANDLE, w.DWORD, w.LPWSTR, PDWORD)
CloseHandle = fn(k32, "CloseHandle", w.BOOL, w.HANDLE)


def note(text):
    """Write one [run_hidden] line to stderr."""
    sys.stderr.write(f"[run_hidden] {text}\n")
    sys.stderr.flush()


def object_name(handle):
    """The name of a window station or desktop."""
    buf = ctypes.create_unicode_buffer(256)
    GetUserObjectInformationW(handle, UOI_NAME, buf, ctypes.sizeof(buf),
                              None)
    return buf.value


def std_handle(which):
    """This process's stdin, stdout or stderr handle made inheritable, or
    an inheritable handle to NUL when it has none."""
    h = GetStdHandle(which)
    if h and h != INVALID_HANDLE and SetHandleInformation(
            h, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT):
        return h
    sa = SECURITY_ATTRIBUTES(ctypes.sizeof(SECURITY_ATTRIBUTES), None, True)
    return CreateFileW("NUL", GENERIC_READ_WRITE, FILE_SHARE_READ_WRITE,
                       ctypes.byref(sa), OPEN_EXISTING, 0, None)


def process_name(pid):
    """The executable name of a running process, or "?"."""
    h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not h:
        return "?"
    buf, size = ctypes.create_unicode_buffer(1024), w.DWORD(1024)
    ok = QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(size))
    CloseHandle(h)
    return os.path.basename(buf.value) if ok else "?"


def job_pids(job):
    """The IDs of the processes in the job."""
    info = JOBOBJECT_BASIC_PROCESS_ID_LIST()
    if not QueryInformationJobObject(job, JOB_BASIC_PROCESS_ID_LIST,
                                     ctypes.byref(info), ctypes.sizeof(info),
                                     None):
        return set()
    return set(info.ProcessIdList[:info.NumberOfProcessIdsInList])


def window_text(hwnd):
    """A window's text. WM_GETTEXT reads another process's controls too;
    SMTO_ABORTIFHUNG never waits on a hung window."""
    buf, result = ctypes.create_unicode_buffer(4096), ctypes.c_size_t()
    if not SendMessageTimeoutW(hwnd, WM_GETTEXT, len(buf), buf,
                               SMTO_ABORTIFHUNG, 500, ctypes.byref(result)):
        return ""
    return buf.value


def child_lines(hwnd):
    """The non-empty text lines of a window's child controls."""
    lines = []

    def child(h, _):
        text = window_text(h).strip()
        if text:
            lines.extend(text.splitlines())
        return True

    EnumChildWindows(hwnd, WNDENUMPROC(child), 0)
    return lines


def report_new_windows(desktop, job, seen):
    """Print each visible window on the desktop not reported yet, limited
    to the job's processes.

    Minimized windows are left out: with no foreground window on this
    desktop, every AutoHotkey script minimizes its own hidden main window
    at startup (source/script.cpp:641, :737).
    """
    pids = job_pids(job) if job else None
    found = []

    def top(hwnd, _):
        if (hwnd not in seen and IsWindowVisible(hwnd)
                and not IsIconic(hwnd)):
            found.append(hwnd)
        return True

    EnumDesktopWindows(desktop, WNDENUMPROC(top), 0)
    for hwnd in found:
        seen.add(hwnd)
        cls = ctypes.create_unicode_buffer(256)
        GetClassNameW(hwnd, cls, 256)
        pid = w.DWORD()
        GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if cls.value in CONSOLE_CLASSES or (
                pids is not None and pid.value not in pids):
            continue
        note(f'window opened: "{window_text(hwnd)}" ({cls.value}) by '
             f"{process_name(pid.value)} pid {pid.value}")
        for line in child_lines(hwnd)[:40]:
            note("  | " + line)


def make_job():
    """A job object that kills its processes when its handle closes, or
    None when one cannot be made."""
    job = CreateJobObjectW(None, None)
    if not job:
        return None
    basic = JOBOBJECT_BASIC_LIMIT_INFORMATION(
        LimitFlags=JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE)
    limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION(
        BasicLimitInformation=basic)
    if SetInformationJobObject(job, JOB_EXTENDED_LIMIT_INFORMATION,
                               ctypes.byref(limits), ctypes.sizeof(limits)):
        return job
    CloseHandle(job)
    return None


def start(command, desktop_path, job):
    """Start the command on the desktop and return (process, job), where
    job is None if the process could not join it; (None, None) when the
    command does not start. It starts suspended, so it is in the job
    before it runs."""
    stdin, stdout, stderr = (std_handle(n) for n in STD_HANDLES)
    si = STARTUPINFOW(cb=ctypes.sizeof(STARTUPINFOW), lpDesktop=desktop_path,
                      dwFlags=STARTF_USESTDHANDLES, hStdInput=stdin,
                      hStdOutput=stdout, hStdError=stderr)
    pi = PROCESS_INFORMATION()
    cmdline = ctypes.create_unicode_buffer(subprocess.list2cmdline(command))
    if not CreateProcessW(None, cmdline, None, None, True, CREATE_SUSPENDED,
                          None, None, ctypes.byref(si), ctypes.byref(pi)):
        note(f"could not start {command[0]} "
             f"(Win32 error {ctypes.get_last_error()})")
        if job:
            CloseHandle(job)
        return None, None
    if job and not AssignProcessToJobObject(job, pi.hProcess):
        note(f"no job object (Win32 error {ctypes.get_last_error()}); "
             "leftover processes are not killed")
        CloseHandle(job)
        job = None
    ResumeThread(pi.hThread)
    CloseHandle(pi.hThread)
    return pi, job


def wait_for(pi, desktop, job, timeout):
    """Wait for the process while reporting its windows; return its exit
    code, TIMED_OUT or INTERRUPTED."""
    seen = set()
    deadline = time.monotonic() + timeout if timeout > 0 else None
    code = None
    try:
        while WaitForSingleObject(pi.hProcess, 250) != 0:
            report_new_windows(desktop, job, seen)
            if deadline and time.monotonic() > deadline:
                note(f"timed out after {timeout:g} s; "
                     "killing the process tree")
                code = TIMED_OUT
                break
    except KeyboardInterrupt:
        note("interrupted; killing the process tree")
        code = INTERRUPTED
    report_new_windows(desktop, job, seen)
    if code is None:
        exit_code = w.DWORD()
        GetExitCodeProcess(pi.hProcess, ctypes.byref(exit_code))
        code = exit_code.value
    return code


def finish(pi, job, code):
    """Kill what the command left running, or its whole process tree after
    a timeout or Ctrl+C."""
    if job:
        for pid in sorted(job_pids(job) - {pi.dwProcessId}):
            note(f"killing leftover process {process_name(pid)} pid {pid}")
        TerminateJobObject(job, code)
        CloseHandle(job)
    elif code in (TIMED_OUT, INTERRUPTED):
        subprocess.run(["taskkill", "/PID", str(pi.dwProcessId), "/T", "/F"],
                       capture_output=True, check=False)
        TerminateProcess(pi.hProcess, code)
    CloseHandle(pi.hProcess)


def main():
    """Run the command line's COMMAND hidden and return its exit code."""
    parser = argparse.ArgumentParser(
        description="Run COMMAND on a hidden desktop.")
    parser.add_argument("--timeout", type=float, default=0,
                        help="kill the command's process tree after this "
                             "many seconds (default: none)")
    parser.add_argument("--desktop", default="ahk-hidden-test",
                        help="desktop name (default: %(default)s)")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    options = parser.parse_args()
    if not options.command:
        parser.error("no command given")

    command = list(options.command)
    command[0] = shutil.which(command[0]) or command[0]
    if command[0].lower().endswith((".cmd", ".bat")):
        command = [os.environ.get("ComSpec", "cmd.exe"), "/d", "/c", *command]

    desktop = CreateDesktopW(options.desktop, None, None, 0, GENERIC_ALL,
                             None)
    if not desktop:
        note(f"CreateDesktop failed (Win32 error {ctypes.get_last_error()})")
        return 1
    desktop_path = (object_name(GetProcessWindowStation()) + "\\"
                    + options.desktop)
    pi, job = start(command, desktop_path, make_job())
    if pi is None:
        CloseDesktop(desktop)
        return 1
    note(f"desktop {desktop_path}: pid {pi.dwProcessId} "
         f"{subprocess.list2cmdline(options.command)}")
    code = wait_for(pi, desktop, job, options.timeout)
    finish(pi, job, code)
    CloseDesktop(desktop)
    # An NTSTATUS exit code such as 0xC0000005 reaches sys.exit as a negative.
    return code - 2**32 if code > 0x7FFFFFFF else code


if __name__ == "__main__":
    sys.exit(main())
