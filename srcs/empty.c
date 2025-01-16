#include <stdlib.h>

int _start()
{
asm volatile
    (
 "mov rax, 60\n"
"mov rdi, 0\n"
"syscall\n"
    );
}