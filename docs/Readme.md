**docs.PsCraft**

This is a toolbox specifically for building and distributing Powershell
code/modules.

Sometimes powershell devs just want something that works. and focus on creating
the module not writing and testing a build script.

## **Using** PsCraft

First make sure you install and Import the module.

```PowerShell
Install-Module PsCraft -verbose:$false
Import-Module PsCraft -verbose:$false
```

### **Create a module with** PsCraft

```PowerShell
New-PsModule -Name DemoModule
# Creates a new module in current directory
```

### **Create a module with** PsCraft

```PowerShell
Add-Signature -File MyNewScript.ps1
```

### **Create a GUI with** PsCraft

Yes you can create a GUI dor your scripts even on Linux using PowerShell.

```PowerShell
Add-GUI -Script MyNewScript.ps1
```

---

## NOTE: [WIP] ...More stuff comming.
