# Release Notes

## Version `versionToDeploy`

### New Features

- Added feature abc.
- Added feature defg.

### Fixes

- Fixed issue lorem.
- Fixed issue xyzz.

### Installation Guide

1. Download the [ModuleZip](https://github.com/<gitUserName>/<ModuleName>/releases/download/v`versionToDeploy`/PsCraft.zip) file attached to the release.
2. **If on Windows**: Right-click the downloaded zip, select Properties, then unblock the file.
    > _This is to prevent having to unblock each file individually after unzipping._
3. Unzip the archive.
4. (Optional) Place the module folder somewhere in your `PSModulePath`.
    > _You can view the paths listed by running the environment variable `$Env:PSModulePath`_
5. Import the module, using the full path to the PSD1 file in place of `<ModuleName>` if the unzipped module folder is not in your `PSModulePath`:

    ```powershell
    # In Env:PSModulePath
    Import-Module <ModuleName>

    # Otherwise, provide the path to the manifest:
    Import-Module -Path Path\to\<ModuleName>\`versionToDeploy`\<ModuleName>.psd1
    ```
