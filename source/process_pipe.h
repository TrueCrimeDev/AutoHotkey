#pragma once

#include "child_process.h"

// ProcessPipe(Command, Args?, WorkingDir?) -- a child process with UTF-8
// stdin/stdout/stderr pipes, held in a job so releasing the object (or
// calling Kill) terminates the whole tree.
class ProcessPipe : public Object
{
	ChildProcess mChild;

	FResult WaitFor(optl<double> aTimeout, bool (ProcessPipe::*aDone)());
	bool LineReady();
	bool DataReady();
	bool Exited();

public:
	static Object *sPrototype;
	static ObjectMemberMd sMembers[];
	static int sMemberCount;

	ProcessPipe() { SetBase(sPrototype); }

	FResult __New(StrArg aCommand, ExprTokenType *aArgs, optl<StrArg> aWorkingDir);

	FResult Send(StrArg aText, optl<double> aTimeout);
	FResult SendLine(StrArg aText, optl<double> aTimeout);
	FResult ReadLine(optl<double> aTimeout, StrRet &aRetVal);
	FResult Read(optl<double> aTimeout, StrRet &aRetVal);
	FResult ReadStdErr(StrRet &aRetVal);
	FResult Wait(optl<double> aTimeout, int &aRetVal);
	FResult Kill();
	FResult Close();

	FResult get_PID(int &aRetVal) { aRetVal = (int)mChild.Pid(); return OK; }
	FResult get_ExitCode(int &aRetVal);
	FResult get_Running(BOOL &aRetVal) { aRetVal = mChild.Started() && !mChild.HasExited(); return OK; }
	FResult get_AtEOF(BOOL &aRetVal);
};
