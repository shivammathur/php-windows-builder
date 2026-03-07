function Invoke-FrankenPhpBuild {
    <#
    .SYNOPSIS
        Build a FrankenPHP package from a thread-safe PHP build.
    .PARAMETER PhpVersion
        PHP Version
    .PARAMETER Arch
        PHP Architecture
    .PARAMETER ArtifactsDirectory
        Directory containing the PHP artifacts to reuse
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='PHP Version')]
        [ValidateNotNull()]
        [ValidateLength(1, [int]::MaxValue)]
        [string] $PhpVersion,
        [Parameter(Mandatory = $true, Position=1, HelpMessage='PHP Architecture')]
        [ValidateNotNull()]
        [ValidateSet('x86', 'x64')]
        [string] $Arch,
        [Parameter(Mandatory = $false, Position=2, HelpMessage='Artifacts directory')]
        [string] $ArtifactsDirectory = ''
    )
    begin {
    }
    process {
        function Expand-ZipArchive {
            param (
                [Parameter(Mandatory = $true)]
                [string] $ArchivePath,
                [Parameter(Mandatory = $true)]
                [string] $DestinationPath
            )

            if (-not (Test-Path -LiteralPath $DestinationPath)) {
                New-Item -ItemType Directory -Force -Path $DestinationPath | Out-Null
            }

            try {
                Expand-Archive -LiteralPath $ArchivePath -DestinationPath $DestinationPath -Force
            } catch {
                7z x $ArchivePath "-o$DestinationPath" -y | Out-Null
            }
        }

        function Get-GitHubHeaders {
            $headers = @{
                'Accept' = 'application/vnd.github+json'
                'User-Agent' = 'php-windows-builder'
                'X-GitHub-Api-Version' = '2022-11-28'
            }
            if ($env:GITHUB_TOKEN) {
                $headers['Authorization'] = 'Bearer ' + $env:GITHUB_TOKEN
            }

            return $headers
        }

        function Get-LatestPeclDepsPackage {
            param (
                [Parameter(Mandatory = $true)]
                [string] $Library,
                [Parameter(Mandatory = $true)]
                [string] $VsVersion,
                [Parameter(Mandatory = $true)]
                [ValidateSet('x86', 'x64')]
                [string] $Arch,
                [Parameter(Mandatory = $true)]
                [string] $Destination
            )

            $pattern = '^' + [regex]::Escape($Library) + '-([0-9][0-9A-Za-z\.\-]*)-' + [regex]::Escape($VsVersion) + '-' + [regex]::Escape($Arch) + '\.zip$'
            $options = @()
            foreach ($link in $peclDepsIndex.Links) {
                if ($null -eq $link.href) {
                    continue
                }

                $fileName = Split-Path -Path $link.href -Leaf
                if ($fileName -match $pattern) {
                    $versionToken = ($matches[1] -split '-')[0]
                    if ($versionToken -notmatch '\.') {
                        $versionToken += '.0'
                    }

                    $options += [PSCustomObject]@{
                        file = $fileName
                        version = $versionToken
                    }
                }
            }

            if (-not $options) {
                throw "Could not find a PECL dependency package for $Library ($VsVersion/$Arch)."
            }

            $latest = $options |
                Sort-Object -Property { [version] $_.version } -Descending |
                Select-Object -First 1

            New-Item -ItemType Directory -Force -Path $Destination | Out-Null

            $archivePath = Join-Path $Destination $latest.file
            $packageUrl = "https://downloads.php.net/~windows/pecl/deps/$($latest.file)"
            Get-File -Url $packageUrl -OutFile $archivePath
            Expand-ZipArchive -ArchivePath $archivePath -DestinationPath $Destination

            return [PSCustomObject]@{
                file = $latest.file
                path = $Destination
            }
        }

        Set-NetSecurityProtocolType

        $vsData = Get-VsVersion -PhpVersion $PhpVersion
        if($null -eq $vsData.vs) {
            throw "PHP version $PhpVersion is not supported."
        }

        $currentDirectory = (Get-Location).Path
        $artifactsDirectoryProvided = -not [string]::IsNullOrWhiteSpace($ArtifactsDirectory)
        if([string]::IsNullOrWhiteSpace($ArtifactsDirectory)) {
            $ArtifactsDirectory = Join-Path $currentDirectory 'artifacts'
        }

        if(-not(Test-Path -LiteralPath $ArtifactsDirectory)) {
            if($artifactsDirectoryProvided) {
                throw "Artifacts directory '$ArtifactsDirectory' does not exist."
            }

            New-Item -ItemType Directory -Force -Path $ArtifactsDirectory | Out-Null
        }

        $artifactsPath = (Resolve-Path $ArtifactsDirectory).Path

        $tempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("frankenphp-" + [System.Guid]::NewGuid().ToString())
        $packageDirectory = Join-Path $tempDirectory 'package'
        $develDirectory = Join-Path $tempDirectory 'devel'
        $sourceDirectory = Join-Path $tempDirectory 'source'
        $depsDirectory = Join-Path $tempDirectory 'deps'
        $watcherDirectory = Join-Path $tempDirectory 'watcher'

        foreach($path in @($tempDirectory, $packageDirectory, $develDirectory, $sourceDirectory, $depsDirectory, $watcherDirectory)) {
            New-Item -ItemType Directory -Force -Path $path | Out-Null
        }

        $versionInUrl = if($PhpVersion -eq 'master') { 'master' } else { $PhpVersion }
        $tsBuildZipFile = "php-$versionInUrl-Win32-$($vsData.vs)-$Arch.zip"
        $tsDevelZipFile = "php-devel-pack-$versionInUrl-Win32-$($vsData.vs)-$Arch.zip"
        $frankenBuildZipFile = "php-$versionInUrl-franken-Win32-$($vsData.vs)-$Arch.zip"
        $frankenBuildZipPath = Join-Path $tempDirectory $frankenBuildZipFile

        $tsBuildZipPath = Join-Path $artifactsPath $tsBuildZipFile
        $tsDevelZipPath = Join-Path $artifactsPath $tsDevelZipFile

        $hasTsBuildArtifact = Test-Path -LiteralPath $tsBuildZipPath
        $hasTsDevelArtifact = Test-Path -LiteralPath $tsDevelZipPath

        $phpDevelPath = ''
        if($hasTsBuildArtifact -and $hasTsDevelArtifact) {
            Write-Host "Using thread-safe PHP artifacts from $artifactsPath"
            Expand-ZipArchive -ArchivePath $tsBuildZipPath -DestinationPath $packageDirectory
            Expand-ZipArchive -ArchivePath $tsDevelZipPath -DestinationPath $develDirectory

            $phpDevelDirectory = Get-ChildItem -Path $develDirectory -Directory | Select-Object -First 1
            if($null -eq $phpDevelDirectory) {
                throw "Failed to extract the PHP developer build from $tsDevelZipFile."
            }

            $phpDevelPath = $phpDevelDirectory.FullName
        } else {
            $missingArtifacts = @()
            if(-not $hasTsBuildArtifact) {
                $missingArtifacts += $tsBuildZipFile
            }
            if(-not $hasTsDevelArtifact) {
                $missingArtifacts += $tsDevelZipFile
            }

            throw "Required TS artifacts were not found in $artifactsPath. Missing: $($missingArtifacts -join ', '). FrankenPHP must use the matching runtime and devel artifacts from the same PHP build."
        }

        $githubHeaders = Get-GitHubHeaders
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/php/frankenphp/releases/latest' -Headers $githubHeaders -Method Get
        $resolvedFrankenPhpRef = $release.tag_name

        $frankenPhpVersion = if($resolvedFrankenPhpRef -match '^v?(.+)$') { $matches[1] } else { $resolvedFrankenPhpRef }
        $frankenPhpCVersion = if($frankenPhpVersion -match '^[0-9A-Za-z\.\-_]+$') { $frankenPhpVersion } else { 'dev' }

        $frankenSourceArchive = Join-Path $tempDirectory 'frankenphp.zip'
        $tagArchiveUrl = "https://codeload.github.com/php/frankenphp/zip/refs/tags/$resolvedFrankenPhpRef"
        $branchArchiveUrl = "https://codeload.github.com/php/frankenphp/zip/refs/heads/$resolvedFrankenPhpRef"
        Get-File -Url $tagArchiveUrl -FallbackUrl $branchArchiveUrl -OutFile $frankenSourceArchive
        Expand-ZipArchive -ArchivePath $frankenSourceArchive -DestinationPath $sourceDirectory

        $frankenSourcePath = (Get-ChildItem -Path $sourceDirectory -Directory | Select-Object -First 1).FullName
        if(-not(Test-Path -LiteralPath $frankenSourcePath)) {
            throw "Failed to prepare the FrankenPHP source tree."
        }

        $peclDepsIndex = Invoke-WebRequest -Uri 'https://downloads.php.net/~windows/pecl/deps/' -UseBasicParsing
        $brotliPath = Join-Path $depsDirectory 'brotli'
        $pthreadsPath = Join-Path $depsDirectory 'pthreads'
        $brotliPackage = Get-LatestPeclDepsPackage -Library 'brotli' -VsVersion $vsData.vs -Arch $Arch -Destination $brotliPath
        $pthreadsPackage = Get-LatestPeclDepsPackage -Library 'pthreads' -VsVersion $vsData.vs -Arch $Arch -Destination $pthreadsPath

        Write-Host "Using $($brotliPackage.file) and $($pthreadsPackage.file) from the PECL dependency mirror"

        $watcherRoot = ''
        $watcherEnabled = $false
        if($Arch -eq 'x64') {
            try {
                $watcherRelease = Invoke-RestMethod -Uri 'https://api.github.com/repos/e-dant/watcher/releases/latest' -Headers $githubHeaders -Method Get
                $watcherAsset = $watcherRelease.assets | Where-Object { $_.name -eq 'x86_64-pc-windows-msvc.tar' } | Select-Object -First 1
                if($null -eq $watcherAsset) {
                    throw "The latest Watcher release does not contain x86_64-pc-windows-msvc.tar."
                }

                $watcherArchive = Join-Path $tempDirectory 'watcher.tar'
                Invoke-WebRequest -Uri $watcherAsset.browser_download_url -Headers $githubHeaders -OutFile $watcherArchive -UseBasicParsing
                tar -xf $watcherArchive -C $watcherDirectory

                $watcherDirectoryInfo = Get-ChildItem -Path $watcherDirectory -Directory | Select-Object -First 1
                if($null -eq $watcherDirectoryInfo) {
                    throw "The Watcher archive did not extract into a directory."
                }

                $watcherRoot = $watcherDirectoryInfo.FullName
                if(-not(Test-Path -LiteralPath (Join-Path $watcherRoot 'libwatcher-c.lib'))) {
                    throw "The Watcher archive does not contain libwatcher-c.lib."
                }

                $watcherEnabled = $true
            } catch {
                throw "Failed to prepare Watcher for the x64 FrankenPHP build. $($_.Exception.Message)"
            }
        } else {
            Write-Warning "Watcher binaries are not published for Windows x86. Building FrankenPHP without watcher support."
        }

        $installerDirectory = Join-Path "${env:ProgramFiles(x86)}\Microsoft Visual Studio" 'Installer'
        $vswherePath = Join-Path $installerDirectory 'vswhere.exe'
        if(-not(Test-Path -LiteralPath $vswherePath)) {
            New-Item -ItemType Directory -Force -Path $installerDirectory | Out-Null
            Get-File -Url 'https://github.com/microsoft/vswhere/releases/latest/download/vswhere.exe' -OutFile $vswherePath
        }

        $llvmPath = & $vswherePath -latest -products * -find "VC\Tools\Llvm\bin"
        if(-not $llvmPath) {
            $jsonPath = [System.IO.Path]::Combine($PSScriptRoot, '..\config\vs.json')
            $vsConfig = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
            $vsConfig.vs.$($vsData.vs).components += 'Microsoft.VisualStudio.Component.VC.Llvm.Clang'
            Add-Vs -VsVersion $vsData.vs -VsConfig $vsConfig
            $llvmPath = & $vswherePath -latest -products * -find "VC\Tools\Llvm\bin"
        }

        if(-not $llvmPath) {
            throw "The LLVM toolchain required for FrankenPHP is not available."
        }

        $llvmPath = @($llvmPath | Select-Object -First 1)[0]
        $frankenPhpBuildPath = Join-Path $frankenSourcePath 'caddy\frankenphp'
        $frankenPhpBinary = Join-Path $frankenPhpBuildPath 'frankenphp.exe'
        $frankenPhpIcon = Join-Path $frankenSourcePath 'frankenphp.ico'

        Push-Location $frankenPhpBuildPath
        try {
            & go install github.com/josephspurrier/goversioninfo/cmd/goversioninfo@latest
            if (-not $?) {
                throw "Failed to install goversioninfo."
            }

            $goPath = (& go env GOPATH).Trim()
            $goversioninfoPath = Join-Path $goPath 'bin\goversioninfo.exe'
            if(-not(Test-Path -LiteralPath $goversioninfoPath)) {
                throw "goversioninfo.exe was not installed successfully."
            }

            $majorVersion = 0
            $minorVersion = 0
            $patchVersion = 0
            if ($frankenPhpVersion -match '^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)') {
                $majorVersion = [int]$matches['major']
                $minorVersion = [int]$matches['minor']
                $patchVersion = [int]$matches['patch']
            }

            $versionInfo = @{
                FixedFileInfo = @{
                    FileVersion = @{ Major = $majorVersion; Minor = $minorVersion; Patch = $patchVersion; Build = 0 }
                    ProductVersion = @{ Major = $majorVersion; Minor = $minorVersion; Patch = $patchVersion; Build = 0 }
                }
                StringFileInfo = @{
                    CompanyName = "FrankenPHP"
                    FileDescription = "The modern PHP app server"
                    FileVersion = $frankenPhpVersion
                    InternalName = "frankenphp"
                    OriginalFilename = "frankenphp.exe"
                    LegalCopyright = "(c) 2022 Kevin Dunglas, MIT License"
                    ProductName = "FrankenPHP"
                    ProductVersion = $frankenPhpVersion
                    Comments = "https://frankenphp.dev/"
                }
                VarFileInfo = @{
                    Translation = @{ LangID = 9; CharsetID = 1200 }
                }
            } | ConvertTo-Json -Depth 10

            Set-Content -Path 'versioninfo.json' -Value $versionInfo -Encoding ascii

            $goversioninfoArgs = @()
            if($Arch -eq 'x64') {
                $goversioninfoArgs += '-64'
            }
            $goversioninfoArgs += @('-icon', $frankenPhpIcon, 'versioninfo.json', '-o', 'resource.syso')
            & $goversioninfoPath @goversioninfoArgs
            if (-not $?) {
                throw "Failed to embed Windows metadata in the FrankenPHP binary."
            }

            $goArch = if($Arch -eq 'x86') { '386' } else { 'amd64' }
            $goTags = 'nobadger,nomysql,nopgx'
            if(-not $watcherEnabled) {
                $goTags += ',nowatcher'
            }

            $includePaths = @(
                "-I$($brotliPath)\include",
                "-I$($pthreadsPath)\include"
            )
            if($watcherEnabled) {
                $includePaths += "-I$watcherRoot"
            }
            $includePaths += @(
                "-I$phpDevelPath\include",
                "-I$phpDevelPath\include\main",
                "-I$phpDevelPath\include\TSRM",
                "-I$phpDevelPath\include\Zend",
                "-I$phpDevelPath\include\ext"
            )

            $linkerFlags = @(
                "-L$($brotliPath)\lib",
                "-L$($pthreadsPath)\lib",
                '-lbrotlienc'
            )
            if($watcherEnabled) {
                $linkerFlags += @("-L$watcherRoot", '-llibwatcher-c')
            }
            $linkerFlags += @(
                "-L$packageDirectory",
                "-L$phpDevelPath\lib",
                '-lphp8ts',
                '-lphp8embed'
            )

            $pathEntries = @(
                $llvmPath,
                $packageDirectory,
                "$brotliPath\bin",
                "$pthreadsPath\bin"
            )
            if($watcherEnabled) {
                $pathEntries += $watcherRoot
            }

            $env:Path = (($pathEntries + @($env:Path)) -join ';')
            $env:CC = 'clang'
            $env:CXX = 'clang++'
            $env:CGO_ENABLED = '1'
            $env:GOARCH = $goArch
            $env:GOTOOLCHAIN = 'local'
            $env:CGO_CFLAGS = (@("-DFRANKENPHP_VERSION=$frankenPhpCVersion") + $includePaths) -join ' '
            $env:CGO_LDFLAGS = $linkerFlags -join ' '

            $customVersion = "FrankenPHP $frankenPhpVersion PHP $PhpVersion Caddy"
            $ldflags = "-extldflags=-fuse-ld=lld -X `"github.com/caddyserver/caddy/v2.CustomVersion=$customVersion`" -X `"github.com/caddyserver/caddy/v2/modules/caddyhttp.ServerHeader=FrankenPHP Caddy`""

            & go build -tags $goTags -ldflags $ldflags
            if (-not $?) {
                throw "Failed to build FrankenPHP."
            }
        } finally {
            Pop-Location
        }

        Copy-Item -Path $frankenPhpBinary -Destination $packageDirectory -Force
        Copy-Item -Path (Join-Path $brotliPath 'bin\brotlienc.dll') -Destination $packageDirectory -Force
        Copy-Item -Path (Join-Path $brotliPath 'bin\brotlidec.dll') -Destination $packageDirectory -Force
        Copy-Item -Path (Join-Path $brotliPath 'bin\brotlicommon.dll') -Destination $packageDirectory -Force
        Copy-Item -Path (Join-Path $pthreadsPath 'bin\pthreadVC3.dll') -Destination $packageDirectory -Force
        if($watcherEnabled) {
            Copy-Item -Path (Join-Path $watcherRoot 'libwatcher-c.dll') -Destination $packageDirectory -Force
        }

        Push-Location $packageDirectory
        try {
            if(Test-Path -LiteralPath $frankenBuildZipPath) {
                Remove-Item -LiteralPath $frankenBuildZipPath -Force
            }
            Compress-Archive -Path * -DestinationPath $frankenBuildZipPath -Force
        } finally {
            Pop-Location
        }

        Copy-Item -Path $frankenBuildZipPath -Destination $artifactsPath -Force
        if($env:GITHUB_OUTPUT) {
            Add-Content -Path $env:GITHUB_OUTPUT -Value "artifact=$frankenBuildZipFile" -Encoding utf8
        }
    }
    end {
    }
}
