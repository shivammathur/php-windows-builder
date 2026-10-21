function Add-PhpDeps {
    <#
    .SYNOPSIS
        Add PHP dependencies, optionally fetching from GitHub Actions workflow runs first.
    .PARAMETER PhpVersion
        PHP version (e.g., 8.4.18, 8.4, or master).
    .PARAMETER VsVersion
        Visual Studio toolset version (e.g., vs16, vs17).
    .PARAMETER Arch
        Target architecture: x86 or x64.
    .PARAMETER Destination
        Destination directory to extract the downloaded deps into.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $PhpVersion,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $VsVersion,
        [Parameter(Mandatory=$true)]
        [ValidateSet('x86','x64')]
        [string] $Arch,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $Destination
    )

    begin {
        $baseurl = 'https://downloads.php.net/~windows/php-sdk/deps'
    }

    process {
        if ($PhpVersion -match '^(5\.[3-6]|7\.0)(\.|$)') {
            if ($env:LIBS_BUILD_RUNS) {
                throw 'Workflow dependency overrides are not supported for legacy dependency bundles.'
            }
            $series = $Matches[1]
            $date = switch ($series) {
                '5.3' { '_2014-09' }
                '5.4' { '_2015-05' }
                '5.5' { '' }
                default { '_2018-12' }
            }
            $archive = Join-Path $env:TEMP "deps-$series-$VsVersion-$Arch.7z"
            Get-File -Url "https://downloads.php.net/~windows/php-sdk/archives/deps-$series-$VsVersion-${Arch}${date}.7z" -OutFile $archive
            $extract = Join-Path $env:TEMP ([guid]::NewGuid().ToString())
            try {
                & 7z x $archive "-o$extract" -y | Out-Host
                if ($LASTEXITCODE -ne 0) { throw "Extracting $archive failed" }
                New-Item -ItemType Directory -Force -Path $Destination | Out-Null
                Copy-Item "$extract\deps\*" $Destination -Recurse -Force
            } finally {
                Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
            }
            return
        }

        if (-not (Test-Path -LiteralPath $Destination)) {
            New-Item -ItemType Directory -Force -Path $Destination | Out-Null
        }

        $downloadedLibs = @()
        if ($env:LIBS_BUILD_RUNS) {
            $downloadedLibs = Get-LibsBuildDeps -Arch $Arch -Destination $Destination
        }

        $packageData = Get-PhpDepsPackages -PhpVersion $PhpVersion -VsVersion $VsVersion -Arch $Arch
        $lines = @($packageData.Packages)
        if ($packageData.OverrideLibraries.Count -ne 0) {
            $downloadedLibs = @($downloadedLibs | Where-Object { $packageData.OverrideLibraries -notcontains $_ })
        }

        foreach ($line in $lines) {
            # Extract library name from package filename (e.g., "net-snmp-5.7.3-vs17-x64.zip" -> "net-snmp")
            $libName = $line -replace '-\d.*$', ''

            if ($downloadedLibs -contains $libName) {
                Write-Host "Skipping package $line (already downloaded from workflow run)"
                continue
            }

            Write-Host "Processing package $line"
            $temp = New-TemporaryFile | Rename-Item -NewName { $_.Name + '.zip' } -PassThru
            $url = "$baseurl/$VsVersion/$Arch/$line"
            Get-File -Url $url -OutFile $temp.FullName
            try {
                Expand-Archive -LiteralPath $temp.FullName -DestinationPath $Destination -Force
            } catch {
                Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
                [System.IO.Compression.ZipFile]::ExtractToDirectory($temp.FullName, $Destination)
            } finally {
                Remove-Item -LiteralPath $temp.FullName -Force -ErrorAction SilentlyContinue
            }
        }

        $extra = Join-Path $Destination 'openssl.cnf'
        if (Test-Path -LiteralPath $extra) {
            $tdir = Join-Path $Destination 'template\ssl'
            New-Item -ItemType Directory -Force -Path $tdir | Out-Null
            Move-Item -LiteralPath $extra -Destination (Join-Path $tdir 'openssl.cnf') -Force
        }
    }
}
