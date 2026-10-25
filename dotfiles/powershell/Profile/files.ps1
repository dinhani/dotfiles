# Archives each item in a path to its own 7z, zip, chd or rvz file.
function Compress-Item {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [ValidateSet("7z", "zip", "chd", "rvz")]
        [string]$Type = "7z",

        [Parameter(Mandatory = $false)]
        [ValidateSet("cd", "dvd")]
        [string]$ChdType = "cd",

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 9)]
        [int]$Level = 9,

        [Parameter(Mandatory = $false)]
        [Alias("j")]
        [int]$Parallel = 1,

        [Parameter(Mandatory = $false)]
        [ValidateSet("All", "Directory", "File")]
        [string]$Kind = "All"
    )

    # parse output path
    if ($OutputPath -eq "") {
        $OutputPath = $InputPath
    }

    # list items
    Write-Host "Listing ($Kind): $InputPath"
    $archiveExtensions = ".7z", ".gz", ".rar", ".zip"
    $items = @(switch ($Kind) {
        "Directory" { Get-ChildItem $InputPath -Directory }
        "File"      { Get-ChildItem $InputPath -File | Where-Object Extension -notin $archiveExtensions }
        "All"       { Get-ChildItem $InputPath | Where-Object Extension -notin $archiveExtensions }
    })
    Write-Host "Found $($items.Count) items"

    # archive items
    $items | ForEach-Object -ThrottleLimit $Parallel -Parallel {
        $source = $_
        $target = Join-Path $using:OutputPath "$($source.BaseName).$using:Type"
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            Write-Warning "Skipping: $target"
            return
        }

        # build command
        switch ($using:Type) {
            "chd" {
                $operation = switch ($using:ChdType) {
                    "cd"  { "createcd" }
                    "dvd" { "createdvd" }
                }
                $image = if ($source.PSIsContainer) {
                    Get-ChildItem -LiteralPath $source.FullName -File |
                        Where-Object Extension -in ".cue", ".iso" |
                        Sort-Object { $_.Extension -ne ".cue" } |
                        Select-Object -First 1
                } elseif ($source.Extension -eq ".iso") {
                    $source
                }
                if ($null -eq $image) {
                    Write-Warning "Skipping, CHD needs an .iso file or a directory with a .cue or .iso: $($source.FullName)"
                    return
                }
                $tool = "chdman"
                $arguments = @($operation, "--input", $image.FullName, "--output", $target)
            }
            "rvz" {
                $tool = "DolphinTool"
                $arguments = @("convert", "--format=rvz", "--compression=lzma2", "--compression_level=9", "--block_size=2097152", "--input=$($source.FullName)", "--output=$target")
            }
            default {
                $content = if ($source.PSIsContainer) {
                    Join-Path $source.FullName "*"
                } else {
                    $source.FullName
                }
                $tool = "7z"
                $arguments = @("a", "-t$using:Type", "-mx=$using:Level", "-bso0", "-bsp0", $target, $content)
            }
        }

        # archive item
        Write-Host "Archiving: $target"
        Write-Host "$tool $($arguments -join ' ')"
        & $tool @arguments
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to archive: $($source.FullName)"
        }
    }
}

# Extracts or tests each 7z, gz, rar or zip archive in a path.
function Expand-Item {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [Alias("j")]
        [int]$Parallel = 1,

        [Parameter(Mandatory = $false)]
        [switch]$CheckSpace,

        [Parameter(Mandatory = $false)]
        [switch]$Flat,

        [Parameter(Mandatory = $false)]
        [switch]$Test,

        [Parameter(Mandatory = $false)]
        [switch]$MoveBroken
    )

    # parse output path
    if ($OutputPath -eq "") {
        $OutputPath = $InputPath
    }

    # list archived items
    Write-Host "Listing archived files: $InputPath"
    $files = Get-ChildItem $InputPath -File | Where-Object { $_.Extension -in ".7z", ".gz", ".rar", ".zip" }
    Write-Host "Found $($files.Count) files"

    # test files
    if ($Test) {
        $dirBroken = Join-Path $InputPath "_broken"
        if ($MoveBroken) {
            New-Item -Path $dirBroken -ItemType Directory -Force | Out-Null
        }
        $files | ForEach-Object -ThrottleLimit $Parallel -Parallel {
            7z t -bso0 -bsp0 $_.FullName
            if ($LASTEXITCODE -eq 0) {
                Write-Host "OK: $($_.FullName)" -ForegroundColor Green
                return
            }
            Write-Host "Failed: $($_.FullName)" -ForegroundColor Red
            if ($using:MoveBroken) {
                Move-Item -LiteralPath $_.FullName -Destination $using:dirBroken
            }
        }
        return
    }

    # unarchive files
    $files | ForEach-Object -ThrottleLimit $Parallel -Parallel {
        # generate unarchive name
        if ($using:Flat) {
            $unarchive = $using:OutputPath
        } else {
            $unarchive = Join-Path $using:OutputPath "$($_.BaseName)"
            if (Test-Path -LiteralPath $unarchive -PathType Container) {
                Write-Warning "Skipping: $unarchive"
                return
            }
        }

        # check space
        if ($using:CheckSpace) {
            $drive = (Get-Item -Path $using:OutputPath).PSDrive
            if ($drive.Free -lt 20GB) {
                Write-Warning "Skipping. Low free space: $unarchive"
                return
            }
        }

        # unarchive entry
        if ($using:Flat) {
            Write-Host "Unarchiving: $($_.BaseName)"
        } else {
            Write-Host "Unarchiving: $unarchive"
        }
        7z x -bso0 -bsp0 "$($_.FullName)" -y -o"$unarchive"
    }
}

# Stores MD5, SHA1 and CRC32 of each file in a path as alternate data streams.
function Set-FileHash {
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = "Path")]
        [string[]]$Path,

        [Parameter(Mandatory = $true, ParameterSetName = "LiteralPath")]
        [string[]]$LiteralPath,

        [Parameter(Mandatory = $false)]
        [Alias("j")]
        [int]$Parallel = 1,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    # load Crc32
    if (-not ('System.IO.Hashing.Crc32' -as [type])) {
        Add-Type -Path (Get-ChildItem "C:\_scoop\apps\dotnet-sdk\current\sdk" -Recurse -Filter 'System.IO.Hashing.dll' |
            Where-Object { $_.FullName -match 'tools[\\/]net\d' } | Select-Object -Last 1).FullName
    }

    # list files
    $items = if ($PSCmdlet.ParameterSetName -eq "Path") {
        Get-Item -Path $Path
    } else {
        Get-Item -LiteralPath $LiteralPath
    }
    $files = @($items | ForEach-Object {
        if ($_.PSIsContainer) {
            Get-ChildItem -LiteralPath $_.FullName -Recurse -File
        } else {
            $_
        }
    })
    $filesTotal = $files.Count
    $counter = [ref]0
    Write-Host "Found $filesTotal files"

    # hash files
    $files | ForEach-Object -ThrottleLimit $Parallel -Parallel {
        $current = [System.Threading.Interlocked]::Increment(($using:counter))
        Write-Progress -Activity "Hashing" -Status "$current / $using:filesTotal" -PercentComplete ($current / $using:filesTotal * 100)

        # \\?\ prefix for paths over MAX_PATH (scriptblocks can't be $using:'d in -Parallel)
        $path = $_.FullName
        if (-not $path.StartsWith('\\?\')) {
            $path = if ($path.StartsWith('\\')) {
                '\\?\UNC\' + $path.Substring(2)
            } else {
                '\\?\' + $path
            }
        }

        # check which hashes are missing
        $streams = Get-Item -LiteralPath $path -Stream * | Select-Object -ExpandProperty Stream
        $needMD5  = $streams -notcontains "MD5"
        $needSHA1 = $streams -notcontains "SHA1"
        $needCRC  = $streams -notcontains "CRC32"

        # hash file in a single streaming pass (no 2 GB array limit) and store computed hashes
        if ($needMD5 -or $needSHA1 -or $needCRC) {
            Write-Host "Hashing: $($_.FullName)"
            $stream = [System.IO.File]::OpenRead($path)
            $md5  = if ($needMD5)  {
                [System.Security.Cryptography.IncrementalHash]::CreateHash([System.Security.Cryptography.HashAlgorithmName]::MD5)
            }
            $sha1 = if ($needSHA1) {
                [System.Security.Cryptography.IncrementalHash]::CreateHash([System.Security.Cryptography.HashAlgorithmName]::SHA1)
            }
            $crc  = if ($needCRC)  {
                [System.IO.Hashing.Crc32]::new()
            }
            try {
                $buffer = [byte[]]::new(64MB)
                while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    if ($md5)  {
                        $md5.AppendData($buffer, 0, $read)
                    }
                    if ($sha1) {
                        $sha1.AppendData($buffer, 0, $read)
                    }
                    if ($crc) {
                        if ($read -eq $buffer.Length) {
                            $crc.Append($buffer)
                        }
                        else {
                            $tmp = [byte[]]::new($read)
                            [System.Array]::Copy($buffer, $tmp, $read)
                            $crc.Append($tmp)
                        }
                    }
                }
            } finally {
                $stream.Dispose()
            }

            if ($md5) {
                $hashMD5 = [System.Convert]::ToHexString($md5.GetHashAndReset())
                Set-Content -LiteralPath $path -Stream MD5 -Value $hashMD5
                $md5.Dispose()
            }
            if ($sha1) {
                $hashSHA1 = [System.Convert]::ToHexString($sha1.GetHashAndReset())
                Set-Content -LiteralPath $path -Stream SHA1 -Value $hashSHA1
                $sha1.Dispose()
            }
            if ($crc) {
                $hash = $crc.GetCurrentHash()
                [System.Array]::Reverse($hash)
                $hashCRC = [System.Convert]::ToHexString($hash)
                Set-Content -LiteralPath $path -Stream CRC32 -Value $hashCRC
            }
        }

        # output hashes
        if ($using:PassThru) {
            [PSCustomObject]@{
                File  = $_
                MD5   = if ($needMD5) {
                    $hashMD5
                } else {
                    Get-Content -LiteralPath $path -Stream MD5
                }
                SHA1  = if ($needSHA1) {
                    $hashSHA1
                } else {
                    Get-Content -LiteralPath $path -Stream SHA1
                }
                CRC32 = if ($needCRC) {
                    $hashCRC
                } else {
                    Get-Content -LiteralPath $path -Stream CRC32
                }
            }
        }
    }
}

# Lists files with identical MD5 across one or more paths.
function Find-Duplicate {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Path,

        [Parameter(Mandatory = $false)]
        [Alias("j")]
        [int]$Parallel = 1
    )

    # list files
    $files = Get-ChildItem $Path -Recurse -File
    Write-Host "Found $($files.Count) files"

    # group files by size and hash only the ones that have duplicates
    $filesToHash = @($files | Group-Object Length | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Group })
    Write-Host "Found $($filesToHash.Count) files with duplicate sizes"
    if ($filesToHash.Count -eq 0) {
        Write-Host "No duplicates found"
        return
    }
    $hashes = Set-FileHash -LiteralPath $filesToHash.FullName -Parallel $Parallel -PassThru

    # show duplicates
    $duplicates = @($hashes |
            Group-Object MD5 |
            Where-Object { $_.Count -gt 1 } |
            Sort-Object Count)

    if ($duplicates.Count -eq 0) {
        Write-Host "No duplicates found"
        return
    }
    $duplicates | ForEach-Object {
        Write-Host ""
        Write-Host "Duplicates: $($_.Name):"
        $_.Group | Sort-Object { $_.File.CreationTime } | ForEach-Object {
            Write-Host "  $($_.File.CreationTime.ToString("yyyy-MM-dd"))"
            Write-Host "    $($_.File.FullName)"
        }
    }
}
