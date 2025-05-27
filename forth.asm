%include "forth_internals.ninc"

section .data
    newline          db 10 ; newline character
    conin            db "CONIN$", 0
    segment          dq SEGMENT_SIZE
    ;ds_base          dq DATA_STACK_SIZE
    stdin_handle     dq 0
    stdout_handle    dq 0
    stderr_handle    dq 0
    ds_top           dq 0 ; top of empty stack

section .bss
    num_bytes        resd 1
    write_count      resd 1
    old_mode         resd 1
    ds_base          resq DATA_STACK_SIZE
    input_buffer     resq INPUT_BUFFER_SIZE

section .text
    global main
    extern GetStdHandle
    extern ReadFile
    ;extern WriteFile
    extern printf
    extern GetLastError
main:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    push r12
    push r13
    push r14
    push r15


    ; set up stack (First things first, but not necessarily in that order. -- Vigtor Borge)
    ; The following four lines move ds_base to the address at the end of its allocated space. This preserves 0-based
    ; indices if we do [rel ds_base - index * CELL_SIZE]
    mov r12, ds_base ; ds_base is "upside down" from our downward growing stack
    mov r8, DATA_STACK_LAST_INDEX
    shl r8, 3
    add r14, r8
    %undef ds_base ; reusing this could lead to subtle bugs or subtle corruption. r14 will contain the value for the
                   ; program lifetime.
    mov r15, [rel ds_top]
    %undef ds_top  ; reusing this could lead to subtle bugs or subtle corruption. r15 will contain the value for the
                   ; program lifetime

    ; get stdin
    mov ecx, STD_INPUT_HANDLE
    call GetStdHandle
    cmp rax, -1
    je .stdin_failed
    mov [rel stdin_handle], rax       ; stdin
    ; get stdout
    mov ecx, STD_OUTPUT_HANDLE

    call GetStdHandle

    cmp rax, -1
    je .stdout_failed
    mov [rel stdout_handle], rax       ; stdout

.line_loop:
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
    lea rdx, [rel num_bytes]
    ; TODO: the following never works. Figure out why.
    cmp rdx, 0
    je .read_failed          ; because user pressed ENTER without any input

    mov eax, [rel num_bytes]
    lea rcx, [rel input_buffer]
    ; we're now pointing at the current line.
    .next_word:

    sub rsp, 16
    call printf
    add rsp, 16
    jmp .line_loop

.read_failed:
    jmp .exit_main
.stdin_failed:
    jmp .exit_main
.stdout_failed:
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
