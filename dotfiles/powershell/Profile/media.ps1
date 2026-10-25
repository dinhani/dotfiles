# Technical summary of media files.
function Invoke-Media {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [int]$Limit = 1
    )

    $files = if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Get-Item -LiteralPath $Path
    } else {
        Get-ChildItem $Path -Recurse -Include *.mkv, *.mp4, *.flac
    }
    $basePath = if (Test-Path -LiteralPath $Path -PathType Leaf) { Split-Path $Path -Parent } else { $Path }
    $filesTotal = $files.Count
    $counter  = [ref]0

    $medias = $files |
        ForEach-Object -ThrottleLimit $Limit -Parallel {
            $current = [System.Threading.Interlocked]::Increment(($using:counter))
            Write-Progress -Activity "Scanning" -Status "$current / $using:filesTotal — $($_.Name)" -PercentComplete ($current / $using:filesTotal * 100)

            $info = ffprobe -v quiet -print_format json -show_format -show_streams $_ 2>$null | ConvertFrom-Json

            $video = $info.streams | Where-Object codec_type -eq "video" | ForEach-Object {
                [PSCustomObject]@{
                    Codec  = $_.codec_name
                    Width  = $_.width
                    Height = $_.height
                    PixFmt = $_.pix_fmt
                }
            }
            $audio = $info.streams | Where-Object codec_type -eq "audio" | ForEach-Object {
                [PSCustomObject]@{
                    Codec       = $_.codec_name
                    Channels    = $_.channels
                    ChannelLayout = $_.channel_layout
                    SampleRate  = $_.sample_rate
                }
            }
            [PSCustomObject]@{
                File   = [System.IO.Path]::GetRelativePath($using:basePath, $_.FullName)
                Video  = $video
                Audio  = $audio
            }
        }

    $medias | Sort-Object File | ForEach-Object {
        Write-Host "$($_.File)" -ForegroundColor Cyan
        $_.Video | ForEach-Object {
            Write-Host "  Video: $($_.Codec) $($_.Width)x$($_.Height) $($_.PixFmt)"
        }
        $_.Audio | Select -First 1 | ForEach-Object {
            Write-Host "  Audio: $($_.Codec) $($_.Channels)ch $($_.ChannelLayout) $($_.SampleRate)Hz"
        }
    }
}


# Normalizes filenames by removing accents and replacing spaces/dashes with single dashes.
function Invoke-RenameAscii {

    param(
        [Parameter(ValueFromPipeline)]
        $Input
    )
     process {
        $filename = if ($Input -is [System.IO.FileInfo]) { $Input.FullName } else { "$Input" }

        $dir    = Split-Path $filename -Parent
        $source = Split-Path $filename -Leaf

        # ignore special cases
        if ($source -like "Cargo.*") { continue }

        # remove accents
        $normalized = $source.Normalize([Text.NormalizationForm]::FormD)
        $target = -join ($normalized.ToCharArray() | Where-Object {
            [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne
            [Globalization.UnicodeCategory]::NonSpacingMark
        })

        # lower
        $target = $target.ToLower()

        # remove spaces / dashes
        $target = $target -replace ' ', '-'
        $target = $target -replace '_', '-'
        $target = $target -replace '---', '-'
        $target = $target -replace '--', '-'

        # rename if changed
        Rename-Item "$dir\$source" "$dir\__$target"
        Rename-Item "$dir\__$target" "$dir\$target"
    }
}
