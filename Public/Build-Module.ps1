function Build-Module {
  # .SYNOPSIS
  #     ModuleHandler buildScript
  # .DESCRIPTION
  #     A custom Psake buildScript for the module ModuleHandler
  # .LINK
  #     https://github.com/alainQtec/ModuleHandler/blob/main/public/Build-Module.ps1
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
    $ModuleName = [Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName')
    $Builder = [ModuleHandler]::New()
    if ($PSBoundParameters.ContainsKey('Verbose')) {
      $Builder::Useverbose = $PSBoundParameters['Verbose']
    }
  }
  Process {
    if ($Help) { return $Builder.WriteHelp() }
    [void]$Builder.Invoke()
    $ModulePath = [ModuleHandler]::PublishtoLocalPsRepo($ModuleName)
    Install-Module $ModuleName -Repository LocalPSRepo
    if ($Task -contains 'Import' -and $psake.build_success) {
      [void][ModuleHandler]::WriteHeading("Import $ModuleName to local scope")
      Invoke-CommandWithLog { Import-Module $ModuleName }
      # or: Invoke-CommandWithLog { Import-Module $([IO.Path]::Combine($Project_Path, $ModuleName)) -Verbose }
    } else {
      Uninstall-Module $ModuleName -ErrorAction Ignore
      [LocalPsModule]::Find($ModulePath).Path | Remove-Item -Recurse -Force -ErrorAction Ignore
    }
  }
  end {
    [ModuleHandler]::ShowEnvSummary("Build finished")
    Clear-BuildEnvironment -Id $env:RUN_ID -Force
    exit ([int](!$psake.build_success))
  }
}