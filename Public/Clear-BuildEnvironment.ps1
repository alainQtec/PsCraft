function Clear-BuildEnvironment {
  [CmdletBinding()]
  Param (
    [Parameter(Position = 0)]
    [ValidatePattern('\w*')]
    [ValidateNotNullOrEmpty()]
    [Alias('Id')]
    [string]$buildId,
    [switch]$Force
  )

  process {
    [void][ModuleHandler]::WriteHeading("CleanUp: Uninstall the test module, and delete the LocalPSRepo")
    if (![string]::IsNullOrWhiteSpace($buildId)) {
      [void][ModuleHandler]::WriteHeading("CleanUp: Remove Environment Variables")
      $OldEnvNames = [Environment]::GetEnvironmentVariables().Keys | Where-Object { $_ -like "$buildId*" }
      if ($OldEnvNames.Count -gt 0) {
        foreach ($Name in $OldEnvNames) {
          Write-BuildLog "Remove env variable $Name"
          [Environment]::SetEnvironmentVariable($Name, $null)
        }
        [Console]::WriteLine()
      } else {
        Write-BuildLog "No old Env variables to remove; Move on ...`n"
      }
    } else {
      Write-Warning "Invalid RUN_ID! Skipping ...`n"
    }
    if ([ModuleHandler]::LocalPSRepo.Exists) {
      Write-BuildLog "Remove 'local' repository"
      if ($null -ne (Get-PSRepository -Name 'LocalPSRepo' -ErrorAction Ignore)) {
        Invoke-Command -ScriptBlock ([ScriptBlock]::Create("Unregister-PSRepository -Name 'LocalPSRepo' -Verbose -ErrorAction Ignore"))
      }; [ModuleHandler]::LocalPSRepo.FullName | Remove-Item -Force -Recurse -ErrorAction Ignore
    }
    if ($Force) {
      [Environment]::SetEnvironmentVariable('RUN_ID', $null)
    }
  }
  end {
    # [PSModuleInfo]::ClearAppDomainLevelModulePathCache()
    if (![bool][int]$env:IsAC) {
      # ......
    }
  }
}