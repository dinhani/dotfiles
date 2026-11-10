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
                    "yes"
                } else {
                    "no"
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

    $arguments = @(
        "--model", $selected.File
        "--alias", "$alias,$aliasContext"
        "--host", "0.0.0.0"
        "--port", $port
        "--device", "CUDA0"
        "--n-gpu-layers", "all"
        "--fit", "off"
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
    $env:GGML_CUDA_PDL = "1"
    $env:GGML_CUDA_GRAPH_OPT = "1"
    try {
        & $server @arguments
    } finally {
        Remove-Item Env:GGML_CUDA_PDL, Env:GGML_CUDA_GRAPH_OPT
    }
}

# Lists the models under Z:\apps\ai with their metadata.
function Show-AiModel {
    param (
        [Parameter(Mandatory = $false, Position = 0)]
        [string]$Name
    )

    $modelRoot = "Z:/apps/ai"
    $ggufQuantPattern = "(?i)[-._](I?Q\d+(_[A-Z0-9]+)*|MXFP4(_MOE)?|BF16|F16|F32)$"
    $ct2QuantPattern = "(?i)ct2-(\w+)$"
    $paramsPattern = "(?i)(?<![a-z\d])(\d+(\.\d+)?[BM])(?![a-z])"
    $vramGB = [math]::Round((Get-GpuMemory).Total / 1GB, 1)
    $typeOrder = @("llm", "llm + vision", "mtp draft", "translation", "speech", "embedding", "reranker", "image", "upscaler", "metric", "*", "unknown", "downloading")

    # model families
    $families = @(
        [PSCustomObject]@{ Name = "Qwen-Image";       Type = "image";       Pattern = "qwen[-_]image" }
        [PSCustomObject]@{ Name = "Qwen";             Type = $null;         Pattern = "qwen" }
        [PSCustomObject]@{ Name = "Gemma";            Type = $null;         Pattern = "gemma" }
        [PSCustomObject]@{ Name = "Mistral";          Type = $null;         Pattern = "mistral|magistral|ministral|devstral|codestral|pixtral|mixtral" }
        [PSCustomObject]@{ Name = "gpt-oss";          Type = $null;         Pattern = "gpt[-_]?oss" }
        [PSCustomObject]@{ Name = "Nemotron";         Type = $null;         Pattern = "nemotron" }
        [PSCustomObject]@{ Name = "Kimi";             Type = $null;         Pattern = "kimi|moonlight" }
        [PSCustomObject]@{ Name = "DeepSeek";         Type = $null;         Pattern = "deepseek" }
        [PSCustomObject]@{ Name = "GLM";              Type = $null;         Pattern = "glm" }
        [PSCustomObject]@{ Name = "MiniMax";          Type = $null;         Pattern = "minimax" }
        [PSCustomObject]@{ Name = "Cohere";           Type = $null;         Pattern = "aya|command[-_]?r|c4ai|cohere" }
        [PSCustomObject]@{ Name = "ERNIE";            Type = $null;         Pattern = "ernie" }
        [PSCustomObject]@{ Name = "Hunyuan";          Type = $null;         Pattern = "hunyuan|hy[-_]mt|hy_v\d" }
        [PSCustomObject]@{ Name = "Phi";              Type = $null;         Pattern = "(?<![a-z])phi" }
        [PSCustomObject]@{ Name = "Granite";          Type = $null;         Pattern = "granite" }
        [PSCustomObject]@{ Name = "OLMo";             Type = $null;         Pattern = "olmo" }
        [PSCustomObject]@{ Name = "SmolLM";           Type = $null;         Pattern = "smollm" }
        [PSCustomObject]@{ Name = "LFM";              Type = $null;         Pattern = "(?<![a-z])lfm" }
        [PSCustomObject]@{ Name = "EXAONE";           Type = $null;         Pattern = "exaone" }
        [PSCustomObject]@{ Name = "Falcon";           Type = $null;         Pattern = "falcon" }
        [PSCustomObject]@{ Name = "InternLM";         Type = $null;         Pattern = "intern" }
        [PSCustomObject]@{ Name = "Seed";             Type = $null;         Pattern = "seed[-_]oss" }
        [PSCustomObject]@{ Name = "Llama";            Type = $null;         Pattern = "llama" }
        [PSCustomObject]@{ Name = "NLLB";             Type = "translation"; Pattern = "nllb|m2m_100" }
        [PSCustomObject]@{ Name = "MADLAD";           Type = "translation"; Pattern = "madlad" }
        [PSCustomObject]@{ Name = "Opus-MT";          Type = "translation"; Pattern = "opus[-_]mt|marian" }
        [PSCustomObject]@{ Name = "Seamless";         Type = "translation"; Pattern = "seamless" }
        [PSCustomObject]@{ Name = "Whisper";          Type = "speech";      Pattern = "whisper" }
        [PSCustomObject]@{ Name = "COMET";            Type = $null;         Pattern = "comet" }
        [PSCustomObject]@{ Name = "BGE";              Type = $null;         Pattern = "bge" }
        [PSCustomObject]@{ Name = "mxbai";            Type = $null;         Pattern = "mxbai" }
        [PSCustomObject]@{ Name = "Jina";             Type = $null;         Pattern = "jina" }
        [PSCustomObject]@{ Name = "Nomic";            Type = $null;         Pattern = "nomic" }
        [PSCustomObject]@{ Name = "E5";               Type = $null;         Pattern = "(?<![a-z])e5[-_]" }
        [PSCustomObject]@{ Name = "GTE";              Type = $null;         Pattern = "(?<![a-z])gte[-_]" }
        [PSCustomObject]@{ Name = "XLM-R";            Type = $null;         Pattern = "xlm[-_]roberta" }
        [PSCustomObject]@{ Name = "BERT";             Type = $null;         Pattern = "bert" }
        [PSCustomObject]@{ Name = "Z-Image";          Type = "image";       Pattern = "z[-_]image" }
        [PSCustomObject]@{ Name = "FLUX";             Type = "image";       Pattern = "flux" }
        [PSCustomObject]@{ Name = "Stable Diffusion"; Type = "image";       Pattern = "stable[-_]diffusion|sdxl|(?<![a-z])sd[-_]?(1\.5|2|3)" }
        [PSCustomObject]@{ Name = "ESRGAN";           Type = "upscaler";    Pattern = "esrgan" }
        [PSCustomObject]@{ Name = "Other";            Type = $null;         Pattern = "." }
    )

    # gguf value reader for the $reader of the file being read
    $readScalar = {
        param ([uint32]$type)
        switch ($type) {
            0 { $reader.ReadByte() }
            1 { $reader.ReadSByte() }
            2 { $reader.ReadUInt16() }
            3 { $reader.ReadInt16() }
            4 { $reader.ReadUInt32() }
            5 { $reader.ReadInt32() }
            6 { $reader.ReadSingle() }
            7 { $reader.ReadBoolean() }
            8 { [System.Text.Encoding]::UTF8.GetString($reader.ReadBytes([int]$reader.ReadUInt64())) }
            10 { $reader.ReadUInt64() }
            11 { $reader.ReadInt64() }
            12 { $reader.ReadDouble() }
        }
    }

    # repos: <uploader>/<repo>, skipping the hf cache folders
    $repos = Get-ChildItem -LiteralPath $modelRoot -Directory |
        Where-Object Name -notin "hub", "xet" |
        Get-ChildItem -Directory |
        Where-Object { -not $Name -or "$($_.Parent.Name)/$($_.Name)" -like "*$Name*" }

    $models = foreach ($repo in $repos) {
        $files = @(Get-ChildItem -LiteralPath $repo.FullName -Recurse -File | Where-Object FullName -notmatch "\\\.cache\\")
        $incomplete = @(Get-ChildItem -LiteralPath (Join-Path $repo.FullName ".cache\huggingface\download") -Filter "*.incomplete" -File -ErrorAction SilentlyContinue | Where-Object Length -gt 0)
        $readme = $files | Where-Object Name -eq "README.md" | Select-Object -First 1
        $readme = if ($readme) { Get-Content -LiteralPath $readme.FullName -Raw }
        $config = $files | Where-Object { $_.Name -eq "config.json" -and $_.DirectoryName -eq $repo.FullName }
        $config = if ($config) { Get-Content -LiteralPath $config.FullName -Raw }
        $hparams = $files | Where-Object Name -eq "hparams.yaml" | Select-Object -First 1
        $hparams = if ($hparams) { Get-Content -LiteralPath $hparams.FullName -Raw }

        if ($incomplete) {
            [PSCustomObject]@{
                Model     = $repo.Name
                Repo      = "$($repo.Parent.Name)/$($repo.Name)"
                Format    = "incomplete"
                Type      = "downloading"
                Size      = ($incomplete | Measure-Object Length -Sum).Sum
            }
        }

        # gguf: one row per model file, read from the header up to the tokenizer block
        $ggufs = @($files | Where-Object Extension -eq ".gguf")
        $vision = @($ggufs | Where-Object Name -like "mmproj-*").Count -gt 0
        foreach ($group in $ggufs | Where-Object Name -notlike "mmproj-*" | Group-Object { $_.FullName -replace "-\d{5}-of-\d{5}\.gguf$", ".gguf" }) {
            $file = $group.Group | Sort-Object Name | Select-Object -First 1
            $stem = [System.IO.Path]::GetFileNameWithoutExtension($group.Name)

            $values = @{}
            $stream = [System.IO.File]::OpenRead($file.FullName)
            try {
                $reader = [System.IO.BinaryReader]::new($stream)
                $null = $reader.ReadBytes(16)
                $count = $reader.ReadUInt64()
                for ($i = 0; $i -lt $count; $i++) {
                    $key = & $readScalar 8
                    if ($key.StartsWith("tokenizer.")) {
                        break
                    }
                    $type = $reader.ReadUInt32()
                    if ($type -ne 9) {
                        $values[$key] = & $readScalar $type
                        continue
                    }
                    $itemType = $reader.ReadUInt32()
                    $itemCount = $reader.ReadUInt64()
                    for ($j = 0; $j -lt $itemCount; $j++) {
                        $null = & $readScalar $itemType
                    }
                }
            } finally {
                $stream.Dispose()
            }

            $architecture = $values["general.architecture"]
            $encoder = $values["$architecture.attention.causal"] -eq $false
            [PSCustomObject]@{
                Model     = $stem -replace $ggufQuantPattern, "" -replace "^[^_]{2,}_(?=[^_]+$)", ""
                Repo      = "$($repo.Parent.Name)/$($repo.Name)"
                Format    = "gguf"
                Type      = if (-not $architecture) {
                    $null
                } elseif ($file.Name -like "mtp-*" -or $architecture -like "*-assistant") {
                    "mtp draft"
                } elseif ($encoder -and $stem -match "rerank") {
                    "reranker"
                } elseif ($encoder) {
                    "embedding"
                } elseif ($vision) {
                    "llm + vision"
                } else {
                    "llm"
                }
                Arch      = $architecture
                Params    = if ($values["general.size_label"] -match "\d") {
                    $values["general.size_label"]
                } elseif ($stem -match $paramsPattern) {
                    $Matches[1].ToUpper()
                } elseif ($values["general.base_model.0.name"] -match $paramsPattern) {
                    $Matches[1].ToUpper()
                }
                Quant     = if ($stem -match $ggufQuantPattern) { $Matches[1] }
                Context   = $values["$architecture.context_length"]
                Size      = ($group.Group | Measure-Object Length -Sum).Sum
            }
        }
        if ($ggufs) {
            continue
        }

        # other formats: one row per repo, from its name, config.json, README and hparams.yaml
        $format = if ($files.Name -contains "model.bin") {
            "ct2"
        } elseif ($files.Extension -contains ".safetensors") {
            "safetensors"
        } elseif ($hparams) {
            "comet"
        } elseif ($config) {
            "no weights"
        }
        if (-not $format) {
            continue
        }
        [PSCustomObject]@{
            Model     = $repo.Name -replace "(?i)-ct2-.*$", ""
            Repo      = "$($repo.Parent.Name)/$($repo.Name)"
            Format    = $format
            Type      = if ($readme -match "(?m)^pipeline_tag:\s*(\S+)" -and $format -ne "comet") {
                $Matches[1]
            } elseif ($format -eq "comet") {
                "metric"
            } elseif ($config -match '"architectures"\s*:\s*\[\s*"\w+For(MaskedLM|CausalLM|SequenceClassification)"') {
                @{ MaskedLM = "fill-mask"; CausalLM = "text-generation"; SequenceClassification = "text-classification" }[$Matches[1]]
            }
            Arch      = if ($hparams -match "(?m)^pretrained_model:\s*(\S+)") {
                $Matches[1]
            } elseif ($config -match '"model_type"\s*:\s*"([^"]+)"') {
                $Matches[1]
            }
            Params    = if ($repo.Name -match $paramsPattern) { $Matches[1].ToUpper() }
            Quant     = if ($repo.Name -match $ct2QuantPattern) {
                $Matches[1]
            } elseif ($config -match '"(?:torch_)?dtype"\s*:\s*"([^"]+)"') {
                $Matches[1]
            }
            Context   = if ($config -match '"max_position_embeddings"\s*:\s*(\d+)') { [int]$Matches[1] }
            Size      = ($files | Measure-Object Length -Sum).Sum
        }
    }
    $models = @(
        $models |
            ForEach-Object {
                $model = $_
                $family = $families | Where-Object { "$($model.Model) $($model.Arch)" -match $_.Pattern } | Select-Object -First 1
                $model | Add-Member -NotePropertyName Family -NotePropertyValue $family.Name
                if (-not $model.Type) {
                    $model.Type = if ($family.Type) {
                        $family.Type
                    } else {
                        "unknown"
                    }
                }
                $model
            } |
            Sort-Object {
                    $index = $typeOrder.IndexOf("$($_.Type)")
                    if ($index -lt 0) {
                        $typeOrder.IndexOf("*")
                    } else {
                        $index
                    }
                },
                Type,
                { $_.Family -eq "Other" },
                Family,
                { [regex]::Replace($_.Model, "\d+", { $args[0].Value.PadLeft(10, "0") }) }
    )
    if ($models.Count -eq 0) {
        Write-Error "No models found in $modelRoot"
        return
    }

    # rows: display text per model
    $culture = [cultureinfo]::InvariantCulture
    $formatSize = {
        param ([double]$bytes)
        if ($bytes -ge 1GB) {
            [string]::Format($culture, "{0:0.0} GB", $bytes / 1GB)
        } else {
            [string]::Format($culture, "{0:0} MB", $bytes / 1MB)
        }
    }
    $rows = foreach ($model in $models) {
        [PSCustomObject]@{
            Type      = $model.Type
            Family    = $model.Family
            Model     = $model.Model
            Params    = "$($model.Params)" -replace "\.0(?=[KMBT])", ""
            Quant     = "$($model.Quant)"
            Context   = if ($model.Context -ge 1048576) {
                "{0}M" -f [math]::Round($model.Context / 1048576)
            } elseif ($model.Context -ge 1024) {
                "{0}K" -f [math]::Round($model.Context / 1024)
            } else {
                "$($model.Context)"
            }
            Size      = & $formatSize $model.Size
            Repo      = $model.Repo
            Bytes     = $model.Size
            SizeStyle = if ($model.Format -in "incomplete", "no weights") {
                $PSStyle.Foreground.White
            } elseif ($model.Size / 1GB + 2 -le $vramGB) {
                $PSStyle.Foreground.Green
            } elseif ($model.Size / 1GB -le $vramGB) {
                $PSStyle.Foreground.Yellow
            } else {
                $PSStyle.Foreground.BrightRed
            }
        }
    }

    # styles
    $reset = $PSStyle.Reset
    $titleStyle = $PSStyle.Bold + $PSStyle.Foreground.BrightCyan
    $frameStyle = $PSStyle.Foreground.Cyan
    $headerStyle = $PSStyle.Foreground.FromRgb(0x808080)

    # columns: width from the longest value
    $columns = @(
        [PSCustomObject]@{ Name = "Family";  Alignment = "Left";  Style = $PSStyle.Bold + $PSStyle.Foreground.BrightMagenta }
        [PSCustomObject]@{ Name = "Model";   Alignment = "Left";  Style = $PSStyle.Foreground.BrightWhite }
        [PSCustomObject]@{ Name = "Params";  Alignment = "Right"; Style = $PSStyle.Foreground.White }
        [PSCustomObject]@{ Name = "Quant";   Alignment = "Left";  Style = $PSStyle.Foreground.White }
        [PSCustomObject]@{ Name = "Context"; Alignment = "Right"; Style = $PSStyle.Foreground.White }
        [PSCustomObject]@{ Name = "Size";    Alignment = "Right"; Style = $null }
        [PSCustomObject]@{ Name = "Repo";    Alignment = "Left";  Style = $PSStyle.Foreground.FromRgb(0xA0A0A0) }
    )
    foreach ($column in $columns) {
        $longest = ($rows | ForEach-Object { "$($_.($column.Name))".Length } | Measure-Object -Maximum).Maximum
        $column | Add-Member -NotePropertyName Width -NotePropertyValue ([math]::Max($column.Name.Length, $longest))
    }
    $formatCell = {
        param ([PSCustomObject]$column, [string]$text, [string]$style)
        $padding = " " * ($column.Width - $text.Length)
        if ($column.Alignment -eq "Right") {
            "$padding$style$text$reset"
        } else {
            "$style$text$reset$padding"
        }
    }
    $ruleWidth = ($columns | Measure-Object Width -Sum).Sum + 2 * ($columns.Count - 1)

    # sections: one per type, labels only on columns with data
    foreach ($type in $rows.Type | Select-Object -Unique) {
        $sectionRows = @($rows | Where-Object Type -eq $type)
        $header = ($columns | ForEach-Object {
            $label = if ($sectionRows.($_.Name) -join "") { $_.Name } else { "" }
            & $formatCell $_ $label $headerStyle
        }) -join "  "
        $noun = if ($sectionRows.Count -eq 1) { "model" } else { "models" }
        $sectionSize = & $formatSize ($sectionRows | Measure-Object Bytes -Sum).Sum

        Write-Host ""
        Write-Host "  $titleStyle$($type.ToUpper())$reset$frameStyle · $($sectionRows.Count) $noun · $sectionSize$reset"
        Write-Host "  $frameStyle$("─" * $ruleWidth)$reset"
        Write-Host "  $($header.TrimEnd())"

        for ($i = 0; $i -lt $sectionRows.Count; $i++) {
            $row = $sectionRows[$i]
            $cells = foreach ($column in $columns) {
                $text = "$($row.($column.Name))"
                if ($column.Name -eq "Family" -and $i -gt 0 -and $row.Family -eq $sectionRows[$i - 1].Family) {
                    $text = ""
                }
                $style = if ($column.Name -eq "Size") {
                    $row.SizeStyle
                } else {
                    $column.Style
                }
                & $formatCell $column $text $style
            }
            Write-Host "  $(($cells -join "  ").TrimEnd())"
        }
    }

    # totals
    $total = & $formatSize ($models | Measure-Object Size -Sum).Sum
    $count = @($models | Where-Object Format -ne "incomplete").Count
    Write-Host ""
    Write-Host ([string]::Format($culture, "  {0}{1} models · {2} · {3:0.0} GB VRAM{4}", $frameStyle, $count, $total, $vramGB, $reset))
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

# llama-server writes one slot line per step of a request:
#   I slot print: id 0 | task 3 | processing task
class LlamaSlotLine {
    [int]$Slot
    [string]$Task
    [string]$Message

    static [LlamaSlotLine] Parse([string]$line) {
        if ($line -notmatch '^(?:[\d.]+\s+)?I slot\s+\w+: id\s+(\d+) \| task (-?\d+) \| (.*)$') {
            return $null
        }
        return [LlamaSlotLine]@{ Slot = $Matches[1]; Task = $Matches[2]; Message = $Matches[3] }
    }

    [bool] StartsJob() {
        return $this.Message -match '^processing task'
    }
}

# Timings gathered from the slot lines between "processing task" and "stop processing".
class LlamaJob {
    [int]$Slot
    [string]$Task
    [bool]$Timed
    [double]$PromptMs
    [int]$PromptTokens
    [double]$GenerationMs
    [int]$GenerationTokens
    [double]$GenerationSpeed
    [Nullable[double]]$DraftAcceptance
    [bool]$Released
    [bool]$Truncated

    [bool] Record([string]$message) {
        if ($message -match '^\s*prompt eval time =\s*([\d.]+) ms /\s*(\d+) tokens') {
            $this.PromptMs = $Matches[1]
            $this.PromptTokens = $Matches[2]
            return $true
        }
        if ($message -match '^\s*eval time =\s*([\d.]+) ms /\s*(\d+) tokens \(\s*[\d.]+ ms per token,\s*([\d.]+) tokens per second') {
            $this.Timed = $true
            $this.GenerationMs = $Matches[1]
            $this.GenerationTokens = $Matches[2]
            $this.GenerationSpeed = $Matches[3]
            return $true
        }
        if ($message -match '^\s*draft acceptance = ([\d.]+)') {
            $this.DraftAcceptance = $Matches[1]
            return $true
        }
        if ($message -match '^stop processing: n_tokens = \d+, truncated = (\d+)') {
            $this.Released = $true
            $this.Truncated = $Matches[1] -ne '0'
            return $true
        }
        return $false
    }

    [string] ToSummary() {
        $culture = [cultureinfo]::InvariantCulture
        $summary = [string]::Format($culture, '{0:HH:mm:ss} │ slot {1}  task {2,-6}', (Get-Date), $this.Slot, $this.Task)
        if (-not $this.Timed) {
            return "$summary │ released without timings"
        }

        $totalMs = $this.PromptMs + $this.GenerationMs
        $draft = if ($null -ne $this.DraftAcceptance) { [string]::Format($culture, 'draft {0,4:0%}', $this.DraftAcceptance) } else { ' ' * 10 }
        $summary += [string]::Format($culture, ' │ prompt {0,6:N0} tks {1,5:0.0} s ({2,3:0%}) {3,6:N0} t/s',
            $this.PromptTokens, ($this.PromptMs / 1000), ($this.PromptMs / $totalMs), ($this.PromptTokens / $this.PromptMs * 1000))
        $summary += [string]::Format($culture, ' │ answer {0,5:N0} tks {1,5:0.0} s ({2,3:0%}) {3,4:N0} t/s  {4}',
            $this.GenerationTokens, ($this.GenerationMs / 1000), ($this.GenerationMs / $totalMs), $this.GenerationSpeed, $draft)
        $totalTokens = $this.PromptTokens + $this.GenerationTokens
        $summary += [string]::Format($culture, ' │ total {0,6:N0} tks {1,5:0.0} s {2:N0} t/s',
            $totalTokens, ($totalMs / 1000), ($totalTokens / $totalMs * 1000))
        if ($this.Truncated) {
            $summary += ' │ truncated'
        }
        return $summary
    }
}

# Replaces llama-server's info, warning and debug lines with one timing line per finished request: tks just llama, or llama-server ... 2>&1 | tks
function Measure-LlamaRequest {
    begin {
        $jobs = @{}
    }

    process {
        if ($null -eq $_) {
            return
        }

        $text = "$_"
        $slotLine = [LlamaSlotLine]::Parse($text)
        if (-not $slotLine) {
            if ($text -notmatch '^(?:[\d.]+\s+)?[IWD] ') {
                Write-Host $text
            }
            return
        }

        if ($slotLine.StartsJob()) {
            $jobs[$slotLine.Slot] = [LlamaJob]@{ Slot = $slotLine.Slot; Task = $slotLine.Task }
            return
        }

        $job = $jobs[$slotLine.Slot]
        if ($job -and $job.Record($slotLine.Message) -and $job.Released) {
            $jobs.Remove($slotLine.Slot)
            Write-Host $job.ToSummary()
        }
    }

    end {
        if (-not $args) {
            return
        }
        $command = $args[0]
        $arguments = @($args | Select-Object -Skip 1)
        & $command @arguments 2>&1 | Measure-LlamaRequest
    }
}
