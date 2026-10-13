$ErrorActionPreference = 'Stop'
if ((git -C source rev-parse HEAD) -ne 'c8a2f56964243694ce4705a3500ef4cff86a7102') { throw 'Unexpected PHP source' }
$text = [IO.File]::ReadAllText('source/ext/gd/libgd/gdft.c')
$start = $text.IndexOf('#define Tcl_UniChar int')
$end = $text.IndexOf('#ifdef HAVE_LIBRAQM', $start)
if ($start -lt 0 -or $end -le $start) { throw 'Cannot extract original GD function' }
$function = $text.Substring($start, $end - $start)
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
if ($env:VCToolsInstallDir) { $env:PATH = "$env:VCToolsInstallDir/bin/$env:VSCMD_ARG_TGT_ARCH;$env:PATH" }
Get-Command cl,link,pgomgr | Format-List Source
Set-Location reduced
try {
    & cl /nologo /MD /O2 /GL /guard:cf /d2FuncCache1 /c gd-reduced.c 2>&1 | Tee-Object compile.log
    if ($LASTEXITCODE) { throw 'Reduced compile failed' }
    $objHash = (Get-FileHash gd-reduced.obj).Hash
    $results = @()
    foreach ($mode in 'control','PATH','NOPATH') {
        $profile = "reduced-$mode.pgd"
        $exe = "reduced-$mode.exe"
        $flags = @('/nologo','gd-reduced.obj',"/OUT:$exe",'/LTCG','/GUARD:CF','/d2:-FuncCache1')
        if ($mode -ne 'control') { $flags += @("/PGD:$profile", "/GENPROFILE:$mode") }
        & link @flags 2>&1 | Tee-Object "$mode-instrument.log"
        if ($LASTEXITCODE) { throw "Reduced $mode initial link failed" }
        & "./$exe" 2>&1 | Tee-Object "$mode-training.log"
        if ($LASTEXITCODE) { throw "Reduced $mode runtime failed" }
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
            }
        }
        if ((Get-FileHash gd-reduced.obj).Hash -ne $objHash) { throw 'Reduced object changed' }
        $results += @{mode=$mode;optimizedLinkExit=$exit;object=$objHash}
    }
    $results | ConvertTo-Json | Set-Content results.json
    if (@($results | Where-Object optimizedLinkExit -ne 0).Count) { throw 'Reduced PGO compiler failure reproduced' }
} finally { Set-Location .. }
