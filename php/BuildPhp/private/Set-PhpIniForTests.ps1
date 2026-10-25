function Set-PhpIniForTests {
    <#
    .SYNOPSIS
        Set PHP INI for tests.
    .PARAMETER BuildDirectory
        Build directory
    .PARAMETER Arch
        Architecture (x86 or x64)
    .PARAMETER Opcache
        Opcache
    .PARAMETER TestType
        Test type
    .PARAMETER PhpVersion
        PHP version used to select extension INI settings.
    #>
    [OutputType()]
    param (
        [Parameter(Mandatory = $true, Position=0, HelpMessage='Build directory')]
        [ValidateNotNull()]
        [ValidateLength(1, [int]::MaxValue)]
        [string] $BuildDirectory,
        [Parameter(Mandatory = $true, Position=1, HelpMessage='Architecture')]
        [ValidateNotNull()]
        [ValidateSet('x86', 'x64')]
        [string] $Arch,
        [Parameter(Mandatory = $true, Position=2, HelpMessage='Specify Cache')]
        [ValidateSet('nocache', 'opcache')]
        [string] $Opcache,
        [Parameter(Mandatory = $true, Position=3, HelpMessage='Test type')]
        [ValidateSet('ext', 'php')]
        [string] $TestType,
        [Parameter(Mandatory = $true, Position=4, HelpMessage='PHP version')]
        [string] $PhpVersion
    )
    begin {
    }
    process {
        $ini = Join-Path $BuildDirectory 'phpbin\php.ini'
        $iniTemplate = Join-Path $PSScriptRoot "..\config\ini\$TestType.ini"
        # The complete extension configuration was validated for PHP 7.2+.
        # Earlier packages do not contain all of these DLLs (for example sodium).
        if ($TestType -eq 'ext' -and $PhpVersion -match '^(\d+\.\d+)' -and
            [version]$Matches[1] -lt [version]'7.2') {
            $iniTemplate = Join-Path $PSScriptRoot '..\config\ini\pre-7.2\ext.ini'
        }
        Copy-Item $iniTemplate $ini -Force
        if ($PhpVersion -match '^(\d+\.\d+)') {
            $versionIni = "$PSScriptRoot\..\config\ini\$($Matches[1])\$TestType.ini"
            if (Test-Path $versionIni -PathType Leaf) {
                Add-Content $ini (Get-Content $versionIni)
            }
        }
        Add-Content $ini "extension_dir=$BuildDirectory\phpbin\ext"
        $testIni = Join-Path $BuildDirectory 'phpbin\php-test.ini'
        Copy-Item $ini $testIni -Force

        if ($Opcache -eq "opcache") {
            $opcacheDll = "$BuildDirectory\phpbin\ext\php_opcache.dll"
            if (Test-Path $opcacheDll -PathType Leaf) {
                Add-Content $testIni "zend_extension=`"$opcacheDll`""
            }
            if ($TestType -eq "php") {
                New-Item "$BuildDirectory/file_cache" -ItemType "directory" -Force > $null 2>&1
            }
            $opcacheIniPath = "$PSScriptRoot\..\config\ini\opcache-$TestType-$Arch.ini"
            $opcacheIni = Get-Content $opcacheIniPath -Raw -ErrorAction Stop
            $opcacheIni = $opcacheIni.Replace("OPCACHE_ERROR_LOG_PATH", "$BuildDirectory\opcache_error.log")
            $opcacheIni = $opcacheIni.Replace("OPCACHE_FILE_CACHE_PATH", "$BuildDirectory\file_cache")
            Add-Content $testIni $opcacheIni
        } else {
            Add-Content $testIni @('opcache.enable=0', 'opcache.enable_cli=0')
        }
    }
    end {
    }
}
