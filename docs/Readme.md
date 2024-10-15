**docs.PsCraft**

<p>
This PowerShell module is a toolbox to streamline the process of building and distributing PowerShell modules.
</br>
<img align="right" src="https://github.com/user-attachments/assets/92fc736a-118e-45cd-8b9f-0df83d1309f8" width="250" height="250" alt="it_just_works" />
<div align="left">
<b>
  Sometimes I just want something to work and not to have think about it.
</b>
</br>
</br>
To focus on writing code and not get bogged down in intricacies of
the build process.

<p>

<p>
This module aims to eliminate the need to <b>write and test build scripts</b>
The only code you are expected to write is in <a href="/Public/">Public</a> functions and <a href="Tests">Tests</a>.

😔 Tests have to be written by humans. There's just no other way.

</p>
</div>

**The goal is to give you a starting point that just works.**

> All you need to do is run 3 commands minimum, then let an LLM take care of the
> rest.

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
