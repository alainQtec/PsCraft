# <img align="right" src="docs/img/icon.png" width="200" height="200" alt="icon" />

<div align="Left">
  <a href="https://www.powershellgallery.com/packages/PsCraft"><b>PsCraft</b></a>
  <p>
    A toolbox to accelerate common tasks involved in <b>developing and sharing PowerShell code</b>.
    </br></br>
    <a href="https://github.com/alainQtec/PsCraft/actions/workflows/CI.yaml">
    <img src="https://github.com/alainQtec/PsCraft/actions/workflows/CI.yaml/badge.svg" alt="CI"/>
    </a>
    <img src="https://github.com/alainQtec/PsCraft/actions/workflows/Publish.yaml/badge.svg" alt="Publish to PowerShell Gallery"/>
    <a href="https://github.com/alainQtec/PsCraft/actions/workflows/Publish.yaml">
    </a>
    <a href="https://www.PowerShellGallery.com/packages/PsCraft">
    <img src="https://img.shields.io/powershellgallery/dt/PsCraft.svg?style=flat&logo=powershell&color=blue"
          alt="PowerShell Gallery" title="PowerShell Gallery" />
    </a>
  </p>
</div>

[result] by using [feature] for [whom]

## **Usage**

- Install from Powershell Gallery:

  ```PowerShell
  Install-Module PsCraft
  ```
- then .. Create, test, build, deploy 🚀.

  ⤷ Ex: **You can create a
  [script module](https://learn.microsoft.com/en-us/powershell/scripting/developer/module/how-to-write-a-powershell-script-module)
  in unders 5 seconds!**
  <!-- <video controls autoplay src="https://github.com/user-attachments/assets/c4373930-ef94-45aa-99de-26b7f5e6cb49" width="320" height="240" controls>Your
  browser does not support the video tag.</video> -->
  <div style="position: relative; width: 100%; padding-bottom: 56.25%">
  <iframe src="https://www.youtube.com/embed/jgEYn-ldr30"
          title="Web Load Testing with West Wind WebSurge 2" frameborder="0" allowfullscreen
          allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
          style="position: absolute; width: 80%; height: 80%; border-radius:10px;">
  </iframe>
  </div>

  `Its only one comand`:

  ```PowerShell
  $module = New-PsModule "CliHelper.Core"
  ```

  (づ ᴗ _ᴗ)づ haleluːjə!

For more usage read the [docs](/docs/Readme.md). they pretty easy!

**Features (W.I.P) :**

- [x] **Create & Manage** modules: Using
      [`PsCraft.ModuleManager`](Private/PsCraft.ModuleManager/PsCraft.ModuleManager.psm1)

- [ ] Add **CodeSigning** Functions: `PsCraft.CodeSigner.psm1`

  <p>Cross-platform <a href ="https://learn.microsoft.com/en-us/previous-versions/windows/hardware/design/dn653556(v=vs.85)">code signing</a>.</p>

  <p>Sign your modules and scripts with digital signatures for enhanced <a href ="https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing?view=powershell-7.4">security and trust</a></p>

- [ ] **Build GUIs faster**: `PsCraft.GuiBuilder.psm1`

  A module to create intuitive graphical interfaces for your modules.

<p>And other todos not mentioned here. Use <a href="https://marketplace.visualstudio.com/items?itemName=Gruntfuggly.todo-tree">todo tree</a> to find all of them.</p>

## License

<p>This project is licensed under the MIT License - Read
 <a href="https://alain.MIT-license.org">License</a> for details. </p>

## Sponsor

If this tool helps you out you can give your support via
[![paypal.me](https://ionicabizau.github.io/badges/paypal.svg)](https://www.paypal.com/donate/?hosted_button_id=3LA3EUKRU6722)

## Contributing

Pull requests are welcome! You can also contribute to this module by
[sharing ideas, and providing feedback](https://github.com/alainQtec/PsCraft/discussions/2).

[![Contributors](https://contrib.rocks/image?repo=alainQtec/PsCraft)](https://github.com/alainQtec/PsCraft/graphs/contributors)

![Alt](https://repobeats.axiom.co/api/embed/9cbc0ffce6f62ace082852045cd005b5ad61cebd.svg "Repobeats analytics image")
