function New-PsModule {
  # .SYNOPSIS
  #   Creates a PsModule Object, that can be saved to the disk.
  # .DESCRIPTION
  #   A longer description of the function, its purpose, common use cases, etc.
  # .LINK
  #   https://github.com/alainQtec/PsCraft/blob/nain/Public/New-PsModule.ps1
  # .EXAMPLE
  #   New-PsModule -Verbose
  #   Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines
  # .OUTPUTS
  #   [PsModule]
  [CmdletBinding(SupportsShouldProcess, DefaultParametersetName = 'ByName')]
  param (
    # The Name Of your Module; note that it Should always match BaseName of its path.
    [Parameter(Position = 0, ParameterSetName = 'ByName')]
    [ValidateNotNullOrEmpty()]
    [string]$Name,

    [Parameter(Position = 0, ParameterSetName = 'ByConfig')]
    [ValidateNotNullOrEmpty()]
    [Array]$Configuration,

    # The FullPath Of your Module.
    [Parameter(Position = 1, ParameterSetName = '__AllParameterSets')]
    [ValidateNotNullOrEmpty()]
    [string]$Path = $(Get-Variable -Name ExecutionContext -ValueOnly).SessionState.Path.CurrentFileSystemLocation.ProviderPath
  )

  begin {
    $ModuleOb = $null
  }

  process {
    Write-Verbose "Creating Module ..."
    if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey("Path")) {
      $ModuleOb = [PsModule]::Create($Name, $path)
    } else {
      $ModuleOb = [PsModule]::Create($Name)
    }
    if ($PSCmdlet.ShouldProcess("", "", "Write Module folder Structure")) {
      $ModuleOb.Save()
    }
  }

  end {
    Write-Verbose "Done"
    return $ModuleOb
  }
}