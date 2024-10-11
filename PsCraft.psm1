using namespace System.IO
using module Private/PsCraft.GuiBuilder
using module Private/PsCraft.CodeSigner
using module Private/PsCraft.ModuleManager
using namespace System.Collections.Generic
using namespace system.management.automation
using namespace System.Management.Automation.Language

#region    Classes
class PsCraft : ModuleManager {
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
  static [ParseResult] ParseCode($Code) {
    # Parses the given code and returns an object with the AST, Tokens and ParseErrors
    Write-Debug "    ENTER: ConvertToAst $Code"
    $ParseErrors = $null
    $Tokens = $null
    if ($Code | Test-Path -ErrorAction SilentlyContinue) {
      Write-Debug "      Parse Code as Path"
      $AST = [System.Management.Automation.Language.Parser]::ParseFile(($Code | Convert-Path), [ref]$Tokens, [ref]$ParseErrors)
    } elseif ($Code -is [System.Management.Automation.FunctionInfo]) {
      Write-Debug "      Parse Code as Function"
      $String = "function $($Code.Name) {`n$($Code.Definition)`n}"
      $AST = [System.Management.Automation.Language.Parser]::ParseInput($String, [ref]$Tokens, [ref]$ParseErrors)
    } else {
      Write-Debug "      Parse Code as String"
      $AST = [System.Management.Automation.Language.Parser]::ParseInput([String]$Code, [ref]$Tokens, [ref]$ParseErrors)
    }
    return [ParseResult]::new($ParseErrors, $Tokens, $AST)
  }
  static [void] CreateModuleFolderStructure([PSmodule]$Module) {
    #TODO: Do stuff before saving the module. (fs preparation & cheking requirements)
    $Module.Save()
  }
  static [HashSet[String]] GetCommandAlias([System.Management.Automation.Language.Ast]$Ast) {
    $Visitor = [AliasVisitor]::new(); $Ast.Visit($Visitor)
    return $Visitor.Aliases
  }
}

#endregion Classes

$CurrentCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture.Name
$script:localizedData = if ($null -ne (Get-Command Get-LocalizedData -ErrorAction SilentlyContinue)) {
  Get-LocalizedData -DefaultUICulture $CurrentCulture
} else {
  $dataFile = [FileInfo]::new([IO.Path]::Combine((Get-Location), $CurrentCulture, 'PsCraft.strings.psd1'))
  if (!$dataFile.Exists) { throw [FileNotFoundException]::new('Unable to find the LocalizedData file.', 'PsCraft.strings.psd1') }
  [scriptblock]::Create("$([IO.File]::ReadAllText($dataFile))").Invoke()
}

# Types that will be available to users when they import the module.
$typestoExport = @(
  [LocalPsModule],
  [PsModule],
  [PsCraft]
)
$TypeAcceleratorsClass = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
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
  Variable = 'localizedData'
  Cmdlet   = '*'
  Alias    = '*'
}
Export-ModuleMember @Param -Verbose