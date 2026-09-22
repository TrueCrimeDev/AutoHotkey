#pragma once

#include "script.h"

namespace ConsoleEval
{
// Shared evaluator for the opt-in BIF and the REPL. Input is limited to
// LINE_SIZE - 1 (16384) UTF-16 code units before entering the native parser.
FResult Evaluate(LPCTSTR aExpression, UserFunc *aScope, ResultToken &aRetVal);
}
