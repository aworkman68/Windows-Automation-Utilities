# Batch TIFF to JPEG Converter

A lightweight Windows PowerShell utility for converting folders of `.tif` and `.tiff` images into high-quality JPEG files.

## Features

- Single-window graphical interface
- Foreground startup window so the utility is easy to find
- Batch conversion of `.tif` and `.tiff` files
- Optional recursive processing of subfolders
- Adjustable JPEG quality from 1–100
- Recommended archival-quality default of 95
- Preservation of base filenames and pixel dimensions
- Option to save JPEGs beside the originals or in a separate folder
- Preservation of relative subfolder structure when using a separate output folder
- Safe skip or overwrite behavior for existing JPEG files
- Live progress, elapsed time, and estimated remaining time
- Cancellation after the current image finishes
- Persistent user settings stored under `%APPDATA%\WindowsAutomationUtilities`
- Timestamped conversion logs
- Completion summary with links to the output folder and log
- Original TIFF files are never deleted or modified

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or PowerShell 7 on Windows
- .NET Framework / Windows Forms and System.Drawing support

## Running the Utility

Open PowerShell in the utility folder and run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\Batch_Convert_TIFF_to_JPEG.ps1"
```

You may also right-click the script and choose **Run with PowerShell**, depending on your local execution-policy settings.

## Usage

1. Select the folder containing the TIFF images.
2. Choose whether to include subfolders.
3. Choose where the JPEG files should be saved.
4. Select the desired JPEG quality. A value of **95** is recommended for high-quality archival scans.
5. Choose whether existing JPEG files may be overwritten.
6. Select **Convert**.
7. Review the completion summary and conversion log.

## File Naming and Dimensions

The converter retains the original base filename and changes only the extension:

```text
M66-001-0284.tif  ->  M66-001-0284.jpg
```

The JPEG retains the TIFF's pixel width and height. The source image is rendered to a standard 24-bit RGB bitmap because JPEG does not support every TIFF pixel format or bit depth.

## Output and Logging

A timestamped log is written to the output location:

```text
TiffToJpegConversion-YYYYMMDD-HHMMSS.log.txt
```

The log records created, skipped, and failed files, image dimensions, source and output sizes, elapsed time, and approximate storage reduction.

## Safety

The original TIFF files are never deleted or changed. Existing JPEGs are skipped by default unless **Overwrite JPEG files that already exist** is selected.

For an unfamiliar collection, test several representative images and compare fine text, handwritten notes, linework, and photographs at the zoom levels important to your workflow before converting the entire collection.

## Known Limitations

- The utility uses `System.Drawing`, which is intended for Windows environments.
- Multipage TIFF files are converted using the first image frame only.
- TIFF metadata is not fully copied to the JPEG; pixel dimensions and valid DPI values are preserved.
- JPEG is a lossy format and is not a replacement for preservation masters when lossless archival storage is required.

## Version

**1.1.0**

## License

Released under the repository's MIT License.
