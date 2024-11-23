using module Private/PsCraft.ModuleManager

# .SYNOPSIS
#  PsCraft: the giga-chad module builder and manager.
# .EXAMPLE
#  [PsModule]$module = New-PsModule "MyModule"   # Creates a new module named "MyModule" in $pwd
#  $builder = [PsCraft]::new($module.Path)
class PsCraft : ModuleManager {
  static [PsObject] $LocalizedData = (Read-ModuleData)
  static [IO.FileInfo] InstallPsGalleryModule([string]$moduleName) {
    return [PsCraft]::InstallPsGalleryModule($moduleName, 'latest', $false)
  }
  static [IO.FileInfo] InstallPsGalleryModule([string]$moduleName, [string]$Version, [bool]$UpdateOnly) {
    # .SYNOPSIS
    #  This method is like install-Module but it installs a PowerShell module no matter what.
    # .DESCRIPTION
    #  Even on systems that seem to not have a broken PowerShellGet.
    $Module_Path = ''; $IsValidversion = ($Version -as 'version') -is [version] -or $Version -eq 'latest'
    if (!$IsValidversion) { throw [System.ArgumentException]::New('Please Provide a valid version string') }
    $IsValidName = $moduleName -match '^[a-zA-Z0-9_.-]+$'
    if (!$IsValidName) { throw [System.ArgumentException]::New('Please Provide a valid module name') }
    # Try Using normal Installation
    try {
      if ($UpdateOnly) {
        [void][PsCraft]::UpdateModule($moduleName, $Version)
      } else {
        [void][PsCraft]::InstallModule($moduleName, $Version)
      }
      $Module_Path = ([PsCraft]::FindLocalPsModule($moduleName)).Psd1 | Split-Path -ErrorAction Stop
    } catch {
      $Module_Path = [PsCraft]::ManuallyInstallModule($moduleName, $Version)
    }
    return $Module_Path
  }
  static [LocalPsModule[]] Search([string]$Name) {
    [ValidateNotNullOrWhiteSpace()][string]$Name = $Name
    $res = @(); $AvailModls = Get-Module -ListAvailable -Name $Name -Verbose:$false -ErrorAction Ignore
    if ($null -ne $AvailModls) {
      foreach ($m in ($AvailModls.ModuleBase -as [string[]])) {
        if ($null -eq $m) {
          $res += [PsCraft]::FindLocalPsModule($Name, 'LocalMachine', $null); continue
        }
        if ([IO.Directory]::Exists($m)) {
          $res += [PsCraft]::FindLocalPsModule($Name, [IO.DirectoryInfo]::New($m))
        }
      }
    }
    return $res
  }
}

# Types that will be available to users when they import the module.
$typestoExport = @(
  [moduleManager],
  [LocalPsModule],
  [PsModule],
  [PsCraft]
)
$TypeAcceleratorsClass = [PsObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
foreach ($Type in $typestoExport) {
  if ($Type.FullName -in $TypeAcceleratorsClass::Get.Keys) {
    $Message = @(
      "Unable to register type accelerator '$($Type.FullName)'"
      'Accelerator already exists.'
    ) -join ' - '

    throw [System.Management.Automation.ErrorRecord]::new(
      [System.InvalidOperationException]::new($Message),
      'TypeAcceleratorAlreadyExists',
      [System.Management.Automation.ErrorCategory]::InvalidOperation,
      $Type.FullName
    )
  }
}
# Add type accelerators for every exportable type.
foreach ($Type in $typestoExport) {
  $TypeAcceleratorsClass::Add($Type.FullName, $Type)
}
# Remove type accelerators when the module is removed.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
  foreach ($Type in $typestoExport) {
    $TypeAcceleratorsClass::Remove($Type.FullName)
  }
}.GetNewClosure();

$scripts = @();
$Public = Get-ChildItem "$PSScriptRoot/Public" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += Get-ChildItem "$PSScriptRoot/Private" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += $Public

foreach ($file in $scripts) {
  Try {
    if ([string]::IsNullOrWhiteSpace($file.fullname)) { continue }
    . "$($file.fullname)"
  } Catch {
    Write-Warning "Failed to import function $($file.BaseName): $_"
    $host.UI.WriteErrorLine($_)
  }
}

$Param = @{
  Function = $Public.BaseName
  Cmdlet   = '*'
  Alias    = '*'
}
Export-ModuleMember @Param