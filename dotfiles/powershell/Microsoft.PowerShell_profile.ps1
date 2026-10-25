Get-ChildItem (Join-Path $PSScriptRoot 'Profile') -Filter *.ps1 | ForEach-Object { . $_.FullName }
