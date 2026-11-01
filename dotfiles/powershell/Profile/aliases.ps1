# Function aliases
Set-Alias a           Show-Alias
Set-Alias c           Clear

Set-Alias llama-coder Start-LlamaCoder
Set-Alias tks         Measure-LlamaRequest

Set-Alias gpu         Show-GpuUsage
Set-Alias gpu-clean   Stop-GpuApp
Set-Alias gpu-restore Start-GpuApp

Set-Alias arc         Compress-Item
Set-Alias unarc       Expand-Item
Set-Alias hash        Set-FileHash
Set-Alias dup         Find-Duplicate
Set-Alias mvascii     Rename-ItemAscii

Set-Alias media       Get-MediaInfo

# Lists the aliases defined in this file.
function Show-Alias {
    $names = Select-String -LiteralPath (Join-Path $PSScriptRoot 'aliases.ps1') -Pattern '^Set-Alias\s+(\S+)' |
        ForEach-Object { $_.Matches[0].Groups[1].Value }
    Get-Alias -Name $names | Format-Table Name, Definition -AutoSize
}
