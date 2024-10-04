# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------

# Archive each directory in the given path.
function Invoke-DirectoriesArchive {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Path
    )

    # list directories
    $directories = Get-ChildItem $Path -Directory

    # archive directories
    foreach ($directory in $directories) {
        $archive = Join-Path $directory.Parent.FullName "$($directory.Name).7z"
        Write-Host "Archiving: $archive"


        $command = "7z a -t7z -mx=9 $archive $($directory.FullName)\*"
        Invoke-Expression $command
    }
}

# Update all git repositories in the given path.
function Invoke-DirectoriesGitPull {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Path
    )

    # list directories
    $directories = Get-ChildItem $Path -Directory

    # update repositories
    foreach ($directory in $directories) {
        Write-Host "Updating: $($directory.FullName)"
        git -C $directory.FullName pull
    }
}

# Find duplicate files in one or more directories.
function Invoke-FindDuplicateFiles {
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

        # hash
        [PSCustomObject]@{
            FullName = $_.FullName
            Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm MD5).Hash
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
Set-Alias dirarc     Invoke-DirectoriesArchive
Set-Alias dirgitpull Invoke-DirectoriesGitPull
Set-Alias dupfiles   Invoke-FindDuplicateFiles

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
