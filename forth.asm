%include "forth_internals.ninc"
;constants
BITS 64
STD_INPUT_HANDLE       equ -10
STD_OUTPUT_HANDLE      equ -11
INPUT_BUFFER_SIZE      equ 256
READ_CHUNK             equ 254   ; leave room to append '\n' or NULL, as appropriate. cf. input_buffer
%define LINE_SIZE 8
%define LINES_PER_BLOCK  16
%define BLOCK_SIZE 128
%define BLOCKS_PER_SEGMENT 64
%define SEGMENT_SIZE 8192
%define DATA_STACK_SIZE 1024
%define CELL_SIZE 8

;word flags and mask
%define f8PRIMITIVE 0b10000000
%define f8IMMEDIATE 0b01000000
%define m8WORD_LEN  0b00001111

;word data bit pattern
;|mask(4 bits):len(4 bits)|word (120)|code_pointer(32)/previous_pointer(32)/pad(64)|
;^--------------qword----------------^---------------dword-----------------^-dword-^
;^--------------qword----------------^-------------------qword---------------------^
%define              WORD_SIZE_BYTE 16
%define              WORD_SIZE_BIT  128

section .data
    newline          db 10 ; newline character
    conin            db "CONIN$", 0
    segment          dq SEGMENT_SIZE
    data_stack_min   dq DATA_STACK_SIZE
    input_buffer     dq INPUT_BUFFER_SIZE
    stdin_handle     dq 0
    stdout_handle    dq 0
    stderr_handle    dq 0

section .bss
    num_bytes        resd 1
    write_count      resd 1
    old_mode         resd 1
    data_stack_max   resq 1
    ds_index         resd 1

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
    mov dword [rel ds_index], -8 ; The first invalid 64-bit offset.
    mov rax, [rel data_stack_min] ; data_stack_min is "upside down" from our downward growing stack
    mov [rel data_stack_max], rax ; so stuff it into data_stack_max. (Numerically the lowest address, but forget that!)
    add rax, DATA_STACK_SIZE * 8 ; get the start of the stack into the register
    mov [rel data_stack_min], rax ; data_stack_min now contains the address at the bottom of the logical stack.
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

    ;lea r14, [rel input_buffer] ; load location of input_buffer for later

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

    ; read succeeded and input_buffer, whose address is stored in r14, holds num_bytes characters
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
    ;N how far back to pick. 1 is dup. 2 picks 2nd from top. ... r8
    ;
    ;mov r8, n
    ;cmp r8,
.dup:
    ;N number of items to check post.  r8
    ;M 'min' address                   r9
    ;I index, unscaled                 r10
    ;E end of stack.                   r11
    ;R resume point.                   r12
    mov ecx, [rel ds_index]
    ; ensure there's something to read.
    cmp ecx, 0
    ; ensure no underflow
    jl .data_stack_underflow
    ; ensure no overflow
    ; calculate current stack pointer
    ; increment to the next place we want to write
    add ecx, CELL_SIZE
    lea rax, [rel data_stack_min]
    sub rax, rcx
    ;rax is now where we want to write
    lea rdx, [rel data_stack_max]
    ;rdx now has the lowest allowable address
    cmp rax, rdx
    jl .data_stack_overflow

    ;rax is at top + 1, so add 1 to get back to top
    add rax, CELL_SIZE
    mov  rcx, [rax]

    ; copy top int top + 1
    sub rax, CELL_SIZE
    mov [rax], rcx

    jmp .next_word

.swap:
    ; ensure there are two things to read
    mov rcx, [rel ds_index]
    cmp rcx, 8
    jl .data_stack_underflow

    lea rax, [rel data_stack_min]
    mov rdx, rax
    sub rax, rcx ; TOS address
    add rcx, CELL_SIZE
    sub rdx, rcx ; TOS - 1 address

    mov r8, [rax]
    mov r9, [rdx]
    mov [rdx], r8
    mov [rax], r9
    jmp .next_word

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
