using namespace System
using namespace System.IO
using namespace System.Management.Automation
<#
.SYNOPSIS
  PsCraft buildScript v0.2.0
.DESCRIPTION
  A custom Psake buildScript for the module PsCraft.
.LINK
  https://github.com/alainQtec/PsCraft/blob/main/build.ps1
.EXAMPLE
  Running ./build.ps1 will only "Init, Compile & Import" the module; That's it, no tests.
  To run tests Use:
  ./build.ps1
  This Will build the module, Import it and run tests using the ./Test-Module.ps1 script.
.EXAMPLE
  ./build.ps1 -Task deploy
  Will build the module, test it and deploy it to PsGallery
#>
[cmdletbinding(DefaultParameterSetName = 'task')]
param(
  [parameter(Mandatory = $false, Position = 0, ParameterSetName = 'task')]
  [ValidateScript({
      $task_seq = [string[]]$_; $IsValid = $true
      $Tasks = @('Clean', 'Compile', 'Test', 'Deploy')
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
  [string[]]$Task = 'Test',

  # Module buildRoot
  [Parameter(Mandatory = $false, Position = 1, ParameterSetName = 'task')]
  [ValidateScript({
      if (Test-Path -Path $_ -PathType Container -ea Ignore) {
        return $true
      } else {
        throw [System.ArgumentException]::new('Path', "Path: $_ is not a valid directory.")
      }
    })][Alias('p')]
  [string]$Path = (Resolve-Path .).Path,

  [Parameter(Mandatory = $false, ParameterSetName = 'task')]
  [string[]]$RequiredModules = @(),

  [parameter(ParameterSetName = 'task')]
  [Alias('i')]
  [switch]$Import,

  [parameter(ParameterSetName = 'help')]
  [Alias('h', '-help')]
  [switch]$Help
)

begin {
  if ($PSCmdlet.ParameterSetName -eq 'help') { Get-Help $MyInvocation.MyCommand.Source -Full | Out-String | Write-Host -f Green; return }
  $req = Invoke-WebRequest -Method Get -Uri https://raw.githubusercontent.com/alainQtec/PsCraft/refs/heads/main/Public/Build-Module.ps1 -SkipHttpErrorCheck -Verbose:$false
  if ($req.StatusCode -ne 200) { throw "Failed to download Build-Module.ps1" }
  $t = New-Item $([IO.Path]::GetTempFileName().Replace('.tmp', '.ps1')) -Verbose:$false; Set-Content -Path $t.FullName -Value $req.Content; . $t.FullName; Remove-Item $t.FullName -Verbose:$false
}
process {
  Build-Module -Task $Task -Path $Path -Import:$Import
}