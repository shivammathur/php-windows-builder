function Add-PhpSourcePatches {
    <#
    .SYNOPSIS
        Apply configured PHP source patches for a version series.
    .PARAMETER PhpVersion
        PHP version or branch name.
    .PARAMETER SourceDirectory
        Extracted PHP source directory.
    #>
    [OutputType([System.IO.FileInfo[]])]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='PHP Version')]
        [ValidateNotNull()]
        [ValidateLength(1, [int]::MaxValue)]
        [string] $PhpVersion,
        [Parameter(Mandatory = $true, Position=1, HelpMessage='Source directory')]
        [ValidateNotNull()]
        [ValidateLength(1, [int]::MaxValue)]
        [string] $SourceDirectory
    )
    begin {
    }
    process {
        $patchFiles = @(Get-PhpSourcePatchFiles -PhpVersion $PhpVersion)
        if ($patchFiles.Count -eq 0) {
            return @()
        }

        $gitCommand = Get-Command git -ErrorAction SilentlyContinue
        if ($null -eq $gitCommand) {
            throw "Git is required for PHP source patches."
        }

        foreach ($patchFile in $patchFiles) {
            & $gitCommand.Source -C $SourceDirectory apply -p0 --check $patchFile.FullName *> $null
            if ($LASTEXITCODE -eq 0) {
                & $gitCommand.Source -C $SourceDirectory apply -p0 $patchFile.FullName *> $null
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to apply PHP source patch $($patchFile.Name) for PHP $PhpVersion."
                }

                Write-Host "Applied PHP source patch ($($patchFile.Name)) in $SourceDirectory"
                continue
            }

            & $gitCommand.Source -C $SourceDirectory apply -R -p0 --check $patchFile.FullName *> $null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Skipped PHP source patch ($($patchFile.Name)) in $SourceDirectory because it is already applied"
                continue
            }

            throw "Failed to apply PHP source patch $($patchFile.Name) for PHP $PhpVersion."
        }

        return $patchFiles
    }
    end {
    }
}
