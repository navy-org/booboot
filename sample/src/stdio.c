#define STB_SPRINTF_IMPLEMENTATION
#define STB_SPRINTF_NOFLOAT
#define STB_SPRINTF_NOUNALIGNED

#include <stdarg.h>

#include "stb_sprintf.h"
#include "stdio.h"

static void putc(char c) { asm volatile("outb %0, %1" : : "a"(c), "Nd"(0xe9)); }

static void puts(char const *s) {
  while (*s) {
    putc(*s);
    s++;
  }
}

void printf(char const *fmt, ...) {
  va_list va;
  va_start(va, fmt);

  char buf[1024] = {0};
  stbsp_vsprintf(buf, fmt, va);

  puts(buf);

  va_end(va);

  putc('\n');
}
