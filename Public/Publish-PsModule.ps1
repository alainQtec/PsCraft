function Publish-PsModule {
  # .SYNOPSIS
  #   Publish PSModule To Local or Remote Repo
  # .DESCRIPTION
  #   A longer description of the function, its purpose, common use cases, etc.
  # .NOTES
  #   Information or caveats about the function e.g. 'This function is not supported in Linux'
  # .LINK
  #   Specify a URI to a help page, this will show when Get-Help -Online is used.
  # .EXAMPLE
  #   Publish-PsModule -Verbose
  #   Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines
  [CmdletBinding(SupportsShouldProcess)]
  param (
    # Parameter help description
    [Parameter(Position = 0, ParameterSetName = 'ByName')]
    [Alias('ModuleName')]
    [string]$Name,

    [Parameter(Position = 1, ParameterSetName = '__AllParameterSets')]
    [string]$ModulePath,

    [Parameter(Position = 2, ParameterSetName = '__AllParameterSets')]
    [Alias('repoDir')]
    [string]$RepoPath
  )

  process {
    $ModuleOb = [PsModule]::Create($Name, $ModulePath)
    if ($PSCmdlet.ShouldProcess('', '', "Publishing")) {
      $ModuleOb.Publish()
    }
  }

  end {
    Write-Verbose "Done"
    return $ModuleOb
  }
}