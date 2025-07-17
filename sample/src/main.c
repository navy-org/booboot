#define HANDOVER_INCLUDE_MACROS
#define HANDOVER_INCLUDE_UTILITES

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "gfx.h"
#include "handover.h"

#define lower2upper(x) ((x) + HANDOVER_UPPER_HALF)

HANDOVER(WITH_CMDLINE, WITH_FB, WITH_FILES, WITH_ACPI);

static HandoverRecord *_Nullable _fb;
static HandoverRecord *_Nullable _logo;

static void draw_logo(void) {
  TgaHeader *header = (TgaHeader *)lower2upper(_logo->start);
  Bgra *fb = (Bgra *)(lower2upper(_fb->start));
  uint32_t *img = (uint32_t *)(sizeof(TgaHeader) + (uint64_t)header);
  size_t i = 0;

  for (size_t y = 0; y < (size_t)header->height; y++) {
    for (size_t x = 0; x < (size_t)header->width; x++) {
      Rgba *pixel = (Rgba *)&img[i++];
      size_t index = x + (_fb->fb.pitch / sizeof(uint32_t)) * y;

      fb[index].r = pixel->r;
      fb[index].g = pixel->g;
      fb[index].b = pixel->b;
      fb[index].a = pixel->a;
    }
  }
}

void _start(uint64_t magic, HandoverPayload *payload) {
  (void)draw_logo;
  printf("Handover magic: %llx", magic);
  printf("Handover payload: %llx", payload);

  if (payload->magic != HANDOVER_MAGIC) {
    printf("Invalid handover payload (%lx)", payload->magic);
    goto hlt;
  }

  if (payload->records[0].tag != HANDOVER_MAGIC) {
    printf("Invalid handover record (%lx)", payload->records[0].tag);
    goto hlt;
  }

  printf("Handover agent: %s", handover_str(payload, payload->agent));
  printf("Handover size: %d", payload->size);
  printf("Handover count: %d", payload->count);

  for (size_t i = 0; i < payload->count; i++) {
    HandoverRecord *record = &payload->records[i];

    switch (record->tag) {
    case HANDOVER_FB: {
      _fb = record;
      break;
    }
    case HANDOVER_CMDLINE: {
      printf("Command line: %s", (char *)lower2upper(record->start));
      break;
    }
    case HANDOVER_FILE: {
      if (memcmp(handover_str(payload, record->file.name), "booboot.tga", 11) ==
          0) {
        _logo = record;
      }
      break;
    }

    case HANDOVER_RSDP: {
      if (memcmp((void *)lower2upper(record->start), "RSD PTR ", 8) == 0) {
        printf("RSDP Signature matched");
      }
      break;
    }
    }

    printf("Handover tag: %s(%x)", handover_tag_name(record->tag), record->tag);
    printf("    flags: %x", record->flags);
    printf("    start: %llx", record->start);
    printf("    size: %llx", record->size);
    printf("    more: %x", record->more);
  }

  if (_fb != NULL && _logo != NULL) {
    draw_logo();
  }

hlt:
  printf("Halting...");
  for (;;) {
    asm("hlt");
  }
}
