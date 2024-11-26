<#
.SYNOPSIS
    PsCraft buildScript v0.1.3
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
      $Tasks = @('Init', 'Clean', 'Compile', 'Test', 'Deploy')
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
  [string[]]$Task = @('Init', 'Clean', 'Compile'),

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
  [string]$gitUser = { return $Iswindows ? $env:UserName : $env:USER }.Invoke(),

  [parameter(ParameterSetName = 'task')]
  [Alias('i')]
  [switch]$Import,

  [parameter(ParameterSetName = 'help')]
  [Alias('h', '-help')]
  [switch]$Help
)

begin {
  function Register-PackageFeed ([switch]$ForceBootstrap) {
    if ($null -eq (Get-PSRepository -Name PSGallery -ErrorAction Ignore)) {
      Unregister-PSRepository -Name PSGallery -Verbose:$false -ErrorAction Ignore
      Register-PSRepository -Default -InstallationPolicy Trusted
    }
    if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
      Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -Verbose:$false
    }
    Get-PackageProvider -Name Nuget -ForceBootstrap:($ForceBootstrap.IsPresent) -Verbose:$false
    if (!(Get-PackageProvider -Name Nuget)) {
      Install-PackageProvider -Name NuGet -Force | Out-Null
    }
  }
  $self = [IO.Path]::Combine($Path, "PsCraft.psm1")
}
process {
  Register-PackageFeed -ForceBootstrap
  if ([IO.File]::Exists($self)) {
    Write-Host "<< Import .psm1" -f Green # to test latest version/features
    Import-Module $self -Verbose:$false
  } else {
    if (!(Get-Module PsCraft -ListAvailable -ErrorAction Ignore)) { Install-Module PsCraft -Verbose:$false };
    $(Get-InstalledModule PsCraft -ErrorAction Ignore).InstalledLocation | Split-Path | Import-Module -Verbose:$false
  }
  if ($PSCmdlet.ParameterSetName -eq 'help') {
    Build-Module -Help
  } else {
    Build-Module -Task $Task -Path $Path -gitUser $gitUser -Import:$Import
  }
}