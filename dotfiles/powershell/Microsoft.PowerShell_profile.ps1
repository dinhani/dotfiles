# custom scripts
Get-ChildItem (Join-Path $PSScriptRoot 'Profile') -Filter *.ps1 | ForEach-Object { . $_.FullName }

# zoxide
Invoke-Expression (& { (zoxide init powershell | Out-String) })

