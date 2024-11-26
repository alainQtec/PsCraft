<#
.SYNOPSIS
    PsCraft buildScript v0.1.5
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
  [parameter(Position = 0, ParameterSetName = 'task', HelpMessage = 'Task Sequence. use --help to learn')]
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

  [Parameter(Mandatory = $false, ParameterSetName = 'task', HelpMessage = 'Module buildRoot')]
  [ValidateScript({
      if (Test-Path -Path $_ -PathType Container -ea Ignore) {
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

  [parameter(ParameterSetName = 'task')]
  [switch]$UseSelf,

  [parameter(ParameterSetName = 'help')]
  [Alias('h', '-help')]
  [switch]$Help
)

begin {
  $defaultBuildRequirements = @("cliHelper.env", "cliHelper.core", "PsCraft") # ie: For this ./build.ps1 to work.
  function Register-PackageFeed ([switch]$ForceBootstrap) {
    if ($null -eq (Get-PSRepository -Name PSGallery -ea Ignore)) {
      Unregister-PSRepository -Name PSGallery -Verbose:$false -ea Ignore
      Register-PSRepository -Default -InstallationPolicy Trusted
    }
    if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
      Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -Verbose:$false
    }
    Get-PackageProvider -Name Nuget -ForceBootstrap:($ForceBootstrap.IsPresent) -Verbose:$false
    if (!(Get-PackageProvider -Name Nuget)) { Install-PackageProvider -Name NuGet -Force }
  }
  function Import-BuildRequirements ([string[]]$req, [string[]]$defaults, [string]$psd) {
    if ($null -eq $req) { $req = @() }
    $defaults.ForEach({ !$req.Contains($_) ? ($req += $_) : $null }) | Out-Null
    Write-Host "Resolve ./build.ps1 requirements: [$($req -join ', ')]" -f Green
    $req.ForEach({ Install-Module $_ -Verbose:$false; Write-Host " [+] Installed module $_" -f Green })
    $psds = (Get-Module -Name $req -ListAvailable -Verbose:$false).Path | Sort-Object -Unique { Split-Path $_ -Leaf }
    if ($UseSelf.IsPresent) { ([IO.File]::Exists($psd) -and [IO.File]::Exists([IO.Path]::Combine($path, "$($path | Split-Path -Leaf).psm1"))) ? ($psds += $psd) : $null }
    $psds | Import-Module -Verbose:$false -ea Stop
  }
}
process {
  if ($PSCmdlet.ParameterSetName -eq 'help') { Get-Help $MyInvocation.MyCommand.Source -Full | Out-String | Write-Host -f Green; return }
  Register-PackageFeed -ForceBootstrap
  $psd1 = [IO.Path]::Combine($Path, "$([IO.DirectoryInfo]::new($Path).BaseName).psd1")
  $data = [PsObject]([scriptblock]::Create("$([IO.File]::ReadAllText($psd1))").Invoke() | Select-Object *)
  Import-BuildRequirements -req $data.RequiredModules -defaults $defaultBuildRequirements -psd $psd1
  Build-Module -Task $Task -Path $Path -gitUser $gitUser -Import:$Import
}