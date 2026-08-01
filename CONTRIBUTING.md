# Contributing

Thank you for your interest in **Windows Automation Utilities**!

This repository is a collection of lightweight Windows utilities designed to automate repetitive tasks involving file management, image processing, archival research, and general productivity. Whether you're reporting an issue, suggesting a feature, or contributing code, your feedback is appreciated.

---

# Project Goals

The primary goals of this project are:

- Solve real-world workflow problems.
- Keep each utility focused on a single purpose.
- Maintain a consistent user experience across all utilities.
- Favor readability and maintainability over unnecessary complexity.
- Keep dependencies to a minimum whenever practical.

---

# Coding Standards

## General

- Write clear, readable, and well-documented code.
- Use descriptive variable and function names.
- Avoid unnecessary complexity.
- Validate all user input.
- Handle errors gracefully.
- Prefer small, reusable helper functions over duplicated code.

---

## User Interface

Utilities should provide a consistent experience.

Where applicable:

- Display dialogs centered on the screen.
- Keep dialog titles consistent.
- Use clear, descriptive labels.
- Present meaningful error messages.
- Display progress for long-running operations.
- Provide a completion summary when finished.

---

## Logging

Utilities that perform file operations should generate a timestamped log file whenever practical.

Typical log information includes:

- Start time
- End time
- Files processed
- Items skipped
- Errors encountered
- Summary statistics

---

## Versioning

This project follows **Semantic Versioning**.

Examples:

```
1.0.0
```

Initial public release.

```
1.0.1
```

Bug fixes.

```
1.1.0
```

New features that remain backward compatible.

```
2.0.0
```

Breaking changes or significant redesigns.

---

# Repository Structure

Each utility should have its own directory.

Example:

```
Utility_Name/

    Utility_Name.ps1

    README.md
```

Standalone applications may include additional folders such as:

```
Source/

Releases/

Assets/

Documentation/
```

---

# Documentation

Every utility should include:

- Purpose
- Features
- Requirements
- Usage instructions
- Example workflow
- Known limitations
- Future enhancements

The repository README should remain concise, while utility-specific details belong in the individual README.

---

# Pull Requests

If you would like to contribute:

- Keep changes focused on a single improvement.
- Update documentation when necessary.
- Follow the existing coding style.
- Test thoroughly before submitting.

---

# Feature Requests

Suggestions for new utilities or improvements are always welcome.

When proposing a feature, please include:

- The problem being solved
- Expected workflow
- Example input and output (when applicable)

---

# Bug Reports

Please include:

- Windows version
- PowerShell version (if applicable)
- Utility version
- Steps to reproduce
- Error messages
- Screenshots if helpful

---

# License

By contributing to this project, you agree that your contributions will be licensed under the MIT License.
