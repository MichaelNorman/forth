;constants
BITS 64
STD_INPUT_HANDLE       equ -10
STD_OUTPUT_HANDLE      equ -11
INPUT_BUFFER_SIZE      equ 256
READ_CHUNK             equ 254   ; leave room to append '\n' or NULL, as appropriate. cf. input_buffer
LINE_SIZE  equ 8
LINES_PER_BLOCK  equ 16
BLOCK_SIZE equ LINE_SIZE * LINES_PER_BLOCK
BLOCKS_PER_SEGMENT equ 64
SEGMENT_SIZE equ BLOCK_SIZE * BLOCKS_PER_SEGMENT
DATA_STACK_SIZE equ 1024
CELL_SIZE equ 8

;word flags and mask
%define f8PRIMITIVE 0b10000000
%define f8IMMEDIATE 0b01000000
%define m8WORD_LEN  0b00001111

;word data bit pattern
;|mask(4 bits):len(4 bits)|word (120)|code_pointer(32)/previous_pointer(32)/pad(64)|
;^--------------qword----------------^---------------dword-----------------^-dword-^
;^--------------qword----------------^-------------------qword---------------------^
%define WORD_SIZE_BYTE 16
%define WORD_SIZE_BIT  128

section .data
    newline db 10 ; newline character
    conin db "CONIN$", 0

section .bss
    input_buffer resb INPUT_BUFFER_SIZE ; reserve more than enough for a long one-liner. cf. READ_CHUNK
    num_bytes resd 1
    write_count resd 1
    old_mode resd 1
    segment resb SEGMENT_SIZE
    data_stack_min resq DATA_STACK_SIZE
    data_stack_max resq 1
    ds_index resd 1

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
    mov dword [ds_index], -8 ; The first invalid 64-bit offset.
    mov rax, [data_stack_min] ; data_stack_min is "upside down" from our downward growing stack
    mov [data_stack_max], rax ; so stuff it into data_stack_max. (Numerically the lowest address, but forget that!)
    add rax, DATA_STACK_SIZE * 8 ; get the start of the stack into the register
    mov [data_stack_min], rax ; data_stack_min now contains the address at the bottom of the logical stack.
    ; get stdin
    mov ecx, STD_INPUT_HANDLE
    call GetStdHandle
    cmp rax, -1
    je .stdin_failed
    mov r12, rax       ; stdin
    ; get stdout
    mov ecx, STD_OUTPUT_HANDLE

    call GetStdHandle

    cmp rax, -1
    je .stdout_failed
    mov r13, rax       ; stdout

    ;lea r14, [rel input_buffer] ; load location of input_buffer for later

.line_loop:
    ; zero out input_buffer
    mov rdi, input_buffer ; load address of input_buffer
    mov rcx, 256 ;
    xor eax, eax
    rep stosb
    ; set up for call to ReadFile
    ; set the current location in which to write the user's input
    mov rcx, r12              ; hFile
    lea rdx, [rel input_buffer]     ; lpBuffer
    mov r8d, READ_CHUNK       ; nNumberOfBytesToRead
    lea r9, [rel num_bytes]   ; lpNumberOfBytesRead
    sub rsp, 16
    mov qword [rsp], 0        ; lpOverlapped, stored in first argument space
    call ReadFile
    add rsp, 16
    ;int3
    ; rax contains success or failure
    test rax, rax
    je .read_failed          ; because reading failed
    ;int3
    lea rdx, [rel num_bytes]
    ; TODO: the following never works. Figure out why.
    cmp dword [rdx], 0
    je .read_failed          ; because user pressed ENTER without any input

    ; read succeeded and input_buffer, whose address is stored in r14, holds num_bytes characters
    mov eax, [rel num_bytes]
    lea rcx, [rel input_buffer]
    ; we're now pointing at the current line.

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

.dup:
    mov ecx, [ds_index]
    ; ensure there's something to read.
    cmp ecx, 0
    ; ensure no underflow
    jl .data_stack_underflow
    ; ensure no overflow
    ; calculate current stack pointer
    ; increment to the next place we want to write
    add ecx, CELL_SIZE
    mov qword rax, [data_stack_min]
    sub rax, ecx
    ;rax is now where we want to write
    mov rdx, [data_stack_max]
    ;rdx now has the lowest allowable address
    cmp rax, rdx
    jl .stack_overflow

    ;rax is at top + 1, so add 1 to get back to top
    add rax, CELL_SIZE
    mov rcx, [rax]

    ; copy top int top + 1
    sub rax, CELL_SIZE
    mov [rax], rcx
    ; ensure index is incremented
    ; put

    jmp .next_word

.exit_main:
    pop r15
    pop r14
    pop r13
    pop r12
    add rsp, 32
    pop rbp
    ret
