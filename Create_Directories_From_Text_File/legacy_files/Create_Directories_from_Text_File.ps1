#requires -Version 5.1
<#
.SYNOPSIS
Creates folders from a list in a text file.

.DESCRIPTION
- Prompts for a text file containing one folder path per line.
- Prompts for a parent destination folder.
- Supports nested folders, for example: Coins\United States.
- Replaces characters that are invalid in Windows folder names.
- Skips blank lines and comment lines beginning with #.
- Skips folders that already exist.
- Displays progress and writes a detailed log file.

Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows.
#>

Add-Type -AssemblyName System.Windows.Forms

function Show-ErrorMessage {
    param([Parameter(Mandatory)][string]$Message)

    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        "Create Folders from List",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

function ConvertTo-SafeFolderSegment {
    param([Parameter(Mandatory)][string]$Segment)

    $safe = $Segment -replace '[<>:"/\\|?*\x00-\x1F]', '_'
    $safe = $safe.Trim().TrimEnd('.', ' ')

    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "_"
    }

    $baseName = ($safe -split '\.')[0]
    $reservedNames = @(
        'CON', 'PRN', 'AUX', 'NUL',
        'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
        'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9'
    )

    if ($reservedNames -contains $baseName.ToUpperInvariant()) {
        $safe = "_$safe"
    }

    return $safe
}

function ConvertTo-SafeRelativeFolderPath {
    param([Parameter(Mandatory)][string]$FolderPath)

    $segments = $FolderPath -split '[\\/]+'
    $safeSegments = New-Object System.Collections.Generic.List[string]

    foreach ($segment in $segments) {
        $trimmed = $segment.Trim()

        if ([string]::IsNullOrWhiteSpace($trimmed) -or
            $trimmed -eq '.' -or
            $trimmed -eq '..') {
            continue
        }

        $safeSegments.Add((ConvertTo-SafeFolderSegment -Segment $trimmed))
    }

    if ($safeSegments.Count -eq 0) {
        return $null
    }

    return [string]::Join([IO.Path]::DirectorySeparatorChar, $safeSegments)
}

$openFile = New-Object System.Windows.Forms.OpenFileDialog
$openFile.Title = "Select the Text File Containing Folder Names"
$openFile.Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
$openFile.CheckFileExists = $true
$openFile.Multiselect = $false

if ($openFile.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Host "Operation cancelled."
    exit
}

$textFile = $openFile.FileName

$folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
$folderBrowser.Description = "Select the Parent Folder Where New Folders Will Be Created"
$folderBrowser.ShowNewFolderButton = $true

if ($folderBrowser.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Host "Operation cancelled."
    exit
}

$destination = $folderBrowser.SelectedPath

try {
    $rawLines = @(Get-Content -LiteralPath $textFile -ErrorAction Stop)
}
catch {
    Show-ErrorMessage "The text file could not be read.`r`n`r`n$($_.Exception.Message)"
    exit 1
}

$folderEntries = @(
    $rawLines |
        ForEach-Object { $_.Trim() } |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and
            -not $_.StartsWith('#')
        }
)

if ($folderEntries.Count -eq 0) {
    Show-ErrorMessage "The selected text file does not contain any folder names."
    exit
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = Join-Path $destination "FolderCreationLog-$timestamp.txt"

$created = 0
$existing = 0
$adjusted = 0
$failed = 0
$skipped = 0
$processedPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$logLines = New-Object System.Collections.Generic.List[string]

$logLines.Add("Create Folders from List")
$logLines.Add("Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$logLines.Add("Source file: $textFile")
$logLines.Add("Destination: $destination")
$logLines.Add("")
$logLines.Add("STATUS`tORIGINAL ENTRY`tRESULTING PATH`tDETAILS")

for ($index = 0; $index -lt $folderEntries.Count; $index++) {
    $originalEntry = $folderEntries[$index]
    $percent = [int](($index / [Math]::Max($folderEntries.Count, 1)) * 100)

    Write-Progress `
        -Activity "Creating folders" `
        -Status "$($index + 1) of $($folderEntries.Count): $originalEntry" `
        -PercentComplete $percent

    $safeRelativePath = ConvertTo-SafeRelativeFolderPath -FolderPath $originalEntry

    if ([string]::IsNullOrWhiteSpace($safeRelativePath)) {
        Write-Host "Skipped invalid entry: $originalEntry" -ForegroundColor Yellow
        $logLines.Add("SKIPPED`t$originalEntry`t`tNo usable folder name remained after validation.")
        $skipped++
        continue
    }

    if ($safeRelativePath -ne ($originalEntry -replace '/', '\')) {
        $adjusted++
    }

    $newFolder = Join-Path $destination $safeRelativePath

    if (-not $processedPaths.Add($newFolder)) {
        Write-Host "Duplicate entry skipped: $safeRelativePath" -ForegroundColor DarkYellow
        $logLines.Add("SKIPPED`t$originalEntry`t$newFolder`tDuplicate entry in source list.")
        $skipped++
        continue
    }

    try {
        if (Test-Path -LiteralPath $newFolder -PathType Container) {
            Write-Host "Already exists: $safeRelativePath" -ForegroundColor Yellow
            $logLines.Add("EXISTS`t$originalEntry`t$newFolder`tFolder already existed.")
            $existing++
        }
        elseif (Test-Path -LiteralPath $newFolder) {
            Write-Host "Failed (a file already uses this name): $safeRelativePath" -ForegroundColor Red
            $logLines.Add("FAILED`t$originalEntry`t$newFolder`tA file already exists at this path.")
            $failed++
        }
        else {
            New-Item -ItemType Directory -Path $newFolder -Force -ErrorAction Stop | Out-Null
            Write-Host "Created: $safeRelativePath" -ForegroundColor Green

            $detail = if ($safeRelativePath -ne ($originalEntry -replace '/', '\')) {
                "Created; invalid characters or path elements were adjusted."
            }
            else {
                "Created successfully."
            }

            $logLines.Add("CREATED`t$originalEntry`t$newFolder`t$detail")
            $created++
        }
    }
    catch {
        Write-Host "Failed: $safeRelativePath - $($_.Exception.Message)" -ForegroundColor Red
        $logLines.Add("FAILED`t$originalEntry`t$newFolder`t$($_.Exception.Message)")
        $failed++
    }
}

Write-Progress -Activity "Creating folders" -Completed

$logLines.Add("")
$logLines.Add("Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$logLines.Add("Folders created: $created")
$logLines.Add("Already existed: $existing")
$logLines.Add("Names adjusted: $adjusted")
$logLines.Add("Entries skipped: $skipped")
$logLines.Add("Failures: $failed")

try {
    $logLines | Set-Content -LiteralPath $logFile -Encoding UTF8 -ErrorAction Stop
}
catch {
    Write-Host "Warning: The log file could not be written: $($_.Exception.Message)" -ForegroundColor Yellow
    $logFile = "(Log could not be written.)"
}

Write-Host ""
Write-Host "------------------------------------------------------------"
Write-Host "Completed!" -ForegroundColor Cyan
Write-Host "Folders created : $created"
Write-Host "Already existed : $existing"
Write-Host "Names adjusted  : $adjusted"
Write-Host "Entries skipped : $skipped"
Write-Host "Failures        : $failed"
Write-Host "Destination     : $destination"
Write-Host "Log file        : $logFile"
Write-Host "------------------------------------------------------------"
Write-Host ""
Read-Host "Press Enter to close"
