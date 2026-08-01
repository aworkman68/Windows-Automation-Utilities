#requires -Version 5.1
<#
.SYNOPSIS
Batch-converts TIFF images to high-quality JPEG files.

.DESCRIPTION
Provides a single Windows Forms interface for configuring and running a batch
TIFF-to-JPEG conversion. The utility preserves base filenames and pixel
 dimensions, supports recursive processing and separate output folders, remembers
settings, displays progress, and writes a detailed timestamped log.

.NOTES
Project: Windows Automation Utilities
Utility: Batch TIFF to JPEG Converter
Version: 1.1.0
Author: Alan Workman
Copyright: (c) 2026 Alan Workman
License: MIT
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:AppName = 'Batch TIFF to JPEG Converter'
$script:Version = '1.1.0'
$script:CancelRequested = $false
$script:LastLogPath = $null
$script:LastOutputFolder = $null

$settingsDirectory = Join-Path $env:APPDATA 'WindowsAutomationUtilities'
$settingsPath = Join-Path $settingsDirectory 'BatchTiffToJpeg.settings.json'

function Load-Settings {
    $defaults = [ordered]@{
        SourceFolder = ''
        IncludeSubfolders = $false
        SaveBesideOriginals = $true
        OutputFolder = ''
        Quality = 95
        OverwriteExisting = $false
    }

    if (Test-Path -LiteralPath $settingsPath) {
        try {
            $saved = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop | ConvertFrom-Json
            foreach ($key in @($defaults.Keys)) {
                if ($null -ne $saved.$key) { $defaults[$key] = $saved.$key }
            }
        } catch { }
    }
    return [pscustomobject]$defaults
}

function Save-Settings {
    param([Parameter(Mandatory)]$Settings)
    try {
        if (-not (Test-Path -LiteralPath $settingsDirectory)) {
            New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null
        }
        $Settings | ConvertTo-Json | Set-Content -LiteralPath $settingsPath -Encoding UTF8
    } catch { }
}

function Show-OwnedMessage {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.IWin32Window]$Owner,
        [Parameter(Mandatory)][string]$Text,
        [string]$Title = $script:AppName,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )
    [System.Windows.Forms.MessageBox]::Show(
        $Owner, $Text, $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK, $Icon
    ) | Out-Null
}

function Select-Folder {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.IWin32Window]$Owner,
        [Parameter(Mandatory)][string]$Description,
        [string]$InitialPath
    )
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    if ($InitialPath -and (Test-Path -LiteralPath $InitialPath -PathType Container)) {
        $dialog.SelectedPath = $InitialPath
    }
    try {
        if ($dialog.ShowDialog($Owner) -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.SelectedPath
        }
    } finally {
        $dialog.Dispose()
    }
    return $null
}

function Get-JpegCodec {
    [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
        Where-Object MimeType -eq 'image/jpeg' |
        Select-Object -First 1
}

function Convert-OneTiff {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][ValidateRange(1,100)][int]$Quality
    )
    $stream = $sourceImage = $bitmap = $graphics = $encoderParameters = $qualityParameter = $null
    try {
        $stream = [System.IO.File]::Open($SourcePath, 'Open', 'Read', 'Read')
        $sourceImage = [System.Drawing.Image]::FromStream($stream, $true, $true)
        $width = $sourceImage.Width
        $height = $sourceImage.Height

        $bitmap = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        if ($sourceImage.HorizontalResolution -gt 0 -and $sourceImage.VerticalResolution -gt 0) {
            try { $bitmap.SetResolution($sourceImage.HorizontalResolution, $sourceImage.VerticalResolution) } catch { }
        }

        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage($sourceImage, 0, 0, $width, $height)

        $destinationDirectory = Split-Path -Parent $DestinationPath
        if (-not (Test-Path -LiteralPath $destinationDirectory)) {
            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        }

        $codec = Get-JpegCodec
        if (-not $codec) { throw 'The JPEG encoder could not be found.' }
        $encoderParameters = New-Object System.Drawing.Imaging.EncoderParameters(1)
        $qualityParameter = New-Object System.Drawing.Imaging.EncoderParameter(
            [System.Drawing.Imaging.Encoder]::Quality, [long]$Quality
        )
        $encoderParameters.Param[0] = $qualityParameter
        $bitmap.Save($DestinationPath, $codec, $encoderParameters)
        return [pscustomobject]@{ Width = $width; Height = $height }
    } finally {
        if ($qualityParameter) { $qualityParameter.Dispose() }
        if ($encoderParameters) { $encoderParameters.Dispose() }
        if ($graphics) { $graphics.Dispose() }
        if ($bitmap) { $bitmap.Dispose() }
        if ($sourceImage) { $sourceImage.Dispose() }
        if ($stream) { $stream.Dispose() }
    }
}

function Format-Bytes([long]$Bytes) {
    if ($Bytes -ge 1TB) { return '{0:N2} TB' -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N2} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N2} KB' -f ($Bytes / 1KB) }
    return "$Bytes bytes"
}

function Format-Duration([TimeSpan]$Duration) {
    if ($Duration.TotalHours -ge 1) { return $Duration.ToString('hh\:mm\:ss') }
    return $Duration.ToString('mm\:ss')
}

$settings = Load-Settings
$form = New-Object System.Windows.Forms.Form
$form.Text = "$script:AppName v$script:Version"
$form.ClientSize = New-Object System.Drawing.Size(680, 570)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.TopMost = $true
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.AutoScaleMode = 'Dpi'

$title = New-Object System.Windows.Forms.Label
$title.Text = $script:AppName
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 18)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(24, 18)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Convert TIFF images to high-quality JPEGs while preserving filenames and pixel dimensions.'
$subtitle.AutoSize = $true
$subtitle.ForeColor = [System.Drawing.Color]::DimGray
$subtitle.Location = New-Object System.Drawing.Point(28, 57)
$form.Controls.Add($subtitle)

function Add-Label($text, $x, $y) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point($x, $y)
    $form.Controls.Add($label)
    return $label
}

Add-Label 'Source folder:' 28 101 | Out-Null
$txtSource = New-Object System.Windows.Forms.TextBox
$txtSource.Location = New-Object System.Drawing.Point(28, 123)
$txtSource.Size = New-Object System.Drawing.Size(518, 25)
$txtSource.Text = [string]$settings.SourceFolder
$form.Controls.Add($txtSource)
$btnSource = New-Object System.Windows.Forms.Button
$btnSource.Text = 'Browse...'
$btnSource.Location = New-Object System.Drawing.Point(556, 121)
$btnSource.Size = New-Object System.Drawing.Size(95, 29)
$form.Controls.Add($btnSource)

$chkRecursive = New-Object System.Windows.Forms.CheckBox
$chkRecursive.Text = 'Include subfolders'
$chkRecursive.AutoSize = $true
$chkRecursive.Location = New-Object System.Drawing.Point(28, 159)
$chkRecursive.Checked = [bool]$settings.IncludeSubfolders
$form.Controls.Add($chkRecursive)

$groupDestination = New-Object System.Windows.Forms.GroupBox
$groupDestination.Text = 'Destination'
$groupDestination.Location = New-Object System.Drawing.Point(28, 192)
$groupDestination.Size = New-Object System.Drawing.Size(623, 128)
$form.Controls.Add($groupDestination)

$rbBeside = New-Object System.Windows.Forms.RadioButton
$rbBeside.Text = 'Save JPEGs beside the original TIFF files'
$rbBeside.AutoSize = $true
$rbBeside.Location = New-Object System.Drawing.Point(16, 27)
$rbBeside.Checked = [bool]$settings.SaveBesideOriginals
$groupDestination.Controls.Add($rbBeside)
$rbSeparate = New-Object System.Windows.Forms.RadioButton
$rbSeparate.Text = 'Save JPEGs in a separate folder'
$rbSeparate.AutoSize = $true
$rbSeparate.Location = New-Object System.Drawing.Point(16, 55)
$rbSeparate.Checked = -not [bool]$settings.SaveBesideOriginals
$groupDestination.Controls.Add($rbSeparate)
$txtOutput = New-Object System.Windows.Forms.TextBox
$txtOutput.Location = New-Object System.Drawing.Point(35, 84)
$txtOutput.Size = New-Object System.Drawing.Size(458, 25)
$txtOutput.Text = [string]$settings.OutputFolder
$groupDestination.Controls.Add($txtOutput)
$btnOutput = New-Object System.Windows.Forms.Button
$btnOutput.Text = 'Browse...'
$btnOutput.Location = New-Object System.Drawing.Point(503, 82)
$btnOutput.Size = New-Object System.Drawing.Size(95, 29)
$groupDestination.Controls.Add($btnOutput)

Add-Label 'JPEG quality:' 28 342 | Out-Null
$numQuality = New-Object System.Windows.Forms.NumericUpDown
$numQuality.Location = New-Object System.Drawing.Point(116, 338)
$numQuality.Size = New-Object System.Drawing.Size(72, 25)
$numQuality.Minimum = 1
$numQuality.Maximum = 100
$numQuality.Value = [decimal][Math]::Min(100, [Math]::Max(1, [int]$settings.Quality))
$form.Controls.Add($numQuality)
$lblQualityHint = New-Object System.Windows.Forms.Label
$lblQualityHint.Text = '95 is recommended for high-quality archival images.'
$lblQualityHint.AutoSize = $true
$lblQualityHint.ForeColor = [System.Drawing.Color]::DimGray
$lblQualityHint.Location = New-Object System.Drawing.Point(200, 342)
$form.Controls.Add($lblQualityHint)

$chkOverwrite = New-Object System.Windows.Forms.CheckBox
$chkOverwrite.Text = 'Overwrite JPEG files that already exist'
$chkOverwrite.AutoSize = $true
$chkOverwrite.Location = New-Object System.Drawing.Point(28, 375)
$chkOverwrite.Checked = [bool]$settings.OverwriteExisting
$form.Controls.Add($chkOverwrite)

$separator = New-Object System.Windows.Forms.Label
$separator.BorderStyle = 'Fixed3D'
$separator.AutoSize = $false
$separator.Location = New-Object System.Drawing.Point(28, 412)
$separator.Size = New-Object System.Drawing.Size(623, 2)
$form.Controls.Add($separator)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = 'Ready.'
$lblStatus.Location = New-Object System.Drawing.Point(28, 428)
$lblStatus.Size = New-Object System.Drawing.Size(623, 22)
$form.Controls.Add($lblStatus)
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(28, 453)
$progress.Size = New-Object System.Drawing.Size(623, 23)
$progress.Minimum = 0
$progress.Maximum = 100
$form.Controls.Add($progress)
$lblDetails = New-Object System.Windows.Forms.Label
$lblDetails.Text = 'No conversion is currently running.'
$lblDetails.Location = New-Object System.Drawing.Point(28, 482)
$lblDetails.Size = New-Object System.Drawing.Size(623, 22)
$lblDetails.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblDetails)

$btnConvert = New-Object System.Windows.Forms.Button
$btnConvert.Text = 'Convert'
$btnConvert.Location = New-Object System.Drawing.Point(444, 520)
$btnConvert.Size = New-Object System.Drawing.Size(100, 34)
$form.Controls.Add($btnConvert)
$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = 'Close'
$btnCancel.Location = New-Object System.Drawing.Point(551, 520)
$btnCancel.Size = New-Object System.Drawing.Size(100, 34)
$form.Controls.Add($btnCancel)
$form.AcceptButton = $btnConvert
$form.CancelButton = $btnCancel

function Update-DestinationControls {
    $enabled = $rbSeparate.Checked
    $txtOutput.Enabled = $enabled
    $btnOutput.Enabled = $enabled
}
Update-DestinationControls
$rbBeside.Add_CheckedChanged({ Update-DestinationControls })
$rbSeparate.Add_CheckedChanged({ Update-DestinationControls })

$btnSource.Add_Click({
    $selected = Select-Folder -Owner $form -Description 'Select the folder containing TIFF files' -InitialPath $txtSource.Text
    if ($selected) { $txtSource.Text = $selected }
})
$btnOutput.Add_Click({
    $initial = if ($txtOutput.Text) { $txtOutput.Text } else { $txtSource.Text }
    $selected = Select-Folder -Owner $form -Description 'Select the folder where JPEG files will be saved' -InitialPath $initial
    if ($selected) { $txtOutput.Text = $selected }
})

$btnCancel.Add_Click({
    if ($btnCancel.Text -eq 'Cancel') {
        $script:CancelRequested = $true
        $btnCancel.Enabled = $false
        $lblStatus.Text = 'Cancelling after the current file...'
    } else {
        $form.Close()
    }
})

$btnConvert.Add_Click({
    $sourceFolder = $txtSource.Text.Trim()
    $outputFolder = $txtOutput.Text.Trim()
    if (-not (Test-Path -LiteralPath $sourceFolder -PathType Container)) {
        Show-OwnedMessage -Owner $form -Text 'Please select a valid source folder.' -Icon Error
        $txtSource.Focus(); return
    }
    if ($rbSeparate.Checked -and [string]::IsNullOrWhiteSpace($outputFolder)) {
        Show-OwnedMessage -Owner $form -Text 'Please select a separate output folder.' -Icon Error
        $txtOutput.Focus(); return
    }
    if ($rbSeparate.Checked -and -not (Test-Path -LiteralPath $outputFolder -PathType Container)) {
        try { New-Item -ItemType Directory -Path $outputFolder -Force -ErrorAction Stop | Out-Null }
        catch { Show-OwnedMessage -Owner $form -Text "The output folder could not be created.`r`n`r`n$($_.Exception.Message)" -Icon Error; return }
    }

    $currentSettings = [pscustomobject]@{
        SourceFolder = $sourceFolder
        IncludeSubfolders = $chkRecursive.Checked
        SaveBesideOriginals = $rbBeside.Checked
        OutputFolder = $outputFolder
        Quality = [int]$numQuality.Value
        OverwriteExisting = $chkOverwrite.Checked
    }
    Save-Settings $currentSettings

    $searchOption = if ($chkRecursive.Checked) { [System.IO.SearchOption]::AllDirectories } else { [System.IO.SearchOption]::TopDirectoryOnly }
    try {
        $files = @(
            [System.IO.Directory]::EnumerateFiles($sourceFolder, '*.tif', $searchOption)
            [System.IO.Directory]::EnumerateFiles($sourceFolder, '*.tiff', $searchOption)
        ) | Sort-Object -Unique
    } catch {
        Show-OwnedMessage -Owner $form -Text "The source folder could not be scanned.`r`n`r`n$($_.Exception.Message)" -Icon Error; return
    }
    if ($files.Count -eq 0) {
        Show-OwnedMessage -Owner $form -Text 'No .tif or .tiff files were found in the selected folder.' -Icon Warning; return
    }

    $script:CancelRequested = $false
    $btnConvert.Enabled = $false
    $btnSource.Enabled = $false
    $btnOutput.Enabled = $false
    $btnCancel.Text = 'Cancel'
    $progress.Value = 0
    $form.TopMost = $false
    $startTime = Get-Date
    $created = $skipped = $failed = 0
    [long]$originalBytes = 0
    [long]$jpegBytes = 0
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logFolder = if ($rbSeparate.Checked) { $outputFolder } else { $sourceFolder }
    $logPath = Join-Path $logFolder "TiffToJpegConversion-$timestamp.log.txt"
    $log = New-Object System.Collections.Generic.List[string]
    $log.Add("$script:AppName v$script:Version")
    $log.Add("Started: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))")
    $log.Add("Source: $sourceFolder")
    $log.Add("Destination: $(if ($rbBeside.Checked) { 'Beside originals' } else { $outputFolder })")
    $log.Add("Quality: $([int]$numQuality.Value)")
    $log.Add('')
    $log.Add("STATUS`tSOURCE`tDESTINATION`tDETAILS")

    for ($i = 0; $i -lt $files.Count; $i++) {
        if ($script:CancelRequested) { break }
        $sourcePath = $files[$i]
        $sourceInfo = Get-Item -LiteralPath $sourcePath
        $originalBytes += $sourceInfo.Length
        $progress.Value = [Math]::Min(100, [int](($i / [Math]::Max(1,$files.Count)) * 100))
        $lblStatus.Text = "Converting $($i + 1) of $($files.Count): $($sourceInfo.Name)"
        $elapsed = (Get-Date) - $startTime
        $remainingText = 'Calculating...'
        if ($i -gt 0) {
            $remaining = [TimeSpan]::FromSeconds(($elapsed.TotalSeconds / $i) * ($files.Count - $i))
            $remainingText = Format-Duration $remaining
        }
        $lblDetails.Text = "Elapsed: $(Format-Duration $elapsed)    Estimated remaining: $remainingText"
        [System.Windows.Forms.Application]::DoEvents()

        $destinationDirectory = if ($rbBeside.Checked) {
            $sourceInfo.DirectoryName
        } elseif ($chkRecursive.Checked) {
            $relative = $sourceInfo.DirectoryName.Substring($sourceFolder.Length).TrimStart('\')
            if ($relative) { Join-Path $outputFolder $relative } else { $outputFolder }
        } else { $outputFolder }
        $destinationPath = Join-Path $destinationDirectory ($sourceInfo.BaseName + '.jpg')

        if ((Test-Path -LiteralPath $destinationPath) -and -not $chkOverwrite.Checked) {
            $skipped++
            $log.Add("SKIPPED`t$sourcePath`t$destinationPath`tJPEG already exists.")
            continue
        }
        try {
            $dimensions = Convert-OneTiff -SourcePath $sourcePath -DestinationPath $destinationPath -Quality ([int]$numQuality.Value)
            $jpegInfo = Get-Item -LiteralPath $destinationPath
            $jpegBytes += $jpegInfo.Length
            $created++
            $log.Add("CREATED`t$sourcePath`t$destinationPath`t$($dimensions.Width)x$($dimensions.Height); $($sourceInfo.Length) -> $($jpegInfo.Length) bytes")
        } catch {
            $failed++
            $log.Add("FAILED`t$sourcePath`t$destinationPath`t$($_.Exception.Message)")
        }
    }

    $endTime = Get-Date
    $elapsedTotal = $endTime - $startTime
    $progress.Value = if ($script:CancelRequested) { $progress.Value } else { 100 }
    $spaceSaved = $originalBytes - $jpegBytes
    $percentSaved = if ($originalBytes -gt 0) { [Math]::Round(($spaceSaved / $originalBytes) * 100, 1) } else { 0 }
    $log.Add('')
    $log.Add("Completed: $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))")
    $log.Add("Cancelled: $script:CancelRequested")
    $log.Add("Created: $created")
    $log.Add("Skipped: $skipped")
    $log.Add("Failed: $failed")
    $log.Add("Space reduction: $(Format-Bytes $spaceSaved) ($percentSaved%)")
    try { $log | Set-Content -LiteralPath $logPath -Encoding UTF8 } catch { $logPath = $null }

    $script:LastLogPath = $logPath
    $script:LastOutputFolder = if ($rbBeside.Checked) { $sourceFolder } else { $outputFolder }
    $lblStatus.Text = if ($script:CancelRequested) { 'Conversion cancelled.' } else { 'Conversion complete.' }
    $lblDetails.Text = "Created: $created    Skipped: $skipped    Failed: $failed    Elapsed: $(Format-Duration $elapsedTotal)"
    $btnConvert.Enabled = $true
    $btnSource.Enabled = $true
    Update-DestinationControls
    $btnCancel.Enabled = $true
    $btnCancel.Text = 'Close'
    $form.TopMost = $true
    $form.Activate()

    $summaryForm = New-Object System.Windows.Forms.Form
    $summaryForm.Text = 'Conversion Results'
    $summaryForm.ClientSize = New-Object System.Drawing.Size(500, 320)
    $summaryForm.StartPosition = 'CenterParent'
    $summaryForm.FormBorderStyle = 'FixedDialog'
    $summaryForm.MaximizeBox = $false
    $summaryForm.MinimizeBox = $false
    $summaryForm.TopMost = $true
    $summaryForm.Font = $form.Font
    $heading = New-Object System.Windows.Forms.Label
    $heading.Text = if ($script:CancelRequested) { 'Conversion Cancelled' } elseif ($failed -gt 0) { 'Conversion Completed with Errors' } else { 'Conversion Completed Successfully' }
    $heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15)
    $heading.AutoSize = $true
    $heading.Location = New-Object System.Drawing.Point(22, 18)
    $summaryForm.Controls.Add($heading)
    $details = New-Object System.Windows.Forms.Label
    $details.Text = "JPEG files created:  $created`r`nFiles skipped:       $skipped`r`nFailures:            $failed`r`nSpace reduction:     $(Format-Bytes $spaceSaved) ($percentSaved%)`r`nElapsed time:        $(Format-Duration $elapsedTotal)`r`n`r`nOriginal TIFF files were not deleted."
    $details.Location = New-Object System.Drawing.Point(26, 65)
    $details.Size = New-Object System.Drawing.Size(445, 150)
    $summaryForm.Controls.Add($details)
    $btnOpenFolder = New-Object System.Windows.Forms.Button
    $btnOpenFolder.Text = 'Open Output Folder'
    $btnOpenFolder.Location = New-Object System.Drawing.Point(25, 252)
    $btnOpenFolder.Size = New-Object System.Drawing.Size(145, 34)
    $btnOpenFolder.Add_Click({ if (Test-Path -LiteralPath $script:LastOutputFolder) { Start-Process explorer.exe -ArgumentList "`"$script:LastOutputFolder`"" } })
    $summaryForm.Controls.Add($btnOpenFolder)
    $btnOpenLog = New-Object System.Windows.Forms.Button
    $btnOpenLog.Text = 'Open Log'
    $btnOpenLog.Location = New-Object System.Drawing.Point(180, 252)
    $btnOpenLog.Size = New-Object System.Drawing.Size(120, 34)
    $btnOpenLog.Enabled = [bool]($script:LastLogPath -and (Test-Path -LiteralPath $script:LastLogPath))
    $btnOpenLog.Add_Click({ if ($script:LastLogPath) { Start-Process notepad.exe -ArgumentList "`"$script:LastLogPath`"" } })
    $summaryForm.Controls.Add($btnOpenLog)
    $btnDone = New-Object System.Windows.Forms.Button
    $btnDone.Text = 'Close'
    $btnDone.Location = New-Object System.Drawing.Point(350, 252)
    $btnDone.Size = New-Object System.Drawing.Size(120, 34)
    $btnDone.Add_Click({ $summaryForm.Close() })
    $summaryForm.Controls.Add($btnDone)
    $summaryForm.AcceptButton = $btnDone
    $summaryForm.CancelButton = $btnDone
    $summaryForm.ShowDialog($form) | Out-Null
    $summaryForm.Dispose()
})

$form.Add_Shown({ $form.Activate(); $form.BringToFront(); $txtSource.Focus() })
$form.Add_FormClosing({ if ($btnCancel.Text -eq 'Cancel') { $_.Cancel = $true; $script:CancelRequested = $true } })
[void]$form.ShowDialog()
$form.Dispose()