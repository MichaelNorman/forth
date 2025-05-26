cmake_minimum_required(VERSION 3.25)
project(ForthASM C)  # <- "C" required to set a linker language

set(SRC_FILE ${CMAKE_SOURCE_DIR}/forth.asm)
set(OBJ_FILE ${CMAKE_BINARY_DIR}/forth.obj)

# Build the object file from NASM source
add_custom_command(
        OUTPUT ${OBJ_FILE}
        COMMAND nasm -I ${CMAKE_SOURCE_DIR} -f win64 ${SRC_FILE} -o ${OBJ_FILE}
        DEPENDS ${SRC_FILE}
        COMMENT "Assembling ${SRC_FILE}"
)

# Create a dummy C file to satisfy the linker and enable C as the linker language
file(WRITE ${CMAKE_BINARY_DIR}/dummy.c "\n")

# Add executable from object file
add_executable(forth ${OBJ_FILE} ${CMAKE_BINARY_DIR}/dummy.c) # ${CMAKE_SOURCE_DIR}/shim.c)


target_link_libraries(forth PRIVATE kernel32)
