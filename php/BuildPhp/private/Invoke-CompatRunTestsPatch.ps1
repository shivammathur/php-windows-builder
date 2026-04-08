function Invoke-CompatRunTestsPatch {
    <#
    .SYNOPSIS
        Apply a compatibility patch file to run-tests.php.
    .PARAMETER Path
        Path to the run-tests.php file.
    .PARAMETER PatchPath
        Path to the compatibility patch file.
    #>
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='Path to run-tests.php')]
        [ValidateNotNull()]
        [string] $Path,
        [Parameter(Mandatory = $true, Position=1, HelpMessage='Path to compatibility patch file')]
        [ValidateNotNull()]
        [string] $PatchPath
    )
    begin {
        function Get-CompatPatchExecutable {
            $patchCommand = Get-Command patch -ErrorAction SilentlyContinue
            if ($null -ne $patchCommand) {
                if ($null -ne $patchCommand.Source -and $patchCommand.Source -ne '') {
                    return $patchCommand.Source
                }

                if ($null -ne $patchCommand.Path -and $patchCommand.Path -ne '') {
                    return $patchCommand.Path
                }
            }

            $gitCommand = Get-Command git -ErrorAction SilentlyContinue
            if ($null -eq $gitCommand) {
                return $null
            }

            $gitDirectory = Split-Path -Path $gitCommand.Source -Parent
            $candidateRoots = @(
                (Split-Path -Path $gitDirectory -Parent),
                (Split-Path -Path (Split-Path -Path $gitDirectory -Parent) -Parent)
            )

            foreach ($gitRoot in $candidateRoots) {
                if ([string]::IsNullOrWhiteSpace($gitRoot)) {
                    continue
                }

                $gitPatch = Join-Path $gitRoot 'usr\bin\patch.exe'
                if (Test-Path -Path $gitPatch) {
                    return $gitPatch
                }
            }

            return $null
        }
    }
    process {
        $patchExecutable = Get-CompatPatchExecutable
        if ($null -eq $patchExecutable) {
            return $false
        }

        $targetDirectory = Split-Path -Path $Path -Parent
        & $patchExecutable -N -s -V never -r - -d $targetDirectory -i $PatchPath
        return $LASTEXITCODE -eq 0
    }
    end {
    }
}
