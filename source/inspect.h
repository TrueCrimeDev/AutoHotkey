#pragma once

// Script-free structured description. The caller frees the returned JSON
// string with free(); nullptr indicates allocation failure.
LPTSTR InspectValue(ExprTokenType &aValue, int aDepth, int aMaxItems);
