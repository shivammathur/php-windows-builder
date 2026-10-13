#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include "xsse.h"

static uint64_t hash = 1469598103934665603ULL;
static void record(__m128i value)
{
    unsigned char bytes[16];
    _mm_storeu_si128((__m128i *)bytes, value);
    for (unsigned i = 0; i < 16; i++) {
        hash = (hash ^ bytes[i]) * 1099511628211ULL;
    }
}

int main(void)
{
    unsigned char bytes[16];
    __m128i sequence = _mm_setr_epi8(0, 1, 2, 3, 4, 5, 6, 7,
                                    8, 9, 10, 11, 12, 13, 14, 15);
    _mm_storeu_si128((__m128i *)bytes, sequence);
    for (unsigned i = 0; i < 16; i++) assert(bytes[i] == i);
    for (int k = 0; k < 256; k++) {
        __m128i a = _mm_set_epi8(k, k+1, k+2, k+3, k+4, k+5, k+6, k+7,
                                k+8, k+9, k+10, k+11, k+12, k+13, k+14, k+15);
        __m128i b = _mm_setr_epi16(k, -k, k+1, -k-1, k+2, -k-2, k+3, -k-3);
        record(a);
        record(b);
        record(_mm_set_epi16(k, -k, 1, 2, 3, 4, 32767, -32768));
        record(_mm_set_epi32(k, -k, INT32_MAX, INT32_MIN));
        record(_mm_setr_epi32(k, -k, INT32_MAX, INT32_MIN));
        record(_mm_set_epi64x(INT64_MAX-k, INT64_MIN+k));
        record(_mm_cvtsi32_si128(-k));
        record(_mm_cvtsi64_si128(INT64_MIN+k));
        record(_mm_loadu_si16(&k));
        record(_mm_loadu_si32(&k));
        record(_mm_loadu_si64(&hash));
        record(_mm_sad_epu8(a, b));
        record(_mm_move_epi64(a));
        record(_mm_shuffle_epi32(a, 0x1b));
        record(_mm_shufflehi_epi16(a, 0x1b));
        record(_mm_shufflelo_epi16(a, 0x1b));
        record(_mm_minpos_epu16(b));
        record(_mm_blend_epi16(a, b, 0xa5));
        for (int mode = 0; mode < 128; mode++) {
            record(_mm_cmpestrm(a, (k % 16) + 1, b, 16 - (k % 16), mode));
            record(_mm_cmpistrm(a, b, mode));
            hash ^= (uint64_t)_mm_cmpestri(a, (k % 16) + 1, b, 16 - (k % 16), mode);
            hash ^= (uint64_t)_mm_cmpistri(a, b, mode);
        }
    }
    _mm_mfence();
    _mm_lfence();
    _mm_pause();
    printf("%016llx\n", (unsigned long long)hash);
    return 0;
}
