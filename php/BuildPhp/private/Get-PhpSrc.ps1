function Get-PhpSrc {
    <#
    .SYNOPSIS
        Get the PHP source code.
    .PARAMETER PhpVersion
        PHP Version
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='PHP Version')]
        [string] $PhpVersion
    )
    begin {
    }
    process {
        Add-Type -Assembly "System.IO.Compression.Filesystem"

        $repository = if ([string]::IsNullOrWhiteSpace($env:PHP_SRC_REPOSITORY)) { "php/php-src" } else { $env:PHP_SRC_REPOSITORY }
        $customRef = if ([string]::IsNullOrWhiteSpace($env:PHP_SRC_REF)) { $null } else { $env:PHP_SRC_REF }
        $baseUrl = "https://github.com/$repository/archive"
        $zipFile = "php-$PhpVersion.zip"
        $directory = "php-$PhpVersion-src"

        if ($PhpVersion.Contains(".")) {
            $ref = if ($null -ne $customRef) { $customRef } else { "php-$PhpVersion" }
            $url = if ($null -ne $customRef) {
                "$baseUrl/$ref.zip"
            } else {
                "$baseUrl/refs/tags/$ref.zip"
            }
        } else {
            $ref = if ($null -ne $customRef) { $customRef } else { $PhpVersion }
            $url = "$baseUrl/$ref.zip"
        }

        $currentDirectory = (Get-Location).Path
        $zipFilePath = Join-Path $currentDirectory $zipFile
        $directoryPath = Join-Path $currentDirectory $directory
        $srcZipFilePath = Join-Path $currentDirectory "php-$PhpVersion-src.zip"
        $existingDirectories = @(Get-ChildItem -Path $currentDirectory -Directory | Select-Object -ExpandProperty FullName)

        Get-File -Url $url -Outfile $zipFile
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFilePath, $currentDirectory)

        $extractedDirectory = Get-ChildItem -Path $currentDirectory -Directory |
            Where-Object { $existingDirectories -notcontains $_.FullName } |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1

        if ($null -eq $extractedDirectory) {
            throw "Failed to locate extracted PHP source directory for $repository@$ref"
        }

        Rename-Item -Path $extractedDirectory.FullName -NewName $directory

        if ($PhpVersion -match '^7\.2\.\d+$') {
            Set-Content -Path (Join-Path $directoryPath 'win32/build/mkdist.php') -Value ((Get-Content -Raw -Path (Join-Path $directoryPath 'win32/build/mkdist.php')).Replace('$hdr_data{$i}', '$hdr_data[$i]')) -NoNewline
        }

        [System.IO.Compression.ZipFile]::CreateFromDirectory($directoryPath, $srcZipFilePath)
    }
    end {
    }
}
