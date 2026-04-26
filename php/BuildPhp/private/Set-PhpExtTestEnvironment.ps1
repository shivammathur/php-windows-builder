function Set-PhpExtTestEnvironment {
    <#
    .SYNOPSIS
        Configure extension-specific test environment dependencies.
    .PARAMETER TestDirectories
        Optional extension test directories to run.
    .PARAMETER BuildDirectory
        PHP build directory.
    .PARAMETER TestsDirectory
        PHP tests directory name.
    .PARAMETER Arch
        PHP architecture.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, Position=0, HelpMessage='Optional extension test directories')]
        [string[]] $TestDirectories = @(),
        [Parameter(Mandatory = $true, Position=1, HelpMessage='PHP build directory')]
        [ValidateNotNull()]
        [ValidateLength(1, [int]::MaxValue)]
        [string] $BuildDirectory,
        [Parameter(Mandatory = $true, Position=2, HelpMessage='PHP tests directory')]
        [ValidateNotNull()]
        [ValidateLength(1, [int]::MaxValue)]
        [string] $TestsDirectory,
        [Parameter(Mandatory = $true, Position=3, HelpMessage='PHP architecture')]
        [ValidateSet('x86', 'x64')]
        [string] $Arch
    )
    process {
        $runAllExtSetup = $null -eq $TestDirectories -or $TestDirectories.Count -eq 0
        $effectiveTestDirectories = if($runAllExtSetup) {
            Get-Content "$PSScriptRoot\..\config\ext_test_directories"
        } else {
            $TestDirectories
        }
        $testDirectoryText = (@($effectiveTestDirectories) -join ';').ToLowerInvariant()

        $testEnvironmentSetups = @(
            [pscustomobject] @{
                Match = @('mysql')
                Command = 'Set-MySqlTestEnvironment'
                Parameters = @{}
            },
            [pscustomobject] @{
                Match = @('pgsql', 'pdo_pgsql')
                Command = 'Set-PgSqlTestEnvironment'
                Parameters = @{}
            },
            [pscustomobject] @{
                Match = @('odbc', 'pdo_odbc')
                Command = 'Set-OdbcTestEnvironment'
                Parameters = @{}
            },
            [pscustomobject] @{
                Match = @('sqlsrv', 'pdo_sqlsrv')
                Command = 'Set-MsSqlTestEnvironment'
                Parameters = @{}
            },
            [pscustomobject] @{
                Match = @('firebird', 'interbase')
                Command = 'Set-FirebirdTestEnvironment'
                Parameters = @{
                    Arch = $Arch
                }
            },
            [pscustomobject] @{
                Match = @('openssl')
                Command = 'Set-OpenSslTestEnvironment'
                Parameters = @{
                    PhpBinDirectory = "$BuildDirectory\phpbin"
                }
            },
            [pscustomobject] @{
                Match = @('enchant')
                Command = 'Set-EnchantTestEnvironment'
                Parameters = @{}
            },
            [pscustomobject] @{
                Match = @('snmp')
                Command = 'Set-SnmpTestEnvironment'
                Parameters = @{
                    TestsDirectoryPath = "$BuildDirectory\$TestsDirectory"
                }
            }
        )

        $selectedSetups = $testEnvironmentSetups | Where-Object {
            $setup = $_
            @($setup.Match | Where-Object { $testDirectoryText.Contains($_) }).Count -gt 0
        }

        foreach($setup in $selectedSetups) {
            $parameters = $setup.Parameters
            & $setup.Command @parameters
        }
    }
}
