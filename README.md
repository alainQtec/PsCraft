# [**PsCraft Toolbox**](https://www.powershellgallery.com/packages/PsCraft/)

PsCraft Toolbox provides cmdlets to speed up common PowerShell development tasks.

[![CI](https://github.com/alainQtec/PsCraft/actions/workflows/CI.yaml/badge.svg)](https://github.com/alainQtec/PsCraft/actions/workflows/CI.yaml)
[![Publish to PowerShell Gallery](https://github.com/alainQtec/PsCraft/actions/workflows/Publish.yaml/badge.svg)](https://github.com/alainQtec/PsCraft/actions/workflows/Publish.yaml)
<a href="https://www.PowerShellGallery.com/packages/PsCraft">
    <img src="https://img.shields.io/powershellgallery/dt/PsCraft.svg?style=flat&logo=powershell&color=blue"
      alt="PowerShell Gallery" title="PowerShell Gallery" />
  </a>

## Installation

- Install from Powershell Gallery:

    ```PowerShell
    Install-Module PsCraft
    ```

## Features

- **Module Creation**: Build robust modules with ease using intuitive commands for cmdlets, functions, variables, and more.

- **Module Management**: Import, export, update, and remove modules with ease, ensuring smooth integration and version control.
- **Secure Your Code**: Sign your modules and scripts with digital signatures for enhanced security and trust.

- **Build GUIs faster**: Create intuitive graphical interfaces for your modules, making them accessible and interactive for all users.

## Usage

- Import the module:

    ```PowerShell
    Import-Module PsCraft
    ```

- Create a new Module:

    ```PowerShell
    New-PsModule -Name DemoModule
    # Creates a new module in current directory
    ```

## Contributing

Pull requests are welcome! You can also contribute to this module by writing code, sharing opinions, and providing feedback.

![Alt](https://repobeats.axiom.co/api/embed/9cbc0ffce6f62ace082852045cd005b5ad61cebd.svg "Repobeats analytics image")

## License

This project is licensed under the MIT License - see the [MIT License](https://alainQtec.MIT-license.org) for details.

