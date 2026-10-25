# Prints one line per media file with its video, audio and subtitle summary.
function Invoke-Media {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [int]$Limit = 1
    )

    $extensions = "*.mkv", "*.mp4", "*.m4v", "*.mov", "*.avi", "*.webm", "*.ts", "*.flac", "*.mp3", "*.m4a"
    $files = if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Get-Item -LiteralPath $Path
    } else {
        Get-ChildItem $Path -Recurse -File -Include $extensions
    }
    $basePath = if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Split-Path $Path -Parent
    } else {
        $Path
    }
    $filesTotal = $files.Count
    $counter  = [ref]0

    $files |
        ForEach-Object -ThrottleLimit $Limit -Parallel {
            $current = [System.Threading.Interlocked]::Increment(($using:counter))
            Write-Progress -Activity "Scanning" -Status "$current / $using:filesTotal — $($_.Name)" -PercentComplete ($current / $using:filesTotal * 100)

            $file = [System.IO.Path]::GetRelativePath($using:basePath, $_.FullName)
            $json = ffprobe -v quiet -print_format json -show_streams $_.FullName
            if ($LASTEXITCODE -ne 0) {
                return [PSCustomObject]@{ Video = "unreadable"; Audio = ""; Subs = ""; File = $file }
            }
            $streams = @(($json | ConvertFrom-Json).streams | Where-Object { $_.disposition.attached_pic -ne 1 })
            $videos = @($streams | Where-Object codec_type -eq "video")
            $audios = @($streams | Where-Object codec_type -eq "audio")
            $subtitles = @($streams | Where-Object codec_type -eq "subtitle")

            # video: codec and resolution class by width (cropped widescreen keeps full width), plus bit depth and HDR only when they are not 8-bit SDR
            $video = ""
            if ($videos) {
                $stream = $videos[0]
                $resolution = if ($stream.width -ge 3200) {
                    "2160p"
                } elseif ($stream.width -ge 1800) {
                    "1080p"
                } elseif ($stream.width -ge 1200) {
                    "720p"
                } else {
                    "$($stream.height)p"
                }
                $video = "$($stream.codec_name) $resolution"
                if ($stream.pix_fmt -match 'p(\d+)(le|be)$') {
                    $video += " $($Matches[1])-bit"
                }
                if ($stream.side_data_list.side_data_type -contains "DOVI configuration record") {
                    $video += " DV"
                } elseif ($stream.color_transfer -eq "smpte2084") {
                    $video += " HDR10"
                } elseif ($stream.color_transfer -eq "arib-std-b67") {
                    $video += " HLG"
                }
            }

            # audio: first track's codec and layout, then the languages of all tracks
            $audio = ""
            if ($audios) {
                $layout = $audios[0].channel_layout -replace '\(.*\)$', ''
                if (-not $layout) {
                    $layout = "$($audios[0].channels)ch"
                }
                $audio = "$($audios[0].codec_name) $layout"
                $languages = @($audios.tags.language | Where-Object { $_ -and $_ -ne "und" } | Select-Object -Unique)
                if ($languages) {
                    $audio += " ($($languages -join ', '))"
                }
            }

            # subtitles: first three languages and how many more
            $subtitleLanguages = @($subtitles.tags.language | Where-Object { $_ -and $_ -ne "und" } | Select-Object -Unique)
            $subs = $subtitleLanguages | Select-Object -First 3 | Join-String -Separator ", "
            if ($subtitleLanguages.Count -gt 3) {
                $subs += " +$($subtitleLanguages.Count - 3)"
            }

            [PSCustomObject]@{
                Video = $video
                Audio = $audio
                Subs  = $subs
                File  = $file
            }
        } |
        Sort-Object File |
        Format-Table -AutoSize
}

# Renames piped files to lowercase ASCII with dashes instead of spaces and underscores.
function Invoke-RenameAscii {
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias("FullName")]
        [string]$Path
    )

    process {
        $dir    = Split-Path $Path -Parent
        $source = Split-Path $Path -Leaf

        # ignore special cases
        if ($source -like "Cargo.*") {
            return
        }

        # remove accents
        $normalized = $source.Normalize([Text.NormalizationForm]::FormD)
        $target = -join ($normalized.ToCharArray() | Where-Object {
            [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne
            [Globalization.UnicodeCategory]::NonSpacingMark
        })

        # lower, spaces and underscores to single dashes
        $target = $target.ToLower() -replace '[ _]', '-' -replace '-{2,}', '-'
        if ($target -ceq $source) {
            return
        }

        # rename in two steps so case-only changes apply
        Rename-Item -LiteralPath (Join-Path $dir $source) -NewName "__$target"
        Rename-Item -LiteralPath (Join-Path $dir "__$target") -NewName $target
    }
}
