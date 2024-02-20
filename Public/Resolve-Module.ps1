function Resolve-Module {
    # .DESCRIPTION
    #   Gets latest module version from PSGallery and installs the update if local module is out of date.
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias('Name')]
        [string[]]$Names,
        [switch]$UpdateModule
    )
    process {
        foreach ($moduleName in $Names) {
            Write-Host "`nResolve dependency Module [$moduleName]" -ForegroundColor Magenta
            $Local_ModuleVersion = Get-LatestModuleVersion -Name $moduleName -Source LocalMachine
            $Latest_ModuleVerion = Get-LatestModuleVersion -Name $moduleName -Source PsGallery
            if (!$Latest_ModuleVerion -or $Latest_ModuleVerion -eq ([version]::New())) {
                $Error_params = @{
                    ExceptionName    = 'System.Data.OperationAbortedException'
                    ExceptionMessage = "Resolve-Module: Get-LatestModuleVersion: Failed to find latest module version for '$moduleName'."
                    ErrorId          = 'CouldNotFindModule'
                    CallerPSCmdlet   = $PSCmdlet
                    ErrorCategory    = 'OperationStoped'
                }
                Write-TerminatingError @Error_params
            }
            if (!$Local_ModuleVersion -or $Local_ModuleVersion -eq ([version]::New())) {
                Write-Verbose -Message "Install $moduleName ..."
                Install-PsGalleryModule -Name $moduleName
            } elseif ($Local_ModuleVersion -lt $Latest_ModuleVerion -and $UpdateModule.IsPresent) {
                Write-Verbose -Message "Update $moduleName from version $Local_ModuleVersion to version [$Latest_ModuleVerion] ..." -Verbose
                Install-PsGalleryModule -Name $moduleName -Version $Latest_ModuleVerion -UpdateOnly
            } else {
                Write-Verbose -Message "Module $moduleName is already Installed and Up-to-date."
            }
            Write-Verbose -Message "Importing module $moduleName ..."
            Get-ModulePath -Name $moduleName | Import-Module -Verbose:$($PSCmdlet.MyInvocation.BoundParameters['verbose'] -eq $true) -Force:$($PSCmdlet.MyInvocation.BoundParameters['Force'] -eq $true)
        }
    }
}