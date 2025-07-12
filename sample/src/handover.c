#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "handover.h"

char const* handover_tag_name(HandoverTag tag) {
    switch (tag) {
#define TAG(NAME, VALUE)  \
    case HANDOVER_##NAME: \
        return #NAME;
        HANDOVER_TAGS(TAG)
#undef TAG
    }
    return "UNKNOWN";
}

bool handover_mergeable(uint32_t tag) {
    switch (tag) {
    case HANDOVER_FREE:
    case HANDOVER_LOADER:
    case HANDOVER_KERNEL:
    case HANDOVER_RESERVED:
        return true;

    default:
        return false;
    }
}

bool handover_overlap(HandoverRecord lhs, HandoverRecord rhs) {
    return lhs.start < rhs.start + rhs.size && rhs.start < lhs.start + lhs.size;
}

bool handover_just_before(HandoverRecord lhs, HandoverRecord rhs) {
    return lhs.start + lhs.size == rhs.start;
}

bool handover_just_after(HandoverRecord lhs, HandoverRecord rhs) {
    return lhs.start == rhs.start + rhs.size;
}

HandoverRecord handover_half_under(HandoverRecord self, HandoverRecord other) {
    if (handover_overlap(self, other) &&
        self.start < other.start) {
        return (HandoverRecord){
            .tag   = self.tag,
            .flags = 0,
            .start = self.start,
            .size  = other.start - self.start,
        };
    }

    return (HandoverRecord){0};
}

HandoverRecord handover_half_over(HandoverRecord self, HandoverRecord other) {
    if (handover_overlap(self, other) &&
        self.start + self.size > other.start + other.size) {
        return (HandoverRecord){
            .tag   = self.tag,
            .flags = 0,
            .start = other.start + other.size,
            .size  = self.start + self.size - other.start - other.size,
        };
    }

    return (HandoverRecord){0};
}

void handover_insert(HandoverPayload* payload, size_t index, HandoverRecord record) {
    for (size_t i = payload->count; i > index; i--) {
        payload->records[i] = payload->records[i - 1];
    }

    payload->records[index] = record;
    payload->count++;
}

void handover_remove(HandoverPayload* payload, size_t index) {
    for (size_t i = index; i < payload->count - 1; i++) {
        payload->records[i] = payload->records[i + 1];
    }

    payload->count--;
}

void handover_append(HandoverPayload* payload, HandoverRecord record) {
    if (record.size == 0) {
        return;
    }

    for (size_t i = 0; i < payload->count; i++) {
        HandoverRecord other = payload->records[i];

        if (record.tag == other.tag && handover_just_after(record, other) && handover_mergeable(record.tag)) {
            handover_remove(payload, i);
            other.size += record.size;
            handover_append(payload, other);
            return;
        }

        if (record.tag == other.tag && handover_just_before(record, other) && handover_mergeable(record.tag)) {
            handover_remove(payload, i);
            other.start -= record.size;
            other.size += record.size;
            handover_append(payload, other);
            return;
        }

        if (handover_overlap(record, other)) {
            if ((handover_mergeable(record.tag) && !handover_mergeable(other.tag)) || other.tag == HANDOVER_FREE) {
                handover_remove(payload, i);

                HandoverRecord lower = handover_half_under(other, record);
                HandoverRecord upper = handover_half_over(other, record);

                handover_append(payload, record);
                handover_append(payload, lower);
                handover_append(payload, upper);
                return;
            } else if (!handover_mergeable(record.tag) && handover_mergeable(other.tag)) {
                handover_remove(payload, i);

                HandoverRecord lower = handover_half_under(record, other);
                HandoverRecord upper = handover_half_over(record, other);

                handover_append(payload, other);
                handover_append(payload, lower);
                handover_append(payload, upper);
                return;
            } else {
                printf("handover: record %s (start: %x, len: %x) collides with %s (start: %x, len: %x)\n", handover_tag_name(record.tag), record.start, record.size, handover_tag_name(other.tag), other.start, other.size);
                abort();
            }
        }

        if (record.start < other.start) {
            handover_insert(payload, i, record);
            return;
        }
    }

    payload->records[payload->count++] = record;
}

char const* handover_str(HandoverPayload const* payload, uint32_t offset) {
    return (char const*)payload + offset;
}

size_t handover_add_string(HandoverPayload* handover, char const* str) {
    size_t len    = strlen(str) + 1;
    size_t offset = handover->size - len;
    memset((void*)((uintptr_t)handover + offset), 0, len);
    memcpy((void*)((uintptr_t)handover + offset), str, len);
    handover->size -= len;
    return offset;
}
