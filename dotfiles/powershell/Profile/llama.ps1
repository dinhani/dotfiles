# Launches a local LLM server using llama-server with optimized presets.
function Start-LlamaCoder {

    param (
        [Parameter(Mandatory = $false)]
        [string]$Model,

        [Parameter(Mandatory = $false)]
        [switch]$DryRun
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

    # Published presets per family, first match wins against "<arch> <display name> <path>". Thinking is the chat-template kwarg that turns reasoning on ($null = fixed by the model).
    # ContextSize caps what a 16 GB card can hold next to the weights (dense attention costs far more KV than hybrid/SWA families); the model's trained context wins when smaller.
    $presets = @(
        [PSCustomObject]@{ Name = "Qwen3-Coder-Next";   Pattern = "qwen3[-_.]?coder[-_.]?next";             ContextSize = 262144; Thinking = $null;                             Sampling = @{ temp = "1.0";  "top-p" = "0.95"; "top-k" = "40"; "min-p" = "0.00"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "Qwen3-Coder";        Pattern = "qwen3[-_.]?coder";                       ContextSize = 131072; Thinking = $null;                             Sampling = @{ temp = "0.7";  "top-p" = "0.80"; "top-k" = "20"; "min-p" = "0.00"; "repeat-penalty" = "1.05"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "Qwen2.5-Coder";      Pattern = "qwen2[-_.]?5[-_.]?coder";                ContextSize =  32768; Thinking = $null;                             Sampling = @{ temp = "0.7";  "top-p" = "0.80"; "top-k" = "20"; "min-p" = "0.00"; "repeat-penalty" = "1.05"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "Qwen3 Instruct";     Pattern = "qwen3.*instruct";                        ContextSize = 131072; Thinking = $null;                             Sampling = @{ temp = "0.7";  "top-p" = "0.80"; "top-k" = "20"; "min-p" = "0.00"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "Qwen3 / 3.5 / 3.6";  Pattern = "qwen3";                                  ContextSize = 262144; Thinking = @{ enable_thinking = $true };      Sampling = @{ temp = "0.6";  "top-p" = "0.95"; "top-k" = "20"; "min-p" = "0.00"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "GLM";                Pattern = "glm";                                    ContextSize = 131072; Thinking = @{ enable_thinking = $true };      Sampling = @{ temp = "0.7";  "top-p" = "1.00"; "top-k" = "40"; "min-p" = "0.01"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "gpt-oss";            Pattern = "gpt[-_]?oss";                            ContextSize = 131072; Thinking = @{ reasoning_effort = "high" };    Sampling = @{ temp = "1.0";  "top-p" = "1.00"; "top-k" = "0";  "min-p" = "0.00"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "Magistral";          Pattern = "magistral";                              ContextSize =  65536; Thinking = $null;                             Sampling = @{ temp = "0.7";  "top-p" = "0.95"; "top-k" = "0";  "min-p" = "0.01"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "Devstral / Mistral"; Pattern = "devstral|codestral|ministral|mistral";   ContextSize =  65536; Thinking = $null;                             Sampling = @{ temp = "0.15"; "top-p" = "1.00"; "top-k" = "0";  "min-p" = "0.01"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "Nemotron";           Pattern = "nemotron";                               ContextSize = 262144; Thinking = @{ enable_thinking = $true };      Sampling = @{ temp = "0.6";  "top-p" = "0.95"; "top-k" = "0";  "min-p" = "0.01"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "Gemma";              Pattern = "gemma";                                  ContextSize = 131072; Thinking = @{ enable_thinking = $true };      Sampling = @{ temp = "1.0";  "top-p" = "0.95"; "top-k" = "64"; "min-p" = "0.00"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "DeepSeek";           Pattern = "deepseek";                               ContextSize =  65536; Thinking = @{ thinking = $true };             Sampling = @{ temp = "0.6";  "top-p" = "0.95"; "top-k" = "0";  "min-p" = "0.00"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
        [PSCustomObject]@{ Name = "generic";            Pattern = ".";                                      ContextSize =  65536; Thinking = @{ enable_thinking = $true };      Sampling = @{ temp = "0.7";  "top-p" = "0.95"; "top-k" = "40"; "min-p" = "0.05"; "repeat-penalty" = "1.00"; "presence-penalty" = "0.0" } }
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
                $name = if ($item) { $item.displayName } else { [System.IO.Path]::GetFileName($path) }
                $preset = $presets | Where-Object { "$($item.arch) $name $path" -match $_.Pattern } | Select-Object -First 1
                $contextCap = $preset.ContextSize
                if ($item.contextLength -and $item.contextLength -lt $contextCap) {
                    $contextCap = [int]$item.contextLength
                }
                $contextSize = @(262144, 131072, 65536, 32768) | Where-Object { $_ -le $contextCap } | Select-Object -First 1
                [PSCustomObject]@{
                    Name        = $name
                    Path        = $path
                    Family      = [regex]::Match($name, $(if ($item) { "^[A-Za-z-]+" } else { "^[A-Za-z]+" })).Value
                    Item        = $item
                    Preset      = $preset
                    ContextSize = if ($contextSize) { $contextSize } else { $contextCap }
                    SizeGB      = ($_.Group | Measure-Object Length -Sum).Sum / 1GB
                    File        = $file.FullName
                }
            } |
            Where-Object { if ($_.Item) { $_.Item.domain -eq "llm" } else { $_.Name -notmatch "^(mmproj|mtp)-|reranker|embed" } } |
            Sort-Object Family, Name
    )
    if ($models.Count -eq 0) {
        Write-Error "No models found in $modelRoot"
        return
    }

    $candidates = if ($Model) { @($models | Where-Object { $_.Name -like "*$Model*" -or $_.Path -like "*$Model*" }) } else { $models }
    if ($candidates.Count -eq 0) {
        Write-Error "No model matches '$Model'. Available: $($models.Name -join ', ')"
        return
    }

    $vramGB = 16
    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        $vramMiB = (& nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | Select-Object -First 1) -as [int]
        if ($vramMiB) {
            $vramGB = [math]::Round($vramMiB / 1024, 1)
        }
    }

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
                Trained = if ($candidate.Item.contextLength) { "{0}K" -f [int]($candidate.Item.contextLength / 1024) } else { "" }
                Context = "{0}K" -f [int]($candidate.ContextSize / 1024)
                Tools   = if ($null -eq $candidate.Item) { "" } elseif ($candidate.Item.trainedForToolUse) { "yes" } else { "no" }
                Vision  = if ($null -eq $candidate.Item) { "" } elseif ($candidate.Item.visionAdapter) { "yes" } else { "no" }
                Size    = "{0:0.0} GB" -f $candidate.SizeGB
                Fit     = if ($candidate.SizeGB + 2 -le $vramGB) { "GPU" } else { "GPU+CPU" }
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
    $contextSize = $selected.ContextSize
    $aliasContext = "$alias-$([int]($contextSize / 1024))k"

    # fit on: with a fixed context, llama.cpp moves MoE experts (then dense layers) to CPU until the rest fits VRAM
    $arguments = @(
        "--model", $selected.File
        "--alias", "$alias,$aliasContext"
        "--host", "0.0.0.0"
        "--port", $port
        "--device", "CUDA0"
        "--fit", "on"
        "--ctx-size", $contextSize
        "--parallel", "1"
        "--batch-size", "2048"
        "--ubatch-size", "2048"
        "--flash-attn", "on"
        "--cache-type-k", "q8_0"
        "--cache-type-v", "q8_0"
        "--jinja"
        # "--reasoning-format", "auto"
        '--reasoning', 'off'
        "--no-mmproj"
    )
    foreach ($option in $preset.Sampling.GetEnumerator() | Sort-Object Key) {
        $arguments += @("--$($option.Key)", $option.Value)
    }
    if ($preset.Thinking) {
        $arguments += @("--chat-template-kwargs", ($preset.Thinking | ConvertTo-Json -Compress))
    }

    Write-Host ""
    [PSCustomObject][ordered]@{
        Model    = "$($selected.Name)  ($($selected.Path))"
        Size     = "{0:0.0} GB, VRAM {1} GB" -f $selected.SizeGB, $vramGB
        Preset   = $preset.Name
        Context  = "{0:N0} tokens" -f $contextSize
        Thinking = if ($preset.Thinking) { $preset.Thinking | ConvertTo-Json -Compress } else { "fixed by model" }
        Sampling = ($preset.Sampling.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join " "
        Endpoint = "http://0.0.0.0:$port/v1"
        OpenCode = "llama-cpp/$aliasContext"
    } | Format-List | Out-Host

    if ($DryRun) {
        Write-Host "$server $($arguments -join ' ')"
        return
    }
    & $server @arguments
}

<#
.SYNOPSIS
    Displays current GPU memory usage for all active processes.

.DESCRIPTION
    This function retrieves the dedicated memory usage of the GPU by polling the system counters.
    It groups the usage by Process ID (PID), retrieves the process name, and calculates
    the usage in Megabytes (MB) and as a percentage of 16GB.
    The output is sorted by usage in descending order.

.EXAMPLE
    Show-GpuUsage
    Displays a table of GPU memory usage for all processes.

.EXAMPLE
    gpu
    Displays a table of GPU memory usage for all processes (using the 'gpu' alias).

.NOTES
    Requires administrative privileges or specific permissions to access GPU counters.
#>
function Show-GpuUsage {
    # get PID/gpu bytes
    Get-Counter '\GPU Process Memory(*)\Dedicated Usage' |
        Select-Object -ExpandProperty CounterSamples |
        ForEach-Object {
            if ($_.InstanceName -match 'pid_(\d+)') {
                [pscustomobject]@{
                    PID   = [int]$matches[1]
                    Bytes = $_.CookedValue
                }
            }
        } |

    # group PIDs and fetch process info
    Group-Object PID |
        ForEach-Object {
            $processID = [int]$_.Name
            $proccess = Get-Process -Id $processID -ErrorAction SilentlyContinue | Select-Object -First 1

            # format
            $bytes = ($_.Group | Measure-Object Bytes -Sum).Sum
            [pscustomobject]@{
                PID         = $processID
                Process     = if ($proccess) { $proccess.ProcessName } else { '(exited)' }
                Usage       = [math]::Round($bytes / 1MB, 1)
                Percentage  = [math]::Round($bytes / 16GB * 100, 1)
            }
        } |
    Sort-Object 'Usage' -Descending |
    Format-Table -AutoSize
}


# Kills common heavy processes to free up GPU VRAM.
function Invoke-GpuCleanup {
    @(
        "avpui",
        "chrome",
        "Code",
        "CrossDeviceResume",
        "explorer",
        "Listary",
        "Microsoft.CmdPal.UI",
        "PhoneExperienceHost",
        "PowerToys.ColorPickerUI",
        "PowerToys.FancyZones",
        "PowerToys.Peek.UI",
        "PowerToys.QuickAccess",
        "PowerToys",
        "RazerAppEngine",
        "ShellExperienceHost",
        "StartMenuExperienceHost",
        "StreamDeck",
        "TabTip",
        "TextInputHost",
        "WhatsApp.Root",
        "WindowsTerminal"
    ) | ForEach-Object {
        Write-Host "Killing: $_"
        taskkill.exe /F /IM "$_.exe" 2>$null | Out-Null
    }
}
