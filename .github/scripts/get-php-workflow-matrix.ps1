[CmdletBinding(DefaultParameterSetName = 'InputVersion')]
param(
    [Parameter(ParameterSetName = 'InputVersion', Mandatory = $true)]
    [string]$PhpVersion,

    [Parameter(ParameterSetName = 'VersionHeader', Mandatory = $true)]
    [string]$VersionHeaderPath,

    [string]$OutputPath = $env:GITHUB_OUTPUT,

    [bool]$SupportsArm64Override
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$parameterSetName = $PSCmdlet.ParameterSetName

function Get-PhpVersionFromHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Could not find php_version.h in $Path"
    }

    $versionContent = Get-Content -LiteralPath $Path -Raw
    $majorMatch = [regex]::Match($versionContent, 'PHP_MAJOR_VERSION\s+(\d+)')
    $minorMatch = [regex]::Match($versionContent, 'PHP_MINOR_VERSION\s+(\d+)')

    if (-not $majorMatch.Success -or -not $minorMatch.Success) {
        throw 'Could not determine PHP major/minor version from php_version.h'
    }

    return "$($majorMatch.Groups[1].Value).$($minorMatch.Groups[1].Value)"
}

function Resolve-PhpVersion {
    if ($parameterSetName -eq 'VersionHeader') {
        return Get-PhpVersionFromHeader -Path $VersionHeaderPath
    }

    return $PhpVersion
}

function Test-SupportsArm64 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    if ($Version -eq 'master') {
        return $true
    }

    $versionMatch = [regex]::Match($Version, '(\d+)\.(\d+)')
    if (-not $versionMatch.Success) {
        return $false
    }

    $normalizedVersion = "$($versionMatch.Groups[1].Value).$($versionMatch.Groups[2].Value)"
    return [version]$normalizedVersion -ge [version]'8.0'
}

function Get-ArchConfigs {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$SupportsArm64
    )

    $archConfigs = @(
        [PSCustomObject]@{ arch = 'x64'; os = 'windows-2022' },
        [PSCustomObject]@{ arch = 'x86'; os = 'windows-2022' }
    )

    if ($SupportsArm64) {
        $archConfigs += [PSCustomObject]@{ arch = 'arm64'; os = 'windows-11-arm' }
    }

    return $archConfigs
}

function New-MatrixJson {
    param(
        [Parameter(Mandatory = $true)]
        [array]$ArchConfigs,

        [string[]]$TsValues = @('nts', 'ts'),

        [string[]]$OpcacheValues,

        [string[]]$TestTypes
    )

    $include = @()
    foreach ($archConfig in $ArchConfigs) {
        foreach ($ts in $TsValues) {
            if ($OpcacheValues -and $TestTypes) {
                foreach ($opcache in $OpcacheValues) {
                    foreach ($testType in $TestTypes) {
                        $include += [PSCustomObject]@{
                            arch      = $archConfig.arch
                            os        = $archConfig.os
                            ts        = $ts
                            opcache   = $opcache
                            test_type = $testType
                        }
                    }
                }
            } else {
                $include += [PSCustomObject]@{
                    arch = $archConfig.arch
                    os   = $archConfig.os
                    ts   = $ts
                }
            }
        }
    }

    return ConvertTo-Json @{ include = $include } -Compress -Depth 4
}

$resolvedPhpVersion = Resolve-PhpVersion
$supportsArm64 = if ($PSBoundParameters.ContainsKey('SupportsArm64Override')) {
    $SupportsArm64Override
} else {
    Test-SupportsArm64 -Version $resolvedPhpVersion
}
$archConfigs = Get-ArchConfigs -SupportsArm64:$supportsArm64

$outputs = [ordered]@{
    'php-version'    = $resolvedPhpVersion
    'supports-arm64' = $supportsArm64.ToString().ToLowerInvariant()
    'build-matrix'   = New-MatrixJson -ArchConfigs $archConfigs
    'test-matrix'    = New-MatrixJson -ArchConfigs $archConfigs -OpcacheValues @('opcache', 'nocache') -TestTypes @('php', 'ext')
    'smoke-matrix'   = New-MatrixJson -ArchConfigs $archConfigs
}

if ($OutputPath) {
    foreach ($entry in $outputs.GetEnumerator()) {
        Add-Content -Path $OutputPath -Value "$($entry.Key)=$($entry.Value)"
    }
}

[PSCustomObject]$outputs
