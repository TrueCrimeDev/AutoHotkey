/* Windows x64 dynamic function call - GAS-compatible port for mingw.
 * Mirrors x64call.asm (MASM) function-for-function. Unwind directives are
 * omitted because GAS doesn't accept MASM's `proc frame` form; SEH-based
 * exception handling for these stubs is unavailable in the mingw build.
 *
 * Functions: PerformDynaCall, DynaCall, GetFloatRetval, GetDoubleRetval.
 * Calling convention: Microsoft x64 (rcx, rdx, r8, r9 + xmm0..xmm3).
 */

.intel_syntax noprefix
.text

.global PerformDynaCall
.global DynaCall
.global GetFloatRetval
.global GetDoubleRetval

/* Arguments:
 *   rcx: size of arguments to be passed via stack
 *   rdx: pointer to arguments to be passed via stack
 *   r8:  pointer to arguments to be passed by registers
 *   r9:  target function pointer
 */
PerformDynaCall:
    push rbp
    push rsi
    push rdi
    mov rbp, rsp

    /* Setup stack frame by subtracting the size of the arguments. */
    sub rsp, rcx

    /* Ensure the stack is 16-byte aligned. */
    mov rax, rcx
    and rax, 15
    mov rsi, 16
    sub rsi, rax
    sub rsp, rsi

    /* Save function address. */
    mov rax, r9

    /* Copy the stack arguments. */
    mov rsi, rdx
    mov rdi, rsp
    rep movsb

    /* Copy the register arguments. */
    mov rcx,  qword ptr [r8]
    mov rdx,  qword ptr [r8+ 8]
    mov r9,   qword ptr [r8+24]
    mov r8,   qword ptr [r8+16]
    movq xmm0, rcx
    movq xmm1, rdx
    movq xmm2, r8
    movq xmm3, r9

    /* Call function. */
    sub rsp, 8*4
    call rax

    /* Restore stack pointer. */
    lea rsp, [rbp]

    pop rdi
    pop rsi
    pop rbp
    ret

/* Arguments:
 *   rcx: number of QWORDs to be passed as arguments
 *   rdx: pointer to arguments
 *   r8:  target function pointer
 *   r9:  not used
 */
DynaCall:
    push rbp
    push rsi
    push rdi
    mov rbp, rsp

    /* Setup stack frame by subtracting max(num_args, 4) * 8. */
    mov rax, 4
    cmp rax, rcx
    cmovl rax, rcx
    shl rax, 3
    sub rsp, rax

    /* Ensure the stack is 16-byte aligned. */
    and rsp, -16

    /* Save function address. */
    mov rax, r8

    /* Copy all arguments to the stack (for simplicity, includes register args). */
    mov rsi, rdx
    mov rdi, rsp
    rep movsq

    /* Copy the register arguments. */
    mov rcx,  qword ptr [rsp]
    mov rdx,  qword ptr [rsp+ 8]
    mov r8,   qword ptr [rsp+16]
    mov r9,   qword ptr [rsp+24]
    movq xmm0, rcx
    movq xmm1, rdx
    movq xmm2, r8
    movq xmm3, r9

    /* Call function. */
    call rax

    /* Restore stack pointer. */
    lea rsp, [rbp]

    pop rdi
    pop rsi
    pop rbp
    ret

/* No body needed; the C++ side declares the proper return type and the
 * x64 ABI keeps the float/double result in xmm0 across the bare ret. */
GetFloatRetval:
    ret

GetDoubleRetval:
    ret
