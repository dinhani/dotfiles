function just {
    Clear-Host
    just.exe @args
}

Register-ArgumentCompleter -Native -CommandName just -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    # parse line
    $line = $commandAst.Extent.Text
    $line = $line.Substring(0, [math]::Min($cursorPosition - $commandAst.Extent.StartOffset, $line.Length))
    $words = @($line.TrimEnd() -split '\s+' | Select-Object -Skip 1)
    if ($wordToComplete -ne '') { $words = @($words | Select-Object -SkipLast 1) }

    # flags
    if ($wordToComplete.StartsWith('-')) {
        $completePrevious = $env:JUST_COMPLETE
        $env:JUST_COMPLETE = 'powershell'
        try {
            $results = @(just.exe -- just @words $wordToComplete)
        }
        finally {
            $env:JUST_COMPLETE = $completePrevious
        }
        foreach ($result in $results) {
            $name, $help = $result.Split("`t", 2)
            if (-not $name.StartsWith('-')) { continue }
            [System.Management.Automation.CompletionResult]::new($name, $name, 'ParameterName', ($help ?? $name))
        }
        return
    }

    # load justfile
    $summary = [System.Diagnostics.Process]::Start([System.Diagnostics.ProcessStartInfo]@{
        FileName = 'just'
        Arguments = '--summary --unsorted'
        WorkingDirectory = $PWD.ProviderPath
        RedirectStandardOutput = $true
        RedirectStandardError = $true
        UseShellExecute = $false
    })
    $dump = just.exe --dump --dump-format json 2>$null | Out-String | ConvertFrom-Json
    $fullNames = -split $summary.StandardOutput.ReadToEnd()
    $summary.WaitForExit()
    if (-not $dump) { return }

    # module scope
    $module = $dump
    foreach ($word in $words | Where-Object { -not $_.StartsWith('-') }) {
        $module = $module.modules.$word
        if (-not $module) { return }
    }
    $path = $module.module_path ? "$($module.module_path)::" : ''

    # recipes and aliases
    $recipes = @{}
    $aliasNames = @{}
    $modules = [System.Collections.Generic.Queue[object]]::new()
    $modules.Enqueue($module)
    while ($modules.Count) {
        $current = $modules.Dequeue()
        $currentPath = $current.module_path ? "$($current.module_path)::" : ''
        foreach ($recipe in $current.recipes.PSObject.Properties.Value) { $recipes[$recipe.namepath] = $recipe }
        foreach ($alias in $current.aliases.PSObject.Properties.Value) { $aliasNames["$currentPath$($alias.target)"] += @($alias.name) }
        foreach ($submodule in $current.modules.PSObject.Properties.Value) { $modules.Enqueue($submodule) }
    }

    # emit
    foreach ($fullName in $fullNames) {
        $recipe = $recipes[$fullName]
        if (-not $recipe -or $recipe.name -eq 'default') { continue }
        $name = $fullName.Substring($path.Length)
        $aliases = $aliasNames[$fullName] ?? @()
        $typed = @($name) + $aliases | Where-Object { $_.StartsWith($wordToComplete, [StringComparison]::OrdinalIgnoreCase) }
        if (-not $typed) { continue }
        $parameters = -join $(foreach ($parameter in $recipe.parameters) {
            $text = switch ($parameter.kind) { 'star' { "*$($parameter.name)" } 'plus' { "+$($parameter.name)" } default { $parameter.name } }
            if ($null -ne $parameter.default) { $text += $parameter.default -is [string] ? "='$($parameter.default)'" : '=…' }
            " $text"
        })
        $tooltip = "$($recipe.doc) $($aliases ? "[alias: $($aliases -join ', ')]" : '')".Trim()
        [System.Management.Automation.CompletionResult]::new($name, "$name$parameters", 'ParameterValue', ($tooltip ? $tooltip : $name))
    }
}

Set-PSReadLineKeyHandler -Key Tab -BriefDescription JustFzfComplete -ScriptBlock {
    param($key, $arg)

    # read line
    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    if ($line.Substring(0, $cursor) -match '(^|[;|&])\s*just$') {
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert(' ')
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    }
    if ($line.Substring(0, $cursor) -notmatch '(^|[;|&])\s*just\s[^;|&]*$') {
        [Microsoft.PowerShell.PSConsoleReadLine]::TabCompleteNext($key, $arg)
        return
    }
    $typed = ($line.Substring(0, $cursor) -split '\s')[-1]
    $wordStart = $cursor - $typed.Length
    $completion = $typed.StartsWith('-') ?
        (TabExpansion2 -inputScript $line -cursorColumn $cursor) :
        (TabExpansion2 -inputScript $line.Remove($wordStart, $typed.Length) -cursorColumn $wordStart)
    $candidates = $completion.CompletionMatches
    if (-not $candidates -or ($candidates | Where-Object ResultType -notin 'ParameterValue', 'ParameterName')) {
        [Microsoft.PowerShell.PSConsoleReadLine]::TabCompleteNext($key, $arg)
        return
    }

    # pick
    $scope = @($line.Substring(0, $wordStart) -replace '^.*\bjust\s+', '' -split '\s+' | Where-Object { $_ -and -not $_.StartsWith('-') })
    $scope = $scope ? ($scope -join '::') + '::' : ''
    $recipeOptions = $candidates[0].ResultType -eq 'ParameterValue' ? @('--preview', 'just --show {4}', '--preview-window', 'right,50%,wrap', '--bind', '?:toggle-preview', '--header', 'enter run · tab fill') : @()
    $width = ($candidates.ListItemText | Measure-Object -Property Length -Maximum).Maximum
    $pressed, $choice = $candidates |
        ForEach-Object {
            $name = $_.CompletionText
            $padding = ' ' * ($width - $_.ListItemText.Length + 2)
            if ($_.ResultType -eq 'ParameterName') {
                return "$name`t`e[33m$name`e[0m$padding`e[34m# $($_.ToolTip)`e[0m`t`t"
            }
            $module, $recipe = $name -match '^(.*::)?(.*)$' ? ($Matches[1], $Matches[2]) : ('', $name)
            $parameters = $_.ListItemText.Substring($name.Length)
            $doc, $aliases = $_.ToolTip -match '^(.*?) ?(\[alias: .*\])?$' ? ($Matches[1], $Matches[2]) : ($_.ToolTip, '')
            $description = ($doc -and $doc -ne $name ? "`e[34m# $doc " : '') + ($aliases ? "`e[35m$aliases" : '')
            "$name`t`e[2m$module`e[22;1m$recipe`e[22;36m$parameters`e[0m$padding$description`e[0m`t$parameters`t$scope$name"
        } |
        fzf --ansi --delimiter "`t" --with-nth 2 --height 40% --layout reverse --tiebreak index --exit-0 --prompt 'just> ' --query $typed --expect tab @recipeOptions
    [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
    if (-not $choice) { return }

    # insert
    $name, $null, $parameters, $null = $choice.Split("`t")
    [Microsoft.PowerShell.PSConsoleReadLine]::Replace($wordStart, $typed.Length, "$name ")
    $argumentsRequired = $parameters -split ' ' | Where-Object { $_ -and $_ -notmatch '^\*|=' }
    if ($pressed -eq 'tab' -or $name.StartsWith('-') -or $argumentsRequired) { return }
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}
