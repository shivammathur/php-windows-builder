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
        $bcmathXssePath = Join-Path $SourceDirectory 'ext\bcmath\libbcmath\src\xsse.h'
        if (-not (Test-Path -Path $bcmathXssePath)) {
            return
        }

        $content = Get-Content -Path $bcmathXssePath -Raw
        $search = 'defined(_M_ARM64)'
        $replacement = '(defined(_M_ARM64) && !defined(_MSC_VER))'

        if ($content.Contains($replacement)) {
            return
        }

        if (-not $content.Contains($search)) {
            Write-Warning "ARM64 bcmath compatibility patch marker not found in $bcmathXssePath"
            return
        }

        $patchedContent = $content.Replace($search, $replacement)
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($bcmathXssePath, $patchedContent, $encoding)
        Write-Host "Applied ARM64 compatibility patch to $bcmathXssePath"
    }
    end {
    }
}
