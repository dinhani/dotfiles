# Apps that Stop-GpuApp kills; Start-GpuApp starts the ones with Restore = $true.
$GpuApps = @(
    [PSCustomObject]@{ Process = "avpui";                   Restore = $false; Start = $null }
    [PSCustomObject]@{ Process = "chrome";                  Restore = $false; Start = "C:\Program Files\Google\Chrome\Application\chrome.exe" }
    [PSCustomObject]@{ Process = "Code";                    Restore = $false; Start = "C:\_scoop\apps\vscode\current\Code.exe" }
    [PSCustomObject]@{ Process = "CrossDeviceResume";       Restore = $false; Start = $null }
    [PSCustomObject]@{ Process = "explorer";                Restore = $true;  Start = "C:\Windows\explorer.exe" }
    [PSCustomObject]@{ Process = "Listary";                 Restore = $true;  Start = "C:\Program Files\Listary\Listary.exe" }
    [PSCustomObject]@{ Process = "Microsoft.CmdPal.UI";     Restore = $true;  Start = "shell:AppsFolder\Microsoft.CommandPalette_8wekyb3d8bbwe!App" }
    [PSCustomObject]@{ Process = "PhoneExperienceHost";     Restore = $false; Start = $null }
    [PSCustomObject]@{ Process = "PowerToys.ColorPickerUI"; Restore = $false; Start = $null }
    [PSCustomObject]@{ Process = "PowerToys.FancyZones";    Restore = $false; Start = $null }
    [PSCustomObject]@{ Process = "PowerToys.Peek.UI";       Restore = $false; Start = $null }
    [PSCustomObject]@{ Process = "PowerToys.QuickAccess";   Restore = $false; Start = $null }
    [PSCustomObject]@{ Process = "PowerToys";               Restore = $true;  Start = "C:\_scoop\apps\powertoys\current\PowerToys.exe" }
    [PSCustomObject]@{ Process = "RazerAppEngine";          Restore = $true;  Start = "C:\Program Files\Razer\RazerAppEngine\RazerAppEngine.exe" }
    [PSCustomObject]@{ Process = "rstudio";                 Restore = $false; Start = $null }
    [PSCustomObject]@{ Process = "ShellExperienceHost";     Restore = $false; Start = $null }
    [PSCustomObject]@{ Process = "Spotify";                 Restore = $false; Start = $null }
    [PSCustomObject]@{ Process = "StartMenuExperienceHost"; Restore = $false; Start = $null }
    [PSCustomObject]@{ Process = "StreamDeck";              Restore = $true;  Start = "C:\Program Files\Elgato\StreamDeck\StreamDeck.exe" }
    [PSCustomObject]@{ Process = "TabTip";                  Restore = $false; Start = $null }
    [PSCustomObject]@{ Process = "TextInputHost";           Restore = $false; Start = $null }
    [PSCustomObject]@{ Process = "WhatsApp.Root";           Restore = $true;  Start = "shell:AppsFolder\5319275A.WhatsAppDesktop_cv1g1gvanyjgm!App" }
    [PSCustomObject]@{ Process = "WindowsTerminal";         Restore = $false; Start = "shell:AppsFolder\Microsoft.WindowsTerminal_8wekyb3d8bbwe!App" }
)

# Starts llama-server with a picked LM Studio model and its family preset.
function Start-LlamaCoder {
    param (
        [Parameter(Mandatory = $false, Position = 0)]
        [string]$Model,

        [Parameter(Mandatory = $false)]
        [ValidateSet(32768, 65536, 131072, 262144)]
        [int]$ContextSize,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Auto", "On", "Off")]
        [string]$Reasoning,

        [Parameter(Mandatory = $false)]
        [double]$Temperature,

        [Parameter(Mandatory = $false)]
        [double]$TopP,

        [Parameter(Mandatory = $false)]
        [int]$TopK,

        [Parameter(Mandatory = $false)]
        [double]$MinP,

        [Parameter(Mandatory = $false)]
        [switch]$DryRun,

        [Parameter(Mandatory = $false, ValueFromRemainingArguments = $true)]
        [string[]]$ServerArguments
    )

    $server = "C:/_scoop/apps/llama.cpp-cu133/current/llama-server.exe"
    $modelRoot = "D:/AI-Models-LMStudio"
    $modelIndex = Join-Path $HOME ".lmstudio/.internal/model-index-cache.json"
    $alias = "llama-coder"
    $port = 18080

    if (-not (Test-Path -LiteralPath $server -PathType Leaf)) {
        Write-Error "llama-server not found: $server"
        return
    }
    if (-not (Test-Path -LiteralPath $modelRoot -PathType Container)) {
        Write-Error "Model directory not found: $modelRoot"
        return
    }

    # Published presets per family, first match wins against "<arch> <display name> <path>". Reasoning is the default --reasoning mode (auto = detected from the chat template).
    # ContextSize caps what a 16 GB card can hold next to the weights (dense attention costs far more KV than hybrid/SWA families); the model's trained context wins when smaller.
    $presets = @(
        [PSCustomObject]@{ Name = "Qwen3-Coder-Next";   Pattern = "qwen3[-_.]?coder[-_.]?next";             ContextSize = 262144; Reasoning = "auto"; ReasoningEffort = $null;   Sampling = @{ temp = "1.0";  "top-p" = "0.95"; "top-k" = "40"; "min-p" = "0.00"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "Qwen3-Coder";        Pattern = "qwen3[-_.]?coder";                       ContextSize = 131072; Reasoning = "auto"; ReasoningEffort = $null;   Sampling = @{ temp = "0.7";  "top-p" = "0.80"; "top-k" = "20"; "min-p" = "0.00"; "repeat-penalty" = "1.05"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "Qwen2.5-Coder";      Pattern = "qwen2[-_.]?5[-_.]?coder";                ContextSize =  32768; Reasoning = "auto"; ReasoningEffort = $null;   Sampling = @{ temp = "0.7";  "top-p" = "0.80"; "top-k" = "20"; "min-p" = "0.00"; "repeat-penalty" = "1.05"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "Qwen3 Instruct";     Pattern = "qwen3.*instruct";                        ContextSize = 131072; Reasoning = "auto"; ReasoningEffort = $null;   Sampling = @{ temp = "0.7";  "top-p" = "0.80"; "top-k" = "20"; "min-p" = "0.00"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "Qwen3 / 3.5 / 3.6";  Pattern = "qwen3";                                  ContextSize = 262144; Reasoning = "on";   ReasoningEffort = $null;   Sampling = @{ temp = "0.6";  "top-p" = "0.95"; "top-k" = "20"; "min-p" = "0.00"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "GLM";                Pattern = "glm";                                    ContextSize = 131072; Reasoning = "on";   ReasoningEffort = $null;   Sampling = @{ temp = "0.7";  "top-p" = "1.00"; "top-k" = "40"; "min-p" = "0.01"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "gpt-oss";            Pattern = "gpt[-_]?oss";                            ContextSize = 131072; Reasoning = "on";   ReasoningEffort = "high";  Sampling = @{ temp = "1.0";  "top-p" = "1.00"; "top-k" = "0";  "min-p" = "0.00"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "Magistral";          Pattern = "magistral";                              ContextSize =  65536; Reasoning = "auto"; ReasoningEffort = $null;   Sampling = @{ temp = "0.7";  "top-p" = "0.95"; "top-k" = "0";  "min-p" = "0.01"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "Devstral / Mistral"; Pattern = "devstral|codestral|ministral|mistral";   ContextSize =  65536; Reasoning = "auto"; ReasoningEffort = $null;   Sampling = @{ temp = "0.15"; "top-p" = "1.00"; "top-k" = "0";  "min-p" = "0.01"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "Nemotron";           Pattern = "nemotron";                               ContextSize = 262144; Reasoning = "on";   ReasoningEffort = $null;   Sampling = @{ temp = "0.6";  "top-p" = "0.95"; "top-k" = "0";  "min-p" = "0.01"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "Gemma";              Pattern = "gemma";                                  ContextSize = 131072; Reasoning = "on";   ReasoningEffort = $null;   Sampling = @{ temp = "1.0";  "top-p" = "0.95"; "top-k" = "64"; "min-p" = "0.00"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "DeepSeek";           Pattern = "deepseek";                               ContextSize =  65536; Reasoning = "on";   ReasoningEffort = $null;   Sampling = @{ temp = "0.6";  "top-p" = "0.95"; "top-k" = "0";  "min-p" = "0.00"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "generic";            Pattern = ".";                                      ContextSize =  65536; Reasoning = "on";   ReasoningEffort = $null;   Sampling = @{ temp = "0.7";  "top-p" = "0.95"; "top-k" = "40"; "min-p" = "0.05"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
    )

    # LM Studio's index supplies family, params, quant, context, tools and vision per gguf path
    $index = @{}
    if (Test-Path -LiteralPath $modelIndex -PathType Leaf) {
        foreach ($item in (Get-Content -LiteralPath $modelIndex -Raw | ConvertFrom-Json).models) {
            if ($item.virtual -or -not $item.entryPoint.absPath) {
                continue
            }
            $index[[System.IO.Path]::GetFullPath($item.entryPoint.absPath)] = $item
        }
    }

    # list models: indexed files must be LLMs; unindexed files fall back to name filtering; multi-part ggufs collapse into their first shard
    $models = @(
        Get-ChildItem -LiteralPath $modelRoot -Recurse -File -Filter "*.gguf" |
            Group-Object { $_.FullName -replace "-\d{5}-of-\d{5}\.gguf$", ".gguf" } |
            ForEach-Object {
                $file = $_.Group | Sort-Object Name | Select-Object -First 1
                $item = $index[$file.FullName]
                $path = [System.IO.Path]::GetRelativePath($modelRoot, $_.Name) -replace "\.gguf$", "" -replace "\\", "/"
                $name = if ($item) {
                    $item.displayName
                } else {
                    [System.IO.Path]::GetFileName($path)
                }
                $preset = $presets | Where-Object { "$($item.arch) $name $path" -match $_.Pattern } | Select-Object -First 1
                $contextCap = $preset.ContextSize
                if ($item.contextLength -and $item.contextLength -lt $contextCap) {
                    $contextCap = [int]$item.contextLength
                }
                $contextDefault = @(262144, 131072, 65536, 32768) | Where-Object { $_ -le $contextCap } | Select-Object -First 1
                $familyPattern = if ($item) {
                    "^[A-Za-z-]+"
                } else {
                    "^[A-Za-z]+"
                }
                [PSCustomObject]@{
                    Name        = $name
                    Path        = $path
                    Family      = [regex]::Match($name, $familyPattern).Value
                    Item        = $item
                    Preset      = $preset
                    ContextSize = if ($contextDefault) {
                        $contextDefault
                    } else {
                        $contextCap
                    }
                    SizeGB      = ($_.Group | Measure-Object Length -Sum).Sum / 1GB
                    File        = $file.FullName
                }
            } |
            Where-Object {
                if ($_.Item) {
                    $_.Item.domain -eq "llm"
                } else {
                    $_.Name -notmatch "^(mmproj|mtp)-|reranker|embed"
                }
            } |
            Sort-Object Family, Name
    )
    if ($models.Count -eq 0) {
        Write-Error "No models found in $modelRoot"
        return
    }

    $candidates = if ($Model) {
        @($models | Where-Object { $_.Name -like "*$Model*" -or $_.Path -like "*$Model*" })
    } else {
        $models
    }
    if ($candidates.Count -eq 0) {
        Write-Error "No model matches '$Model'. Available: $($models.Name -join ', ')"
        return
    }

    $vramGB = [math]::Round((Get-GpuMemory).Total / 1GB, 1)

    # picker: one row per model, a blank row between families
    $selected = $candidates[0]
    if ($candidates.Count -gt 1) {
        $rows = for ($i = 0; $i -lt $candidates.Count; $i++) {
            $candidate = $candidates[$i]
            if ($i -gt 0 -and $candidate.Family -ne $candidates[$i - 1].Family) {
                [PSCustomObject]@{ "#" = "" }
            }
            [PSCustomObject]@{
                "#"     = $i + 1
                Family  = $candidate.Family
                Name    = $candidate.Name
                Params  = $candidate.Item.params
                Quant   = $candidate.Item.quant.name
                Trained = if ($candidate.Item.contextLength) {
                    "{0}K" -f [int]($candidate.Item.contextLength / 1024)
                } else {
                    ""
                }
                Context = "{0}K" -f [int]($candidate.ContextSize / 1024)
                Tools   = if ($null -eq $candidate.Item) {
                    ""
                } elseif ($candidate.Item.trainedForToolUse) {
                    "yes"
                } else {
                    "no"
                }
                Vision  = if ($null -eq $candidate.Item) {
                    ""
                } elseif ($candidate.Item.visionAdapter) {
                    "yes"
                } else {
                    "no"
                }
                Size    = "{0:0.0} GB" -f $candidate.SizeGB
                Fit     = if ($candidate.SizeGB + 2 -le $vramGB) {
                    "GPU"
                } else {
                    "GPU+CPU"
                }
                Preset  = $candidate.Preset.Name
            }
        }
        $rows | Format-Table -AutoSize | Out-Host

        $selection = Read-Host "Select a model number"
        $modelIndexChosen = 0
        if (-not [int]::TryParse($selection, [ref]$modelIndexChosen) -or $modelIndexChosen -lt 1 -or $modelIndexChosen -gt $candidates.Count) {
            Write-Error "Select a number from 1 to $($candidates.Count)"
            return
        }
        $selected = $candidates[$modelIndexChosen - 1]
    }
    $preset = $selected.Preset
    $overrides = @()

    # apply overrides on top of the preset
    $context = $selected.ContextSize
    if ($PSBoundParameters.ContainsKey("ContextSize")) {
        $context = $ContextSize
        $overrides += "context"
        if ($selected.Item.contextLength -and $context -gt $selected.Item.contextLength) {
            Write-Warning "Context $context is larger than the $($selected.Item.contextLength) the model was trained on"
        }
    }
    $reasoningMode = $preset.Reasoning
    if ($PSBoundParameters.ContainsKey("Reasoning")) {
        $reasoningMode = $Reasoning.ToLower()
        $overrides += "reasoning"
    }
    $sampling = $preset.Sampling.Clone()
    $samplingParameters = [ordered]@{ Temperature = "temp"; TopP = "top-p"; TopK = "top-k"; MinP = "min-p" }
    foreach ($parameter in $samplingParameters.GetEnumerator()) {
        if ($PSBoundParameters.ContainsKey($parameter.Key)) {
            $sampling[$parameter.Value] = "$($PSBoundParameters[$parameter.Key])"
            $overrides += $parameter.Value
        }
    }
    $aliasContext = "$alias-$([int]($context / 1024))k"

    # fit on: with a fixed context, llama.cpp moves MoE experts (then dense layers) to CPU until the rest fits VRAM
    $arguments = @(
        "--model", $selected.File
        "--alias", "$alias,$aliasContext"
        "--host", "0.0.0.0"
        "--port", $port
        "--device", "CUDA0"
        "--fit", "on"
        "--ctx-size", $context
        "--parallel", "1"
        "--batch-size", "2048"
        "--ubatch-size", "2048"
        "--flash-attn", "on"
        "--cache-type-k", "q8_0"
        "--cache-type-v", "q8_0"
        "--jinja"
        # "--reasoning-format", "auto"
        "--reasoning", $reasoningMode
        "--no-mmproj"
    )
    foreach ($option in $sampling.GetEnumerator() | Sort-Object Key) {
        $arguments += @("--$($option.Key)", $option.Value)
    }
    if ($preset.ReasoningEffort -and $reasoningMode -ne "off") {
        $arguments += @("--reasoning-effort", $preset.ReasoningEffort)
    }
    if ($ServerArguments) {
        $arguments += $ServerArguments
    }

    Write-Host ""
    [PSCustomObject][ordered]@{
        Model     = "$($selected.Name)  ($($selected.Path))"
        Size      = "{0:0.0} GB, VRAM {1} GB" -f $selected.SizeGB, $vramGB
        Preset    = $preset.Name
        Context   = "{0:N0} tokens" -f $context
        Reasoning = if ($preset.ReasoningEffort -and $reasoningMode -ne "off") {
            "$reasoningMode, effort $($preset.ReasoningEffort)"
        } else {
            $reasoningMode
        }
        Sampling  = ($sampling.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join " "
        Overrides = if ($overrides) {
            $overrides -join ", "
        } else {
            "none"
        }
        Extra     = if ($ServerArguments) {
            $ServerArguments -join " "
        } else {
            "none"
        }
        Endpoint  = "http://0.0.0.0:$port/v1"
        OpenCode  = "llama-cpp/$aliasContext"
    } | Format-List | Out-Host

    if ($DryRun) {
        Write-Host "$server $($arguments -join ' ')"
        return
    }
    & $server @arguments
}

# Prints total, used, reserved and free GPU memory and the dedicated memory each process holds.
function Show-GpuUsage {
    $memory = Get-GpuMemory
    $usedRatio = $memory.Used / $memory.Total
    $reservedRatio = $memory.Reserved / $memory.Total
    $freeRatio = $memory.Free / $memory.Total

    # virtual display adapters also report counters, with 0 bytes in use
    $adapter = (Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage').CounterSamples |
        Sort-Object CookedValue -Descending |
        Select-Object -First 1
    $processes = (Get-Counter '\GPU Process Memory(*)\Dedicated Usage').CounterSamples |
        Where-Object { $_.InstanceName -like "*_$($adapter.InstanceName)" -and $_.CookedValue -gt 0 } |
        Group-Object { [int]($_.InstanceName -replace '^pid_(\d+)_.*$', '$1') } |
        ForEach-Object {
            $process = Get-Process -Id $_.Name -ErrorAction SilentlyContinue
            $bytes = ($_.Group | Measure-Object CookedValue -Sum).Sum
            [PSCustomObject]@{
                PID         = [int]$_.Name
                Process     = if ($process) {
                    $process.ProcessName
                } else {
                    "(exited)"
                }
                "Used (MB)" = [long][math]::Round($bytes / 1MB)
                "Of total"  = $bytes / $memory.Total
            }
        } |
        Sort-Object "Used (MB)" -Descending

    # summary
    $barWidth = 40
    $barUsed = [int][math]::Round($usedRatio * $barWidth)
    $barReserved = [int][math]::Round($reservedRatio * $barWidth)
    $barColor = if ($usedRatio -lt 0.6) {
        "Green"
    } elseif ($usedRatio -lt 0.85) {
        "Yellow"
    } else {
        "Red"
    }
    Write-Host ""
    Write-Host "  $($memory.Name)"
    Write-Host "  [" -NoNewline
    Write-Host ("█" * $barUsed) -ForegroundColor $barColor -NoNewline
    Write-Host ("▓" * $barReserved) -ForegroundColor DarkGray -NoNewline
    Write-Host ("░" * ($barWidth - $barUsed - $barReserved)) -ForegroundColor DarkGray -NoNewline
    Write-Host "]"
    Write-Host ("  Total     {0,6:N1} GB" -f ($memory.Total / 1GB))
    Write-Host ("  Used      {0,6:N1} GB  {1,6:P1}" -f ($memory.Used / 1GB), $usedRatio) -ForegroundColor $barColor
    Write-Host ("  Reserved  {0,6:N1} GB  {1,6:P1}" -f ($memory.Reserved / 1GB), $reservedRatio) -ForegroundColor DarkGray
    Write-Host ("  Free      {0,6:N1} GB  {1,6:P1}" -f ($memory.Free / 1GB), $freeRatio)

    # processes
    $processes |
        Format-Table PID, Process, "Used (MB)",
            @{ Name = "Of total"; Expression = { $_."Of total" }; FormatString = "P1"; Alignment = "Right" },
            @{ Name = "Usage"; Expression = {
                $eighths = [int][math]::Round($_."Of total" * 20 * 8)
                $partial = if ($eighths % 8 -gt 0) { "▏▎▍▌▋▊▉"[$eighths % 8 - 1] } else { "" }
                (("█" * [math]::Floor($eighths / 8)) + $partial).PadRight(20, "░")
            } } -AutoSize |
        Out-Host
    Write-Host "  Memory shared between processes is counted for each of them, so the rows can add up to more than Used."
}

# Kills apps that hold GPU VRAM so more is free for llama-server.
function Stop-GpuApp {
    foreach ($app in $GpuApps) {
        if (Get-Process -Name $app.Process -ErrorAction SilentlyContinue) {
            Write-Host "Killing: $($app.Process)"
            taskkill /F /IM "$($app.Process).exe" | Out-Null
        }
    }
}

# Starts the apps from $GpuApps that have Restore = $true.
function Start-GpuApp {
    foreach ($app in $GpuApps | Where-Object Restore) {
        if (-not (Get-Process -Name $app.Process -ErrorAction SilentlyContinue)) {
            Write-Host "Starting: $($app.Process)"
            Start-Process $app.Start
        }
    }
}

# Returns the name and the total, reserved, used and free memory in bytes of the NVIDIA GPU.
function Get-GpuMemory {
    $output = nvidia-smi --query-gpu=name,memory.total,memory.reserved,memory.used,memory.free --format=csv,noheader,nounits
    if ($LASTEXITCODE -ne 0) {
        throw "nvidia-smi failed with exit code $LASTEXITCODE"
    }
    $fields = ($output | Select-Object -First 1) -split ',\s*'
    [PSCustomObject]@{
        Name     = $fields[0]
        Total    = [long]$fields[1] * 1MB
        Reserved = [long]$fields[2] * 1MB
        Used     = [long]$fields[3] * 1MB
        Free     = [long]$fields[4] * 1MB
    }
}
