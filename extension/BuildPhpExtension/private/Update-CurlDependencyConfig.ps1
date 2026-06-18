Function Update-CurlDependencyConfig {
    <#
    .SYNOPSIS
        Add curl brotli/zstd CHECK_LIB calls to config.w32 when required.
    .PARAMETER PhpVersion
        PHP Version
    .PARAMETER ConfigW32Path
        Path to config.w32
    #>
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='PHP Version')]
        [string] $PhpVersion,
        [Parameter(Mandatory = $false, Position=1, HelpMessage='Path to config.w32')]
        [string] $ConfigW32Path = 'config.w32'
    )
    begin {
    }
    process {
        if (-not (Test-Path -LiteralPath $ConfigW32Path -PathType Leaf)) {
            return $false
        }

        $configLines = Get-Content -Path $ConfigW32Path | ForEach-Object {
            if ($_ -match 'libzstd\.lib' -and $_ -notmatch 'libzstd_a\.lib') {
                $_ -replace 'libzstd\.lib', 'libzstd_a.lib;libzstd.lib'
            } else {
                $_
            }
        }
        $originalContent = Get-Content -Path $ConfigW32Path -Raw
        $configW32Content = $configLines -join "`r`n"
        $updatedZstdLibrary = $configW32Content -ne $originalContent.TrimEnd()

        if ($configW32Content -notmatch 'libcurl') {
            if ($updatedZstdLibrary) {
                Set-Content -Path $ConfigW32Path -Value $configW32Content -Encoding ASCII
                return $true
            }
            return $false
        }

        $curlLibraries = @('brotlidec.lib', 'brotlicommon.lib')
        $missingLibraries = @($curlLibraries | Where-Object {
            $configW32Content -notmatch ("CHECK_LIB\((['""])" + [regex]::Escape($_) + '\1')
        })
        if ($missingLibraries.Count -eq 0) {
            if ($updatedZstdLibrary) {
                Set-Content -Path $ConfigW32Path -Value $configW32Content -Encoding ASCII
                return $true
            }
            return $false
        }

        $updatedLines = New-Object 'System.Collections.Generic.List[string]'
        $updated = $false

        foreach ($line in $configLines) {
            if (-not $updated) {
                $negatedPattern = '^(?<indent>\s*)if\s*\(\s*!\s*CHECK_LIB\((?<quote>[''"])(?<lib>[^''"]*nghttp2[^''"]*)\k<quote>(?<signature>\s*,\s*[^)]*)\)(?<suffix>.*)$'
                $negatedMatch = [regex]::Match($line, $negatedPattern)
                if ($negatedMatch.Success) {
                    $indent = $negatedMatch.Groups['indent'].Value
                    $quote = $negatedMatch.Groups['quote'].Value
                    $library = $negatedMatch.Groups['lib'].Value
                    $signature = $negatedMatch.Groups['signature'].Value
                    $suffix = $negatedMatch.Groups['suffix'].Value
                    $continuationIndent = $indent + '    '
                    $updatedLines.Add("${indent}if(!CHECK_LIB($quote$library$quote$signature) ||")
                    for ($i = 0; $i -lt $missingLibraries.Count; $i++) {
                        $lineSuffix = if ($i -eq ($missingLibraries.Count - 1)) { $suffix } else { ' ||' }
                        $updatedLines.Add("${continuationIndent}!CHECK_LIB($quote$($missingLibraries[$i])$quote$signature)$lineSuffix")
                    }
                    $updated = $true
                    continue
                }

                $chainPattern = '^(?<indent>\s*)(?<prefix>&&\s*)?CHECK_LIB\((?<quote>[''"])(?<lib>[^''"]*nghttp2[^''"]*)\k<quote>(?<signature>\s*,\s*[^)]*)\)(?<suffix>.*)$'
                $chainMatch = [regex]::Match($line, $chainPattern)
                if ($chainMatch.Success) {
                    $indent = $chainMatch.Groups['indent'].Value
                    $prefix = $chainMatch.Groups['prefix'].Value
                    $quote = $chainMatch.Groups['quote'].Value
                    $library = $chainMatch.Groups['lib'].Value
                    $signature = $chainMatch.Groups['signature'].Value
                    $suffix = $chainMatch.Groups['suffix'].Value
                    $updatedLines.Add("${indent}${prefix}CHECK_LIB($quote$library$quote$signature)")
                    for ($i = 0; $i -lt $missingLibraries.Count; $i++) {
                        $lineSuffix = if ($i -eq ($missingLibraries.Count - 1)) { $suffix } else { '' }
                        $updatedLines.Add("${indent}&& CHECK_LIB($quote$($missingLibraries[$i])$quote$signature)$lineSuffix")
                    }
                    $updated = $true
                    continue
                }
            }

            $updatedLines.Add($line)
        }

        $updatedContent = $updatedLines -join "`r`n"
        if (-not $updated -or $updatedContent -eq $configW32Content) {
            if ($updatedZstdLibrary) {
                Set-Content -Path $ConfigW32Path -Value $configW32Content -Encoding ASCII
                return $true
            }
            return $false
        }

        Set-Content -Path $ConfigW32Path -Value $updatedContent -Encoding ASCII
        return $true
    }
    end {
    }
}
