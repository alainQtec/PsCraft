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

## **Usage**

- Install from Powershell Gallery:

  ```PowerShell
  Install-Module PsCraft
  ```
- then ..
  > .gif video of usage will go here.

  (づ ᴗ _ᴗ)づ haleluːjə!

For more usage read the [docs](/docs/Readme.md). they pretty easy!

**Features (W.I.P) :**

- [x] **Create & Manage** modules: Using
      [`PsCraft.ModuleManager`](Private/PsCraft.ModuleManager/PsCraft.ModuleManager.psm1)

  <details>
    <summary>Example</summary>

  ⤷ **You can build robust modules unders 5 seconds!**

  - Foo
  - Bar

  `Example`:

  ```js
  function logSomething(something) {
    console.log("Something", something);
  }
  ```

  </details>

- [ ] Add **CodeSigning** Functions: `PsCraft.CodeSigner.psm1`

  <p>Cross-platform <a href ="https://learn.microsoft.com/en-us/previous-versions/windows/hardware/design/dn653556(v=vs.85)">code signing</a>.</p>

  <p>Sign your modules and scripts with digital signatures for enhanced <a href ="https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing?view=powershell-7.4">security and trust</a></p>

- [ ] **Build GUIs faster**: `PsCraft.GuiBuilder.psm1`

  A module to create intuitive graphical interfaces for your modules.

  <p>Use<a href="https://marketplace.visualstudio.com/items?itemName=Gruntfuggly.todo-tree">todo tree</a> to find all of them.</p>

## License

<p>This project is licensed under the MIT License - Read
 <a href="https://alain.MIT-license.org">License</a> for details. </p>

## Contributing

Pull requests are welcome! You can also contribute to this module by writing
code, sharing opinions, and providing feedback.

![Alt](https://repobeats.axiom.co/api/embed/9cbc0ffce6f62ace082852045cd005b5ad61cebd.svg "Repobeats analytics image")
