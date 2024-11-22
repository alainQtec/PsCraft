using namespace System.IO
function Find-InstalledModule {
  # .SYNOPSIS
  #   Find modules installed on your machine based on scope, version, name, etc.
  # .DESCRIPTION
  #   Its like using Get-InstalledModule but you can even find unregistered/"manually Installed" modules. (as long as they are in any of $env:PsModulePath folders)
  # .EXAMPLE
  #   Find-InstalledModule psake | Select-Object -Expand Path | Import-Module -Verbose
  # .NOTES
  #   By default the cmdlet will search for the highest version from the specified scope.
  #   If you want all versions, use -All switch
  [CmdletBinding(DefaultParameterSetName = 'n')]
  [OutputType([LocalPsModule], [LocalPsModule[]])]
  param (
    # The name of the module to search for.
    [Parameter(Position = 0, Mandatory = $false, ParameterSetName = '__AllParameterSets')]
    [Alias('n')]
    [string]$Name,

    # The scope of the module (LocalMachine or CurrentUser).
    # If you don't use this parameter then, this cmdlet uses LocalMachine as a default scope.
    [Parameter(Position = 1, Mandatory = $false, ParameterSetName = 'n')]
    [ValidateSet("LocalMachine", "CurrentUser")]
    [Alias('s')]
    [string]$Scope,

    # The version of the module to search for.
    [Parameter(Position = 2, Mandatory = $false, ParameterSetName = 'n')]
    [Alias('v')]
    [Version]$Version,

    # The directory to search within for the module.
    [Parameter(Position = 1, Mandatory = $false, ParameterSetName = 'b')]
    [Alias('base', 'b')]
    [DirectoryInfo]$ModuleBase,

    # All versions, even duplicates.
    [switch]$All
  )

  begin {
    $res = $null
    $hsn = $PSBoundParameters.ContainsKey('Name')
    $hsv = $PSBoundParameters.ContainsKey('Version')
    $hsm = $PSBoundParameters.ContainsKey('ModuleBase')
    $hss = $PSBoundParameters.ContainsKey('Scope')
  }

  process {
    try {
      $res = switch ($true) {
        $($hsn -and $hss -and $hsv) { [PsCraft]::FindLocalPsModule($Name, $Scope, $Version); break }
        $($hsn -and $hss) { [PsCraft]::FindLocalPsModule($Name, $Scope); break }
        $($hsn -and $hsv) { [PsCraft]::FindLocalPsModule($Name, $Version); break }
        $($hsm -and $hsn) { [PsCraft]::FindLocalPsModule($Name, $ModuleBase); break }
        $hsn { [PsCraft]::FindLocalPsModule($Name); break }
        $hsm { [PsCraft]::FindLocalPsModule($ModuleBase.FullName); break }
        Default {
          [PsCraft]::FindLocalPsModule("*")
        }
      }
    } catch {
      Write-Error "Failed to find module: $_"
    }
  }

  end {
    if ($res) {
      return $res
    } else {
      Write-Verbose "No module found matching the specified criteria."
    }
  }
}
