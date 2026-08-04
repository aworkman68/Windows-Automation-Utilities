# Create Directories from Text File

**Version 2.0.1**  
Part of the **Windows Automation Utilities** project.

Create directories in bulk from a text file containing one folder name or relative folder path per line.

## Version 2.0.1

- Fixed a Windows PowerShell 5.1 compatibility error that prevented directory creation after previewing the list.
- The analyzed item collection is now used directly instead of being wrapped with the array subexpression operator.

## Features

- Single-window graphical interface
- Opens in the foreground and takes focus
- Live validation and preview
- Supports nested directory paths
- Detects directories to create, existing directories, duplicates, invalid entries, and adjusted names
- Optionally replaces invalid Windows filename characters with underscores
- Ignores blank lines
- Optionally ignores comment lines beginning with `#`
- Blocks parent-directory traversal using `..`
- Shows creation progress
- Writes a timestamped log
- Remembers the last source file, destination folder, and options
- Compatible with Windows PowerShell 5.1 and PowerShell 7 on Windows

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or PowerShell 7
- .NET Framework and Windows Forms

## Running the Utility

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\Create_Folders_From_Text_List.ps1"
```

PowerShell 7:

```powershell
pwsh.exe -ExecutionPolicy Bypass -File ".\Create_Folders_From_Text_List.ps1"
```

## Text File Format

Use one directory name or relative directory path per line:

```text
Books
Books\Military History
Books\Numismatics
Maps
Photographs\Civil War
Photographs\World War II
```

Forward slashes are also accepted. Blank lines are ignored.

With comment handling enabled:

```text
# Main categories
Books
Maps
Photographs
```

## Preview Statuses

| Status    | Meaning                                              |
| --------- | ---------------------------------------------------- |
| Create    | The directory will be created.                       |
| Adjusted  | The directory will be created with a corrected name. |
| Exists    | The directory already exists.                        |
| Duplicate | The resulting path appears more than once.           |
| Invalid   | The entry cannot be used safely.                     |
| Conflict  | A file already occupies the requested path.          |

## Invalid Windows Names

When replacement is enabled, invalid characters are replaced with underscores:

```text
< > : " / \ | ? *
```

Reserved names such as `CON`, `AUX`, `NUL`, `COM1`, and `LPT1` are prefixed with an underscore. Trailing spaces and periods are removed.

## Safety

- Creation is limited to the selected destination folder.
- `..` path traversal is rejected.
- Existing directories are not changed.
- Existing files are not overwritten.
- Duplicate entries are skipped.
- A confirmation prompt appears before creation.

## Logging

Logs are written to the destination folder:

```text
DirectoryCreation-YYYYMMDD-HHMMSS.log.txt
```

## Settings

Preferences are stored in:

```text
%APPDATA%\WindowsAutomationUtilities\DirectoryCreator.settings.json
```

Delete that file to restore defaults.

## Known Limitations

- Each non-comment line represents one relative directory path.
- Long paths depend on the active Windows long-path configuration.
- Permissions may prevent creation in protected locations.

## Future Enhancements

- Drag-and-drop text-file selection
- Export preview results
- Optional rollback for the current run
- CSV import
- Reusable directory templates

## License

Released under the MIT License.
