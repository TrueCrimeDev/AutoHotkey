/* Windows x64 RegisterCallback stub - GAS-compatible port for mingw.
 * Mirrors x64stub.asm (MASM). MASM unwind directives are omitted (GAS
 * doesn't accept `proc frame`); SEH unwind for this stub is unavailable
 * in the mingw build but the call sequence itself is unchanged.
 */

.intel_syntax noprefix
.text

.global RegisterCallbackAsmStub

/* Offsets must match the C++ side (RCCallbackFunc layout). */
.set CallbackFunctionOffset, 8*3

RegisterCallbackAsmStub:
    /* For the 'mov' further below. */
    add rsp, 8

    /* Save the parameters in the spill area for consistency. */
    mov qword ptr [rsp+8*0], rcx
    mov qword ptr [rsp+8*1], rdx
    mov qword ptr [rsp+8*2], r8
    mov qword ptr [rsp+8*3], r9

    /* Set parameters for the upcoming function call. */
    mov rcx, rsp        /* UINT_PTR* aParams */
    mov rdx, rax        /* RCCallbackFunc* cbAddress */

    /* Call callback stub function. */
    sub rsp, 8*6
    call qword ptr [rax+CallbackFunctionOffset]
    add rsp, 8*5

    ret
