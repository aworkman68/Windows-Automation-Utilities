#requires -Version 5.1
<#
.SYNOPSIS
Batch-converts TIFF images to high-quality JPEG files.

.DESCRIPTION
- Prompts for a source folder containing .tif or .tiff files.
- Optionally includes subfolders.
- Preserves the original base filename and pixel dimensions.
- Saves JPEG files either beside the originals or in a selected output folder.
- Uses configurable JPEG quality (default: 95).
- Skips existing JPEGs unless overwrite is enabled.
- Does not delete or modify the original TIFF files.
- Writes a conversion log when complete.

Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

function Show-Message {
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Title = "TIFF to JPEG Converter",
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )

    [System.Windows.Forms.MessageBox]::Show(
        $Text,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $Icon
    ) | Out-Null
}

function Ask-YesNo {
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Title = "TIFF to JPEG Converter"
    )

    $result = [System.Windows.Forms.MessageBox]::Show(
        $Text,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Select-Folder {
    param(
        [Parameter(Mandatory)][string]$Description,
        [string]$InitialPath
    )

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true

    if ($InitialPath -and (Test-Path -LiteralPath $InitialPath -PathType Container)) {
        $dialog.SelectedPath = $InitialPath
    }

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }

    return $null
}

function Get-JpegCodec {
    return [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
        Where-Object { $_.MimeType -eq "image/jpeg" } |
        Select-Object -First 1
}

function Convert-TiffToJpeg {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][int]$Quality
    )

    $sourceImage = $null
    $outputBitmap = $null
    $graphics = $null
    $encoderParameters = $null
    $stream = $null

    try {
        $stream = [System.IO.File]::Open(
            $SourcePath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )

        $sourceImage = [System.Drawing.Image]::FromStream($stream, $true, $true)

        $outputBitmap = New-Object System.Drawing.Bitmap(
            $sourceImage.Width,
            $sourceImage.Height,
            [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
        )

        if ($sourceImage.HorizontalResolution -gt 0 -and $sourceImage.VerticalResolution -gt 0) {
            try {
                $outputBitmap.SetResolution(
                    $sourceImage.HorizontalResolution,
                    $sourceImage.VerticalResolution
                )
            }
            catch {
                # Some TIFFs contain unsupported DPI values. Pixel dimensions are still preserved.
            }
        }

        $graphics = [System.Drawing.Graphics]::FromImage($outputBitmap)
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        $destinationRectangle = New-Object System.Drawing.Rectangle(
            0,
            0,
            $sourceImage.Width,
            $sourceImage.Height
        )

        $graphics.DrawImage(
            $sourceImage,
            $destinationRectangle,
            0,
            0,
            $sourceImage.Width,
            $sourceImage.Height,
            [System.Drawing.GraphicsUnit]::Pixel
        )

        $graphics.Dispose()
        $graphics = $null

        $sourceImage.Dispose()
        $sourceImage = $null

        $stream.Dispose()
        $stream = $null

        $jpegCodec = Get-JpegCodec
        if (-not $jpegCodec) {
            throw "The JPEG encoder could not be found."
        }

        $encoderParameters = New-Object System.Drawing.Imaging.EncoderParameters(1)
        $qualityParameter = New-Object System.Drawing.Imaging.EncoderParameter(
            [System.Drawing.Imaging.Encoder]::Quality,
            [long]$Quality
        )
        $encoderParameters.Param[0] = $qualityParameter

        $destinationDirectory = Split-Path -Parent $DestinationPath
        if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        }

        $outputBitmap.Save($DestinationPath, $jpegCodec, $encoderParameters)
    }
    finally {
        if ($graphics) { $graphics.Dispose() }
        if ($sourceImage) { $sourceImage.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($encoderParameters) { $encoderParameters.Dispose() }
        if ($outputBitmap) { $outputBitmap.Dispose() }
    }
}

$sourceFolder = Select-Folder -Description "Select the folder containing TIFF files"

if (-not $sourceFolder) {
    Write-Host "Operation cancelled."
    exit
}

$includeSubfolders = Ask-YesNo -Text "Include TIFF files in subfolders?"

$saveBesideOriginals = Ask-YesNo -Text @"
Save each JPEG beside its original TIFF?

Choose No to select one separate output folder.
"@

$outputFolder = $null

if (-not $saveBesideOriginals) {
    $outputFolder = Select-Folder `
        -Description "Select the folder where JPEG files will be saved" `
        -InitialPath $sourceFolder

    if (-not $outputFolder) {
        Write-Host "Operation cancelled."
        exit
    }
}

$qualityText = [Microsoft.VisualBasic.Interaction]::InputBox(
    "Enter JPEG quality from 1 to 100.`r`n`r`n95 is recommended for high-quality archival images.",
    "JPEG Quality",
    "95"
)

if ([string]::IsNullOrWhiteSpace($qualityText)) {
    Write-Host "Operation cancelled."
    exit
}

$quality = 0

if (-not [int]::TryParse($qualityText, [ref]$quality) -or $quality -lt 1 -or $quality -gt 100) {
    Show-Message `
        -Text "Please enter a whole number between 1 and 100." `
        -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}

$overwriteExisting = Ask-YesNo -Text @"
Overwrite JPEG files that already exist?

Choosing No is safer and will skip existing files.
"@

$searchOption = if ($includeSubfolders) {
    [System.IO.SearchOption]::AllDirectories
}
else {
    [System.IO.SearchOption]::TopDirectoryOnly
}

$tiffFiles = @(
    [System.IO.Directory]::EnumerateFiles($sourceFolder, "*.tif", $searchOption)
    [System.IO.Directory]::EnumerateFiles($sourceFolder, "*.tiff", $searchOption)
) | Sort-Object -Unique

if ($tiffFiles.Count -eq 0) {
    Show-Message `
        -Text "No .tif or .tiff files were found in the selected folder." `
        -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning)
    exit
}

$created = 0
$skipped = 0
$failed = 0
$totalOriginalBytes = [long]0
$totalJpegBytes = [long]0
$logLines = New-Object System.Collections.Generic.List[string]

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logBaseFolder = if ($outputFolder) { $outputFolder } else { $sourceFolder }
$logPath = Join-Path $logBaseFolder "TiffToJpegConversion-$timestamp.log.txt"

$logLines.Add("TIFF to JPEG Conversion Log")
$logLines.Add("Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$logLines.Add("Source folder: $sourceFolder")
$logLines.Add("Include subfolders: $includeSubfolders")
$logLines.Add("Output mode: $(if ($saveBesideOriginals) { 'Beside originals' } else { $outputFolder })")
$logLines.Add("JPEG quality: $quality")
$logLines.Add("Overwrite existing: $overwriteExisting")
$logLines.Add("")
$logLines.Add("STATUS`tSOURCE`tDESTINATION`tDETAILS")

for ($index = 0; $index -lt $tiffFiles.Count; $index++) {
    $sourcePath = $tiffFiles[$index]
    $sourceInfo = Get-Item -LiteralPath $sourcePath
    $totalOriginalBytes += $sourceInfo.Length

    $percent = [int](($index / [Math]::Max($tiffFiles.Count, 1)) * 100)

    Write-Progress `
        -Activity "Converting TIFF images to JPEG" `
        -Status "$($index + 1) of $($tiffFiles.Count): $($sourceInfo.Name)" `
        -PercentComplete $percent

    if ($saveBesideOriginals) {
        $destinationDirectory = $sourceInfo.DirectoryName
    }
    else {
        if ($includeSubfolders) {
            $relativeDirectory = $sourceInfo.DirectoryName.Substring($sourceFolder.Length).TrimStart('\')
            $destinationDirectory = if ([string]::IsNullOrWhiteSpace($relativeDirectory)) {
                $outputFolder
            }
            else {
                Join-Path $outputFolder $relativeDirectory
            }
        }
        else {
            $destinationDirectory = $outputFolder
        }
    }

    $destinationPath = Join-Path `
        $destinationDirectory `
        ([System.IO.Path]::GetFileNameWithoutExtension($sourceInfo.Name) + ".jpg")

    if ((Test-Path -LiteralPath $destinationPath) -and -not $overwriteExisting) {
        Write-Host "Skipped existing: $destinationPath" -ForegroundColor Yellow
        $logLines.Add("SKIPPED`t$sourcePath`t$destinationPath`tJPEG already exists.")
        $skipped++
        continue
    }

    try {
        Convert-TiffToJpeg `
            -SourcePath $sourcePath `
            -DestinationPath $destinationPath `
            -Quality $quality

        $jpegInfo = Get-Item -LiteralPath $destinationPath
        $totalJpegBytes += $jpegInfo.Length

        Write-Host "Created: $destinationPath" -ForegroundColor Green
        $logLines.Add(
            "CREATED`t$sourcePath`t$destinationPath`t$($sourceInfo.Length) bytes -> $($jpegInfo.Length) bytes"
        )
        $created++
    }
    catch {
        Write-Host "Failed: $sourcePath - $($_.Exception.Message)" -ForegroundColor Red
        $logLines.Add("FAILED`t$sourcePath`t$destinationPath`t$($_.Exception.Message)")
        $failed++
    }
}

Write-Progress -Activity "Converting TIFF images to JPEG" -Completed

$spaceSaved = $totalOriginalBytes - $totalJpegBytes
$percentSaved = if ($totalOriginalBytes -gt 0) {
    [Math]::Round(($spaceSaved / $totalOriginalBytes) * 100, 1)
}
else {
    0
}

$logLines.Add("")
$logLines.Add("Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$logLines.Add("JPEG files created: $created")
$logLines.Add("Files skipped: $skipped")
$logLines.Add("Failures: $failed")
$logLines.Add("Original TIFF bytes processed: $totalOriginalBytes")
$logLines.Add("JPEG bytes created: $totalJpegBytes")
$logLines.Add("Approximate space reduction: $percentSaved%")

try {
    $logLines | Set-Content -LiteralPath $logPath -Encoding UTF8
}
catch {
    Write-Host "Warning: The log file could not be written." -ForegroundColor Yellow
    $logPath = "(Log could not be written.)"
}

$summary = @"
Conversion complete.

JPEG files created: $created
Files skipped: $skipped
Failures: $failed
Approximate space reduction: $percentSaved%

Original TIFF files were not deleted.

Log file:
$logPath
"@

Write-Host ""
Write-Host "------------------------------------------------------------"
Write-Host $summary -ForegroundColor Cyan
Write-Host "------------------------------------------------------------"

Show-Message -Text $summary

Read-Host "Press Enter to close"