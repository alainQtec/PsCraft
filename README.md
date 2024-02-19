# [**PsModuleGen**](https://www.powershellgallery.com/packages/PsModuleGen/)

 "A PowerShell module generator module"

Helps to easily create a new PowerShell module.

[![CI](https://github.com/alainQtec/PsModuleGen/actions/workflows/CI.yaml/badge.svg)](https://github.com/alainQtec/PsModuleGen/actions/workflows/CI.yaml)
[![Upload artifact from Ubuntu](https://github.com/alainQtec/PsModuleGen/actions/workflows/Upload_Artifact.yaml/badge.svg)](https://github.com/alainQtec/PsModuleGen/actions/workflows/Upload_Artifact.yaml)
[![Publish to PowerShell Gallery](https://github.com/alainQtec/PsModuleGen/actions/workflows/Publish.yaml/badge.svg)](https://github.com/alainQtec/PsModuleGen/actions/workflows/Publish.yaml)
<a href="https://www.PowerShellGallery.com/packages/PsModuleGen">
    <img src="https://img.shields.io/powershellgallery/dt/PsModuleGen.svg?style=flat&logo=powershell&color=blue"
      alt="PowerShell Gallery" title="PowerShell Gallery" />
  </a>

## Installation

- Install from Powershell Gallery:

    ```PowerShell
    Install-Module PsModuleGen
    ```

## Usage

- Import the module:

    ```PowerShell
    Import-Module PsModuleGen
    ```

- Create a new Module:

    ```PowerShell
    New-PsModule -Name DemoModule
    # Creates a new module in current directory
    ```

## Contributing

Pull requests are welcome! You can also contribute to this module by writing code, sharing opinions, and providing feedback.

## License

This project is licensed under the MIT License - see the [MIT License](https://alainQtec.MIT-license.org) for details.

## Todos

- [x] Add ast parser to the main class

- [ ] Add module manifest generator

- [ ] Add module directory tree generator

- [ ] Use AI to generate tags
<!-- Git version should be '{Major}.{Minor}.{Patch}.{env:BUILDCOUNT ?? 0}' -->
