using namespace System
using namespace System.IO
using namespace System.Management.Automation
function Resolve-Module {
  # .DESCRIPTION
  #   Gets latest module version from PSGallery and installs the update if local module is out of date.
  [CmdletBinding()][OutputType([Object[]], [IO.FileInfo[]])]
  param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [Alias('n', 'Name')]
    [string[]]$Names,

    [Parameter(Mandatory = $false)]
    [Alias('u')]
    [switch]$Update,

    [Parameter(Mandatory = $false)]
    [Alias('ro')]
    [switch]$removeold
  )
  begin {
    [bool]$useverbose = $PSCmdlet.MyInvocation.BoundParameters['verbose'] -eq $true
    [bool]$useforce = $PSCmdlet.MyInvocation.BoundParameters['Force'] -eq $true
    $res = @()
  }
  process {
    $Names | ForEach-Object {
      Write-Host "Resolve: Module [$_] " -f Magenta -NoNewline
      $Local_ModuleVersion = Get-LatestModuleVersion -Name $_ -Source LocalMachine
      $Latest_ModuleVerion = Get-LatestModuleVersion -Name $_ -Source PsGallery -ErrorAction Ignore
      if (!$Latest_ModuleVerion -or $Latest_ModuleVerion -eq ([version]::New())) {
        $exception = [System.Management.Automation.ItemNotFoundException]::new("ResolveModule.Get-LatestModuleVersion: Failed to find latest module version for '$_'.")
        $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'CouldNotFindModule', 'OperationStopped', $_)
        if ((Test-Connection -TargetName www.powershellgallery.com -Traceroute).Reply.Status -Contains "TimeExceeded") {
          $PSCmdlet.WriteError($errorRecord)
        } else {
          $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
      }
      if (!$Local_ModuleVersion -or $Local_ModuleVersion -eq ([version]::New())) {
        Write-Verbose -Message "Install $_ ..."
        $res += [Pscraft]::InstallPsGalleryModule($_)
      } elseif ($Local_ModuleVersion -lt $Latest_ModuleVerion -and $UpdateModule.IsPresent) {
        Write-Verbose -Message "Update $_ from version $Local_ModuleVersion to version [$Latest_ModuleVerion] ..." -Verbose
        $res += [Pscraft]::InstallPsGalleryModule($_, $Latest_ModuleVerion, $true)
      } else {
        Write-Host ">> " -NoNewline
        Write-Host "$_ is already Installed and Up-to-date." -f Green
      }
      if ($removeold.IsPresent) {
        # TODO: remove duplicates and old versions using Clear-ModuleVersions
        if (![Pscraft]::removeold($_)) {
          Write-Error -Exception System.Management.Automation.ItemNotFoundException -Message "Can't find Module $_" -ErrorId "ModuleNotFound" -Category "ObjectNotFound"
        }
      }
      Write-Verbose -Message "Importing module $_ ..."
      (Find-InstalledModule $_).Path | Import-Module -Verbose:$useverbose -Force:$useforce
    }
  }
  end {
    return $res
  }
}