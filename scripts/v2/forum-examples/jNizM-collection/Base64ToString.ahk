; =============================================================================================================================================================
; Author ........: jNizM
; Released ......: 2021-04-23
; Modified ......: 2023-01-12
; Tested with....: AutoHotkey v2.0.2 (x64)
; Tested on .....: Windows 11 - 22H2 (x64)
; Function ......: Base64ToString( Base64 )
;
; Parameter(s)...: Base64 - the base64 string to convert
;
; Return ........: Converts a base64 string to a readable string.
; =============================================================================================================================================================

#Requires AutoHotkey v2.0

Base64ToString(Base64)
{
	static CRYPT_STRING_BASE64 := 0x00000001

	if !(DllCall("crypt32\CryptStringToBinaryW", "Str", Base64, "UInt", 0, "UInt", CRYPT_STRING_BASE64, "Ptr", 0, "UInt*", &Size := 0, "Ptr", 0, "Ptr", 0))
		throw OSError()

	String := Buffer(Size)
	if !(DllCall("crypt32\CryptStringToBinaryW", "Str", Base64, "UInt", 0, "UInt", CRYPT_STRING_BASE64, "Ptr", String, "UInt*", Size, "Ptr", 0, "Ptr", 0))
		throw OSError()

	return StrGet(String, "UTF-8")
}


; =============================================================================================================================================================
; Example
; =============================================================================================================================================================

MsgBox Base64ToString("VGhlIHF1aWNrIGJyb3duIGZveCBqdW1wcyBvdmVyIHRoZSBsYXp5IGRvZw==")
