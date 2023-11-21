# Changelog

* Added funtion Initialize-CliProfile used to Load/reload PowerShell `$Profile
* Added function Write-ColorOutput

## Install guide

1. Download the [ModuleZip](https://github.com/alainQtec/PsModuleGen/releases/download/v`versionToDeploy`/PsModuleGen.zip) file attached to the release.
2. **If on Windows**: Right-click the downloaded zip, select Properties, then unblock the file.
    > _This is to prevent having to unblock each file individually after unzipping._
3. Unzip the archive.
4. (Optional) Place the module folder somewhere in your ``PSModulePath``.
    > _You can view the paths listed by running the environment variable ```$Env:PSModulePath``_
5. Import the module, using the full path to the PSD1 file in place of ``PsModuleGen`` if the unzipped module folder is not in your ``PSModulePath``:

    ``````powershell
    # In Env:PSModulePath
    Import-Module PsModuleGen

    # Otherwise, provide the path to the manifest:
    Import-Module -Path Path\to\PsModuleGen\`versionToDeploy`\PsModuleGen.psd1
    ``````
