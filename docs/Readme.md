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
Import-Module PsCraft
```

**Create a module:**

```PowerShell
New-PsModule -Name MyModule
```

<!-- Image goes here -->

## References

The structure used by this module is based on official documentation.

Practical Module Development concepts like separating functionality into
directories, along with modular imports, are practical tips shared in blog posts
and forums and various developer blogs.

- [About_Modules](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_modules)
- [The SysAdmin channel](https://thesysadminchannel.com/powershell-module/)

- [Mikefrobbins](https://mikefrobbins.com/2018/08/17/powershell-script-module-design-public-private-versus-functions-internal-folders-for-functions/)
- [Further down the rabbit hole: PowerShell modules and encapsulation](https://www.simple-talk.com/dotnet/.net-tools/further-down-the-rabbit-hole-powershell-modules-and-encapsulation/)

- [Jsnover.com/docs/MonadManifesto.pdf](https://www.jsnover.com/Docs/MonadManifesto.pdf)

### Misc

1. Sign your scripts

```PowerShell
Add-Signature -File MyNewScript.ps1
```

2. Create GUIs

Yes you can create a GUI dor your scripts even on Linux using PowerShell.

```PowerShell
Add-GUI -Script MyNewScript.ps1
```

---

### [WIP] ...

todo: fix Unresolved **bugs**:

1. remove any invisible characters from repo.

Example: removing any invisible Chars

```PowerShell
function Remove-InvisibleChars {
    <#
    .SYNOPSIS
    Removes invisible characters from all files in the current directory and subdirectories.

    .NOTES
    - Written by chatgpt for Linux.
    - Requires `sed` or appropriate substitution tool.
    #>
    [CmdletBinding()]
    param (
        [string[]]$chars = @(
          "`x00", # Null
          "`x01", # Start of Header
          "`x02", # Start of Text
          "`x03", # End of Text
          "`x09", # Horizontal Tab
          "`x0B", # Vertical Tab
          "`x0C"  # Form Feed
        )
    )

    # Retrieve all files recursively
    $files = Get-ChildItem -File -Recurse -Force

    foreach ($file in $files) {
        Write-Verbose "Processing file: $($file.FullName)"

        # Read content of the file
        $content = Get-Content -Raw -Path $file.FullName

        # Remove invisible characters
        foreach ($char in $chars) {
            $charValue = [char][byte]($char -replace '`x', '0x')
            $content = $content -replace [regex]::Escape($charValue), ''
        }

        # Save the cleaned content back to the file
        $cleanFilePath = [System.IO.Path]::Combine($file.DirectoryName, "$($file.BaseName)_clean$($file.Extension)")
        Set-Content -Path $cleanFilePath -Value $content
    }

    # Optionally delete old files and rename cleaned files
    foreach ($file in $files) {
        $cleanFilePath = [System.IO.Path]::Combine($file.DirectoryName, "$($file.BaseName)_clean$($file.Extension)")
        if (Test-Path $cleanFilePath) {
            Remove-Item -Path $file.FullName -Verbose
            Rename-Item -Path $cleanFilePath -NewName $file.Name -Verbose
        }
    }
}
```
