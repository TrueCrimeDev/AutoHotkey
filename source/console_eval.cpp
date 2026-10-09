#include "stdafx.h"
#include "script.h"
#include "globaldata.h"
#include "abi.h"
#include "console_eval.h"
#include <memory>

// Shared by the Eval BIF and the REPL (Script::ReplDrainInput).  Evaluates aExpression
// against aScope (nullptr = global scope) and stores the value in aRetVal.  On failure
// an AHK exception is left in g->ThrownToken and a failed FResult is returned.
FResult ConsoleEval::Evaluate(LPCTSTR aExpression, UserFunc *aScope, ResultToken &aRetVal)
{
	UserFunc *caller = aScope;

	// Use the loader's line-size limit before entering parser code which uses
	// token-count-dependent stack storage. Oversized input must remain catchable.
	size_t len = _tcslen(aExpression);
	if (len >= LINE_SIZE)
		return FValueError(_T("Eval expression exceeds the 16384-character limit."));
	// Parsing modifies the text. Own one temporary heap copy instead of placing
	// two copies of arbitrary caller input on the native stack.
	std::unique_ptr<TCHAR, decltype(&free)> buf((LPTSTR)malloc((len + 1) * sizeof(TCHAR)), free);
	if (!buf)
		return FR_E_OUTOFMEM;
	_tcscpy(buf.get(), aExpression);

	Line *scratch = nullptr;
	if (g_script.ParseExprToPostfix(buf.get(), caller, scratch) != OK)
	{
		// The parser reports failure through ScriptError, which (inside try, or with OnError)
		// leaves a generic Error in g->ThrownToken.  Rebuild it as a SyntaxError through
		// CreateRuntimeException so that What, Extra and Stack are filled the same way as
		// for every other runtime error, then apply the Eval-specific File, Line and Column.

		// 1) Take the Message and Extra of any pre-existing thrown exception.  Holding a
		// reference keeps those strings valid after the token is freed, until the new
		// exception has copied them.
		LPCTSTR msg = _T("Invalid expression");
		LPCTSTR extra = nullptr;
		Object *prev = nullptr;
		if (g->ThrownToken)
		{
			if (g->ThrownToken->symbol == SYM_OBJECT)
				prev = dynamic_cast<Object*>(g->ThrownToken->object);
			if (prev)
			{
				prev->AddRef();
				LPTSTR prev_msg = prev->GetOwnPropString(_T("Message"));
				if (prev_msg && *prev_msg)
					msg = prev_msg;
				extra = prev->GetOwnPropString(_T("Extra"));
			}
			// 2) Free the old exception (clears g->ThrownToken).
			g_script.FreeExceptionToken(g->ThrownToken);
		}

		// 3) Build the SyntaxError the way the engine builds any runtime error: Error.__New
		// sets Message, What (the throwing BIF, i.e. Eval), Extra, File, Line and Stack.
		Line *line = g_script.mCurrLine;
		auto *err = dynamic_cast<Object*>(line->CreateRuntimeException(msg, extra, ErrorPrototype::Syntax));
		if (prev)
			prev->Release();
		if (!err)
			return g->ThrownToken ? FR_FAIL : FR_E_OUTOFMEM; // __New threw, or Object::Create failed.
		err->SetOwnProp(_T("File"),    _T("_Eval"));
		err->SetOwnProp(_T("Line"),    (__int64)0);
		err->SetOwnProp(_T("Column"),  (__int64)0);

		// 4) Throw it (mirrors BIF_Throw pattern).
		ResultToken *token = new ResultToken;
		token->symbol = SYM_OBJECT;
		token->object = err; // CreateRuntimeException returns refcount=1; token owns it.
		token->mem_to_free = nullptr;
		line->SetThrownToken(*g, token, FAIL);
		return FR_FAIL;
	}

	// ACT_EXPRESSION causes ExpandExpression to discard the final result (it's designed
	// for stand-alone side-effect expressions). Use ACT_SWITCH instead: it has no special
	// handling in ExpandExpression, so the result flows through into aResultToken.
	scratch->mActionType = ACT_SWITCH;

	// Privatize Line::sDerefBuf so that any function calls made during evaluation
	// (e.g. StrLen(), user-defined functions) can safely allocate their own deref
	// buffers without corrupting the outer evaluation layer's buffer.  This mirrors
	// what ExecUntil's ACT_SWITCH handler does before calling ExpandSingleArg().
	PRIVATIZE_S_DEREF_BUF;

	// Evaluate the scratch Line's mArg[0] postfix using ExpandSingleArg,
	// which is the same thin wrapper used by the Switch/For machinery.
	ResultToken eval_result;
	eval_result.mem_to_free = nullptr;

	ResultType eval_status = scratch->ExpandSingleArg(0, eval_result, our_deref_buf, our_deref_buf_size);

	if (eval_status != OK)
	{
		DEPRIVATIZE_S_DEREF_BUF;
		if (eval_result.mem_to_free)
			free(eval_result.mem_to_free);
		return FR_FAIL; // AHK exception already propagated (e.g. thrown object).
	}

	// Transfer the result into aRetVal BEFORE calling DEPRIVATIZE, because a
	// string result with mem_to_free==nullptr may point into our_deref_buf, which
	// DEPRIVATIZE may free or return to the outer layer (making the pointer stale).
	FResult fret = OK;
	if (eval_result.symbol == SYM_OBJECT)
	{
		// ExpandSingleArg already AddRef'd the object for eval_result.
		// Transfer ownership to aRetVal (no extra AddRef, no Release).
		aRetVal.symbol = SYM_OBJECT;
		aRetVal.object = eval_result.object;
		// eval_result.mem_to_free is always nullptr for objects.
	}
	else if (eval_result.symbol == SYM_STRING)
	{
		if (eval_result.mem_to_free)
		{
			// The string is already in heap memory. Transfer ownership to aRetVal
			// so it will be freed by the caller via the normal ResultToken::Free path.
			aRetVal.AcceptMem(eval_result.mem_to_free, eval_result.marker_length);
			eval_result.mem_to_free = nullptr; // ownership transferred
		}
		else
		{
			// The string may be in our_deref_buf (not yet freed) or in persistent
			// storage (variable contents, literal). Copy it into aRetVal now,
			// while our_deref_buf is still valid.
			size_t slen = (eval_result.marker_length != (size_t)-1)
				? eval_result.marker_length
				: _tcslen(eval_result.marker);
			if (!aRetVal.Malloc(eval_result.marker, slen))
				fret = FR_FAIL; // MemoryError already set; free buffer below.
		}
	}
	else
	{
		// Integer, float, unset, etc. — a plain value copy is sufficient.
		aRetVal.CopyValueFrom(eval_result);
	}

	// Restore the outer deref buffer now that we've copied everything we need
	// out of our_deref_buf. DEPRIVATIZE frees any inner buffer and restores the
	// saved outer one (or keeps a new buffer if the original was NULL).
	DEPRIVATIZE_S_DEREF_BUF;

	return fret;
}



bif_impl FResult Eval(StrArg aExpression, ResultToken &aRetVal)
{
	if (!g_AllowEval)
		return FError(_T("Eval is disabled (add #EnableEval to your script or pass /Eval)"));

	// Resolve scope from the caller's UserFunc (if any) so that local variables
	// referenced in the expression are resolved correctly.
	return ConsoleEval::Evaluate(aExpression, g->CurrentFunc, aRetVal);
}
