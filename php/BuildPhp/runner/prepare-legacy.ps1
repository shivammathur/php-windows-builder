$ErrorActionPreference = 'Stop'

# PHP 5 expands every object path onto the linker command line. Use
# NMAKE inline response files for the core, SAPIs and shared extensions.
$makefile = Get-Content Makefile -Raw
$pattern = '(?m)^\t@\$\(CC\) ([^\r\n]+ /link [^\r\n]+)\r?$'
$makefile = [regex]::Replace($makefile, $pattern, {
    param($match)
    $arguments = $match.Groups[1].Value.Replace(' /link ', ' ')
    return "`t@`$(LD) @<<`r`n$arguments`r`n<<"
})
Set-Content Makefile $makefile -Encoding ascii -NoNewline
