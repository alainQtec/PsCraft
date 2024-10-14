# Changelog

- Added funtion Initialize-CliProfile used to Load/reload PowerShell `$Profile
- Added function Write-ColorOutput

## Install guide

1. Download the
   [ModuleZip](https://github.com/alainQtec/PsCraft/releases/download/v`versionToDeploy`/PsCraft.zip)
   file attached to the release.
2. **If on Windows**: Right-click the downloaded zip, select Properties, then
   unblock the file.
   > _This is to prevent having to unblock each file individually after
   > unzipping._
3. Unzip the archive.
4. (Optional) Place the module folder somewhere in your `PsModulePath`.
   > _You can view the paths listed by running the environment variable
   > ```$Env:PsModulePath``_
5. Import the module, using the full path to the PSD1 file in place of `PsCraft`
   if the unzipped module folder is not in your `PsModulePath`:

   ```powershell
   # In Env:PsModulePath
   Import-Module PsCraft

   # Otherwise, provide the path to the manifest:
   Import-Module -Path Path\to\PsCraft\`versionToDeploy`\PsCraft.psd1
   ```
