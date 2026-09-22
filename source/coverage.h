#ifndef coverage_h
#define coverage_h

#include <windows.h>

class Line;

// Line coverage for scripts, enabled by /Coverage=<path>.
//
// "Lines found" come from the parsed Line list (every module chain), so the
// parser is the source of truth for what counts as executable.  "Lines hit"
// are counted at the same points where the debugger's per-line hook fires.
// The report is written in LCOV tracefile format (SF/DA/LF/LH/end_of_record)
// and rewritten in full on every flush, so a crash still leaves the data
// gathered up to that point.
namespace Coverage
{
	// Enables collection.  Accepts a caller-owned string; a relative path is
	// resolved against the working directory *now*, before the script can
	// change it.
	void SetPath(LPCTSTR aPath);
	bool IsEnabled();

	// Record one execution of a source line.  Hot path; callers gate on
	// g_CoverageEnabled so the disabled case costs a single predictable branch.
	void Hit(WORD aFileIndex, UINT aLineNumber);
	// Same, from ExecUntil's per-line dispatch: skips structural lines (braces,
	// else/catch/finally/case) and While, which PerformLoopWhile counts per iteration.
	void HitLine(Line *aLine);

	// Write the LCOV report. Normal exit uses a synchronized snapshot. Signal and
	// fatal handlers use best-effort mode: skip a busy/unprepared collector rather
	// than waiting on a thread which may be suspended or faulting while holding it.
	void Flush(bool aBestEffort = false);
}

extern bool g_CoverageEnabled;

#endif
