#requires -Version 5.1
<#
Windows Automation Utilities
Create Directories from Text File
Version 2.0.1
Author: Alan Workman
License: MIT
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$AppName = "Create Directories from Text File"
$Version = "2.0.1"
$SettingsDir = Join-Path $env:APPDATA "WindowsAutomationUtilities"
$SettingsFile = Join-Path $SettingsDir "DirectoryCreator.settings.json"

function Load-Settings {
    $s = [ordered]@{
        SourceFile = ""
        DestinationFolder = [Environment]::GetFolderPath("MyDocuments")
        ReplaceInvalid = $true
        IgnoreComments = $true
        Width = 980
        Height = 760
    }
    if (Test-Path -LiteralPath $SettingsFile) {
        try {
            $saved = Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json
            foreach ($k in @($s.Keys)) { if ($null -ne $saved.$k) { $s[$k] = $saved.$k } }
        } catch {}
    }
    [pscustomobject]$s
}

function Save-Settings {
    param($Form,$SourceBox,$DestinationBox,$ReplaceBox,$CommentsBox)
    try {
        if (-not (Test-Path -LiteralPath $SettingsDir)) {
            New-Item -ItemType Directory -Path $SettingsDir -Force | Out-Null
        }
        [ordered]@{
            SourceFile = $SourceBox.Text
            DestinationFolder = $DestinationBox.Text
            ReplaceInvalid = $ReplaceBox.Checked
            IgnoreComments = $CommentsBox.Checked
            Width = $Form.Width
            Height = $Form.Height
        } | ConvertTo-Json | Set-Content -LiteralPath $SettingsFile -Encoding UTF8
    } catch {}
}

function Convert-Segment {
    param([string]$Text,[bool]$ReplaceInvalid)
    $value = $Text.Trim()
    if ($ReplaceInvalid) {
        $value = $value -replace '[<>:"/\\|?*\x00-\x1F]', '_'
    } elseif ($value -match '[<>:"/\\|?*\x00-\x1F]') {
        return [pscustomobject]@{Valid=$false;Value="";Adjusted=$false;Error="Invalid Windows filename character."}
    }

    $before = $value
    $value = $value.TrimEnd('.', ' ')
    $adjusted = ($value -ne $Text.Trim()) -or ($before -ne $value)

    if ([string]::IsNullOrWhiteSpace($value)) {
        return [pscustomobject]@{Valid=$false;Value="";Adjusted=$false;Error="Empty folder name after validation."}
    }

    $reserved = @('CON','PRN','AUX','NUL','COM1','COM2','COM3','COM4','COM5','COM6','COM7','COM8','COM9',
                  'LPT1','LPT2','LPT3','LPT4','LPT5','LPT6','LPT7','LPT8','LPT9')
    $base = ($value -split '\.')[0].ToUpperInvariant()
    if ($reserved -contains $base) {
        if ($ReplaceInvalid) { $value = "_$value"; $adjusted = $true }
        else { return [pscustomobject]@{Valid=$false;Value="";Adjusted=$false;Error="Reserved Windows device name."} }
    }

    [pscustomobject]@{Valid=$true;Value=$value;Adjusted=$adjusted;Error=""}
}

function Convert-RelativePath {
    param([string]$Text,[bool]$ReplaceInvalid)
    $parts = $Text -split '[\\/]+'
    $safe = New-Object System.Collections.Generic.List[string]
    $adjusted = $false

    foreach ($part in $parts) {
        $p = $part.Trim()
        if ([string]::IsNullOrWhiteSpace($p) -or $p -eq '.') { $adjusted = $true; continue }
        if ($p -eq '..') {
            return [pscustomobject]@{Valid=$false;Value="";Adjusted=$false;Error="Parent path traversal (..) is not allowed."}
        }
        $r = Convert-Segment $p $ReplaceInvalid
        if (-not $r.Valid) { return [pscustomobject]@{Valid=$false;Value="";Adjusted=$false;Error=$r.Error} }
        if ($r.Adjusted) { $adjusted = $true }
        $safe.Add($r.Value)
    }

    if ($safe.Count -eq 0) {
        return [pscustomobject]@{Valid=$false;Value="";Adjusted=$false;Error="No usable folder name remains."}
    }

    [pscustomobject]@{
        Valid=$true
        Value=[string]::Join([IO.Path]::DirectorySeparatorChar,$safe)
        Adjusted=$adjusted
        Error=""
    }
}

function Analyze-List {
    param([string]$Source,[string]$Destination,[bool]$ReplaceInvalid,[bool]$IgnoreComments)

    if ([string]::IsNullOrWhiteSpace($Source)) { return [pscustomobject]@{Valid=$false;Error="Select a source text file."} }
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { return [pscustomobject]@{Valid=$false;Error="The source text file does not exist."} }
    if ([string]::IsNullOrWhiteSpace($Destination)) { return [pscustomobject]@{Valid=$false;Error="Select a destination folder."} }
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) { return [pscustomobject]@{Valid=$false;Error="The destination folder does not exist."} }

    try { $lines = @(Get-Content -LiteralPath $Source -ErrorAction Stop) }
    catch { return [pscustomobject]@{Valid=$false;Error="Unable to read the source file: $($_.Exception.Message)"} }

    $items = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    foreach ($line in $lines) {
        $entry = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        if ($IgnoreComments -and $entry.StartsWith('#')) { continue }

        $r = Convert-RelativePath $entry $ReplaceInvalid
        if (-not $r.Valid) {
            $items.Add([pscustomobject]@{Status="Invalid";Original=$entry;Relative="";Full="";Detail=$r.Error})
            continue
        }

        $full = Join-Path $Destination $r.Value
        if (-not $seen.Add($full)) { $status="Duplicate"; $detail="Duplicate entry in source file." }
        elseif (Test-Path -LiteralPath $full -PathType Container) { $status="Exists"; $detail="Directory already exists." }
        elseif (Test-Path -LiteralPath $full) { $status="Conflict"; $detail="A file already occupies this path." }
        elseif ($r.Adjusted) { $status="Adjusted"; $detail="Will be created with an adjusted name." }
        else { $status="Create"; $detail="Ready to create." }

        $items.Add([pscustomobject]@{Status=$status;Original=$entry;Relative=$r.Value;Full=$full;Detail=$detail})
    }

    if ($items.Count -eq 0) { return [pscustomobject]@{Valid=$false;Error="The text file contains no usable entries."} }

    [pscustomobject]@{
        Valid=$true; Error=""; Items=$items
        Total=$items.Count
        ToCreate=@($items | Where-Object {$_.Status -in @("Create","Adjusted")}).Count
        Existing=@($items | Where-Object {$_.Status -eq "Exists"}).Count
        Adjusted=@($items | Where-Object {$_.Status -eq "Adjusted"}).Count
        Duplicates=@($items | Where-Object {$_.Status -eq "Duplicate"}).Count
        Invalid=@($items | Where-Object {$_.Status -in @("Invalid","Conflict")}).Count
    }
}

function Show-Complete {
    param($Owner,$Created,$Existing,$Skipped,$Failed,$Adjusted,$Destination,$LogPath)
    $d = New-Object System.Windows.Forms.Form
    $d.Text = "Directory Creation Complete"
    $d.Size = New-Object System.Drawing.Size(610,390)
    $d.StartPosition = "CenterParent"
    $d.FormBorderStyle = "FixedDialog"
    $d.MaximizeBox = $false
    $d.MinimizeBox = $false
    $d.ShowInTaskbar = $false
    $d.TopMost = $true
    $d.Font = New-Object System.Drawing.Font("Segoe UI",10)

    $t = New-Object System.Windows.Forms.Label
    $t.Text = "Directory creation complete"
    $t.Font = New-Object System.Drawing.Font("Segoe UI Semibold",16)
    $t.AutoSize = $true
    $t.Location = New-Object System.Drawing.Point(28,24)
    $d.Controls.Add($t)

    $s = New-Object System.Windows.Forms.Label
    $s.AutoSize = $false
    $s.Location = New-Object System.Drawing.Point(30,74)
    $s.Size = New-Object System.Drawing.Size(540,175)
    $s.Text = "Created: $Created`r`nAlready existed: $Existing`r`nSkipped: $Skipped`r`nFailed: $Failed`r`nAdjusted names created: $Adjusted`r`n`r`nDestination:`r`n$Destination"
    $d.Controls.Add($s)

    $b1 = New-Object System.Windows.Forms.Button
    $b1.Text = "Open Folder"; $b1.Size = New-Object System.Drawing.Size(135,40)
    $b1.Location = New-Object System.Drawing.Point(30,292)
    $b1.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$Destination`"" })
    $d.Controls.Add($b1)

    $b2 = New-Object System.Windows.Forms.Button
    $b2.Text = "Open Log"; $b2.Size = New-Object System.Drawing.Size(135,40)
    $b2.Location = New-Object System.Drawing.Point(180,292)
    $b2.Enabled = $LogPath -and (Test-Path -LiteralPath $LogPath)
    $b2.Add_Click({ if (Test-Path -LiteralPath $LogPath) { Start-Process $LogPath } })
    $d.Controls.Add($b2)

    $b3 = New-Object System.Windows.Forms.Button
    $b3.Text = "Close"; $b3.Size = New-Object System.Drawing.Size(135,40)
    $b3.Location = New-Object System.Drawing.Point(435,292)
    $b3.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $d.Controls.Add($b3); $d.AcceptButton=$b3; $d.CancelButton=$b3

    [void]$d.ShowDialog($Owner)
    $d.Dispose()
}

$settings = Load-Settings
$form = New-Object System.Windows.Forms.Form
$form.Text = "$AppName - v$Version"
$form.Size = New-Object System.Drawing.Size([int]$settings.Width,[int]$settings.Height)
$form.MinimumSize = New-Object System.Drawing.Size(860,680)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Segoe UI",10)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.TopMost = $true

$w=[int]$form.ClientSize.Width; $h=[int]$form.ClientSize.Height

$title=New-Object System.Windows.Forms.Label
$title.Text="Windows Automation Utilities"; $title.Font=New-Object System.Drawing.Font("Segoe UI Semibold",17)
$title.AutoSize=$true; $title.Location=New-Object System.Drawing.Point(28,20); $form.Controls.Add($title)

$sub=New-Object System.Windows.Forms.Label
$sub.Text="$AppName - Version $Version"; $sub.AutoSize=$true; $sub.ForeColor=[System.Drawing.Color]::DimGray
$sub.Location=New-Object System.Drawing.Point(30,58); $form.Controls.Add($sub)

$l1=New-Object System.Windows.Forms.Label
$l1.Text="Source text file"; $l1.AutoSize=$true; $l1.Location=New-Object System.Drawing.Point(30,104); $form.Controls.Add($l1)
$source=New-Object System.Windows.Forms.TextBox
$source.Anchor="Top,Left,Right"; $source.Location=New-Object System.Drawing.Point(32,130)
$source.Size=New-Object System.Drawing.Size(($w-180),29); $source.Text=[string]$settings.SourceFile; $form.Controls.Add($source)
$sourceBrowse=New-Object System.Windows.Forms.Button
$sourceBrowse.Anchor="Top,Right"; $sourceBrowse.Text="Browse..."; $sourceBrowse.Location=New-Object System.Drawing.Point(($w-130),127)
$sourceBrowse.Size=New-Object System.Drawing.Size(100,35); $form.Controls.Add($sourceBrowse)

$l2=New-Object System.Windows.Forms.Label
$l2.Text="Destination parent folder"; $l2.AutoSize=$true; $l2.Location=New-Object System.Drawing.Point(30,178); $form.Controls.Add($l2)
$dest=New-Object System.Windows.Forms.TextBox
$dest.Anchor="Top,Left,Right"; $dest.Location=New-Object System.Drawing.Point(32,204)
$dest.Size=New-Object System.Drawing.Size(($w-180),29); $dest.Text=[string]$settings.DestinationFolder; $form.Controls.Add($dest)
$destBrowse=New-Object System.Windows.Forms.Button
$destBrowse.Anchor="Top,Right"; $destBrowse.Text="Browse..."; $destBrowse.Location=New-Object System.Drawing.Point(($w-130),201)
$destBrowse.Size=New-Object System.Drawing.Size(100,35); $form.Controls.Add($destBrowse)

$options=New-Object System.Windows.Forms.GroupBox
$options.Text="Options"; $options.Anchor="Top,Left,Right"; $options.Location=New-Object System.Drawing.Point(32,250)
$options.Size=New-Object System.Drawing.Size(($w-64),82); $form.Controls.Add($options)
$replace=New-Object System.Windows.Forms.CheckBox
$replace.Text="Replace invalid Windows filename characters with underscores"; $replace.AutoSize=$true
$replace.Location=New-Object System.Drawing.Point(18,32); $replace.Checked=[bool]$settings.ReplaceInvalid; $options.Controls.Add($replace)
$comments=New-Object System.Windows.Forms.CheckBox
$comments.Text="Ignore lines beginning with #"; $comments.AutoSize=$true
$comments.Location=New-Object System.Drawing.Point(520,32); $comments.Checked=[bool]$settings.IgnoreComments; $options.Controls.Add($comments)

$preview=New-Object System.Windows.Forms.GroupBox
$preview.Text="Validation and Preview"; $preview.Anchor="Top,Bottom,Left,Right"
$preview.Location=New-Object System.Drawing.Point(32,350); $preview.Size=New-Object System.Drawing.Size(($w-64),($h-450))
$form.Controls.Add($preview)

$status=New-Object System.Windows.Forms.Label
$status.Anchor="Top,Left,Right"; $status.AutoSize=$false; $status.Location=New-Object System.Drawing.Point(18,28)
$status.Size=New-Object System.Drawing.Size(($preview.ClientSize.Width-36),25); $preview.Controls.Add($status)
$stats=New-Object System.Windows.Forms.Label
$stats.Anchor="Top,Left,Right"; $stats.AutoSize=$false; $stats.Location=New-Object System.Drawing.Point(18,58)
$stats.Size=New-Object System.Drawing.Size(($preview.ClientSize.Width-36),25); $preview.Controls.Add($stats)

$grid=New-Object System.Windows.Forms.DataGridView
$grid.Anchor="Top,Bottom,Left,Right"; $grid.Location=New-Object System.Drawing.Point(18,92)
$grid.Size=New-Object System.Drawing.Size(($preview.ClientSize.Width-36),($preview.ClientSize.Height-110))
$grid.ReadOnly=$true; $grid.AllowUserToAddRows=$false; $grid.AllowUserToDeleteRows=$false
$grid.RowHeadersVisible=$false; $grid.AutoSizeColumnsMode="Fill"; $grid.SelectionMode="FullRowSelect"
$grid.BackgroundColor=[System.Drawing.SystemColors]::Window
[void]$grid.Columns.Add("Status","Status"); [void]$grid.Columns.Add("Original","Original Entry"); [void]$grid.Columns.Add("Result","Resulting Relative Path")
$grid.Columns["Status"].FillWeight=18; $grid.Columns["Original"].FillWeight=40; $grid.Columns["Result"].FillWeight=42
$preview.Controls.Add($grid)

$progress=New-Object System.Windows.Forms.ProgressBar
$progress.Anchor="Bottom,Left,Right"; $progress.Location=New-Object System.Drawing.Point(32,($h-82))
$progress.Size=New-Object System.Drawing.Size(($w-370),24); $form.Controls.Add($progress)

$create=New-Object System.Windows.Forms.Button
$create.Anchor="Bottom,Right"; $create.Text="Create Directories"; $create.Size=New-Object System.Drawing.Size(165,42)
$create.Location=New-Object System.Drawing.Point(($w-330),($h-92)); $create.Enabled=$false; $form.Controls.Add($create)
$close=New-Object System.Windows.Forms.Button
$close.Anchor="Bottom,Right"; $close.Text="Close"; $close.Size=New-Object System.Drawing.Size(130,42)
$close.Location=New-Object System.Drawing.Point(($w-150),($h-92)); $close.Add_Click({$form.Close()}); $form.Controls.Add($close)
$form.AcceptButton=$create; $form.CancelButton=$close

$script:Analysis=$null; $script:Busy=$false
$refresh={
    if ($script:Busy) { return }
    $a=Analyze-List $source.Text $dest.Text $replace.Checked $comments.Checked
    $script:Analysis=$a; $grid.Rows.Clear()
    if (-not $a.Valid) {
        $status.Text=$a.Error; $status.ForeColor=[System.Drawing.Color]::Firebrick
        $stats.Text="Total: -    To create: -    Existing: -    Adjusted: -    Duplicates: -    Invalid: -"
        $create.Enabled=$false; return
    }
    foreach($item in $a.Items) {
        $i=$grid.Rows.Add($item.Status,$item.Original,$item.Relative)
        $row=$grid.Rows[$i]
        switch($item.Status) {
            "Create" {$row.DefaultCellStyle.ForeColor=[System.Drawing.Color]::DarkGreen}
            "Adjusted" {$row.DefaultCellStyle.ForeColor=[System.Drawing.Color]::DarkOrange}
            "Exists" {$row.DefaultCellStyle.ForeColor=[System.Drawing.Color]::DarkGoldenrod}
            "Duplicate" {$row.DefaultCellStyle.ForeColor=[System.Drawing.Color]::DimGray}
            default {$row.DefaultCellStyle.ForeColor=[System.Drawing.Color]::Firebrick}
        }
        foreach($c in $row.Cells){$c.ToolTipText=$item.Detail}
    }
    $stats.Text="Total: $($a.Total)    To create: $($a.ToCreate)    Existing: $($a.Existing)    Adjusted: $($a.Adjusted)    Duplicates: $($a.Duplicates)    Invalid: $($a.Invalid)"
    if($a.ToCreate -gt 0){$status.Text="Ready to create $($a.ToCreate) directories."; $status.ForeColor=[System.Drawing.Color]::DarkGreen; $create.Enabled=$true}
    else{$status.Text="No new directories need to be created."; $status.ForeColor=[System.Drawing.Color]::DarkGoldenrod; $create.Enabled=$false}
}

$sourceBrowse.Add_Click({
    $d=New-Object System.Windows.Forms.OpenFileDialog
    $d.Title="Select the Text File Containing Folder Names"; $d.Filter="Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
    if(Test-Path -LiteralPath $source.Text -PathType Leaf){$d.FileName=$source.Text}
    if($d.ShowDialog($form) -eq "OK"){$source.Text=$d.FileName}; $d.Dispose()
})
$destBrowse.Add_Click({
    $d=New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description="Select the Parent Folder Where New Directories Will Be Created"; $d.ShowNewFolderButton=$true
    if(Test-Path -LiteralPath $dest.Text -PathType Container){$d.SelectedPath=$dest.Text}
    if($d.ShowDialog($form) -eq "OK"){$dest.Text=$d.SelectedPath}; $d.Dispose()
})
$source.Add_TextChanged($refresh); $dest.Add_TextChanged($refresh); $replace.Add_CheckedChanged($refresh); $comments.Add_CheckedChanged($refresh)

$create.Add_Click({
    $a=Analyze-List $source.Text $dest.Text $replace.Checked $comments.Checked
    if(-not $a.Valid -or $a.ToCreate -lt 1){return}
    $answer=[System.Windows.Forms.MessageBox]::Show($form,"Create $($a.ToCreate) directories in:`r`n`r`n$($dest.Text)?",$AppName,"YesNo","Question")
    if($answer -ne "Yes"){return}

    $script:Busy=$true
    foreach($c in @($create,$close,$sourceBrowse,$destBrowse,$source,$dest,$replace,$comments)){$c.Enabled=$false}
    $created=0;$existing=0;$skipped=0;$failed=0;$adjustedCreated=0
    $logPath=Join-Path $dest.Text ("DirectoryCreation-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".log.txt")
    $log=New-Object System.Collections.Generic.List[string]
    $log.Add("Windows Automation Utilities");$log.Add("$AppName");$log.Add("Version: $Version")
    $log.Add("Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')");$log.Add("Source: $($source.Text)");$log.Add("Destination: $($dest.Text)")
    $log.Add("");$log.Add("STATUS`tORIGINAL ENTRY`tRESULTING PATH`tDETAILS")

    $items=$a.Items
    for($n=0;$n -lt $items.Count;$n++){
        $item=$items[$n]; $progress.Value=[Math]::Min([int]((($n+1)/[Math]::Max($items.Count,1))*100),100)
        $status.Text="Processing $($n+1) of $($items.Count): $($item.Original)"; [System.Windows.Forms.Application]::DoEvents()
        switch($item.Status){
            "Create" {try{New-Item -ItemType Directory -Path $item.Full -Force -ErrorAction Stop|Out-Null;$created++;$log.Add("CREATED`t$($item.Original)`t$($item.Full)`tCreated successfully.")}catch{$failed++;$log.Add("FAILED`t$($item.Original)`t$($item.Full)`t$($_.Exception.Message)")}}
            "Adjusted" {try{New-Item -ItemType Directory -Path $item.Full -Force -ErrorAction Stop|Out-Null;$created++;$adjustedCreated++;$log.Add("CREATED`t$($item.Original)`t$($item.Full)`tCreated with adjusted name.")}catch{$failed++;$log.Add("FAILED`t$($item.Original)`t$($item.Full)`t$($_.Exception.Message)")}}
            "Exists" {$existing++;$log.Add("EXISTS`t$($item.Original)`t$($item.Full)`tAlready existed.")}
            default {$skipped++;$log.Add("SKIPPED`t$($item.Original)`t$($item.Full)`t$($item.Detail)")}
        }
    }

    $log.Add("");$log.Add("Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $log.Add("Created: $created");$log.Add("Already existed: $existing");$log.Add("Skipped: $skipped");$log.Add("Failed: $failed");$log.Add("Adjusted names created: $adjustedCreated")
    try{$log|Set-Content -LiteralPath $logPath -Encoding UTF8}catch{$logPath=""}

    Save-Settings $form $source $dest $replace $comments
    Show-Complete $form $created $existing $skipped $failed $adjustedCreated $dest.Text $logPath

    $script:Busy=$false
    foreach($c in @($close,$sourceBrowse,$destBrowse,$source,$dest,$replace,$comments)){$c.Enabled=$true}
    $progress.Value=0; & $refresh
})

$form.Add_FormClosing({Save-Settings $form $source $dest $replace $comments})
$form.Add_Shown({$form.Activate();$form.BringToFront();$source.Focus();$form.TopMost=$false})
& $refresh
[void]$form.ShowDialog()
$form.Dispose()