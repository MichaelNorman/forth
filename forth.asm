%include "forth_internals.ninc"
%include "nasm_string.ninc"

section .data
    newline          db 10 ; newline character
    segment_size          dq SEGMENT_SIZE
    ;stdin_handle     dq 0
    ;stdout_handle    dq 0
    ;stderr_handle    dq 0
    ds_top           dq 0 ; top of empty stack,  the index where the next `push` operation will place an item.
    abort_state      db 0;
    conin             db "CONIN$", 0
    pre_msg           db "Getting ready to fail.", 10, 0
    abort_msg         db "Aborted. TOS = 0. Ready", 10, 0
    stdin_failed_msg  db "Failed to get stdin.", 10, 0
    stdout_failed_msg db "Failed to get stdout.", 10, 0
    read_failed_msg   db "Read failed.", 10, 0
    ok                db "Bytes read: %d. OK.", 10, 0
    prompt            db ":> ", 0
    bytes_read_fmt    db "Bytes read: %d", 10, 0
    crlf              db 0x0d, 0x0a, 0
    space_eoe         db " eoe "
    cycle_promptless  db 0
    test_message      db "Test message.", 10, 0
    str_newline       db 10, 0
section .bss
    num_bytes        resd 1
    write_count      resd 1
    old_mode         resd 1 ; place to hold the console mode before we reset it
    ds_base          resq 256
    input_buffer resb 256
    stdin_handle resq 1
    stdout_handle resq 1
    stderr_handle resq 1

section .text
    global main
    extern GetStdHandle
    extern ReadFile
    ;extern WriteFile
    extern printf
    extern puts
    extern GetLastError
    extern strcmp

main:
    push rbp
    mov rbp, rsp
    ; Free up some registers
    push r12
    push r13
    push r14
    push r15
    ; !!--------------ALIGNED------------------!!
    sub rsp, 32

    ; Set up stack ("First things first, but not necessarily in that order." -- Vigtor Borge)
    ; The following four lines move ds_base to the address at the end of its allocated space. This preserves 0-based
    ; indices if we do [rel ds_base - index * 8]
    lea r12, [rel ds_base] ; ds_base is "upside down" from our downward growing stack
    mov r8, DATA_STACK_LAST_INDEX ; the pseudo-size of the buffer, which will properly relocate ds_base
    shl r8, 3 ;calculate the pseudo-size of the  buffer
    add r14, r8 ; calculate the "base" of the downward-growing stack (effectively: base + size - 8)
    %undef ds_base ; reusing this could lead to subtle bugs or subtle corruption. r14 will contain the value for the
                   ; program lifetime.
    mov r15, 0
    %undef ds_top  ; reusing this could lead to subtle bugs or subtle corruption. r15 will contain the value for the
                   ; program lifetime

    ; get stdin
    mov ecx, GET_STDIN_HANDLE
    call GetStdHandle
    cmp rax, -1
    je .stdin_failed
    mov [rel stdin_handle], rax

    ; get stdout
    mov ecx, GET_STDOUT_HANDLE
    call GetStdHandle
    cmp rax, -1 ; valid?
    je .stdout_failed

    mov [rel stdout_handle], rax       ; stdout
    ;testing abort message logic
    or byte [rel abort_state], NO_ABORT
; This Forth interpreter will be "free-running," rather than count=based. Rather than checking for `\0' at every
; step, we mandate an end-of-execution, or EOE, word. This is an internal word that .quit: must add to evey line of
; input before calling the interpreter. If multiline entry mode is implemented later, the user will have to type the `f`
; word, euphemistically referred to as "the do character," to call Forth on the accumulated input. It is probably that
; the do character will be translated to the EOE word before the interpreter is called.

; The general algorithm for the initial case is then:
;   zero out the input_buffer
;   get a line of input at least 8 = 4 + len("eoe") + 1 bytes shorter than the buffer size, starting 4 bytes in
;   write the number of characters into the first four bytes
;   append "eoe" to it
;   fall through to .interpret: starting four bytes in
;   jump to .quit:
;
; The general algorithm for the fancypants case is then:
;   zero out the input buffer
;   get a line of input at least 8 = 4 + len("eoe") + 1 bytes shorter than the buffer size, starting 4 bytes in
;   check for trailing `f`, substitute eoe if `f` present and set interpret flag
;   write the adjusted number of characters into the first four bytes
;   .accumulate: starting four bytes in
;   jump to .quit: if interpret flag not set
;   fall through to .interpret:
;   zero out accumulator and reset pointer
;   jump to .quit:

.quit:
    ; print OK and the prompt
    cmp byte [rel cycle_promptless], 0
    mov byte [rel cycle_promptless], 0
    jne .promptless
    mov edx, [rel num_bytes]
    lea rcx, [rel ok]
    call printf
    lea rcx, [rel prompt]
    call printf
    .promptless:
    ; zero out input_buffer
    mov rdi, input_buffer ; load address of input_buffer
    ; get a line of input at least 8 = 4 + len("eoe") + 1 bytes shorter than the buffer size, starting 4 bytes in
    mov rcx, 256 ;
    xor eax, eax
    rep stosb
    ; set up for call to ReadFile
    ; set the current location in which to write the user's input
    mov rcx, [rel stdin_handle]     ; hFile
    lea rdx, [rel input_buffer]     ; lpBuffer
    mov r8d, 250                    ; nNumberOfBytesToRead: 256 - len(" eoe ") - len("\0")
    lea r9, [rel num_bytes]         ; lpNumberOfBytesRead
    sub rsp, 16
    mov qword [rsp + 0x20], 0              ; lpOverlapped, stored in first argument space
    call ReadFile
    add rsp, 16
    ; rax contains success or failure
    test rax, rax
    jz .read_failed          ; because reading failed

    ;mov eax, [rel num_bytes]
    ;mov edx, eax
    ;lea rcx, [rel bytes_read_fmt]
    ;call printf

    mov edx, [rel num_bytes]

    ; check to see if we have `\r\n`, replace with `\0\0` if we do. Update num_bytes if necessary
    mov eax, [rel num_bytes]
    lea rcx, [rel input_buffer]
    add rcx, rax
    sub rcx, 2
    lea rdx, [rel crlf]
    call strcmp
    test rax, rax
    jnz .skip_trim
    mov word [rcx], 0
    sub dword [rel num_bytes], 2

    ; lea rcx, [rel test_message]
    ; call printf
    .skip_trim:
    mov rax, [rel num_bytes]
    movsx rax, eax
    lea rcx, [rel input_buffer]
    add rcx, rax
    dec rcx
    cmp byte [rcx], 0x0d
    jnz .start_append_eoe
    mov byte [rcx], 0                      ; lop off `\n`
    sub dword [rel num_bytes], 1           ; adjust our endpoint
    mov byte [rel cycle_promptless], 1
    .start_append_eoe:
    xor r10, r10
    .append_loop:
    ; space_eoe i " eoe \0"
    cmp r10, 5
    jz .append_break
    lea r11, [rel space_eoe]
    add r11, r10
    movzx r11, byte [r11]
    lea r12, [rel input_buffer]
    add r12, r10
    add r12, [rel num_bytes]
    mov [r12], r11b
    ;mov [rel input_buffer + r10], r11b
    inc r10
    jmp .append_loop
    .append_break:
    lea rcx, [rel input_buffer]
    call printf
    lea rcx, [rel str_newline]
    call printf

    .interpret:
    ;lea rcx, [rel test_message]
    ;call printf
    jmp .quit
    ;mov rcx, [rel stdin_failed_msg]
    ;call puts


.abort:
    mov r15, 0 ; throw away the stack, but leave the values there.
    test byte [rel abort_state], NO_ABORT
    jnz .quit
    lea  rcx, [rel abort_msg]
    call puts
    and byte [rel abort_state], ~NO_ABORT

.read_failed:
    lea rcx, [rel read_failed_msg]
    call printf
    jmp .exit_main
.stdin_failed:
    lea rcx, [rel stdin_failed_msg]
    call puts
    jmp .exit_main
.stdout_failed:
    lea rcx, [rel stdout_failed_msg]
    call puts
    jmp .exit_main

.pick:
    ;N how far back to pick. 0 is dup. 1 picks 2nd from top. ... r8
    _underflow r8
    mov rax, 1
    _overflow rax
    _unchecked_get_relative r8, rax
    _push rax, r13

.dup:
    ;N number of items to check post.  r8
    ;M 'min' address                   r9
    ;I index, unscaled                 r10
    ;E end of stack.                   r11
    ;R resume point.                   r12
    _underflow r8
    _overflow r8
     ; (index_reg, back_reg, ds_base_reg, output_reg)
     ;mov
    _unchecked_get_relative r8, rax
    _push r8, rax ; use r13 for scratch space
    ;jmp .next_word

.swap:
    ; ensure there 2 things to swap
    mov r13, 2
    _underflow r13
    ; (back_reg, output_reg, addr_scratch_reg)
    mov r8, 0
    _unchecked_get_relative r8, rax
    inc r8
    _unchecked_get_relative r8, r9

    ; (back_reg, input_reg, addr_scratch_reg)
    _unchecked_set_relative r8, rax, r13
    dec r8
    _unchecked_set_relative r8, r9, r13
    ;jmp .next_word

.plus:
    mov r13, 2
    _underflow r13
    ; (output_reg, scratch_reg)
    _pop rax, r13
    _pop r8, r13
    add rax, r8
    ;(input_reg, offset_scratch_reg)
    _push rax, r13

.drop:
    mov r13, 1
    _underflow r13
    dec r15

.nip:
    mov r13, 2
    _underflow r13
    mov r13, r15
    dec r13
    shl r13, 3
    mov r12, r14
    sub r12, r13
    mov r11, [r12]
    sub r12, 8
    mov [r12], r11
    dec r15

.over: ; ( x1 x2 -- x1 x2 x1 )
    mov r13, 2
    ;_udnderflow r13
    mov r13, 1
    _overflow r13
    ;_unchecked_get_relative


.tuck: ;( x1 x2 -- x2 x1 x2 )
    mov r13, 2
    ;_udnderflow r13
    mov r13, 1
    _overflow r13 ; TODO: UNFINISHED

.data_stack_underflow:
    jmp .exit_main

.data_stack_overflow:
    jmp .exit_main

.exit_main:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    ret
