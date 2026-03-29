# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------

# Prints each argument passed to the function with its index.
function Write-Args {
    for($i = 0; $i -lt $args.length; $i++) {
        "$i`: $($args[$i])"
    }
}

# Archive each file in the given path to 7z, zip, chd or rvz.
function Invoke-Archive {
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
        [int]$Limit = 1,

        [Parameter(Mandatory = $false)]
        [switch]$Directory,

        [Parameter(Mandatory = $false)]
        [switch]$File
    )

    # parse output path
    if ($OutputPath -eq "") {
        $OutputPath = $InputPath
    }

    # list files
    if ($Directory) {
        Write-Host "Listing directories: $InputPath"
        $files = Get-ChildItem $InputPath -Directory
    } elseif ($File) {
        Write-Host "Listing files: $InputPath"
        $files = Get-ChildItem $InputPath -File | Where-Object { $_.Extension -notin ".7z", ".gz", ".rar", ".zip" }
    } else {
        Write-Host "Listing files and directories: $InputPath"
        $files = Get-ChildItem $InputPath | Where-Object { $_.Extension -notin ".7z", ".gz", ".rar", ".zip" }
    }
    Write-Host "Found $($files.Count) files."

    # archive files
    $files | ForEach-Object -ThrottleLimit $Limit -Parallel {
        # track filename
        $source = $_

        # generate target name
        $target = Join-Path $using:OutputPath "$($_.BaseName).$using:Type"
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            Write-Warning "Skipping: $target"
            continue
        }

        # archive entry
        Write-Host "Archiving: $target"

        switch ($using:Type) {
            "chd" {
                $operation = switch ($using:ChdType) {
                    "cd"  { "createcd" }
                    "dvd" { "createdvd" }
                }
                if ($source.PSIsContainer) {
                    $cueOrIso = $null
                    foreach ($ext in @("*.cue", "*.iso")) {
                        $cueOrIso = Get-ChildItem -Path $source.FullName -Filter $ext | Select-Object -First 1
                        if ($null -ne $cueOrIso) {
                            break
                        }
                    }
                    if ($null -eq $cueOrIso) {
                        Write-Warning "No .cue or .iso file found in directory: $($source.FullName)"
                        continue
                    }
                    $command = "chdman $operation --input `"$($cueOrIso.FullName)`" --output `"$target`""
                } elseif ($_.Extension -eq ".iso") {
                    $command = "chdman $operation --input `"$($source.FullName)`" --output `"$target`""
                } else {
                    Write-Warning "CHD format only supports directories or ISO files"
                    continue
                }
            }
            "rvz" {
                $command = "DolphinTool convert --format=rvz --compression=lzma2 --compression_level=9 --block_size=2097152 --input=`"$($source.FullName)`" --output=`"$target`""
            }
            { $_ -in "7z", "zip" } {
                if ($_.PSIsContainer) {
                    $command = "7z a -t$($using:Type) -mx=$($using:Level) -bso0 -bsp0 `"$target`" `"$($source.FullName)\*`""
                } else {
                    $command = "7z a -t$($using:Type) -mx=$($using:Level) -bso0 -bsp0 `"$target`" `"$($source.FullName)`""
                }
            }
        }

        Write-Host "$command"
        Invoke-Expression $command
    }
}

# Unarchive each file in the given path.
function Invoke-Unarchive {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [int]$Limit = 1,

        [Parameter(Mandatory = $false)]
        [switch]$CheckSpace
    )

    # parse output path
    if ($OutputPath -eq "") {
        $OutputPath = $InputPath
    }

    # list archived items
    Write-Host "Listing archived files: $InputPath"
    $files = Get-ChildItem $InputPath -File | Where-Object { $_.Extension -in ".7z", ".gz", ".rar", ".zip" }
    Write-Host "Found $($files.Count) files."

    # unarchive files
    $files | ForEach-Object -ThrottleLimit $Limit -Parallel {
        # generate unarchive name
        $unarchive = Join-Path $using:OutputPath "$($_.BaseName)"
        if (Test-Path -LiteralPath $unarchive -PathType Container) {
            Write-Warning "Skipping: $unarchive"
            continue
        }

        # check space
        if ($using:CheckSpace) {
            $drive = (Get-Item -Path $using:OutputPath).PSDrive
            if ($drive.Free -lt 20GB) {
                Write-Warning "Skipping. Low free space: $unarchive"
                continue
            }
        }

        # unarchive entry
        Write-Host "Unarchiving: $unarchive"
        7z x -bso0 -bsp0 "$($_.FullName)" -y -o"$unarchive"
    }
}

# Test all archives in the given path.
function Invoke-UnarchiveTest {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [Parameter(Mandatory = $false)]
        [int]$Limit = 1,

        [Parameter(Mandatory = $false)]
        [switch]$Remove
    )

    # list archives
    Write-Host "Listing archived files: $InputPath"
    $files = Get-ChildItem $InputPath -File | Where-Object { $_.Extension -in ".7z", ".zip" }
    Write-Host "Found $($files.Count) files."

    # create broken dir
    $dirBroken = Join-Path $InputPath "_broken"
    if ($Remove) {
        New-Item -Path $dirBroken -ItemType Directory -Force -ErrorAction SilentlyContinue
    }

    # test archives
    $files | ForEach-Object -ThrottleLimit $Limit -Parallel {
        $command = "7z t `"$($_.FullName)`""
        Write-Host "$command"
        Invoke-Expression $command

        if ($LastExitCode -ne 0) {
            Write-Host "Failed: $($_.FullName)" -ForegroundColor Red
            if ($using:Remove) {
                Move-Item -Path $_ -Destination $using:dirBroken
            }
        }
    }
}

# Converts a zip to 7z file.
function Invoke-ZipTo7z {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputPath
    )

    # get input path folder
    $inputPath = Get-Item $InputPath
    $inputPathFolder = ([System.IO.Path]::GetDirectoryName($inputPath))

    # generate temp path
    $inputPathBasename = [System.IO.Path]::GetFileNameWithoutExtension($inputPath)
    $unarchived = Join-Path ([System.IO.Path]::GetTempPath()) "ZipTo7z" $inputPathBasename

    # unarchive zip to temp path
    Write-Host "`nUnarchiving: $inputPath"
    if (Test-Path -LiteralPath $unarchived -PathType Container) {
        Write-Warning "Skipping: $inputPath"
    } else {
        $command = "7z x -bso0 -bsp0 `"$inputPath`" -y -o`"$unarchived`""
        Write-Host $command
        Invoke-Expression $command
    }

    # archive 7z
    Write-Host "`nArchiving: $unarchived"
    $archived = "$unarchived.7z"
    if (Test-Path -LiteralPath $archived -PathType Leaf) {
        Write-Warning "Skipping: $archived"
    } else {
        $command = "7z a -t7z -mx=9 -bso0 -bsp0 `"$archived`" `"$($unarchived)\*`""
        Write-Host $command
        Invoke-Expression $command
    }

    # move archived to same folder as input path
    Write-Host "`nMoving: $archived to $inputPathFolder"
    Move-Item -LiteralPath $archived -Destination $inputPathFolder -Force
}

# Hash all files in the given path and store it as AlternateDataStream.
function Invoke-Hash {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [int]$Limit = 1
    )

    # list files
    Write-Host "Listing files: $Path"
    $files = Get-ChildItem $Path -Recurse -File
    Write-Host "Found $($files.Count) files."

    # hash files
    $files | ForEach-Object -ThrottleLimit $Limit -Parallel {
        # get ADS hash
        $hasHash = (Get-Item -LiteralPath $_.FullName -Stream * | Where-Object { $_.Stream -eq "HASH" }).Count -gt 0
        if ($hasHash) {
            return
        }

        # hash and store it
        Write-Host "Hashing: $($_.FullName)"
        $hash = Get-FileHash -LiteralPath $_.FullName -Algorithm MD5
        Set-Content -LiteralPath $_.FullName -Stream HASH -Value $hash.Hash
    }
}

# Find duplicate files in one or more directories.
function Invoke-FindDuplicates {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Path,

        [Parameter(Mandatory = $false)]
        [int]$Limit = 1
    )

    # list files
    $files = Get-ChildItem $Path -Recurse -File
    Write-Host "Found $($files.Count) files."

    # group files by size and hash only the ones that have duplicates
    $filesToHash = $files | Group-Object Length | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Group }
    Write-Host "Found $($filesToHash.Count) files with duplicate sizes."

    # hash in parallel
    $processing = [System.Collections.Concurrent.ConcurrentQueue[bool]]::new()
    $hashes = $filesToHash | ForEach-Object -ThrottleLimit $Limit -Parallel {
        # increment counter and log
        $processing = $using:processing
        $processing.Enqueue($true)
        Write-Progress -Activity "Hashing" -Status "$($processing.Count)/$($using:filesToHash.Count)" -PercentComplete ($processing.Count / $using:filesToHash.Count * 100)

        # get hash or compute it
        $hasHash = (Get-Item -LiteralPath $_.FullName -Stream * | Where-Object { $_.Stream -eq "HASH" }).Count -gt 0
        Write-Host $_.FullName
        if ($hasHash) {
            $hash = Get-Content -LiteralPath $_.FullName -Stream HASH
        } else {
            $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm MD5).Hash
        }

        # store hash if had to compute
        if(-not $hasHash) {
            Set-Content -LiteralPath $_.FullName -Stream HASH -Value $hash
        }

        # hash
        [PSCustomObject]@{
            FullName = $_.FullName
            CreatedAt = $_.CreationTime
            Hash = $hash
        }
    }

    # show duplicates
    $hashes = $hashes |
            Group-Object Hash |
            Where-Object { $_.Count -gt 1 } |
            Sort-Object Count

    if ($hashes.Count -eq 0) {
        Write-Host "No duplicates found."
    } else {
        $hashes | ForEach-Object {
            Write-Host ""
            Write-Host "Duplicates: $($_.Name):"
            $_.Group | Sort-Object CreatedAt | ForEach-Object {
                Write-Host "  $($_.CreatedAt.ToString("yyyy-MM-dd"))"
                Write-Host "    $($_.FullName)"
            }
        }
    }
}

# Technical summary of media files.
function Invoke-Media {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [int]$Limit = 1
    )

    $files = Get-ChildItem $Path -Recurse -Include *.mkv, *.mp4, *.flac
    $filesTotal = $files.Count
    $counter  = [ref]0

    $medias = $files |
        ForEach-Object -ThrottleLimit $Limit -Parallel {
            $current = [System.Threading.Interlocked]::Increment(($using:counter))
            Write-Progress -Activity "Scanning" -Status "$current / $using:filesTotal — $($_.Name)" -PercentComplete ($current / $using:filesTotal * 100)

            $info = ffprobe -v quiet -print_format json -show_format -show_streams $_ 2>$null | ConvertFrom-Json

            $video = $info.streams | Where-Object codec_type -eq "video" | ForEach-Object {
                [PSCustomObject]@{
                    Codec  = $_.codec_name
                    Width  = $_.width
                    Height = $_.height
                    PixFmt = $_.pix_fmt
                }
            }
            $audio = $info.streams | Where-Object codec_type -eq "audio" | ForEach-Object {
                [PSCustomObject]@{
                    Codec       = $_.codec_name
                    Channels    = $_.channels
                    ChannelLayout = $_.channel_layout
                    SampleRate  = $_.sample_rate
                }
            }
            [PSCustomObject]@{
                File   = $_.Name
                Video  = $video
                Audio  = $audio
            }
        }

    $medias | Sort-Object File | ForEach-Object {
        Write-Host "$($_.File)" -ForegroundColor Cyan
        $_.Video | ForEach-Object {
            Write-Host "  Video: $($_.Codec) $($_.Width)x$($_.Height) $($_.PixFmt)"
        }
        $_.Audio | ForEach-Object {
            Write-Host "  Audio: $($_.Codec) $($_.Channels)ch $($_.ChannelLayout) $($_.SampleRate)Hz"
        }
    }
}


# Install a package using winget.
function Invoke-Install {
    param (
        [string]$name,
        [string]$package,
        [string]$location = $null,
        [string]$locationExtra = $null
    )

    # log
    Write-Host "`nInstalling ${name}: ${package}"

    # prepare command with location
    $command = "winget install --id $package --accept-package-agreements --no-upgrade --disable-interactivity"
    if ($location) {
        $command += " --location $location"
        if ($locationExtra) {
            $command += " --custom '$locationExtra$location'"
        }
    }

    # execute command
    Write-Host $command
    Invoke-Expression $command
}

# ------------------------------------------------------------------------------
# Aliases
# ------------------------------------------------------------------------------

# PowerShell aliases
function SortSize {
    param(
        [Parameter(ValueFromPipeline=$true)]
        $input
    )
    $input | Sort-Object Length
}
function SortSizeDesc {
    param(
        [Parameter(ValueFromPipeline=$true)]
        $input
    )
    $input | Sort-Object Length -Descending
}
function Top {
    param(
        [Parameter(ValueFromPipeline=$true)]
        $input,

        [Parameter(Position = 1, Mandatory = $false)]
        [int]$n = 10
    )
    $input | Select-Object -First $n
}

function Skip {
    param(
        [Parameter(ValueFromPipeline=$true)]
        $input,

        [Parameter(Position = 1, Mandatory = $false)]
        [int]$n = 10
    )
    $input | Select-Object -Skip $n
}

# Function aliases
Set-Alias c          Clear
Set-Alias unarc      Invoke-Unarchive
Set-Alias arc        Invoke-Archive
Set-Alias unarc-test Invoke-UnarchiveTest
Set-Alias hash       Invoke-Hash
Set-Alias dup        Invoke-FindDuplicates
Set-Alias add        Invoke-Install
Set-Alias media      Invoke-Media
Set-Alias zzz        Invoke-ZipTo7z

# Git aliases
function ggam    { git add --all .; git commit -m }
function gga     { git add --all }
function ggb     { git branch }
function ggbkill { git branch | grep -vE 'main|master' | xargs -p -I{} git branch -D {} }
function ggc     { git checkout }
function ggd     { git diff $1 | bat }
function ggdn    { git diff --name-only }
function ggl     { git log | bat }
function ggm     { param ($message) git commit -m $message }
function ggma    { git commit --amend -m }
function ggman   { git commit --amend --no-edit }
function ggme    { param ($message) git commit --allow-empty -m $message }
function ggp     { git pull }
function ggr     { git reset }
function ggrb    { git rebase -i }
function ggs     { git status }

function ggsub   { git submodule update --init --recursive }
