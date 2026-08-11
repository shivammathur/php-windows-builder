function Get-ExtensionSbomMetadata {
    <#
    .SYNOPSIS
        Detect extension metadata and license evidence from its clean source tree.
    #>
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [string] $SourcePath,
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [string] $Version,
        [string] $SourceUrl = '',
        [string] $ScanCodePath = ''
    )

    if(-not(Test-Path -LiteralPath $SourcePath -PathType Container)) {
        throw "Extension source '$SourcePath' was not found."
    }
    if(-not($ScanCodePath)) { $ScanCodePath = Get-SbomTool -Name scancode }

    $workingDirectory = Join-Path ([IO.Path]::GetTempPath()) "extension-source-scan-$([Guid]::NewGuid())"
    New-Item -Path $workingDirectory -ItemType Directory -Force | Out-Null
    try {
        $scanPath = Join-Path $workingDirectory 'scancode.json'
        $arguments = @(
            '--license'
            '--license-text'
            '--copyright'
            '--package'
            '--summary'
            '--classify'
            '--license-clarity-score'
            '--only-findings'
            '--strip-root'
            '--ignore', '*/.git/*'
            '--ignore', '*.tgz'
            '--quiet'
            '--json', $scanPath
            (Resolve-Path -LiteralPath $SourcePath).Path
        )
        Push-Location (Split-Path -Path $ScanCodePath -Parent)
        try {
            & $ScanCodePath @arguments | Out-Host
            $succeeded = $?
            $exitCode = Get-Variable -Name LASTEXITCODE -ValueOnly -ErrorAction SilentlyContinue
        } finally {
            Pop-Location
        }
        if(-not($succeeded) -or ($null -ne $exitCode -and $exitCode -ne 0)) {
            throw "ScanCode failed with exit code $exitCode."
        }
        $scan = Read-SbomJson -Path $scanPath
    } finally {
        if(Test-Path -LiteralPath $workingDirectory -PathType Container) {
            Remove-Item -LiteralPath $workingDirectory -Recurse -Force
        }
    }

    $rootPackage = $null
    if($null -ne $scan.PSObject.Properties['packages']) {
        $rootPackage = @($scan.packages | Where-Object {
            $null -ne $_ -and @($_.datafile_paths | ForEach-Object {
                ([string]$_).Replace('\', '/').TrimStart([char[]]'./')
            }) -contains 'composer.json'
        }) | Select-Object -First 1
    }

    $authors = @()
    $description = ''
    $homepage = ''
    $vcsUrl = ''
    $purl = ''
    $metadataEvidence = ''
    if($null -ne $rootPackage) {
        $authors = @($rootPackage.parties | Where-Object {
            $_.role -eq 'author' -and -not([string]::IsNullOrWhiteSpace([string]$_.name))
        } | ForEach-Object {
            [PSCustomObject][ordered]@{
                type = if($_.type -eq 'organization') { 'organization' } else { 'person' }
                name = [string]$_.name
                email = [string]$_.email
            }
        })
        $description = [string]$rootPackage.description
        $homepage = [string]$rootPackage.homepage_url
        if(-not($homepage)) { $homepage = [string]$rootPackage.repository_homepage_url }
        $vcsUrl = [string]$rootPackage.vcs_url
        $purl = [string]$rootPackage.purl
        $metadataEvidence = 'composer.json'
    }

    $packageXmlPath = Join-Path $SourcePath 'package.xml'
    if(Test-Path -LiteralPath $packageXmlPath -PathType Leaf) {
        try {
            [xml]$packageXml = Get-Content -LiteralPath $packageXmlPath -Raw
            if($authors.Count -eq 0) {
                $authors = @($packageXml.SelectNodes("/*[local-name()='package']/*[(local-name()='lead' or local-name()='developer') and not(*[local-name()='active']='no')]") |
                    ForEach-Object {
                        $nameNode = $_.SelectSingleNode("./*[local-name()='name']")
                        $emailNode = $_.SelectSingleNode("./*[local-name()='email']")
                        [PSCustomObject][ordered]@{
                            type = 'person'
                            name = if($null -ne $nameNode) { [string]$nameNode.InnerText } else { '' }
                            email = if($null -ne $emailNode) { [string]$emailNode.InnerText } else { '' }
                        }
                    } | Where-Object { $_.name })
            }
            if(-not($description)) {
                $summaryNode = $packageXml.SelectSingleNode("/*[local-name()='package']/*[local-name()='summary']")
                if($null -ne $summaryNode) {
                    $description = [regex]::Replace($summaryNode.InnerText, '\s+', ' ').Trim()
                }
            }
            if(-not($metadataEvidence)) { $metadataEvidence = 'package.xml' }
        } catch {
            Write-Warning "Ignoring invalid optional PECL metadata at '$packageXmlPath': $($_.Exception.Message)"
        }
    }

    $license = ''
    $declaredLicense = ''
    if($null -ne $scan.PSObject.Properties['summary']) {
        $declaredLicense = [string]$scan.summary.declared_license_expression
    }
    if($declaredLicense -and $null -ne $scan.PSObject.Properties['license_detections']) {
        $license = [string](@($scan.license_detections | Where-Object {
            $_.license_expression -eq $declaredLicense
        }) | Select-Object -First 1).license_expression_spdx
    }

    $legalFiles = @()
    if($null -ne $scan.PSObject.Properties['files']) {
        $legalFiles = @($scan.files | Where-Object {
            $null -ne $_ -and $_.is_top_level -and $_.is_legal
        })
    }
    if(-not($license)) {
        $legalLicenseFile = @($legalFiles | Where-Object {
            $null -ne $_ -and $_.detected_license_expression_spdx
        }) | Select-Object -First 1
        if($null -ne $legalLicenseFile) {
            $license = [string]$legalLicenseFile.detected_license_expression_spdx
        }
    }
    if(-not($license) -and $null -ne $rootPackage) {
        $license = [string]$rootPackage.declared_license_expression_spdx
    }

    $licenseEvidence = @($legalFiles | Where-Object {
        $null -ne $_ -and $_.detected_license_expression_spdx
    } | ForEach-Object { ([string]$_.path).Replace('\', '/') } | Select-Object -Unique)
    $copyright = @($legalFiles | ForEach-Object { $_.copyrights } | ForEach-Object {
        [string]$_.copyright
    } | Where-Object { $_ } | Select-Object -Unique) -join '; '
    $licenseRefs = @()
    if($license -match 'LicenseRef-') {
        $licenseRefIds = @([regex]::Matches($license, 'LicenseRef-[A-Za-z0-9.-]+') |
            ForEach-Object { $_.Value } | Select-Object -Unique)
        foreach($licenseRefId in $licenseRefIds) {
            $licenseTexts = @($legalFiles | Where-Object {
                ([string]$_.detected_license_expression_spdx).Contains($licenseRefId)
            } | ForEach-Object {
                $licensePath = Join-Path $SourcePath ([string]$_.path)
                if(Test-Path -LiteralPath $licensePath -PathType Leaf) {
                    (Get-Content -LiteralPath $licensePath -Raw).Trim()
                }
            } | Where-Object { $_ } | Select-Object -Unique)
            if($licenseTexts.Count -gt 0) {
                $licenseRefs += [PSCustomObject][ordered]@{
                    id = $licenseRefId
                    text = $licenseTexts -join [Environment]::NewLine
                }
            }
        }
        if($licenseRefs.Count -ne $licenseRefIds.Count) {
            $license = ''
            $licenseRefs = @()
        }
    }

    if(-not($homepage) -and $SourceUrl -match '(?i)pecl\.php\.net') {
        $homepage = $SourceUrl
    } elseif(-not($vcsUrl) -and $SourceUrl -match '(?i)(github|gitlab|bitbucket|\.git(?:$|[?#]))') {
        $vcsUrl = $SourceUrl
    }
    if(-not($purl)) {
        $slug = (ConvertTo-SbomSlug -Value $Name).ToLowerInvariant()
        $purl = "pkg:generic/$slug@$([Uri]::EscapeDataString($Version))"
    } elseif($Version -and $purl -notmatch '@') {
        $purl = "$purl@$([Uri]::EscapeDataString($Version))"
    }

    $scannerName = 'scancode-toolkit'
    $scannerVersion = (Get-SbomConfiguration -Name settings).tools.scancode.version
    if($null -ne $scan.PSObject.Properties['headers'] -and @($scan.headers).Count -gt 0) {
        $scannerName = [string]$scan.headers[0].tool_name
        $scannerVersion = [string]$scan.headers[0].tool_version
    }

    return [PSCustomObject][ordered]@{
        name = $Name
        version = $Version
        description = $description
        authors = $authors
        homepage = $homepage
        vcs_url = $vcsUrl
        source_url = $SourceUrl
        purl = $purl
        license = $license
        license_refs = $licenseRefs
        copyright = $copyright
        metadata_evidence = $metadataEvidence
        license_evidence = $licenseEvidence
        scanner = [PSCustomObject][ordered]@{
            name = $scannerName
            version = $scannerVersion
        }
    }
}
