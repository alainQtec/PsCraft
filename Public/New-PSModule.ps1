function New-PsModule {
  # .SYNOPSIS
  #   Creates a PsModule Object, that can be saved to the disk.
  # .DESCRIPTION
  #   New-Module serves two ways of creating modules, but in either case, it can generate the psd1 and psm1 necessary for a module based on script files.
  #   In one use case, its just a simplified wrapper for New-ModuleManifest which answers some of the parameters based on the files already in the module folder.
  #   In the second use case, it allows you to collect one or more scripts and put them into a new module folder.
  # .LINK
  #   https://github.com/alainQtec/PsCraft/blob/nain/Public/New-PsModule.ps1
  # .EXAMPLE
  #   New-PsModule -Verbose
  #   Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines
  # .Example
  #   Get-ChildItem *.ps1, *.psd1 -Recurse | New-PsModule MyUtility
  #   This example shows how to pipe the files into the New-PsModule, and yet another approach to collecting the files needed. [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Medium", DefaultParameterSetName = "NewModuleManifest")]
  # .OUTPUTS
  #   [PsModule]
  [CmdletBinding(SupportsShouldProcess, DefaultParametersetName = 'ByName')]
  param (
    # The Name Of your Module; note that it Should always match BaseName of its path.
    [Parameter(Position = 0, ParameterSetName = 'ByName')]
    [ValidateScript({ if ($_ -match "[$([regex]::Escape(([io.path]::GetInvalidFileNameChars() -join '')))]") { throw "The ModuleName must be a valid folder name. The character '$($matches[0])' is not valid in a Module name." } else { $true } })]
    [string]$Name,

    [Parameter(Position = 0, ParameterSetName = 'ByConfig')]
    [ValidateNotNullOrEmpty()]
    [Array]$Configuration,

    # The FullPath Of your Module.
    [Parameter(Position = 1, Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = '__AllParameterSets')]
    [ValidateNotNullOrEmpty()]
    [string]$Path = '.',

    # The name of the author to use for the psd1 and copyright statement
    [PSDefaultValue(Help = { "Env:UserName: (${Env:UserName})" })]
    [String]$Author = $Env:UserName,

    # A short description of the contents of the module.
    [Parameter(Position = 1)]
    [PSDefaultValue(Help = { "'A collection of script files by ${Env:UserName}' (uses the value from the Author parmeter)" })]
    [string]${Description} = "A collection of script files by $Author",

    # The version of the module
    # (This is a passthru for New-ModuleManifest)
    [Parameter()]
    [PSDefaultValue(Help = "1.0 (when -Upgrade is set, increments the existing value to the nearest major version number)")]
    [Alias("Version", "MV")]
    [Version]${ModuleVersion} = "1.0",

    # (This is a passthru for New-ModuleManifest)
    [AllowEmptyString()]
    [String]$CompanyName = "None (Personal Module)",

    # Specifies the minimum version of the Common Language Runtime (CLR) of the Microsoft .NET Framework that the module requires (Should be 2.0 or 4.0). Defaults to the (rounded) currently available ClrVersion.
    # (This is a passthru for New-ModuleManifest)
    [version]
    [PSDefaultValue(help = { "Your current CLRVersion number (rounded): ($PSVersionTable.CLRVersion)" })]
    ${ClrVersion} = $PSVersionTable.CLRVersion,

    # Specifies the minimum version of Windows PowerShell that will work with this module. Defaults to 1 less than your current version.
    # (This is a passthru for New-ModuleManifest)
    [version]
    [PSDefaultValue(Help = { "Your current PSVersion number (rounded): ($($PSVersionTable.PSVersion.ToString(2))" })]
    [Alias("PSV")]
    ${PowerShellVersion} = ("{0:F1}" -f [double]($PSVersionTable.PSVersion | Select-Object @{l = 'str'; e = { $_.Major.ToString() + '.' + $_.Minor.ToString() } }).str),

    # Specifies modules that this module requires. (This is a passthru for New-ModuleManifest)
    [System.Object[]]
    [Alias("Modules", "RM")]
    ${RequiredModules} = $null,

    # Specifies the assembly (.dll) files that the module requires. (This is a passthru for New-ModuleManifest)
    [AllowEmptyCollection()]
    [string[]]
    [Alias("Assemblies", "RA")]
    ${RequiredAssemblies} = $null
  )

  begin {
    $Module = $null; $Path = [PsCraft]::GetResolvedPath($Path)
  }

  process {
    Write-Host "[+] Creating Module $Name ..." # Todo: Add loading animation
    if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey("Path")) {
      $Module = [PsModule]::Create($Name, $path)
    } else {
      $Module = [PsModule]::Create($Name)
    }
    if ($PSCmdlet.ShouldProcess("", "", "Format and Write Module folder structure")) {
      [void]$Module.save()
      if ([IO.Directory]::Exists($Module.Path.FullName)) {
        [string]$HostOs = [PsCraft]::GetHostOs()
        if ($HostOs -in ("Linux", "MacOSX")) {
          &tree -a $Module.Path.FullName | Out-Host
        } elseif ($HostOs -eq "Windows") {
          # TODO: Use the Show-Tree Cmdlet : WIP in github.com/alainQtec/cliHelper.core
          # Here's a very half-ass version of it:
          Get-ChildItem -Recurse $Path | ForEach-Object { $depth = ($_ | Split-Path -Parent | Split-Path -Leaf).Count; $(' ' * $depth * 2) + $_.Name | Write-Host -f Blue }
        }
      }
    }
  }

  end {
    return $Module
  }
}