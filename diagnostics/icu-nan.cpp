#include <unicode/unum.h>
#include <unicode/numfmt.h>
#include <unicode/locid.h>
#include <unicode/fieldpos.h>
#include <unicode/ustring.h>
#include <cmath>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <memory>
#include <string>

int main() {
    UErrorCode status = U_ZERO_ERROR;
    UNumberFormat *c = unum_open(UNUM_DECIMAL, nullptr, 0, "en", nullptr, &status);
    std::unique_ptr<icu::NumberFormat> cpp(icu::NumberFormat::createInstance(icu::Locale("en"), UNUM_DECIMAL, status));
    if (U_FAILURE(status) || !c || !cpp) return 1;
    uint64_t patterns[] = {0x7ff8000000000000ULL, 0xfff8000000000000ULL, 0x7ff0000000000000ULL, 0xfff0000000000000ULL};
    double values[5] = {NAN, 0, 0, 0, 0};
    for (int i = 0; i < 4; ++i) std::memcpy(&values[i + 1], &patterns[i], sizeof(double));
    for (double value : values) {
        uint64_t bits;
        std::memcpy(&bits, &value, sizeof(bits));
        UChar buffer[256];
        status = U_ZERO_ERROR;
        int32_t length = unum_formatDouble(c, value, buffer, 256, nullptr, &status);
        if (U_FAILURE(status)) return 2;
        std::string ctext;
        icu::UnicodeString(buffer, length).toUTF8String(ctext);
        icu::UnicodeString formatted;
        icu::FieldPosition pos;
        status = U_ZERO_ERROR;
        cpp->format(value, formatted, pos, status);
        if (U_FAILURE(status)) return 3;
        std::string cpptext;
        formatted.toUTF8String(cpptext);
        std::printf("%016llx sign=%d C=[%s] C++=[%s]\n", static_cast<unsigned long long>(bits), std::signbit(value) ? 1 : 0, ctext.c_str(), cpptext.c_str());
    }
    unum_close(c);
    return 0;
}
