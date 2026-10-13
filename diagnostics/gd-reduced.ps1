param([ValidateSet('original','no-cache','no-vector','no-numeric','no-named','no-utf','no-hex','no-decimal','unsigned-index','unsigned-byte','unsigned-accumulator')][string]$Variant='original')
$ErrorActionPreference = 'Stop'
if ((git -C source rev-parse HEAD) -ne 'c8a2f56964243694ce4705a3500ef4cff86a7102') { throw 'Unexpected PHP source' }
$text = [IO.File]::ReadAllText('source/ext/gd/libgd/gdft.c')
$start = $text.IndexOf('#define Tcl_UniChar int')
$end = $text.IndexOf('#ifdef HAVE_LIBRAQM', $start)
if ($start -lt 0 -or $end -le $start) { throw 'Cannot extract original GD function' }
$function = $text.Substring($start, $end - $start)
if ($Variant -eq 'no-vector') {
    $function = $function.Replace('for (i =', "__pragma(loop(no_vector)) for (i =")
} elseif ($Variant -eq 'no-numeric') {
    $function = $function.Replace("if (byte == '#') {", "if (0 && byte == '#') {")
} elseif ($Variant -eq 'no-named') {
    $function = $function.Replace('key.name = p = entity_name_buf;', 'if (0) { key.name = p = entity_name_buf;')
    $tail = "`n        }`n    }`n`n    /* Unroll"
    if (-not $function.Contains($tail)) { throw 'Named branch boundary changed' }
    $function = $function.Replace($tail, "`n            }$tail")
} elseif ($Variant -eq 'no-utf') {
    $function = $function.Replace('if (byte < 0x', 'if (0 && byte < 0x')
} elseif ($Variant -eq 'no-hex') {
    $function = $function.Replace("if (byte == 'x' || byte == 'X')", "if (0 && (byte == 'x' || byte == 'X'))")
} elseif ($Variant -eq 'no-decimal') {
    $function = $function.Replace('for (i = 2; i < 8; i++)', 'for (i = 2; i < 2; i++)')
} elseif ($Variant -eq 'unsigned-index') {
    $function = $function.Replace('int i, n = 0;', 'unsigned int i; int n = 0;')
} elseif ($Variant -eq 'unsigned-byte') {
    $function = $function.Replace('int byte;', 'unsigned int byte;')
} elseif ($Variant -eq 'unsigned-accumulator') {
    $function = $function.Replace('int i, n = 0;', 'int i; unsigned int n = 0;')
}
$comparator = [regex]::Match($text, '(?s)static int comp_entities\([^}]+\}').Value
if (-not $comparator) { throw 'Missing comparator' }
New-Item reduced -ItemType Directory -Force | Out-Null
Copy-Item source/ext/gd/libgd/entities.h reduced/entities.h
$prefix = @'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "entities.h"
'@
$harness = @'
/* Volatile indirection keeps real calls and prevents folding the input table. */
static int (* volatile convert)(const char *, int *) = gdTcl_UtfToUniChar;
int main(void) {
    static const struct { const char *s; int cp; int bytes; } cases[] = {
        {"A",65,1}, {"&#197;",197,6}, {"&#x6C34;",27700,8},
        {"&amp;",38,5}, {"&unknown;",38,1}, {"&#xGG;",38,1},
        {"\xc3\x85",197,2}, {"\xe6\xb0\xb4",27700,3},
        {"\xc3z",195,1}, {"\xe6\xb0z",230,1}, {"",0,1}
    };
    unsigned long long sum=0;
    for (int repeat=0; repeat<10000; repeat++) {
        for (unsigned int j=0; j<sizeof(cases)/sizeof(cases[0]); j++) {
            int cp=-1;
            int bytes=convert(cases[j].s,&cp);
            if (cp!=cases[j].cp || bytes!=cases[j].bytes) {
                fprintf(stderr,"case %u: %d/%d expected %d/%d\n",j,cp,bytes,cases[j].cp,cases[j].bytes);
                return 1;
            }
            sum+=(unsigned)cp+(unsigned)bytes;
        }
        for (unsigned int j=0; j<NR_OF_ENTITIES; j++) {
            char entity[ENTITY_NAME_LENGTH_MAX+3];
            int cp=-1;
            sprintf(entity,"&%s;",entities[j].name);
            int bytes=convert(entity,&cp);
            if (cp!=entities[j].value || bytes!=(int)strlen(entity)) return 2;
            sum+=(unsigned)cp+(unsigned)bytes;
        }
    }
    printf("GD UTF/entity checks passed: %llu\n",sum);
    return 0;
}
'@
[IO.File]::WriteAllText('reduced/gd-reduced.c', "$prefix`n$comparator`n$function`n$harness")
if ($Variant -in 'no-numeric','no-named','no-utf','no-hex','no-decimal') {
    # Reduction cases deliberately remove behavior, solely to isolate compiler input.
    # Their optimized checksum must still equal their own non-PGO control.
    $harness = $harness.Replace('if (cp!=cases[j].cp || bytes!=cases[j].bytes)', 'if (0)')
    $harness = $harness.Replace('if (cp!=entities[j].value || bytes!=(int)strlen(entity)) return 2;', '')
    [IO.File]::WriteAllText('reduced/gd-reduced.c', "$prefix`n$comparator`n$function`n$harness")
}
if ($env:VCToolsInstallDir) { $env:PATH = "$env:VCToolsInstallDir/bin/$env:VSCMD_ARG_TGT_ARCH;$env:PATH" }
Get-Command cl,link,pgomgr | Format-List Source
Set-Location reduced
try {
    $compileFlags = @('/nologo','/MD','/O2','/GL','/guard:cf','/c','gd-reduced.c')
    if ($Variant -ne 'no-cache') { $compileFlags += '/d2FuncCache1' }
    & cl @compileFlags 2>&1 | Tee-Object compile.log
    if ($LASTEXITCODE) { throw 'Reduced compile failed' }
    $objHash = (Get-FileHash gd-reduced.obj).Hash
    $results = @()
    $modes = if ($Variant -eq 'original') { @('control','PATH','NOPATH') } else { @('control','PATH') }
    foreach ($mode in $modes) {
        $profile = "reduced-$mode.pgd"
        $exe = "reduced-$mode.exe"
        $flags = @('/nologo','gd-reduced.obj',"/OUT:$exe",'/LTCG','/GUARD:CF')
        if ($Variant -ne 'no-cache') { $flags += '/d2:-FuncCache1' }
        if ($mode -ne 'control') { $flags += @("/PGD:$profile", "/GENPROFILE:$mode") }
        & link @flags 2>&1 | Tee-Object "$mode-instrument.log"
        if ($LASTEXITCODE) { throw "Reduced $mode initial link failed" }
        & "./$exe" 2>&1 | Tee-Object "$mode-training.log"
        if ($LASTEXITCODE) { throw "Reduced $mode runtime failed" }
        $output = Get-Content "$mode-training.log" -Raw
        if ($mode -eq 'control') { $expected = $output }
        elseif ($output -cne $expected) { throw 'Instrumented result differs from control' }
        $exit = 0
        if ($mode -ne 'control') {
            & pgomgr /merge $profile 2>&1 | Tee-Object "$mode-merge.log"
            if ($LASTEXITCODE) { throw 'Reduced profile merge failed' }
            & pgomgr /summary $profile 2>&1 | Tee-Object "$mode-summary.log"
            if ($LASTEXITCODE) { throw 'Reduced profile summary failed' }
            Remove-Item $exe
            $flags = @($flags | Where-Object { $_ -notlike '/GENPROFILE:*' }) + '/USEPROFILE'
            & link @flags 2>&1 | Tee-Object "$mode-optimize.log"
            $exit = $LASTEXITCODE
            if (-not $exit) {
                & "./$exe" 2>&1 | Tee-Object "$mode-runtime.log"
                if ($LASTEXITCODE) { throw 'Reduced optimized runtime failed' }
                if ((Get-Content "$mode-runtime.log" -Raw) -cne $expected) { throw 'Optimized result differs from control' }
            }
        }
        if ((Get-FileHash gd-reduced.obj).Hash -ne $objHash) { throw 'Reduced object changed' }
        $results += @{mode=$mode;optimizedLinkExit=$exit;object=$objHash}
    }
    $results | ConvertTo-Json | Set-Content results.json
    if (@($results | Where-Object optimizedLinkExit -ne 0).Count) { throw 'Reduced PGO compiler failure reproduced' }
} finally { Set-Location .. }
