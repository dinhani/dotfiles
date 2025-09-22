# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------

# Prints each argument passed to the function with its index.
function Write-Args {
    for($i = 0; $i -lt $args.length; $i++) {
        "$i`: $($args[$i])"
    }
}

# Archive each file in the given path to 7z zip or chd.
function Invoke-Archive {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [ValidateSet("7z", "zip", "chd")]
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

    # list entries
    if ($Directory) {
        Write-Host "Listing directories: $InputPath"
        $entries = Get-ChildItem $InputPath -Directory
    } elseif ($File) {
        Write-Host "Listing files: $InputPath"
        $entries = Get-ChildItem $InputPath -File | Where-Object { $_.Extension -notin ".7z", ".gz", ".rar", ".zip" }
    } else {
        Write-Host "Listing files and directories: $InputPath"
        $entries = Get-ChildItem $InputPath | Where-Object { $_.Extension -notin ".7z", ".gz", ".rar", ".zip" }
    }
    Write-Host "Found $($entries.Count) entries."

    # archive entries
    $entries | ForEach-Object -ThrottleLimit $Limit -Parallel {
        # generate archive name
        $archive = Join-Path $using:OutputPath "$($_.BaseName).$using:Type"
        if (Test-Path -LiteralPath $archive -PathType Leaf) {
            Write-Warning "Skipping: $archive"
            continue
        }

        # archive entry
        Write-Host "Archiving: $archive"

        # chd
        if ($using:Type -eq "chd") {
            $operation = switch ($using:ChdType) {
                "cd"  { "createcd" }
                "dvd" { "createdvd" }
            }
            if ($_.PSIsContainer) {
                $cueOrIso = $null
                foreach ($ext in @("*.cue", "*.iso")) {
                    $cueOrIso = Get-ChildItem -Path $_.FullName -Filter $ext | Select-Object -First 1
                    if ($null -ne $cueOrIso) {
                        break
                    }
                }
                if ($null -eq $cueOrIso) {
                    Write-Warning "No .cue or .iso file found in directory: $($_.FullName)"
                    continue
                }
                #$command = "chdman $operation --numprocessors 6 --input `"$($cueOrIso.FullName)`" --output `"$archive`""
                $command = "chdman $operation --input `"$($cueOrIso.FullName)`" --output `"$archive`""
            } else {
                Write-Warning "CHD format only supports directories"
            }
        }
        # 7z
        else {
            if ($_.PSIsContainer) {
                $command = "7z a -t$($using:Type) -mx=$($using:Level) -bso0 -bsp0 `"$archive`" `"$($_.FullName)\*`""
            } else {
                $command = "7z a -t$($using:Type) -mx=$($using:Level) -bso0 -bsp0 `"$archive`" `"$($_.FullName)`""
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
        [int]$Limit = 1
    )

    # parse output path
    if ($OutputPath -eq "") {
        $OutputPath = $InputPath
    }

    # list archived items
    Write-Host "Listing archived files: $InputPath"
    $entries = Get-ChildItem $InputPath -File | Where-Object { $_.Extension -in ".7z", ".gz", ".rar", ".zip" }
    Write-Host "Found $($entries.Count) entries."

    # unarchive entries
    $entries | ForEach-Object -ThrottleLimit $Limit -Parallel {
        # generate unarchive name
        $unarchive = Join-Path $using:OutputPath "$($_.BaseName)"
        if (Test-Path -LiteralPath $unarchive -PathType Container) {
            Write-Warning "Skipping: $unarchive"
            continue
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
        [string]$InputPath
    )

    # list archives
    Write-Host "Listing archived files: $InputPath"
    $entries = Get-ChildItem $InputPath -File | Where-Object { $_.Extension -in ".7z", ".zip" }
    Write-Host "Found $($entries.Count) entries."

    # test archives
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $entry = $entries[$i]
        & 7z t `"$($entry.FullName)`"
        if ($LastExitCode -ne 0) {
            Write-Host "Failed: $($entry.FullName)"
        }
        Write-Progress `
            -Activity "Testing..." `
            -Status "$($i + 1)/$($entries.Count): $($entry.Name)" `
            -PercentComplete ((($i + 1) / $entries.Count) * 100)
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
        [string]$Path
    )

    # list files
    Write-Host "Listing files: $Path"
    $files = Get-ChildItem $Path -Recurse -File
    Write-Host "Found $($files.Count) files."

    # hash files
    $files | ForEach-Object -ThrottleLimit 10 -Parallel {
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
        [string[]]$Path
    )

    # list files
    $files = Get-ChildItem $Path -Recurse -File
    Write-Host "Found $($files.Count) files."

    # group files by size and hash only the ones that have duplicates
    $filesToHash = $files | Group-Object Length | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Group }
    Write-Host "Found $($filesToHash.Count) files with duplicate sizes."

    # hash in parallel
    $processing = [System.Collections.Concurrent.ConcurrentQueue[bool]]::new()
    $hashes = $filesToHash | ForEach-Object -ThrottleLimit 10 -Parallel {
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

        # hash
        [PSCustomObject]@{
            FullName = $_.FullName
            CreatedAt = $_.CreationTime
            Hash = $hash
        }
    }

    # show duplicates
    if ($hashes.Count -eq 0) {
        Write-Host "No duplicate found."
    } else {
        $hashes |
            Group-Object Hash |
            Where-Object { $_.Count -gt 1 } |
            Sort-Object Count |
            ForEach-Object {
                Write-Host ""
                Write-Host "Duplicates: $($_.Name):"
                $_.Group | ForEach-Object {
                    Write-Host "  $($_.CreatedAt.ToString("yyyy-MM-dd"))"
                    Write-Host "    $($_.FullName)"
                }
        }
    }
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