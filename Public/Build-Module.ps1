function Build-Module {
  # .SYNOPSIS
  #     Module buildScript
  # .DESCRIPTION
  #     A custom Psake buildScript for any module that was created by PsCraft.
  # .LINK
  #     https://github.com/alainQtec/PsCraft/blob/main/public/Build-Module.ps1
  # .EXAMPLE
  #     Running Build-Module will only "Init, Compile & Import" the module; That's it, no tests.
  #     To run tests Use:
  #     Build-Module -Task Test
  #     This Will build the module, Import it and run tests using the ./Test-Module.ps1 script.
  # .EXAMPLE
  #     Build-Module -Task deploy
  #     Will build the module, test it and deploy it to PsGallery
  [cmdletbinding(DefaultParameterSetName = 'task')]
  param(
    [parameter(Position = 0, ParameterSetName = 'task')]
    [ValidateScript({
        $task_seq = [string[]]$_; $IsValid = $true
        $Tasks = @('Init', 'Clean', 'Compile', 'Import', 'Test', 'Deploy')
        foreach ($name in $task_seq) {
          $IsValid = $IsValid -and ($name -in $Tasks)
        }
        if ($IsValid) {
          return $true
        } else {
          throw [System.ArgumentException]::new('Task', "ValidSet: $($Tasks -join ', ').")
        }
      }
    )][ValidateNotNullOrEmpty()]
    [string[]]$Task = @('Init', 'Clean', 'Compile', 'Import'),

    [parameter(ParameterSetName = 'help')]
    [Alias('-?')]
    [switch]$Help
  )

  Begin {
    #Requires -RunAsAdministrator
    if ($null -ne ${env:=::}) { Throw 'Please Run this script as Administrator' }
    if ($Help) { return $Builder.WriteHelp() }
    $ModuleName = [Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName')
  }
  Process {
    $Builder = New-Object -TypeName PsCraft
    if ($PSBoundParameters.ContainsKey('Verbose')) {
      $Builder::Useverbose = $PSBoundParameters['Verbose']
    }
    [void]$Builder.Invoke()
    $ModulePath = [PsCraft]::PublishtoLocalPsRepo($ModuleName)
    Install-Module $ModuleName -Repository LocalPSRepo
    if ($Task -contains 'Import' -and $psake.build_success) {
      [void][PsCraft]::WriteHeading("Import $ModuleName to local scope")
      Write-BuildLog -Command "Import-Module $ModuleName"; Import-Module $ModuleName
      # or: Import-Module $([IO.Path]::Combine($Project_Path, $ModuleName)) -Verbose
    } else {
      Uninstall-Module $ModuleName -ErrorAction Ignore
      Find-InstalledModule $ModulePath | ForEach-Object { $_.Delete() }
    }
  }
  end {
    [PsCraft]::ShowEnvSummary("Build finished")
    Clear-BuildEnvironment -Id $env:RUN_ID -Force
    exit ([int](!$psake.build_success))
  }
}