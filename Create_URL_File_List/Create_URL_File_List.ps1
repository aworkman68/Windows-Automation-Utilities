#requires -Version 5.1
<#
.SYNOPSIS
Generates sequential URL lists from a numbered starting URL.

.DESCRIPTION
Windows Automation Utilities - Sequential URL List Generator
Version: 2.0.2
Author: Alan Workman
License: MIT

Features:
- Single-window Windows Forms interface
- Three range modes: ending URL, ending number, or number of files
- Live validation and preview
- Automatic extension, prefix, and number-padding detection
- Save to a text file and/or copy to the Windows clipboard
- Remembers the last output folder and selected options
- Foreground/topmost startup behavior
- Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:AppName = "Sequential URL List Generator"
$script:AppVersion = "2.0.2"
$script:SettingsFolder = Join-Path $env:APPDATA "WindowsAutomationUtilities"
$script:SettingsFile = Join-Path $script:SettingsFolder "SequentialUrlGenerator.settings.json"

function Load-Settings {
    $defaults = [ordered]@{
        OutputFolder = [Environment]::GetFolderPath("MyDocuments")
        OutputFileName = "Generated_URLs.txt"
        RangeMode = "Ending URL"
        SaveFile = $true
        CopyClipboard = $true
        WindowWidth = 900
        WindowHeight = 720
    }

    if (Test-Path -LiteralPath $script:SettingsFile) {
        try {
            $saved = Get-Content -LiteralPath $script:SettingsFile -Raw | ConvertFrom-Json
            foreach ($key in @($defaults.Keys)) {
                if ($null -ne $saved.$key) {
                    $defaults[$key] = $saved.$key
                }
            }
        }
        catch {
            # Invalid settings are ignored and defaults are used.
        }
    }

    return [pscustomobject]$defaults
}

function Save-Settings {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Form]$Form,
        [Parameter(Mandatory)][System.Windows.Forms.ComboBox]$ModeBox,
        [Parameter(Mandatory)][System.Windows.Forms.TextBox]$OutputFolderBox,
        [Parameter(Mandatory)][System.Windows.Forms.TextBox]$OutputNameBox,
        [Parameter(Mandatory)][System.Windows.Forms.CheckBox]$SaveFileBox,
        [Parameter(Mandatory)][System.Windows.Forms.CheckBox]$CopyClipboardBox
    )

    try {
        if (-not (Test-Path -LiteralPath $script:SettingsFolder)) {
            New-Item -ItemType Directory -Path $script:SettingsFolder -Force | Out-Null
        }

        [ordered]@{
            OutputFolder = $OutputFolderBox.Text
            OutputFileName = $OutputNameBox.Text
            RangeMode = $ModeBox.SelectedItem
            SaveFile = $SaveFileBox.Checked
            CopyClipboard = $CopyClipboardBox.Checked
            WindowWidth = $Form.Width
            WindowHeight = $Form.Height
        } | ConvertTo-Json | Set-Content -LiteralPath $script:SettingsFile -Encoding UTF8
    }
    catch {
        # Settings persistence is optional; do not interrupt normal use.
    }
}

function Parse-NumberedUrl {
    param([string]$UrlText)

    if ([string]::IsNullOrWhiteSpace($UrlText)) {
        return [pscustomobject]@{ Valid = $false; Error = "Enter a starting URL." }
    }

    $uri = $null
    if (-not [System.Uri]::TryCreate($UrlText.Trim(), [System.UriKind]::Absolute, [ref]$uri)) {
        return [pscustomobject]@{ Valid = $false; Error = "The URL is not valid." }
    }

    if ($uri.Scheme -notin @("http", "https")) {
        return [pscustomobject]@{ Valid = $false; Error = "The URL must begin with http:// or https://." }
    }

    $fileName = [System.IO.Path]::GetFileName($uri.AbsolutePath)
    $extension = [System.IO.Path]::GetExtension($fileName)
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($fileName)

    if ([string]::IsNullOrWhiteSpace($fileName) -or [string]::IsNullOrWhiteSpace($extension)) {
        return [pscustomobject]@{ Valid = $false; Error = "The URL must end with a filename and extension." }
    }

    if ($stem -notmatch "^(.*?)(\d+)$") {
        return [pscustomobject]@{ Valid = $false; Error = "The filename must end with a number." }
    }

    $prefix = $Matches[1]
    $numberText = $Matches[2]
    $directoryUrl = $UrlText.Trim().Substring(0, $UrlText.Trim().LastIndexOf("/") + 1)

    return [pscustomobject]@{
        Valid = $true
        Uri = $uri
        BaseUrl = $directoryUrl
        Prefix = $prefix
        NumberText = $numberText
        Number = [long]$numberText
        Digits = $numberText.Length
        Extension = $extension
        FileName = $fileName
        Error = $null
    }
}

function Resolve-UrlRange {
    param(
        [string]$StartUrl,
        [string]$Mode,
        [string]$RangeValue
    )

    $start = Parse-NumberedUrl -UrlText $StartUrl
    if (-not $start.Valid) {
        return [pscustomobject]@{ Valid = $false; Error = $start.Error }
    }

    $endNumber = $null

    switch ($Mode) {
        "Ending URL" {
            $end = Parse-NumberedUrl -UrlText $RangeValue
            if (-not $end.Valid) {
                return [pscustomobject]@{ Valid = $false; Error = "Ending URL: $($end.Error)" }
            }

            $startDirectory = $start.Uri.GetLeftPart([System.UriPartial]::Path)
            $startDirectory = $startDirectory.Substring(0, $startDirectory.LastIndexOf("/") + 1)
            $endDirectory = $end.Uri.GetLeftPart([System.UriPartial]::Path)
            $endDirectory = $endDirectory.Substring(0, $endDirectory.LastIndexOf("/") + 1)

            if (-not $startDirectory.Equals($endDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
                return [pscustomobject]@{ Valid = $false; Error = "The starting and ending URLs are not in the same directory." }
            }

            if (-not $start.Prefix.Equals($end.Prefix, [System.StringComparison]::Ordinal)) {
                return [pscustomobject]@{ Valid = $false; Error = "The starting and ending filenames use different prefixes." }
            }

            if (-not $start.Extension.Equals($end.Extension, [System.StringComparison]::OrdinalIgnoreCase)) {
                return [pscustomobject]@{ Valid = $false; Error = "The starting and ending URLs use different file extensions." }
            }

            if ($start.Digits -ne $end.Digits) {
                return [pscustomobject]@{ Valid = $false; Error = "The starting and ending numbers use different padding widths." }
            }

            $endNumber = $end.Number
        }

        "Ending number" {
            $parsed = [long]0
            if (-not [long]::TryParse($RangeValue.Trim(), [ref]$parsed)) {
                return [pscustomobject]@{ Valid = $false; Error = "Enter a valid ending number." }
            }
            $endNumber = $parsed
        }

        "Number of files" {
            $count = [long]0
            if (-not [long]::TryParse($RangeValue.Trim(), [ref]$count) -or $count -lt 1) {
                return [pscustomobject]@{ Valid = $false; Error = "Enter a file count of 1 or greater." }
            }
            $endNumber = $start.Number + $count - 1
        }

        default {
            return [pscustomobject]@{ Valid = $false; Error = "Select a range mode." }
        }
    }

    if ($endNumber -lt $start.Number) {
        return [pscustomobject]@{ Valid = $false; Error = "The ending number comes before the starting number." }
    }

    $count = ($endNumber - $start.Number) + 1

    if ($count -gt 1000000) {
        return [pscustomobject]@{ Valid = $false; Error = "The requested range exceeds 1,000,000 URLs." }
    }

    $firstUrl = "$($start.BaseUrl)$($start.Prefix)$($start.Number.ToString("D$($start.Digits)"))$($start.Extension)"
    $lastUrl = "$($start.BaseUrl)$($start.Prefix)$($endNumber.ToString("D$($start.Digits)"))$($start.Extension)"

    return [pscustomobject]@{
        Valid = $true
        Start = $start
        EndNumber = $endNumber
        Count = $count
        FirstUrl = $firstUrl
        LastUrl = $lastUrl
        Error = $null
    }
}

function Build-UrlList {
    param([Parameter(Mandatory)]$Range)

    $builder = New-Object System.Text.StringBuilder

    for ($i = $Range.Start.Number; $i -le $Range.EndNumber; $i++) {
        $number = $i.ToString("D$($Range.Start.Digits)")
        [void]$builder.Append($Range.Start.BaseUrl)
        [void]$builder.Append($Range.Start.Prefix)
        [void]$builder.Append($number)
        [void]$builder.Append($Range.Start.Extension)
        [void]$builder.Append([Environment]::NewLine)
    }

    return $builder.ToString().TrimEnd("`r", "`n")
}

function Get-PreviewText {
    param([Parameter(Mandatory)]$Range)

    $sample = New-Object System.Collections.Generic.List[string]

    if ($Range.Count -le 8) {
        for ($i = $Range.Start.Number; $i -le $Range.EndNumber; $i++) {
            $sample.Add("$($Range.Start.BaseUrl)$($Range.Start.Prefix)$($i.ToString("D$($Range.Start.Digits)"))$($Range.Start.Extension)")
        }
    }
    else {
        for ($i = $Range.Start.Number; $i -lt $Range.Start.Number + 4; $i++) {
            $sample.Add("$($Range.Start.BaseUrl)$($Range.Start.Prefix)$($i.ToString("D$($Range.Start.Digits)"))$($Range.Start.Extension)")
        }

        $sample.Add("...")
        for ($i = $Range.EndNumber - 3; $i -le $Range.EndNumber; $i++) {
            $sample.Add("$($Range.Start.BaseUrl)$($Range.Start.Prefix)$($i.ToString("D$($Range.Start.Digits)"))$($Range.Start.Extension)")
        }
    }

    return [string]::Join([Environment]::NewLine, $sample)
}

function Show-CompletionDialog {
    param(
        [Parameter(Mandatory)][System.Windows.Forms.Form]$Owner,
        [long]$Count,
        [string]$OutputPath,
        [bool]$Copied
    )

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Generation Complete"
    $dialog.Size = [System.Drawing.Size]::new([int](560), [int](330))
    $dialog.MinimumSize = [System.Drawing.Size]::new([int](560), [int](330))
    $dialog.StartPosition = "CenterParent"
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.TopMost = $true
    $dialog.Font = New-Object System.Drawing.Font("Segoe UI", 10)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "Generated successfully"
    $title.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 16)
    $title.AutoSize = $true
    $title.Location = [System.Drawing.Point]::new([int](28), [int](24))
    $dialog.Controls.Add($title)

    $summary = New-Object System.Windows.Forms.Label
    $summary.AutoSize = $false
    $summary.Location = [System.Drawing.Point]::new([int](30), [int](72))
    $summary.Size = [System.Drawing.Size]::new([int](490), [int](115))
    $summary.Text = "URLs generated: $Count`r`nSaved file: $(if ($OutputPath) { $OutputPath } else { 'Not requested' })`r`nCopied to clipboard: $(if ($Copied) { 'Yes' } else { 'No' })"
    $dialog.Controls.Add($summary)

    $openFolder = New-Object System.Windows.Forms.Button
    $openFolder.Text = "Open Folder"
    $openFolder.Size = [System.Drawing.Size]::new([int](125), [int](38))
    $openFolder.Location = [System.Drawing.Point]::new([int](30), [int](220))
    $openFolder.Enabled = -not [string]::IsNullOrWhiteSpace($OutputPath)
    $openFolder.Add_Click({
        if ($OutputPath) {
            Start-Process explorer.exe -ArgumentList "/select,`"$OutputPath`""
        }
    })
    $dialog.Controls.Add($openFolder)

    $openFile = New-Object System.Windows.Forms.Button
    $openFile.Text = "Open File"
    $openFile.Size = [System.Drawing.Size]::new([int](125), [int](38))
    $openFile.Location = [System.Drawing.Point]::new([int](170), [int](220))
    $openFile.Enabled = -not [string]::IsNullOrWhiteSpace($OutputPath)
    $openFile.Add_Click({
        if ($OutputPath) {
            Start-Process -FilePath $OutputPath
        }
    })
    $dialog.Controls.Add($openFile)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = "Close"
    $close.Size = [System.Drawing.Size]::new([int](125), [int](38))
    $close.Location = [System.Drawing.Point]::new([int](395), [int](220))
    $close.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dialog.AcceptButton = $close
    $dialog.CancelButton = $close
    $dialog.Controls.Add($close)

    [void]$dialog.ShowDialog($Owner)
    $dialog.Dispose()
}

$settings = Load-Settings

$form = New-Object System.Windows.Forms.Form
$form.Text = "$script:AppName - v$script:AppVersion"
$form.Size = [System.Drawing.Size]::new([int]([int]$settings.WindowWidth), [int]([int]$settings.WindowHeight))
$form.MinimumSize = [System.Drawing.Size]::new([int](780), [int](650))
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.TopMost = $true
$form.KeyPreview = $true

$title = New-Object System.Windows.Forms.Label
$title.Text = "Windows Automation Utilities"
$title.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 17)
$title.AutoSize = $true
$title.Location = [System.Drawing.Point]::new([int](24), [int](18))
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "$script:AppName  -  Version $script:AppVersion"
$subtitle.AutoSize = $true
$subtitle.ForeColor = [System.Drawing.Color]::DimGray
$subtitle.Location = [System.Drawing.Point]::new([int](27), [int](55))
$form.Controls.Add($subtitle)

$startLabel = New-Object System.Windows.Forms.Label
$startLabel.Text = "Starting URL"
$startLabel.AutoSize = $true
$startLabel.Location = [System.Drawing.Point]::new([int](28), [int](98))
$form.Controls.Add($startLabel)

$startBox = New-Object System.Windows.Forms.TextBox
$startBox.Anchor = "Top,Left,Right"
$startBox.Location = [System.Drawing.Point]::new([int](30), [int](122))
$startBox.Size = [System.Drawing.Size]::new([int]($form.ClientSize.Width - 60), [int](29))
$form.Controls.Add($startBox)

$modeLabel = New-Object System.Windows.Forms.Label
$modeLabel.Text = "Range mode"
$modeLabel.AutoSize = $true
$modeLabel.Location = [System.Drawing.Point]::new([int](28), [int](170))
$form.Controls.Add($modeLabel)

$modeBox = New-Object System.Windows.Forms.ComboBox
$modeBox.DropDownStyle = "DropDownList"
$modeBox.Location = [System.Drawing.Point]::new([int](30), [int](194))
$modeBox.Size = [System.Drawing.Size]::new([int](210), [int](30))
[void]$modeBox.Items.AddRange(@("Ending URL", "Ending number", "Number of files"))
$selectedMode = $modeBox.Items.IndexOf([string]$settings.RangeMode)
$modeBox.SelectedIndex = if ($selectedMode -ge 0) { $selectedMode } else { 0 }
$form.Controls.Add($modeBox)

$rangeLabel = New-Object System.Windows.Forms.Label
$rangeLabel.Text = "Ending URL"
$rangeLabel.AutoSize = $true
$rangeLabel.Location = [System.Drawing.Point]::new([int](260), [int](170))
$form.Controls.Add($rangeLabel)

$rangeBox = New-Object System.Windows.Forms.TextBox
$rangeBox.Anchor = "Top,Left,Right"
$rangeBox.Location = [System.Drawing.Point]::new([int](262), [int](194))
$rangeBox.Size = [System.Drawing.Size]::new([int]($form.ClientSize.Width - 292), [int](29))
$form.Controls.Add($rangeBox)

$outputGroup = New-Object System.Windows.Forms.GroupBox
$outputGroup.Text = "Output"
$outputGroup.Anchor = "Top,Left,Right"
$outputGroup.Location = [System.Drawing.Point]::new([int](30), [int](246))
$outputGroup.Size = [System.Drawing.Size]::new([int]($form.ClientSize.Width - 60), [int](126))
$form.Controls.Add($outputGroup)

$saveFileBox = New-Object System.Windows.Forms.CheckBox
$saveFileBox.Text = "Save text file"
$saveFileBox.Checked = [bool]$settings.SaveFile
$saveFileBox.AutoSize = $true
$saveFileBox.Location = [System.Drawing.Point]::new([int](18), [int](28))
$outputGroup.Controls.Add($saveFileBox)

$copyClipboardBox = New-Object System.Windows.Forms.CheckBox
$copyClipboardBox.Text = "Copy URLs to clipboard"
$copyClipboardBox.Checked = [bool]$settings.CopyClipboard
$copyClipboardBox.AutoSize = $true
$copyClipboardBox.Location = [System.Drawing.Point]::new([int](160), [int](28))
$outputGroup.Controls.Add($copyClipboardBox)

$outputFolderBox = New-Object System.Windows.Forms.TextBox
$outputFolderBox.Anchor = "Top,Left,Right"
$outputFolderBox.Location = [System.Drawing.Point]::new([int](18), [int](70))
$outputFolderBox.Size = [System.Drawing.Size]::new([int]($outputGroup.ClientSize.Width - 345), [int](29))
$outputFolderBox.Text = [string]$settings.OutputFolder
$outputGroup.Controls.Add($outputFolderBox)

$outputNameBox = New-Object System.Windows.Forms.TextBox
$outputNameBox.Anchor = "Top,Right"
$outputNameBox.Location = [System.Drawing.Point]::new([int]($outputGroup.ClientSize.Width - 315), [int](70))
$outputNameBox.Size = [System.Drawing.Size]::new([int](190), [int](29))
$outputNameBox.Text = [string]$settings.OutputFileName
$outputGroup.Controls.Add($outputNameBox)

$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Anchor = "Top,Right"
$browseButton.Text = "Browse..."
$browseButton.Location = [System.Drawing.Point]::new([int]($outputGroup.ClientSize.Width - 115), [int](68))
$browseButton.Size = [System.Drawing.Size]::new([int](95), [int](34))
$outputGroup.Controls.Add($browseButton)

$infoGroup = New-Object System.Windows.Forms.GroupBox
$infoGroup.Text = "Validation and Preview"
$infoGroup.Anchor = "Top,Bottom,Left,Right"
$infoGroup.Location = [System.Drawing.Point]::new([int](30), [int](388))
$infoGroup.Size = [System.Drawing.Size]::new([int]($form.ClientSize.Width - 60), [int]($form.ClientSize.Height - 480))
$form.Controls.Add($infoGroup)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Anchor = "Top,Left,Right"
$statusLabel.AutoSize = $false
$statusLabel.Location = [System.Drawing.Point]::new([int](18), [int](28))
$statusLabel.Size = [System.Drawing.Size]::new([int]($infoGroup.ClientSize.Width - 36), [int](24))
$statusLabel.Text = "Enter a starting URL."
$infoGroup.Controls.Add($statusLabel)

$statsLabel = New-Object System.Windows.Forms.Label
$statsLabel.Anchor = "Top,Left,Right"
$statsLabel.AutoSize = $false
$statsLabel.Location = [System.Drawing.Point]::new([int](18), [int](56))
$statsLabel.Size = [System.Drawing.Size]::new([int]($infoGroup.ClientSize.Width - 36), [int](48))
$statsLabel.Text = "Prefix: -    Extension: -    Padding: -    Files: -"
$infoGroup.Controls.Add($statsLabel)

$previewBox = New-Object System.Windows.Forms.TextBox
$previewBox.Anchor = "Top,Bottom,Left,Right"
$previewBox.Location = [System.Drawing.Point]::new([int](18), [int](106))
$previewBox.Size = [System.Drawing.Size]::new([int]($infoGroup.ClientSize.Width - 36), [int]($infoGroup.ClientSize.Height - 124))
$previewBox.Multiline = $true
$previewBox.ScrollBars = "Both"
$previewBox.WordWrap = $false
$previewBox.ReadOnly = $true
$previewBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$infoGroup.Controls.Add($previewBox)

$generateButton = New-Object System.Windows.Forms.Button
$generateButton.Anchor = "Bottom,Right"
$generateButton.Text = "Generate"
$generateButton.Size = [System.Drawing.Size]::new([int](125), [int](40))
$generateButton.Location = [System.Drawing.Point]::new([int]($form.ClientSize.Width - 290), [int]($form.ClientSize.Height - 64))
$generateButton.Enabled = $false
$form.Controls.Add($generateButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Anchor = "Bottom,Right"
$cancelButton.Text = "Close"
$cancelButton.Size = [System.Drawing.Size]::new([int](125), [int](40))
$cancelButton.Location = [System.Drawing.Point]::new([int]($form.ClientSize.Width - 150), [int]($form.ClientSize.Height - 64))
$cancelButton.Add_Click({ $form.Close() })
$form.Controls.Add($cancelButton)
$form.CancelButton = $cancelButton
$form.AcceptButton = $generateButton

$script:CurrentRange = $null

$updateUi = {
    switch ([string]$modeBox.SelectedItem) {
        "Ending URL" {
            $rangeLabel.Text = "Ending URL"
        }
        "Ending number" {
            $rangeLabel.Text = "Ending number"
        }
        "Number of files" {
            $rangeLabel.Text = "Number of files"
        }
    }

    $range = Resolve-UrlRange `
        -StartUrl $startBox.Text `
        -Mode ([string]$modeBox.SelectedItem) `
        -RangeValue $rangeBox.Text

    $script:CurrentRange = $range

    $outputValid = $true
    $outputError = $null

    if (-not $saveFileBox.Checked -and -not $copyClipboardBox.Checked) {
        $outputValid = $false
        $outputError = "Select at least one output option."
    }
    elseif ($saveFileBox.Checked) {
        if ([string]::IsNullOrWhiteSpace($outputFolderBox.Text)) {
            $outputValid = $false
            $outputError = "Select an output folder."
        }
        elseif ([string]::IsNullOrWhiteSpace($outputNameBox.Text)) {
            $outputValid = $false
            $outputError = "Enter an output filename."
        }
    }

    $outputFolderBox.Enabled = $saveFileBox.Checked
    $outputNameBox.Enabled = $saveFileBox.Checked
    $browseButton.Enabled = $saveFileBox.Checked

    if ($range.Valid -and $outputValid) {
        $statusLabel.Text = "Ready to generate."
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
        $statsLabel.Text = "Prefix: $($range.Start.Prefix)    Extension: $($range.Start.Extension)    Padding: $($range.Start.Digits) digits    Files: $($range.Count)"
        $previewBox.Text = Get-PreviewText -Range $range
        $generateButton.Enabled = $true
    }
    else {
        $message = if (-not $range.Valid) { $range.Error } else { $outputError }
        $statusLabel.Text = $message
        $statusLabel.ForeColor = [System.Drawing.Color]::Firebrick
        $statsLabel.Text = "Prefix: -    Extension: -    Padding: -    Files: -"
        $previewBox.Clear()
        $generateButton.Enabled = $false
    }
}

$startBox.Add_TextChanged($updateUi)
$rangeBox.Add_TextChanged($updateUi)
$modeBox.Add_SelectedIndexChanged($updateUi)
$saveFileBox.Add_CheckedChanged($updateUi)
$copyClipboardBox.Add_CheckedChanged($updateUi)
$outputFolderBox.Add_TextChanged($updateUi)
$outputNameBox.Add_TextChanged($updateUi)

$browseButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select the folder for the generated URL list"
    $dialog.ShowNewFolderButton = $true

    if (Test-Path -LiteralPath $outputFolderBox.Text -PathType Container) {
        $dialog.SelectedPath = $outputFolderBox.Text
    }

    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $outputFolderBox.Text = $dialog.SelectedPath
    }

    $dialog.Dispose()
})

$generateButton.Add_Click({
    $range = Resolve-UrlRange `
        -StartUrl $startBox.Text `
        -Mode ([string]$modeBox.SelectedItem) `
        -RangeValue $rangeBox.Text

    if (-not $range.Valid) {
        [System.Windows.Forms.MessageBox]::Show(
            $form,
            $range.Error,
            $script:AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }

    $urlText = Build-UrlList -Range $range
    $outputPath = $null
    $copied = $false

    try {
        if ($saveFileBox.Checked) {
            $outputName = $outputNameBox.Text.Trim()
            if (-not $outputName.EndsWith(".txt", [System.StringComparison]::OrdinalIgnoreCase)) {
                $outputName += ".txt"
                $outputNameBox.Text = $outputName
            }

            if (-not (Test-Path -LiteralPath $outputFolderBox.Text -PathType Container)) {
                New-Item -ItemType Directory -Path $outputFolderBox.Text -Force | Out-Null
            }

            $outputPath = Join-Path $outputFolderBox.Text $outputName
            [System.IO.File]::WriteAllText($outputPath, $urlText, (New-Object System.Text.UTF8Encoding($false)))
        }

        if ($copyClipboardBox.Checked) {
            [System.Windows.Forms.Clipboard]::SetText($urlText)
            $copied = $true
        }

        Save-Settings `
            -Form $form `
            -ModeBox $modeBox `
            -OutputFolderBox $outputFolderBox `
            -OutputNameBox $outputNameBox `
            -SaveFileBox $saveFileBox `
            -CopyClipboardBox $copyClipboardBox

        Show-CompletionDialog `
            -Owner $form `
            -Count $range.Count `
            -OutputPath $outputPath `
            -Copied $copied
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            $form,
            "The URL list could not be generated.`r`n`r`n$($_.Exception.Message)",
            $script:AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
})

$form.Add_FormClosing({
    Save-Settings `
        -Form $form `
        -ModeBox $modeBox `
        -OutputFolderBox $outputFolderBox `
        -OutputNameBox $outputNameBox `
        -SaveFileBox $saveFileBox `
        -CopyClipboardBox $copyClipboardBox
})

$form.Add_Shown({
    $form.Activate()
    $form.BringToFront()
    $startBox.Focus()
    $form.TopMost = $false
})

& $updateUi
[void]$form.ShowDialog()
$form.Dispose()