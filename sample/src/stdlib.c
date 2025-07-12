#include "stdlib.h"

void abort(void)
{
    for (;;)
    {
        __asm__ ("hlt");
    }
}