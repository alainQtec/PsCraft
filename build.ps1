<#
.SYNOPSIS
    PsCraft buildScript v0.1.1
.DESCRIPTION
    A custom Psake buildScript for the module PsCraft.
.LINK
    https://github.com/alainQtec/PsCraft/blob/main/build.ps1
.EXAMPLE
    Running ./build.ps1 will only "Init, Compile & Import" the module; That's it, no tests.
    To run tests Use:
    ./build.ps1 -Task Test
    This Will build the module, Import it and run tests using the ./Test-Module.ps1 script.
.EXAMPLE
    ./build.ps1 -Task deploy
    Will build the module, test it and deploy it to PsGallery
#>
[cmdletbinding(DefaultParameterSetName = 'task')]
param(
  [parameter(Position = 0, ParameterSetName = 'task')]
  [ValidateScript({
      $task_seq = [string[]]$_; $IsValid = $true
      $Tasks = @('Init', 'Clean', 'Compile', 'Import', 'Test', 'Deploy')
      foreach ($name in $task_seq) {
        $IsValid = $IsValid -and ($name -in $Tasks)
      }
      if ($IsValid) {
        return $true
      } else {
        throw [System.ArgumentException]::new('Task', "ValidSet: $($Tasks -join ', ').")
      }
    }
  )][ValidateNotNullOrEmpty()][Alias('t')]
  [string[]]$Task = @('Init', 'Clean', 'Compile', 'Import'),

  # Module buildRoot
  [Parameter(Mandatory = $false, ParameterSetName = 'task')]
  [ValidateScript({
      if (Test-Path -Path $_ -PathType Container -ErrorAction Ignore) {
        return $true
      } else {
        throw [System.ArgumentException]::new('Path', "Path: $_ is not a valid directory.")
      }
    })][Alias('p')]
  [string]$Path = (Get-Item -Path "." -Verbose:$false).FullName,

  [Parameter(Mandatory = $false, ParameterSetName = 'task')]
  [Alias('u')][ValidateNotNullOrWhiteSpace()]
  [string]$GitHubUsername,

  [parameter(ParameterSetName = 'help')]
  [Alias('h', '-help')]
  [switch]$Help
)
Begin {
  Import-Module ./PsCraft.psm1 -Verbose:$false
}
process {
  Build-Module @PSBoundParameters
}