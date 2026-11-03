function claude {
    $profiles = 'claude', 'claude-2', 'claude-3'
    $selectionFile = Join-Path $env:LOCALAPPDATA 'claude-profile.txt'

    $profileLast = if (Test-Path $selectionFile) { (Get-Content $selectionFile -Raw).Trim() } else { $profiles[0] }
    $position = [Math]::Max(1, [array]::IndexOf($profiles, $profileLast) + 1)

    $orange = $PSStyle.Foreground.FromRgb(0xd97757)
    $yellow = $PSStyle.Foreground.FromRgb(0xe5c07b)
    $red = $PSStyle.Foreground.FromRgb(0xe06c75)
    $gray = $PSStyle.Foreground.BrightBlack
    $reset = $PSStyle.Reset

    Clear-Host
    Write-Host "${gray}fetching usage…$reset" -NoNewline
    $accounts = $profiles | ForEach-Object -ThrottleLimit $profiles.Count -Parallel {
        $profileName = $_
        $configFile = if ($profileName -eq 'claude') { Join-Path $HOME '.claude.json' } else { Join-Path $HOME ".$profileName\.claude.json" }
        $credentialsFile = Join-Path $HOME ".$profileName\.credentials.json"
        $config = if (Test-Path $configFile) { Get-Content $configFile -Raw | ConvertFrom-Json -AsHashtable }
        $oauth = if (Test-Path $credentialsFile) { (Get-Content $credentialsFile -Raw | ConvertFrom-Json).claudeAiOauth }

        $tokenValid = $oauth -and $oauth.expiresAt -gt [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $usage = $null
        $usageError = $null
        if ($tokenValid) {
            try {
                $usage = Invoke-RestMethod 'https://api.anthropic.com/api/oauth/usage' -TimeoutSec 5 -Headers @{
                    Authorization    = "Bearer $($oauth.accessToken)"
                    'anthropic-beta' = 'oauth-2025-04-20'
                }
            }
            catch {
                $usageError = $_.Exception.Message
            }
        }

        [pscustomobject]@{
            Profile    = $profileName
            Email      = $config.oauthAccount.emailAddress
            TokenValid = $tokenValid
            Usage      = $usage
            UsageError = $usageError
        }
    } | Sort-Object { [array]::IndexOf($profiles, $_.Profile) }
    Write-Host "`r$($PSStyle.EraseLine)" -NoNewline

    $profileWidth = ($profiles | Measure-Object -Property Length -Maximum).Maximum
    $emailWidth = ($accounts | ForEach-Object { "$($_.Email)".Length } | Measure-Object -Maximum).Maximum
    $today = (Get-Date).Date
    $weekFullAny = $accounts.Usage.limits | Where-Object { $_.kind -eq 'weekly_all' -and $_.percent -ge 100 }
    $sessionResetWidth = if ($weekFullAny) { 'weekly limit reached'.Length } else { 'not started'.Length }

    $items = foreach ($account in $accounts) {
        $usage = if (-not $account.Email) {
            'not logged in'
        }
        elseif ($account.UsageError) {
            'usage unavailable'
        }
        elseif (-not $account.TokenValid) {
            'token expired'
        }
        else {
            $weekFull = ($account.Usage.limits | Where-Object kind -eq 'weekly_all').percent -ge 100
            $cells = foreach ($kind in 'session', 'weekly_all') {
                $limit = $account.Usage.limits | Where-Object kind -eq $kind
                $label = if ($kind -eq 'session') { 'session' } else { 'week' }
                $percent = [Math]::Clamp([int]$limit.percent, 0, 100)
                $color = if ($percent -ge 90) { $red } elseif ($percent -ge 70) { $yellow } else { $orange }

                $resetText = if ($kind -eq 'session' -and $weekFull) {
                    'weekly limit reached'
                }
                elseif (-not $limit.resets_at) {
                    'not started'
                }
                else {
                    $resetsAt = ([DateTimeOffset]$limit.resets_at).LocalDateTime.AddSeconds(30)
                    $format = if ($resetsAt.Date -eq $today) { 'HH:mm' } else { 'ddd HH:mm' }
                    $resetsAt.ToString($format) -replace '\.', ''
                }
                $resetWidth = if ($kind -eq 'session') { $sessionResetWidth } else { 11 }
                "$label $color$("$percent%".PadLeft(4))$reset  $($resetText.PadRight($resetWidth))"
            }
            $cells -join ' │ '
        }

        $marker = if ($account.Profile -eq $profileLast) { " $orange● last$reset" } else { '' }
        "$($account.Profile)`t$($account.Profile.PadRight($profileWidth)) │ $("$($account.Email)".PadRight($emailWidth)) │ $usage$reset$marker"
    }

    $selection = $items | fzf --ansi --delimiter "`t" --with-nth 2 `
        --no-input --layout reverse --height ~10 --info hidden --no-scrollbar `
        --pointer '▌' --highlight-line --header 'Select Claude profile:' `
        --color "pointer:#d97757,current-bg:#2a2320,current-fg:white:bold,gutter:-1" `
        --bind "load:pos($position),j:down,k:up,1:pos(1)+accept,2:pos(2)+accept,3:pos(3)+accept"
    if (-not $selection) { return }
    $profileSelected = ("$selection" -split "`t")[0].Trim()
    Set-Content $selectionFile $profileSelected

    $configDirPrevious = $env:CLAUDE_CONFIG_DIR
    $env:CLAUDE_CONFIG_DIR = if ($profileSelected -eq 'claude') { $null } else { Join-Path $HOME ".$profileSelected" }
    try {
        claude.exe --dangerously-skip-permissions @args
    }
    finally {
        $env:CLAUDE_CONFIG_DIR = $configDirPrevious
    }
}
