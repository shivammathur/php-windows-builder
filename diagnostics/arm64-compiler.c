#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "PMurHash.h"

#ifdef NO_CONTRACTION
#pragma fp_contract(off)
#endif
__declspec(noinline) static void range_probe(double low, double high, double step) {
    unsigned i, count = 0;
    double element;
    for (i = 0, element = low; i < 7 && element <= high; ++i, element = low + (i * step)) {
        printf("range[%u]=%.17g\n", i, element);
        ++count;
    }
    printf("range_count=%u\n", count);
}

int main(void) {
    unsigned char data[256];
    unsigned offset, length, split, failures = 0, cases = 0;
    for (offset = 0; offset < 4; ++offset) {
        for (length = 0; length <= 64; ++length) {
            unsigned j;
            for (j = 0; j < length; ++j) data[offset+j] = (unsigned char)(j*37+11);
            for (split = 0; split <= length; ++split) {
                uint32_t direct = 0, dc = 0, stream = 0, sc = 0;
                PMurHash32_Process(&direct, &dc, data+offset, length);
                direct = PMurHash32_Result(direct, dc, length);
                PMurHash32_Process(&stream, &sc, data+offset, split);
                PMurHash32_Process(&stream, &sc, data+offset+split, length-split);
                stream = PMurHash32_Result(stream, sc, length);
                if (direct != stream) {
                    if (failures < 10) printf("mismatch offset=%u length=%u split=%u direct=%08x stream=%08x\n", offset, length, split, direct, stream);
                    ++failures;
                }
                ++cases;
            }
        }
    }
    printf("murmur_cases=%u murmur_failures=%u\n", cases, failures);
    range_probe(-0.03, 0.03, 0.01);
    return 0;
}
