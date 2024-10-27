using namespace System.IO
using module Private/PsCraft.GuiBuilder
using module Private/PsCraft.CodeSigner
using module Private/PsCraft.ModuleManager
using namespace System.Collections.Generic
using namespace system.management.automation
using namespace System.Collections.ObjectModel
using namespace System.Management.Automation.Language

#region    Classes
# .SYNOPSIS
#  PsCraft: the giga-chad module builder and manager.
# .EXAMPLE
#  [PsModule]$module = New-PsModule "MyModule"   # Creates a new module named "MyModule" in $pwd
#  $builder = [PsCraft]::new($module.Path)
class PsCraft : ModuleManager {
  static [PsObject]$LocalizedData = (Get-PsCraftData)
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
        if ([Directory]::Exists($m)) {
          $res += [PsCraft]::FindLocalPsModule($Name, [DirectoryInfo]::New($m))
        }
      }
    }
    return $res
  }
}
#endregion Classes

#region    functions
function script:Get-PsCraftData {
  # .Example
  # see result by running: [PsCraft]::LocalizedData
  [CmdletBinding()]
  [OutputType([PsObject])]
  param (
    [Parameter(Position = 0, Mandatory = $false, ValueFromPipeline = $true)]
    [ValidateNotNullOrWhiteSpace()]
    [string]$Path,

    [Parameter(Position = 1, Mandatory = $false)]
    [AllowNull()][Alias('Property')]
    [string]$PropertyName = $null
  )
  begin {
    if (!$PSBoundParameters.ContainsKey("Path")) {
      # [void][Directory]::SetCurrentDirectory($PSScriptRoot)
      $CultureName = [System.Threading.Thread]::CurrentThread.CurrentCulture.Name
      $Path = [IO.Path]::Combine($PSScriptRoot, $CultureName, 'PsCraft.strings.psd1')
    }
  }
  process {
    if ([string]::IsNullOrWhiteSpace($PropertyName)) {
      $null = Get-Item -Path $Path -ErrorAction Stop
      $data = New-Object PsObject; $text = [IO.File]::ReadAllText("$Path")
      $data = [scriptblock]::Create("$text").Invoke()
      return $data
    }
    $Tokens = $Null; $ParseErrors = $Null
    # search the Manifest root properties, and also the nested hashtable properties.
    if ([IO.Path]::GetExtension($_) -ne ".psd1") { throw "Path must point to a .psd1 file" }
    if (!(Test-Path $Path)) {
      $Error_params = @{
        ExceptionName    = "ItemNotFoundException"
        ExceptionMessage = "Can't find file $Path"
        ErrorId          = "PathNotFound,Metadata\Import-Metadata"
        Caller           = $PSCmdlet
        ErrorCategory    = "ObjectNotFound"
      }
      Write-TerminatingError @Error_params
    }
    $AST = [Parser]::ParseFile($Path, [ref]$Tokens, [ref]$ParseErrors)
    $KeyValue = $Ast.EndBlock.Statements
    $KeyValue = @([PsCraft]::FindHashKeyValue($PropertyName, $KeyValue))
    if ($KeyValue.Count -eq 0) {
      $Error_params = @{
        ExceptionName    = "ItemNotFoundException"
        ExceptionMessage = "Can't find '$PropertyName' in $Path"
        ErrorId          = "PropertyNotFound,Metadata\Get-Metadata"
        Caller           = $PSCmdlet
        ErrorCategory    = "ObjectNotFound"
      }
      Write-TerminatingError @Error_params
    }
    if ($KeyValue.Count -gt 1) {
      $SingleKey = @($KeyValue | Where-Object { $_.HashKeyPath -eq $PropertyName })
      if ($SingleKey.Count -gt 1) {
        $Error_params = @{
          ExceptionName    = "System.Reflection.AmbiguousMatchException"
          ExceptionMessage = "Found more than one '$PropertyName' in $Path. Please specify a dotted path instead. Matching paths include: '{0}'" -f ($KeyValue.HashKeyPath -join "', '")
          ErrorId          = "AmbiguousMatch,Metadata\Get-Metadata"
          Caller           = $PSCmdlet
          ErrorCategory    = "InvalidArgument"
        }
        Write-TerminatingError @Error_params
      } else {
        $KeyValue = $SingleKey
      }
    }
    $KeyValue = $KeyValue[0]
    # $KeyValue.SafeGetValue()
    return $KeyValue
  }
}
#endregion functions

# Types that will be available to users when they import the module.
$typestoExport = @(
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

$Private = Get-ChildItem ([IO.Path]::Combine($PSScriptRoot, 'Private')) -Filter "*.ps1" -ErrorAction SilentlyContinue
$Public = Get-ChildItem ([IO.Path]::Combine($PSScriptRoot, 'Public')) -Filter "*.ps1" -ErrorAction SilentlyContinue
foreach ($file in $($Public + $Private)) {
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
Export-ModuleMember @Param -Verbose