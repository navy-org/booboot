#pragma once

#include <stddef.h>

int memcmp(void const *s1, void const *s2, size_t n);

void *memset(void *s, int c, size_t n);

size_t strlen(char const *s);

void *memcpy(void *s1, void const *s2, size_t n);