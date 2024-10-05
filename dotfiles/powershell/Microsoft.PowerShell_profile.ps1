# ------------------------------------------------------------------------------
# Examples
# ------------------------------------------------------------------------------
# Install-Module -Name ThreadJob
# $jobs = @()
# ForEach-Object {
#     $jobs += Start-ThreadJob -StreamingHost $Host -ScriptBlock  {
#         $arg = $args[0]
#     } -ThrottleLimit 10 -ArgumentList $_
# }
# Wait-Job -Job $jobs

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------

# Archive each file in the given path to 7zip or zip.
function Invoke-Archive {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$InputPath,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [ValidateSet("7z", "zip")]
        [string]$Type = "7z",

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 9)]
        [int]$Level = 9,

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
    foreach ($entry in $entries) {
        # ignore already archived entries
        if (Test-Path $entry -PathType Leaf) {
            continue
        }

        # generate archive name
        $archive = Join-Path $OutputPath "$($entry.Name).$Type"
        Write-Host "Archiving: $archive"

        # archive entry
        $command = "7z a -t$Type -mmt16 -mx=$Level -bso0 -bsp0 $archive $($entry.FullName)\*"
        Write-Host $command
        Invoke-Expression $command
    }
}

# Unarchive each file in the given path.
function Invoke-Unarchive {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$InputPath,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath
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
    foreach ($entry in $entries) {
        # ignore already unarchived entries
        if (Test-Path $entry -PathType Container) {
            continue
        }

        # generate unarchive name
        $unarchive = Join-Path $OutputPath "$($entry.BaseName)"
        Write-Host "Unarchiving: $unarchive"

        # unarchive entry
        $command = "7z x '$entry' -mmt16 -y -o'$unarchive'"
        Write-Host $command
        Invoke-Expression $command
    }
}

# Hash all files in the given path and store it as AlternateDataStream.
function Invoke-Hash {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Path
    )

    # list files
    Write-Host "Listing files: $Path"
    $files = Get-ChildItem $Path -Recurse -File
    Write-Host "Found $($files.Count) files."

    # hash files
    $files | ForEach-Object -ThrottleLimit 16 -Parallel {
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
    $hashes = $filesToHash | ForEach-Object -ThrottleLimit 16 -Parallel {
        # increment counter and log
        $processing = $using:processing
        $processing.Enqueue($true)
        Write-Progress -Activity "Hashing" -Status "$($processing.Count)/$($using:filesToHash.Count)" -PercentComplete ($processing.Count / $using:filesToHash.Count * 100)

        # get hash or compute it
        $hasHash = (Get-Item -LiteralPath $_.FullName -Stream * | Where-Object { $_.Stream -eq "HASH" }).Count -gt 0
        if ($hasHash) {
            $hash = Get-Content -LiteralPath $_.FullName -Stream HASH
        } else {
            $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm MD5).Hash
        }

        # hash
        [PSCustomObject]@{
            FullName = $_.FullName
            Hash = $hash
        }
    }

    # show duplicates
    $hashes |
        Group-Object Hash |
        Where-Object { $_.Count -gt 1 } |
        Sort-Object Count |
        ForEach-Object {
            Write-Host ""
            Write-Host "Duplicates: $($_.Name):"
            $_.Group.FullName | ForEach-Object { Write-Host "  $_" }
        }
}

# ------------------------------------------------------------------------------
# Aliases
# ------------------------------------------------------------------------------

# Function aliases
Set-Alias arc        Invoke-Archive
Set-Alias unarc      Invoke-Unarchive
Set-Alias hash       Invoke-Hash
Set-Alias dup        Invoke-FindDuplicates

# Git aliases
function gga     { git add --all }
function ggam    { git add --all .; git commit -m }
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
