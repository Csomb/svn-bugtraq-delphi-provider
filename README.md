# SVN BugTraq Delphi Provider

A lightweight TortoiseSVN BugTraq provider implemented in Delphi.

This project allows you to integrate an external issue tracker (or any HTTP-based source) directly into the TortoiseSVN commit workflow. It enables selecting an issue from a custom endpoint and automatically inserting it into the commit message.

---

## Features

* Integrates with TortoiseSVN BugTraq interface
* Custom HTTP endpoint support (JSON-based)
* Issue selection dialog with grid view
* Configurable endpoint URL via TortoiseSVN "Options"
* Supports both x86 and x64 builds
* Minimal dependencies (WinInet-based HTTP client)

---

## How it works

1. TortoiseSVN calls the provider during commit
2. The provider opens a custom dialog
3. The dialog fetches issue data from a configured URL
4. User selects an issue
5. The selected issue is appended to the commit message

---

## Expected JSON format

The endpoint must return a JSON array:

```json
[
  {
    "partner": "Example",
    "id": 123,
    "desc": "Fix login bug"
  },
  {
    "partner": "Example",
    "id": 124,
    "desc": "Add new feature"
  }
]
```

Required fields:

* `id` → numeric issue ID
* `desc` → issue title/description
* `partner` → optional (displayed in grid)

---

## Installation

### 1. Build

Compile the project for both architectures:

* Win32 (x86)
* Win64 (x64)

---

### 2. Register the DLL

Use `regsvr32`:

#### 64-bit:

```bat
regsvr32 YourProvider_x64.dll
```

#### 32-bit:

```bat
regsvr32 YourProvider_x86.dll
```

> Important: Use the correct `regsvr32` version:
>
> * `System32` → 64-bit
> * `SysWOW64` → 32-bit

---

### 3. Configure in TortoiseSVN

1. Right-click on a working copy folder
2. Go to:

   ```
   TortoiseSVN → Settings → Issue Tracker Integration
   ```
3. Add new provider:

   * Select your provider from the list
4. Click **Options**
5. Enter your endpoint URL

Example:

```
https://your-server/api/issues
```

---

## Usage

1. Start a commit in TortoiseSVN
2. Click **"Select issue"**
3. Choose an item from the list
4. The issue description will be appended to the commit message

---

## Configuration format

The provider stores settings as a parameter string:

```
url=https://your-server/api/issues
```

---

## Notes

* HTTPS certificates can be ignored (configurable in code)
* Network errors will raise exceptions
* JSON parsing is minimal and expects valid input
* The UI is intentionally simple and can be customized

---

## Limitations

* Only basic JSON parsing (no nested structures)
* No pagination or filtering (yet)
* No authentication UI (basic auth supported in code)

---

## Development

### Main components

* `BugTraqProviderUnit` → COM provider implementation
* `SelectTicketFormUnit` → issue selection dialog
* `OptionsUnit` → configuration dialog
* `HttpClientUnit` → WinInet-based HTTP helper

---

## License

Free to use and modify.

---

## Why this exists

Because integrating a custom issue tracker into TortoiseSVN using Delphi is poorly documented and unnecessarily painful.

This project provides a working example so others don’t have to figure it out from scratch.
