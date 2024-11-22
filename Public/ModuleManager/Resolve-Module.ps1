function Resolve-Module {
  # .DESCRIPTION
  #   Gets latest module version from PSGallery and installs the update if local module is out of date.
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [Alias('n', 'Name')]
    [string[]]$Names,

    [Parameter(Mandatory = $false)]
    [Alias('u')]
    [switch]$UpdateModule,

    [Parameter(Mandatory = $false)]
    [Alias('ro')]
    [switch]$removeold
  )
  begin {
    [bool]$useverbose = $PSCmdlet.MyInvocation.BoundParameters['verbose'] -eq $true
    [bool]$useforce = $PSCmdlet.MyInvocation.BoundParameters['Force'] -eq $true
  }
  process {
    foreach ($moduleName in $Names) {
      Write-Host "`nResolve: Module [$moduleName]" -f Magenta
      $Local_ModuleVersion = Get-LatestModuleVersion -Name $moduleName -Source LocalMachine
      $Latest_ModuleVerion = Get-LatestModuleVersion -Name $moduleName -Source PsGallery
      if (!$Latest_ModuleVerion -or $Latest_ModuleVerion -eq ([version]::New())) {
        $Error_params = @{
          ExceptionName    = 'System.Data.OperationAbortedException'
          ExceptionMessage = "ResolveModule.Get-LatestModuleVersion: Failed to find latest module version for '$moduleName'."
          ErrorId          = 'CouldNotFindModule'
          Caller           = $PSCmdlet
          ErrorCategory    = 'OperationStoped'
        }
        Write-TerminatingError @Error_params
      }
      if (!$Local_ModuleVersion -or $Local_ModuleVersion -eq ([version]::New())) {
        Write-Verbose -Message "Install $moduleName ..."
        [Pscraft]::InstallPsGalleryModule($moduleName)
      } elseif ($Local_ModuleVersion -lt $Latest_ModuleVerion -and $UpdateModule.IsPresent) {
        Write-Verbose -Message "Update $moduleName from version $Local_ModuleVersion to version [$Latest_ModuleVerion] ..." -Verbose
        [Pscraft]::InstallPsGalleryModule($moduleName, $Latest_ModuleVerion, $true)
      } else {
        Write-Host "Resolve: Module $moduleName is already Installed and Up-to-date." -f Green
      }
      if ($removeold.IsPresent) {
        # TODO: remove duplicates and old versions using Clear-ModuleVersions
        if (![Pscraft]::removeold($moduleName)) {
          Write-Error -Exception System.Management.Automation.ItemNotFoundException -Message "Can't find Module $moduleName" -ErrorId "ModuleNotFound" -Category "ObjectNotFound"
        }
      }
      Write-Verbose -Message "Importing module $moduleName ..."
      Find-InstalledModule $moduleName | Import-Module -Verbose:$useverbose -Force:$useforce
    }
  }
}