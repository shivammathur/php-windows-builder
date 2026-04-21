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
        $search = 'defined(_M_ARM64)'
        $replacement = '(defined(_M_ARM64) && !defined(_MSC_VER))'
        $encoding = New-Object System.Text.UTF8Encoding($false)
        $compatibilityFiles = @(
            (Join-Path $SourceDirectory 'ext\bcmath\libbcmath\src\xsse.h'),
            (Join-Path $SourceDirectory 'Zend\zend_simd.h')
        )

        foreach ($filePath in $compatibilityFiles) {
            if (-not (Test-Path -Path $filePath)) {
                continue
            }

            $content = Get-Content -Path $filePath -Raw
            if ($content.Contains($replacement)) {
                continue
            }

            if (-not $content.Contains($search)) {
                Write-Warning "ARM64 compatibility patch marker not found in $filePath"
                continue
            }

            $patchedContent = $content.Replace($search, $replacement)
            [System.IO.File]::WriteAllText($filePath, $patchedContent, $encoding)
            Write-Host "Applied ARM64 compatibility patch to $filePath"
        }
    }
    end {
    }
}
