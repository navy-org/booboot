#include "string.h"

int memcmp(void const *s1, void const *s2, size_t n)
{
    for (size_t i = 0; i < n; i++)
    {
        int diff = *(char *)s1 - *(char *)s2;
        if (diff != 0) {
            return diff;
        }
    }

    return 0;
}

void *memset(void *s, int c, size_t n)
{
    char *p = (char *)s;

    while (n--) {
        *p++ = c;
    }

    return s;
}

size_t strlen(char const *s)
{
    size_t i = 0;
    for (; s[i] != '\0'; i++)
        ;
    return i;
}

void *memcpy(void *s1, void const *s2, size_t n) {
    char *p1 = (char *)s1;
    char const *p2 = (char const *)s2;

    while (n--)
    {
        *p1++ = *p2++;
    }

    return s1;
}
