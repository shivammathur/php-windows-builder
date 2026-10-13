function Get-Arm64SimdConstructorBlock {
    return @"
static XSSE_FORCE_INLINE int8x16_t _xsse_make_int8x16(
    int8_t v0, int8_t v1, int8_t v2, int8_t v3,
    int8_t v4, int8_t v5, int8_t v6, int8_t v7,
    int8_t v8, int8_t v9, int8_t v10, int8_t v11,
    int8_t v12, int8_t v13, int8_t v14, int8_t v15)
{
    const int8_t values[16] = {
        v0, v1, v2, v3, v4, v5, v6, v7,
        v8, v9, v10, v11, v12, v13, v14, v15
    };
    return vld1q_s8(values);
}

static XSSE_FORCE_INLINE uint8x16_t _xsse_make_uint8x16(
    uint8_t v0, uint8_t v1, uint8_t v2, uint8_t v3,
    uint8_t v4, uint8_t v5, uint8_t v6, uint8_t v7,
    uint8_t v8, uint8_t v9, uint8_t v10, uint8_t v11,
    uint8_t v12, uint8_t v13, uint8_t v14, uint8_t v15)
{
    const uint8_t values[16] = {
        v0, v1, v2, v3, v4, v5, v6, v7,
        v8, v9, v10, v11, v12, v13, v14, v15
    };
    return vld1q_u8(values);
}

static XSSE_FORCE_INLINE int16x8_t _xsse_make_int16x8(
    int16_t v0, int16_t v1, int16_t v2, int16_t v3,
    int16_t v4, int16_t v5, int16_t v6, int16_t v7)
{
    const int16_t values[8] = { v0, v1, v2, v3, v4, v5, v6, v7 };
    return vld1q_s16(values);
}

static XSSE_FORCE_INLINE uint16x8_t _xsse_make_uint16x8(
    uint16_t v0, uint16_t v1, uint16_t v2, uint16_t v3,
    uint16_t v4, uint16_t v5, uint16_t v6, uint16_t v7)
{
    const uint16_t values[8] = { v0, v1, v2, v3, v4, v5, v6, v7 };
    return vld1q_u16(values);
}

static XSSE_FORCE_INLINE int32x4_t _xsse_make_int32x4(
    int32_t v0, int32_t v1, int32_t v2, int32_t v3)
{
    const int32_t values[4] = { v0, v1, v2, v3 };
    return vld1q_s32(values);
}

static XSSE_FORCE_INLINE int64x2_t _xsse_make_int64x2(
    int64_t v0, int64_t v1)
{
    const int64_t values[2] = { v0, v1 };
    return vld1q_s64(values);
}
"@
}

function Add-MsvcArm64SimdCompat {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Content,
        [Parameter(Mandatory = $false)]
        [bool] $AddBarrierIntrinsics = $false
    )

    $patched = $Content

    $typedefMatch = [regex]::Match($patched, '^\s*typedef int8x16_t __m128i;\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if ($typedefMatch.Success -and $patched -notmatch '_xsse_make_int8x16') {
        $patched = $patched.Insert($typedefMatch.Index + $typedefMatch.Length, "`n`n" + (Get-Arm64SimdConstructorBlock))
    }

    if ($AddBarrierIntrinsics) {
        if ($patched -notmatch '#include <intrin\.h>') {
            $patched = [regex]::Replace(
                $patched,
                '(?m)^(\s*#include <arm_neon\.h>\s*)$',
                '$1' + "`n#include <intrin.h>",
                [System.Text.RegularExpressions.RegexOptions]::None
            )
        }

        $patched = $patched.Replace('__asm__ __volatile__("dsb sy" ::: "memory");', '__dsb(_ARM64_BARRIER_SY);')
        $patched = $patched.Replace('__asm__ __volatile__("dsb ld" ::: "memory");', '__dsb(_ARM64_BARRIER_LD);')
        $patched = $patched.Replace('__asm__ __volatile__("yield");', '__yield();')
    }

    $regexOptions = [System.Text.RegularExpressions.RegexOptions]::Singleline
    $replacements = @(
        @{
            Pattern = 'vreinterpretq_s8_s16\(\s*\(int16x8_t\)\s*\{(.*?)\}\s*\)'
            Replacement = 'vreinterpretq_s8_s16(_xsse_make_int16x8($1))'
        },
        @{
            Pattern = 'vreinterpretq_s8_s32\(\s*\(int32x4_t\)\s*\{(.*?)\}\s*\)'
            Replacement = 'vreinterpretq_s8_s32(_xsse_make_int32x4($1))'
        },
        @{
            Pattern = 'vreinterpretq_s8_s64\(\s*\(int64x2_t\)\s*\{(.*?)\}\s*\)'
            Replacement = 'vreinterpretq_s8_s64(_xsse_make_int64x2($1))'
        },
        @{
            Pattern = 'vreinterpretq_s8_u16\(\s*\(uint16x8_t\)\s*\{(.*?)\}\s*\)'
            Replacement = 'vreinterpretq_s8_u16(_xsse_make_uint16x8($1))'
        },
        @{
            Pattern = 'vreinterpretq_s8_u8\(\s*\(uint8x16_t\)\s*\{(.*?)\}\s*\)'
            Replacement = 'vreinterpretq_s8_u8(_xsse_make_uint8x16($1))'
        },
        @{
            Pattern = '\(\s*int8x16_t\s*\)\s*\{(.*?)\}'
            Replacement = '_xsse_make_int8x16($1)'
        },
        @{
            Pattern = '\(\s*int16x8_t\s*\)\s*\{(.*?)\}'
            Replacement = '_xsse_make_int16x8($1)'
        },
        @{
            Pattern = '\(\s*int32x4_t\s*\)\s*\{(.*?)\}'
            Replacement = '_xsse_make_int32x4($1)'
        },
        @{
            Pattern = '\(\s*int64x2_t\s*\)\s*\{(.*?)\}'
            Replacement = '_xsse_make_int64x2($1)'
        },
        @{
            Pattern = '\(\s*uint16x8_t\s*\)\s*\{(.*?)\}'
            Replacement = '_xsse_make_uint16x8($1)'
        },
        @{
            Pattern = '\(\s*uint8x16_t\s*\)\s*\{(.*?)\}'
            Replacement = '_xsse_make_uint8x16($1)'
        },
        @{
            Pattern = '\(\(\s*int8x16_t\s*\)\s*\{(.*?)\}\s*\)'
            Replacement = '(_xsse_make_int8x16($1))'
        },
        @{
            Pattern = '\(\(\s*int16x8_t\s*\)\s*\{(.*?)\}\s*\)'
            Replacement = '(_xsse_make_int16x8($1))'
        },
        @{
            Pattern = '\(\(\s*int32x4_t\s*\)\s*\{(.*?)\}\s*\)'
            Replacement = '(_xsse_make_int32x4($1))'
        },
        @{
            Pattern = '\(\(\s*int64x2_t\s*\)\s*\{(.*?)\}\s*\)'
            Replacement = '(_xsse_make_int64x2($1))'
        },
        @{
            Pattern = '\(\(\s*uint16x8_t\s*\)\s*\{(.*?)\}\s*\)'
            Replacement = '(_xsse_make_uint16x8($1))'
        },
        @{
            Pattern = '\(\(\s*uint8x16_t\s*\)\s*\{(.*?)\}\s*\)'
            Replacement = '(_xsse_make_uint8x16($1))'
        }
    )

    foreach ($replacement in $replacements) {
        $patched = [regex]::Replace(
            $patched,
            $replacement.Pattern,
            $replacement.Replacement,
            $regexOptions
        )
    }

    return $patched
}

function Add-Arm64SourceCompatPatches {
    <#
    .SYNOPSIS
        Apply ARM64-specific source compatibility patches before building PHP.
    .PARAMETER SourceDirectory
        PHP source directory.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='PHP source directory')]
        [ValidateNotNull()]
        [ValidateLength(1, [int]::MaxValue)]
        [string] $SourceDirectory
    )
    begin {
    }
    process {
        $encoding = New-Object System.Text.UTF8Encoding($false)
        $compatibilityFiles = @(
            @{
                Path = (Join-Path $SourceDirectory 'ext\bcmath\libbcmath\src\xsse.h')
                AddBarrierIntrinsics = $true
            },
            @{
                Path = (Join-Path $SourceDirectory 'Zend\zend_simd.h')
                AddBarrierIntrinsics = $false
            }
        )

        foreach ($compatibilityFile in $compatibilityFiles) {
            $filePath = $compatibilityFile.Path
            if (-not (Test-Path -Path $filePath)) {
                continue
            }

            $content = Get-Content -Path $filePath -Raw
            $patchedContent = Add-MsvcArm64SimdCompat -Content $content -AddBarrierIntrinsics $compatibilityFile.AddBarrierIntrinsics
            if ($patchedContent -eq $content) {
                continue
            }

            [System.IO.File]::WriteAllText($filePath, $patchedContent, $encoding)
            Write-Host "Applied ARM64 compatibility patch to $filePath"
        }
    }
    end {
    }
}
