function Add-ClangProfileRuntime {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('x86', 'x64')][string] $Arch)

    $resourceDirectory = (& clang --print-resource-dir).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Could not locate the Clang resource directory' }
    $runtimeArch = if ($Arch -eq 'x86') { 'i386' } else { 'x86_64' }
    $library = "clang_rt.profile-$runtimeArch.lib"
    $runtimeDirectory = Join-Path $resourceDirectory 'lib/windows'
    if (Test-Path (Join-Path $runtimeDirectory $library)) { return }

    # The Windows x64 LLVM installer does not include the x86 profile runtime.
    # Extract only that library from the matching official installer.
    $versionText = & clang --version | Out-String
    if ($versionText -notmatch 'clang version (\d+\.\d+\.\d+)') { throw 'Could not determine the LLVM runtime version' }
    $version = $Matches[1]
    $platform = if ($Arch -eq 'x86') { 'win32' } else { 'win64' }
    $headers = @{}
    if ($env:GITHUB_TOKEN) { $headers.Authorization = "Bearer $env:GITHUB_TOKEN" }
    $release = Invoke-RestMethod "https://api.github.com/repos/llvm/llvm-project/releases/tags/llvmorg-$version" -Headers $headers
    $asset = @($release.assets | Where-Object name -eq "LLVM-$version-$platform.exe")
    if ($asset.Count -ne 1 -or $asset[0].digest -notmatch '^sha256:([a-f0-9]{64})$') {
        throw "No checksummed LLVM $version $platform installer found; install the matching profiling runtime"
    }
    $expectedHash = $Matches[1]
    $temporary = New-Item (Join-Path ([IO.Path]::GetTempPath()) "llvm-profile-$([guid]::NewGuid())") -ItemType Directory
    $installer = Join-Path $temporary 'llvm.exe'
    Get-File -Url $asset[0].browser_download_url -OutFile $installer
    if ((Get-FileHash $installer -Algorithm SHA256).Hash -ne $expectedHash) { throw 'LLVM installer checksum mismatch' }
    $resourceVersion = Split-Path $resourceDirectory -Leaf
    & 7z e $installer "lib/clang/$resourceVersion/lib/windows/$library" "-o$temporary" -y
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path "$temporary/$library")) { throw "Could not extract $library" }
    New-Item $runtimeDirectory -ItemType Directory -Force | Out-Null
    Copy-Item "$temporary/$library" $runtimeDirectory
    Write-Host "Added LLVM $version $runtimeArch profiling runtime"
}
