# Sequential URL List Generator

**Version 2.0.2**  
Part of the **Windows Automation Utilities** project.

Generate a sequential list of URLs from a numbered starting URL. The utility is useful for archival collections, scanned books, image repositories, and download managers such as JDownloader.

## Features

- Single-window graphical interface
- Opens in the foreground and takes focus
- Three range modes:
  - Ending URL
  - Ending number
  - Number of files
- Automatically detects:
  - URL directory
  - Filename prefix
  - Starting number
  - Number padding
  - File extension
- Live validation
- Preview of the first and last generated URLs
- Save output to a UTF-8 text file
- Copy generated URLs directly to the Windows clipboard
- Use either or both output methods
- Remembers the last output folder, filename, range mode, and output options
- Supports `.tif`, `.tiff`, `.jpg`, `.jpeg`, `.png`, and other filename extensions
- Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or PowerShell 7
- .NET Framework/Windows Forms

## Running the Utility

From PowerShell:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\Create_URL_File_List.ps1"
```

PowerShell 7 users may run:

```powershell
pwsh.exe -ExecutionPolicy Bypass -File ".\Create_URL_File_List.ps1"
```

## Range Modes

### Ending URL

Provide both the first and final URL.

```text
Starting:
https://catalog.archives.gov/example/M66-001-0284.tif

Ending:
https://catalog.archives.gov/example/M66-001-0354.tif
```

The directory, filename prefix, extension, and number padding must match.

### Ending Number

Provide the starting URL and the final numeric suffix.

```text
Starting URL:
https://catalog.archives.gov/example/M66-001-0284.tif

Ending number:
354
```

The utility preserves the four-digit padding and generates through `0354`.

### Number of Files

Provide the starting URL and the total number of URLs to create.

```text
Starting URL:
https://catalog.archives.gov/example/M66-001-0284.tif

Number of files:
71
```

## Output

The utility can:

- Save the generated URLs to a `.txt` file
- Copy the URLs to the clipboard
- Perform both operations at the same time

The text file is written as UTF-8 without a byte-order mark, making it suitable for most download managers and text editors.

## Validation

Generation is disabled until all required information is valid. The utility detects:

- Invalid or incomplete URLs
- Missing filename extensions
- Filenames without a numeric suffix
- Mismatched URL directories
- Mismatched filename prefixes
- Mismatched file extensions
- Mismatched number padding
- Ending values before the starting number
- Missing output selections

For safety, one operation is limited to 1,000,000 generated URLs.

## Settings

Preferences are stored in:

```text
%APPDATA%\WindowsAutomationUtilities\SequentialUrlGenerator.settings.json
```

Deleting that file restores the defaults.

## Known Limitations

- The sequential number must appear at the end of the filename, immediately before the extension.
- The utility generates URL text but does not verify that each remote URL exists.
- Query-string changes between sequential files are not generated.

## Future Enhancements

- Optional remote URL verification
- Reporting missing URLs
- Recent URL history
- Drag-and-drop input
- Export formats tailored to additional download managers

## License

Released under the MIT License.

## Version 2.0.2 Fixes

- Corrected PowerShell 5.1 layout calculations that caused controls to collapse to their default sizes.
- Restored full-width URL and output fields.
- Added additional spacing below the application header.
