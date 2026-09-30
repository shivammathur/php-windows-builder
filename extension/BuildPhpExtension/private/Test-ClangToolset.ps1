function Test-ClangToolset {
    <# Check the downloaded runtime, since existing 8.6 releases use MSVC. #>
    [OutputType([bool])]
    param([Parameter(Mandatory)][string] $PhpBinary)

    $info = & $PhpBinary -n -i
    if ($LASTEXITCODE -ne 0) { throw "Could not identify compiler for $PhpBinary" }
    return [bool]($info -match '^Compiler => .*clang')
}
