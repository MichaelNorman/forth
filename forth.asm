%include "forth_internals.ninc"

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
    handle_fmt        db "GetStdHandle returned: %llx", 10, 0
    last_error_fmt    db "Last error code was: %lu", 10, 0

section .bss
    num_bytes        resd 1
    write_count      resd 1
    old_mode         resd 1 ; place to hold the console mode before we reset it
    ds_base          resq DATA_STACK_SIZE
    input_buffer     resq INPUT_BUFFER_SIZE
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

main:
    push rbp
    mov rbp, rsp
    ; Free up some registers
    push r12
    push r13
    push r14
    push r15
    ; reserve shadow space
    sub rsp, 32

    ; set up stack (First thins first, but not necessarily in that order. -- Vigtor Borge)
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
    ; THE FOLLOWING LINES SUCCEED
    lea rcx, [rel pre_msg]
    call puts
    ; get stdin
    mov ecx, GET_STDIN_HANDLE
    call GetStdHandle
    call GetLastError
    lea rcx, [rel last_error_fmt]
    mov rdx, rax
    call printf
    cmp rax, -1
    je .stdin_failed
    lea rcx, [rel handle_fmt]
    mov rdx, rax
    call printf

    ;default rel
    ; THE FOLLOWING LINE FAILS
    mov [rel stdin_handle], rdx       ; stdin
    ; THE FOLLOWING LINES NEVER RUN
    lea rcx, [rel abort_msg]
    call puts

    ; get stdout
    mov ecx, GET_STDOUT_HANDLE
    call GetStdHandle

    cmp rax, -1 ; valid?
    je .stdout_failed

    mov [rel stdout_handle], rax       ; stdout
    lea rcx, [rel abort_msg]
    call puts
    ;testing abort message logic
    or byte [rel abort_state], NO_ABORT

.abort:
    mov r15, 0 ; throw away the stack, but leave the values there.
    test byte [rel abort_state], NO_ABORT
    jnz .quit
    lea  rcx, [rel abort_msg]
    call puts
    and byte [rel abort_state], ~NO_ABORT

.quit:
    ; zero out input_buffer
    mov rdi, input_buffer ; load address of input_buffer
    mov rcx, 256 ;
    xor eax, eax
    rep stosb
    ; set up for call to ReadFile
    ; set the current location in which to write the user's input
    mov rcx, [rel stdin_handle]     ; hFile
    lea rdx, [rel input_buffer]     ; lpBuffer
    mov r8d, READ_CHUNK             ; nNumberOfBytesToRead
    lea r9, [rel num_bytes]         ; lpNumberOfBytesRead
    sub rsp, 16
    mov qword [rsp], 0              ; lpOverlapped, stored in first argument space
    call ReadFile
    add rsp, 16
    ;int3
    ; rax contains success or failure
    test rax, rax
    je .read_failed          ; because reading failed
    ;int3
    mov rdx, [rel num_bytes] ; TODO: test this. Went from `lea`to `mov`
    cmp rdx, 0
    je .read_failed          ; because user pressed ENTER without any input

    ; TODO: Rework this into Forth's `auit` loop.
    ;jmp .quit

    sub rsp, 16
    call printf
    add rsp, 16
    ;jmp .line_loop ; TODO: Rework this into Forth's `auit` loop.

.read_failed:
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
    pop r15
    pop r14
    pop r13
    pop r12
    add rsp, 32
    pop rbp
    ret
