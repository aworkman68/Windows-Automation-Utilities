# Windows Automation Utilities

> **Small utilities. Real problems. Practical solutions.**

A collection of lightweight Windows automation utilities built to simplify repetitive tasks involving file management, image processing, archival research, and everyday productivity.

These tools were developed to solve real-world workflow challenges and are designed to be portable, easy to use, and easy to maintain. Rather than attempting to be feature-rich applications, each utility focuses on performing one task exceptionally well.

---

## Why This Repository Exists

As a software engineer, I frequently encounter repetitive tasks that interrupt productivity or consume valuable time. This repository contains practical utilities that I've developed to automate those tasks, allowing me to spend less time on manual work and more time solving interesting problems.

Many of these tools originated while working with:

- Digital archival collections
- Image processing workflows
- Bulk file management
- Historical research projects
- Software development automation

Each utility was created to address a specific need and continues to evolve as new features and improvements are identified.

---

## Utilities

| Utility                                  | Description                                                                                     |      Status       |
| ---------------------------------------- | ----------------------------------------------------------------------------------------------- | :---------------: |
| 📁 **Create Directories from Text File** | Creates folders from a text file, including nested folders, with validation and logging.        |     ✅ Stable     |
| 🔗 **Create URL File List**              | Generates sequential URL lists for bulk downloading resources such as National Archives images. |     ✅ Stable     |
| 🖼 **Batch TIFF to JPEG Converter**      | Converts TIFF images into high-quality JPEGs while preserving filenames and image dimensions.   |     ✅ Stable     |
| 📸 **Fixed Region Screenshot Capture**   | Native Windows application for rapid fixed-region screen capture. _(Standalone repository)_     | 🚧 In Development |

---

## Features

Although each utility serves a different purpose, they share a common design philosophy.

- Lightweight and portable
- Simple graphical interface
- Logging and progress reporting
- Validation and error handling
- Safe defaults
- Consistent user experience
- Windows PowerShell 5.1 and PowerShell 7 compatibility _(PowerShell utilities)_

---

## Repository Structure

```text
Windows-Automation-Utilities/
│
├── README.md
├── CHANGELOG.md
├── LICENSE
│
├── Create_URL_File_List/
│   ├── Create_URL_File_List.ps1
│   └── README.md
│
├── Batch_Convert_TIFF_to_JPEG/
│   ├── Batch_Convert_TIFF_to_JPEG.ps1
│   └── README.md
│
├── Create_Directories_from_Text_File/
│   ├── Create_Directories_from_Text_File.ps1
│   └── README.md
│
└── docs/
    ├── screenshots/
    └── images/
```

---

## Requirements

### PowerShell Utilities

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or PowerShell 7
- .NET Framework (included with Windows)

### Standalone Applications

Requirements vary by application and are documented within each project.

---

## Design Goals

These utilities are developed with the following goals in mind:

- Automate repetitive workflows
- Reduce manual effort
- Remain easy to understand and modify
- Require minimal installation
- Follow consistent coding and UI standards
- Continue evolving through practical use

---

## Roadmap

Future utilities currently being considered include:

- OCR Helper
- Contact Sheet Generator
- Batch Image Renamer
- Archive Downloader
- Metadata Editor
- File Integrity Verifier
- PDF Image Extractor

---

## Contributing

Suggestions, bug reports, and ideas for improvements are always welcome.

While these utilities were originally developed for personal workflows, they are shared in the hope that others may find them useful as well.

---

## License

This project is licensed under the **MIT License**.

See the **LICENSE** file for details.

---

## Author

**Alan Workman**

---

_"Automating the repetitive so you can focus on the important."_
