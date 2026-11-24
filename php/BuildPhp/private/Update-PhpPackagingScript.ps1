function Update-PhpPackagingScript {
    param([string] $PhpVersion, [string] $SourceDirectory)

    if ($PhpVersion -match '^7\.2\.') {
        # The SDK's packaging interpreter requires square-bracket string offsets.
        $path = Join-Path $SourceDirectory 'win32/build/mkdist.php'
        $script = [IO.File]::ReadAllText($path)
        if ($script.Contains('$hdr_data{$i}')) {
            [IO.File]::WriteAllText($path, $script.Replace('$hdr_data{$i}', '$hdr_data[$i]'))
        }
    }
}
