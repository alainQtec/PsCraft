function Get-LocalModule {
  # .SYNOPSIS
  #  Gets basic details of an Installed Psmodule
  # .DESCRIPTION
  #  Its like using Get-InstalledModule but you can even find unregistered/"manually Installed" modules. (as long as they are in any of $env:PsmodulePath folders)
  # .EXAMPLE
  #  Get-LocalModule psake | Select-Object -Expand Path | Import-Module -Verbose
  [CmdletBinding()]
  [OutputType([LocalPsModule])]
  param (
    # The name of the installed module to search on the machine.
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,

    # The required module version. You don't use this parameter,
    # then this cmdlet will search for the highest version from the specified scope.
    [Parameter(Mandatory = $false, Position = 1)]
    [ValidateNotNullOrEmpty()]
    [version]$version,

    # If you don't use this parameter then, this cmdlet uses LocalMachine as a default scope.
    [Parameter(Mandatory = $false, Position = 2)]
    [ValidateSet('CurrentUser', 'LocalMachine')]
    [string]$Scope
  )
  begin {
    $PsModule = $null
  }
  process {
    $PsModule = switch ($true) {
      $($PSBoundParameters.ContainsKey('version') -and $PSBoundParameters.ContainsKey('Scope')) { [LocalPsModule]::Find($Name, $Scope, $version) ; break }
      $($PSBoundParameters.ContainsKey('version') -and !$PSBoundParameters.ContainsKey('Scope')) { [LocalPsModule]::Find($Name, 'LocalMachine', $version) ; break }
      $(!$PSBoundParameters.ContainsKey('version') -and $PSBoundParameters.ContainsKey('Scope')) { [LocalPsModule]::Find($Name, $Scope, $version) ; break }
      $(!$PSBoundParameters.ContainsKey('version') -and !$PSBoundParameters.ContainsKey('Scope')) { [LocalPsModule]::Find($Name) ; break }
      Default { New-Object LocalPsModule($Name) }
    }
  }
  end {
    return $PsModule
  }
}