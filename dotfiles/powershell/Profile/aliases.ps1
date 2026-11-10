# Function aliases
Set-Alias a           Show-Alias            # Lists aliases.
Set-Alias c           Clear                 # Clears the screen.

Set-Alias llama-coder Start-LlamaCoder      # Starts llama-server with a picked model.
Set-Alias tks         Measure-LlamaRequest  # Shows one timing line per llama request.
Set-Alias models      Show-AiModel          # Lists models in Z:\apps\ai.

Set-Alias gpu         Show-GpuUsage         # Shows GPU memory usage.
Set-Alias gpu-clean   Stop-GpuApp           # Kills apps holding VRAM.
Set-Alias gpu-restore Start-GpuApp          # Restarts apps killed by gpu-clean.

Set-Alias arc         Compress-Item         # Archives each item to 7z, zip, chd or rvz.
Set-Alias unarc       Expand-Item           # Extracts or tests archives.
Set-Alias hash        Set-FileHash          # Stores file hashes as alternate data streams.
Set-Alias dup         Find-Duplicate        # Lists duplicate files.
Set-Alias mvascii     Rename-ItemAscii      # Renames files to lowercase ASCII.

Set-Alias media       Get-MediaInfo         # Lists video, audio and subtitle info.

# Lists the aliases in this file, grouped by the script that defines their command.
function Show-Alias {
    $aliases = Select-String -LiteralPath (Join-Path $PSScriptRoot 'aliases.ps1') -Pattern '^Set-Alias\s+(\S+)\s+(\S+)\s*(?:#\s*(.*))?' |
        ForEach-Object {
            $file = (Get-Command $_.Matches[0].Groups[2].Value -ErrorAction SilentlyContinue).ScriptBlock.File
            [PSCustomObject]@{
                Alias       = $_.Matches[0].Groups[1].Value
                Command     = $_.Matches[0].Groups[2].Value
                Context     = if ($file -and (Split-Path $file -Leaf) -ne 'aliases.ps1') {
                    [System.IO.Path]::GetFileNameWithoutExtension($file)
                } else {
                    'shell'
                }
                Description = $_.Matches[0].Groups[3].Value
            }
        }

    $aliasWidth = ($aliases.Alias | Measure-Object Length -Maximum).Maximum + 2
    $commandWidth = ($aliases.Command | Measure-Object Length -Maximum).Maximum + 2
    foreach ($context in $aliases.Context | Select-Object -Unique) {
        Write-Host ""
        Write-Host "  $context" -ForegroundColor Cyan
        foreach ($alias in $aliases | Where-Object Context -eq $context) {
            Write-Host "    $($alias.Alias.PadRight($aliasWidth))" -ForegroundColor Green -NoNewline
            Write-Host $alias.Command.PadRight($commandWidth) -NoNewline
            Write-Host $alias.Description -ForegroundColor DarkGray
        }
    }
    Write-Host ""
}
