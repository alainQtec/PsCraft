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
    [string]$Path = '.'
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
          &tree -a $Module.Path.FullName
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