# ------------------------------------------
# National Archives URL List Generator
# Generates all URLs between two image URLs
# ------------------------------------------

$startUrl = Read-Host "Enter the STARTING image URL"
$endUrl   = Read-Host "Enter the ENDING image URL"

$outputFile = Read-Host "Enter output filename"
if (-not $outputFile.EndsWith(".txt")) {
    $outputFile += ".txt"
}

# Parse URLs
$startUri = [System.Uri]$startUrl
$endUri   = [System.Uri]$endUrl

# Verify same folder
if ($startUri.GetLeftPart([System.UriPartial]::Path).Substring(0,
    $startUri.GetLeftPart([System.UriPartial]::Path).LastIndexOf("/") + 1) -ne
    $endUri.GetLeftPart([System.UriPartial]::Path).Substring(0,
    $endUri.GetLeftPart([System.UriPartial]::Path).LastIndexOf("/") + 1))
{
    Write-Host ""
    Write-Host "ERROR: URLs are not in the same directory."
    exit
}

$baseUrl = $startUrl.Substring(0, $startUrl.LastIndexOf("/") + 1)

$startName = [System.IO.Path]::GetFileNameWithoutExtension($startUri.AbsolutePath)
$endName   = [System.IO.Path]::GetFileNameWithoutExtension($endUri.AbsolutePath)

# Preserve and validate the file extension from the input URLs
$startExtension = [System.IO.Path]::GetExtension($startUri.AbsolutePath)
$endExtension   = [System.IO.Path]::GetExtension($endUri.AbsolutePath)

if ([string]::IsNullOrWhiteSpace($startExtension) -or
    [string]::IsNullOrWhiteSpace($endExtension)) {
    Write-Host ""
    Write-Host "ERROR: Both URLs must include a file extension such as .jpg or .tif."
    exit
}

if (-not $startExtension.Equals($endExtension, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Host ""
    Write-Host "ERROR: Starting and ending URLs use different file extensions."
    Write-Host "Starting extension: $startExtension"
    Write-Host "Ending extension  : $endExtension"
    exit
}

# Extract prefix and numeric suffix
if ($startName -notmatch "^(.*?)(\d+)$") {
    Write-Host "ERROR: Could not determine image number from starting filename."
    exit
}

$prefix = $Matches[1]
$startNumberText = $Matches[2]

if ($endName -notmatch "^(.*?)(\d+)$") {
    Write-Host "ERROR: Could not determine image number from ending filename."
    exit
}

$endPrefix = $Matches[1]
$endNumberText = $Matches[2]

# Verify prefixes match
if ($prefix -ne $endPrefix) {
    Write-Host ""
    Write-Host "ERROR: Filenames do not share the same prefix."
    Write-Host "$prefix"
    Write-Host "$endPrefix"
    exit
}

$digits = $startNumberText.Length

$startNumber = [int]$startNumberText
$endNumber   = [int]$endNumberText

if ($endNumber -lt $startNumber) {
    Write-Host ""
    Write-Host "ERROR: Ending image comes before starting image."
    exit
}

$urls = foreach ($i in $startNumber..$endNumber) {
    $number = $i.ToString("D$digits")
    "$baseUrl$prefix$number$startExtension"
}

$urls | Set-Content $outputFile

Write-Host ""
Write-Host "--------------------------------"
Write-Host "Finished!"
Write-Host "URLs created : $($urls.Count)"
Write-Host "Saved to     : $outputFile"
Write-Host "--------------------------------"