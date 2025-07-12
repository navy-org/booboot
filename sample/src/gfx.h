#pragma once

#include <stdint.h>

typedef struct [[gnu::packed]]
{
    char idlength;
    char colourmaptype;
    char datatypecode;
    short int colourmaporigin;
    short int colourmaplength;
    char colourmapdepth;
    short int x_origin;
    short int y_origin;
    short width;
    short height;
    char bitsperpixel;
    char imagedescriptor;
} TgaHeader;

typedef struct
{
    uint8_t b;
    uint8_t g;
    uint8_t r;
    uint8_t a;
} Bgra;

typedef struct
{
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t a;
} Rgba;