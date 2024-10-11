using namespace System.IO
using namespace System.Threading
using namespace System.ComponentModel
using namespace System.Collections.Generic
using namespace System.Management.Automation
using namespace System.Collections.ObjectModel
using namespace System.Runtime.InteropServices
using namespace System.Management.Automation.Language

enum SaveOptions {
  AcceptAllChangesAfterSave # After changes are saved, we resets change tracking.
  DetectChangesBeforeSave # Before changes are saved, the DetectChanges method is called to synchronize Objects.
  None # Changes are saved without the DetectChanges or the AcceptAllChangesAfterSave methods being called. This can be equivalent of Force, as it can ovewrite objects.
}

#region    Classes

# .SYNOPSIS
# ModuleManager Class
# .EXAMPLE
# $handler = [ModuleManager]::new("MyModule", "C:\Path\To\MyModule.psm1")
# if ($handler.TestModulePath()) {
#    $handler.ImportModule()
#    $functions = $handler.ListExportedFunctions()
#    Write-Host "Exported functions: $functions"
#  } else {
#    Write-Host "Module not found at specified path"
#  }
#  TODO: Add more robust example. (This shit can do way much more.)

class ModuleManager : Microsoft.PowerShell.Commands.ModuleCmdletBase {
  [List[string]]$TaskList
  [List[string]]$RequiredModules
  [ValidateNotNullOrWhiteSpace()][string]$ModuleName
  [ValidateNotNullOrWhiteSpace()][string]$BuildOutputPath # $RootPath/BouldOutput/$ModuleName
  [ValidateNotNullOrEmpty()][DirectoryInfo]$RootPath # Module Project root
  [ValidateNotNullOrEmpty()][DirectoryInfo]$TestsPath
  [ValidateNotNullOrEmpty()][version]$ModuleVersion
  [ValidateNotNullOrEmpty()][FileInfo]$dataFile # ..strings.psd1
  [ValidateNotNullOrEmpty()][FileInfo]$buildFile
  static [DirectoryInfo]$LocalPSRepo
  static [Collection[psobject]]$LocalizedData
  static [PSCmdlet]$CallerCmdlet
  static [bool]$Useverbose

  ModuleManager() {}
  ModuleManager([string]$RootPath) { [void][ModuleManager]::_Create($RootPath, $this) }
  static [ModuleManager] Create() { return [ModuleManager]::_Create($null, $null) }
  static [ModuleManager] Create([string]$RootPath) { return [ModuleManager]::_Create($RootPath, $null) }

  [bool] ImportModule([string]$path) {
    try {
      $m = Import-Module -Name $path -Force -PassThru
      if ($m) { $m.Psobject.Properties.Name.ForEach({ $this.$($_) = $m.$($_) }) }
      return $?
    } catch {
      Write-Error "Failed to import module: $_"
      return $false
    }
  }
  [void] RemoveModule() {
    Remove-Module -Name $this.Name -Force -ErrorAction SilentlyContinue
  }
  [void] BuildModule() {
    [void][ModuleManager]::ShowEnvSummary("Preparing build environment")
    $this.setBuildVariables()
    [Console]::WriteLine()
    $sc = {
      $script:DefaultParameterValues = @{
        '*-Module:Verbose'           = $false
        'Import-Module:ErrorAction'  = 'Stop'
        'Import-Module:Force'        = $true
        'Import-Module:Verbose'      = $false
        'Install-Module:ErrorAction' = 'Stop'
        'Install-Module:Scope'       = 'CurrentUser'
        'Install-Module:Verbose'     = $false
      }
    }
    Write-BuildLog -Command ($sc.ToString() -join "`n"); $sc.Invoke()
    [void][ModuleManager]::WriteHeading("Prepare package feeds")
    [Console]::WriteLine()
    if ($null -eq (Get-PSRepository -Name PSGallery -ErrorAction Ignore)) {
      Unregister-PSRepository -Name PSGallery -Verbose:$false -ErrorAction Ignore
      Register-PSRepository -Default -InstallationPolicy Trusted
    }
    if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
      Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -Verbose:$false
    }
    # if ((Get-Command dotnet -ErrorAction Ignore) -and ([bool](Get-Variable -Name IsWindows -ErrorAction Ignore) -and !$(Get-Variable IsWindows -ValueOnly))) {
    #     dotnet dev-certs https --trust
    # }
    Get-PackageProvider -Name Nuget -ForceBootstrap -Verbose:$false
    if (!(Get-PackageProvider -Name Nuget)) {
      Install-PackageProvider -Name NuGet -Force | Out-Null
    }
    $null = Import-PackageProvider -Name NuGet -Force
    foreach ($Name in @('PackageManagement', 'PowerShellGet')) {
      $(Get-Variable Host -ValueOnly).UI.WriteLine(); Resolve-Module -Name $Name -ro -u -Verbose:$script:DefaultParameterValues['*-Module:Verbose'] -ErrorAction Stop
    }
    $build_sys = [Environment]::GetEnvironmentVariable($env:RUN_ID + 'BuildSystem');
    $lastCommit = git log - 1 --pretty = % B
    [void][ModuleManager]::WriteHeading("Current build system is $build_sys")
    [void][ModuleManager]::WriteHeading("Finalizing build Prerequisites and Resolving dependencies ...")
    $IsVTs = $build_sys -eq 'VSTS' -or ($env:CI -eq "true" -and $env:GITHUB_RUN_ID)
    if ($IsVTs -and [ModuleManager]::TaskList.Contains('Deploy')) {
      $Psv = (Get-Variable PSVersionTable -ValueOnly).PSVersion
      $MSG = "Task is 'Deploy' and conditions for deployment are:`n" +
      "    + GitHub API key is not null       : $(![string]::IsNullOrWhiteSpace($env:GitHubPAT))`n" +
      "    + Current branch is main           : $(($env:GITHUB_REF -replace "refs/heads/") -eq 'main')`n" +
      "    + Source is not a pull request     : $($env:GITHUB_EVENT_NAME -ne "pull_request") [$env:GITHUB_EVENT_NAME]`n" +
      "    + Commit message matches '!deploy' : $($lastCommit -match "!deploy") [$lastCommit]`n" +
      "    + Is Current PS version < 5 ?      : $($Psv.Major -lt 5) [$($Psv.ToString())]`n" +
      "    + NuGet API key is not null        : $(![string]::IsNullOrWhiteSpace($env:NUGETAPIKEY))`n"
      if ($Psv.Major -lt 5 -or [string]::IsNullOrWhiteSpace($env:NUGETAPIKEY) -or [string]::IsNullOrWhiteSpace($env:GitHubPAT) ) {
        $MSG = $MSG.Replace('and conditions for deployment are:', 'but conditions are not correct for deployment.')
        $MSG | Write-Host -ForegroundColor Yellow
        if (($([Environment]::GetEnvironmentVariable($env:RUN_ID + 'CommitMessage')) -match '!deploy' -and $([Environment]::GetEnvironmentVariable($env:RUN_ID + 'BranchName')) -eq "main") -or $script:ForceDeploy -eq $true) {
          Write-Warning "Force Deploying detected"
        } else {
          "Skipping Psake for this job!" | Write-Host -ForegroundColor Yellow
          exit 0
        }
      }
    };
    [ModuleManager]::RequiredModules | Resolve-Module -UpdateModule -Verbose
    [Console]::WriteLine()
    Write-BuildLog "Module Requirements Successfully resolved."
    [ModuleManager]::ShowEnvSummary("Build started")
    $null = Set-Content -Path ($this.buildFile.FullName) -Value $this.BuildScript
    [void][ModuleManager]::WriteHeading("Invoking psake with task list: [ $([ModuleManager]::TaskList -join ', ') ]")
    $psakeParams = @{
      nologo    = $true
      buildFile = $this.buildFile.FullName
      taskList  = [ModuleManager]::TaskList
    }
    if ([ModuleManager]::TaskList.Contains('TestOnly')) {
      Set-Variable -Name ExcludeTag -Scope global -Value @('Module')
    } else {
      Set-Variable -Name ExcludeTag -Scope global -Value $null
    }
    Invoke-psake @psakeParams -Verbose:$($this.Useverbose)
    [Console]::WriteLine()
    Remove-Item -Path $this.buildFile.FullName -Verbose | Out-Null
    [Console]::WriteLine()
  }
  [psobject] TestModule() {
    if ([string]::IsNullOrWhiteSpace($this.version)) {
      $this.Moduleversion = [version[]][DirectoryInfo]::New([Path]::Combine($this.BuildOutputPath, $this.ModuleName)).GetDirectories().Name | Select-Object -Last 1
    }
    $latest_build = [DirectoryInfo]::New((Resolve-Path ([Path]::Combine($this.BuildOutputPath, $this.ModuleName, $this.version)) -ErrorAction Stop))
    $manifestFile = [IO.FileInfo]::New([Path]::Combine($latest_build.FullName, "$($this.ModuleName).psd1"));
    if (!$latest_build.Exists) { throw [DirectoryNotFoundException]::New("Directory $([Path]::GetRelativePath($this.ModulePath, $latest_build.FullName)) Not Found") }
    if (!$manifestFile.Exists) { throw [FileNotFoundException]::New("Could Not Find Module manifest File $([Path]::GetRelativePath($this.ModulePath, $manifestFile.FullName))") }
    Get-Module $this.ModuleName | Remove-Module
    Write-Host "[+] Testing Module: '$($latest_build.FullName)'" -ForegroundColor Green
    Test-ModuleManifest -Path $manifestFile.FullName -ErrorAction Stop -Verbose:$false
    return (Invoke-Pester -Path $([ModuleManager]::TestsPath) -OutputFormat NUnitXml -OutputFile "$([ModuleManager]::TestsPath)\results.xml" -PassThru)
  }
  [void] SetBuildVariables() {
    $this.SetBuildVariables($this.RootPath.FullName, $env:RUN_ID)
  }
  [void] SetBuildVariables([string]$RootPath, [string]$Prefix) {
    [ValidateNotNullOrWhiteSpace()][string]$Prefix = $Prefix
    [validateNotNullOrWhiteSpace()][string]$RootPath = $RootPath
    Resolve-Module cliHelper.env -ro -ea Stop -verbose:$false
    if (![bool][int]$env:IsAC) {
      $LocEnvFile = [IO.FileInfo]::New([Path]::GetFullPath([Path]::Combine($RootPath, '.env')))
      if (!$LocEnvFile.Exists) {
        New-Item -Path $LocEnvFile.FullName -ItemType File -ErrorAction Stop
        Write-BuildLog "Created a new .env file"
      }
      # Set all Default/Preset Env: variables from the .env
      Set-Env -source $LocEnvFile -Scope Process
      if (![string]::IsNullOrWhiteSpace($env:LAST_BUILD_ID)) {
        Set-Env -Name LAST_BUILD_ID -Value $Prefix -OutFile $LocEnvFile
        Get-Item $LocEnvFile -Force | ForEach-Object { $_.Attributes = $_.Attributes -bor "Hidden" }
        Write-Host "Clean Last Builds's Env~ variables" -f Green
        Clear-BuildEnvironment -Id $env:LAST_BUILD_ID
      }
    }
    $Version = [ModuleManager]::LocalizedData.ModuleVersion; $BuildScriptPath = $null; $BuildNumber = $null; $ProjectName = $null; $BuildOutput = $null
    if ($null -eq $Version) { throw [System.ArgumentNullException]::new('version', "Please make sure localizedData.ModuleVersion is not null.") }
    [void][ModuleManager]::WriteHeading("Set Build Variables for Version: $Version")
    Set-Env -Name ('{0}{1}' -f $Prefix, 'BuildStart') -Value $(Get-Date -Format o)
    Set-Env -Name ('{0}{1}' -f $Prefix, 'BuildScriptPath') -Value $RootPath
    Set-Variable -Name BuildScriptPath -Value ([Environment]::GetEnvironmentVariable($Prefix + 'BuildScriptPath')) -Scope Local -Force
    Set-Env -Name ('{0}{1}' -f $Prefix, 'BuildSystem') -Value $(if ([bool][int]$env:IsCI -or ($Env:BUILD_BUILDURI -like 'vstfs:*')) { "VSTS" } else { [System.Environment]::MachineName })
    Set-Env -Name ('{0}{1}' -f $Prefix, 'ProjectPath') -Value $(if ([bool][int]$env:IsCI) { $Env:SYSTEM_DEFAULTWORKINGDIRECTORY } else { $BuildScriptPath })
    Set-Env -Name ('{0}{1}' -f $Prefix, 'BranchName') -Value $(if ([bool][int]$env:IsCI) { $Env:BUILD_SOURCEBRANCHNAME } else { $(Push-Location $BuildScriptPath; "$(git rev-parse --abbrev-ref HEAD)".Trim(); Pop-Location) })
    Set-Env -Name ('{0}{1}' -f $Prefix, 'CommitMessage') -Value $(if ([bool][int]$env:IsCI) { $Env:BUILD_SOURCEVERSIONMESSAGE } else { $(Push-Location $BuildScriptPath; "$(git log --format=%B -n 1)".Trim(); Pop-Location) })
    Set-Env -Name ('{0}{1}' -f $Prefix, 'BuildNumber') -Value $(if ([bool][int]$env:IsCI) { $Env:BUILD_BUILDNUMBER } else { $(if ([string]::IsNullOrWhiteSpace($Version)) { '1.0.0.1' } else { $Version }) })
    Set-Variable -Name BuildNumber -Value ([Environment]::GetEnvironmentVariable($Prefix + 'BuildNumber')) -Scope Local -Force
    Set-Env -Name ('{0}{1}' -f $Prefix, 'BuildOutput') -Value $([Path]::Combine($BuildScriptPath, "BuildOutput"))
    Set-Variable -Name BuildOutput -Value ([Environment]::GetEnvironmentVariable($Prefix + 'BuildOutput')) -Scope Local -Force
    Set-Env -Name ('{0}{1}' -f $Prefix, 'ProjectName') -Value [ModuleManager]::LocalizedData.ModuleName
    Set-Variable -Name ProjectName -Value ([Environment]::GetEnvironmentVariable($Prefix + 'ProjectName')) -Scope Local -Force
    Set-Env -Name ('{0}{1}' -f $Prefix, 'PSModulePath') -Value $([Path]::Combine($BuildOutput, $ProjectName, $BuildNumber))
    Set-Env -Name ('{0}{1}' -f $Prefix, 'PSModuleManifest') -Value $([Path]::Combine($BuildOutput, $ProjectName, $BuildNumber, "$ProjectName.psd1"))
    Set-Env -Name ('{0}{1}' -f $Prefix, 'ModulePath') -Value $(if (![string]::IsNullOrWhiteSpace($Env:PSModuleManifest)) { [Path]::GetDirectoryName($Env:PSModuleManifest) } else { [Path]::GetDirectoryName($BuildOutput) })
    Set-Env -Name ('{0}{1}' -f $Prefix, 'ReleaseNotes') -Value [ModuleManager]::LocalizedData.ReleaseNotes
  }
  [void] SetBuildScript() {
    # .SYNOPSIS
    #  Creates the psake build script
    if (!$this.buildFile.Exists) { throw [FileNotFoundException]::new('Unable to find the build script.') }; {
      # PSake makes variables declared here available in other scriptblocks
      Properties {
        $ProjectName = [Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName')
        $BuildNumber = [Environment]::GetEnvironmentVariable($env:RUN_ID + 'BuildNumber')
        $ProjectRoot = [Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectPath')
        if (!$ProjectRoot) {
          if ($pwd.Path -like "*ci*") { Set-Location .. }
          $ProjectRoot = $pwd.Path
        }
        $outputDir = [Environment]::GetEnvironmentVariable($env:RUN_ID + 'BuildOutput')
        $Timestamp = Get-Date -UFormat "%Y%m%d-%H%M%S"
        $PSVersion = $PSVersionTable.PSVersion.ToString()
        $outputModDir = [Path]::Combine([Environment]::GetEnvironmentVariable($env:RUN_ID + 'BuildOutput'), $ProjectName)
        $tests = [IO.Path]::Combine($projectRoot, "Tests");
        $lines = ('-' * 70)
        $Verbose = @{}
        $TestFile = "TestResults_PS$PSVersion`_$TimeStamp.xml"
        $outputModVerDir = [IO.Path]::Combine([Environment]::GetEnvironmentVariable($env:RUN_ID + 'BuildOutput'), $ProjectName, $BuildNumber)
        $PathSeperator = [IO.Path]::PathSeparator
        $DirSeperator = [IO.Path]::DirectorySeparatorChar
        if ([Environment]::GetEnvironmentVariable($env:RUN_ID + 'CommitMessage') -match "!verbose") {
          $Verbose = @{ Verbose = $True }
        }
        $null = @($tests, $Verbose, $TestFile, $outputDir, $outputModDir, $outputModVerDir, $lines, $DirSeperator, $PathSeperator)
        $null = Invoke-Command -NoNewScope -Script {
          $l = [IO.File]::ReadAllLines([Path]::Combine($([Environment]::GetEnvironmentVariable($env:RUN_ID + 'BuildScriptPath')), 'build.ps1'));
          $t = New-Item $([Path]::GetTempFileName().Replace('.tmp', '.ps1'));
          $ind1 = $l.IndexOf('  #region    BuildHelper_Functions'); $ind2 = $l.IndexOf('  #endregion BuildHelper_Functions')
          Set-Content -Path "$($t.FullName)" -Value $l[$ind1 .. $ind2] -Encoding UTF8 | Out-Null; . $t;
          Remove-Item -Path $t.FullName
        }
      }
      FormatTaskName ({
          param($String)
          "$(([ModuleManager]::WriteHeading("Executing task: $String")) -join "`n")"
        }
      )
      #Task Default -Depends Init,Test and Compile. Deploy Has to be done Manually
      Task default -Depends Test

      Task Init {
        Set-Location $ProjectRoot
        Write-Verbose "Build System Details:"
        Write-Verbose "$((Get-ChildItem Env: | Where-Object {$_.Name -match "^(BUILD_|SYSTEM_|BH)"} | Sort-Object Name | Format-Table Name,Value -AutoSize | Out-String).Trim())"
        Write-Verbose "Module Build version: $BuildNumber"
      } -Description 'Initialize build environment'
      Task -Name clean -Depends Init {
        $Host.UI.WriteLine()
        $modules = Get-Module -Name $ProjectName -ListAvailable -ErrorAction Ignore
        $modules | Remove-Module -Force; $modules | Uninstall-Module -ErrorAction Ignore -Force
        Remove-Module $ProjectName -Force -ErrorAction SilentlyContinue
        if (Test-Path -Path $outputDir -PathType Container -ErrorAction SilentlyContinue) {
          Write-Verbose "Cleaning Previous build Output ..."
          Get-ChildItem -Path $outputDir -Recurse -Force | Remove-Item -Force -Recurse
        }
        "    Cleaned previous Output directory [$outputDir]"
      } -Description 'Cleans module output directory'

      Task Compile -Depends Clean {
        Write-Verbose "Create module Output directory"
        New-Item -Path $outputModVerDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        $ModuleManifest = [IO.FileInfo]::New([Environment]::GetEnvironmentVariable($env:RUN_ID + 'PSModuleManifest'))
        Write-Verbose "Add Module files ..."
        try {
          @(
            "en-US"
            "Private"
            "Public"
            "LICENSE"
            "$($ModuleManifest.Name)"
            "$ProjectName.psm1"
          ).ForEach({ Copy-Item -Recurse -Path $([Path]::Combine($([Environment]::GetEnvironmentVariable($env:RUN_ID + 'BuildScriptPath')), $_)) -Destination $([Environment]::GetEnvironmentVariable($env:RUN_ID + 'PSModulePath')) })
        } catch {
          throw $_
        }
        if (!$ModuleManifest.Exists) { throw [FileNotFoundException]::New('Could Not Create Module Manifest!') }
        $functionsToExport = @(); $publicFunctionsPath = [Path]::Combine([Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectPath'), "Public")
        if (Test-Path $publicFunctionsPath -PathType Container -ErrorAction SilentlyContinue) {
          Get-ChildItem -Path $publicFunctionsPath -Filter "*.ps1" -Recurse -File | ForEach-Object {
            $functionsToExport += $_.BaseName
          }
        }
        $manifestContent = Get-Content -Path $ModuleManifest -Raw
        $publicFunctionNames = Get-ChildItem -Path $publicFunctionsPath -Filter "*.ps1" | Select-Object -ExpandProperty BaseName

        Write-Verbose -Message "Editing $($ModuleManifest.Name) ..."
        # Using .Replace() is Better than Update-ModuleManifest as this does not destroy the Indentation in the Psd1 file.
        $manifestContent = $manifestContent.Replace(
          "'<FunctionsToExport>'", $(if ((Test-Path -Path $publicFunctionsPath) -and $publicFunctionNames.count -gt 0) { "'$($publicFunctionNames -join "',`n        '")'" }else { $null })
        ).Replace(
          "<ModuleVersion>", $([Environment]::GetEnvironmentVariable($env:RUN_ID + 'BuildNumber'))
        ).Replace(
          "<ReleaseNotes>", $([Environment]::GetEnvironmentVariable($env:RUN_ID + 'ReleaseNotes'))
        ).Replace(
          "<Year>", ([Datetime]::Now.Year)
        )
        $manifestContent | Set-Content -Path $ModuleManifest
        if ((Get-ChildItem $outputModVerDir | Where-Object { $_.Name -eq "$($([Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName'))).psd1" }).BaseName -cne $([Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName'))) {
          "    Renaming manifest to correct casing"
          Rename-Item (Join-Path $outputModVerDir "$($([Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName'))).psd1") -NewName "$($([Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName'))).psd1" -Force
        }
        $Host.UI.WriteLine()
        "    Created compiled module at [$outputModDir]"
        "    Output version directory contents"
        Get-ChildItem $outputModVerDir | Format-Table -AutoSize
      } -Description 'Compiles module from source'

      Task Import -Depends Compile {
        $Host.UI.WriteLine()
        '    Testing import of the Compiled module.'
        Test-ModuleManifest -Path $([Environment]::GetEnvironmentVariable($env:RUN_ID + 'PSModuleManifest'))
        Import-Module $([Environment]::GetEnvironmentVariable($env:RUN_ID + 'PSModuleManifest'))
      } -Description 'Imports the newly compiled module'

      Task Test -Depends Import {
        [void][ModuleManager]::WriteHeading("Executing Script: ./Test-Module.ps1")
        $test_Script = [IO.FileInfo]::New([Path]::Combine($ProjectRoot, 'Test-Module.ps1'))
        if (!$test_Script.Exists) { throw [FileNotFoundException]::New($test_Script.FullName) }
        Import-Module Pester -Verbose:$false -Force -ErrorAction Stop
        $origModulePath = $Env:PSModulePath
        Push-Location $ProjectRoot
        if ($Env:PSModulePath.split($pathSeperator) -notcontains $outputDir ) {
          $Env:PSModulePath = ($outputDir + $pathSeperator + $origModulePath)
        }
        Remove-Module $ProjectName -ErrorAction SilentlyContinue -Verbose:$false
        Import-Module $outputModDir -Force -Verbose:$false
        $Host.UI.WriteLine();
        $TestResults = & $test_Script
        Write-Host '    Pester invocation complete!' -ForegroundColor Green
        $TestResults | Format-List
        if ($TestResults.FailedCount -gt 0) {
          Write-Error -Message "One or more Pester tests failed!"
        }
        Pop-Location
        $Env:PSModulePath = $origModulePath
      } -Description 'Run Pester tests against compiled module'

      Task Deploy -Depends Test -Description 'Release new github version and Publish module to PSGallery' {
        if ([Environment]::GetEnvironmentVariable($env:RUN_ID + 'BuildSystem') -eq 'VSTS' -or ($env:CI -eq "true" -and $env:GITHUB_RUN_ID)) {
          # Load the module, read the exported functions, update the psd1 FunctionsToExport
          $commParsed = [Environment]::GetEnvironmentVariable($env:RUN_ID + 'CommitMessage') | Select-String -Pattern '\sv\d+\.\d+\.\d+\s'
          if ($commParsed) {
            $commitVer = $commParsed.Matches.Value.Trim().Replace('v', '')
          }
          $current_build_version = $CurrentVersion = (Get-Module $([Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName'))).Version
          $Latest_Module_Verion = Get-LatestModuleVersion -Name ([Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName')) -Source PsGallery
          "Module Current version on the PSGallery: $Latest_Module_Verion"
          $galVerSplit = "$Latest_Module_Verion".Split('.')
          $nextGalVer = [System.Version](($galVerSplit[0..($galVerSplit.Count - 2)] -join '.') + '.' + ([int]$galVerSplit[-1] + 1))
          # Bump MODULE Version
          $versionToDeploy = switch ($true) {
            $($commitVer -and ([System.Version]$commitVer -lt $nextGalVer)) {
              Write-Host -ForegroundColor Yellow "Version in commit message is $commitVer, which is less than the next Gallery version and would result in an error. Possible duplicate deployment build, skipping module bump and negating deployment"
              Set-Env -Name ($env:RUN_ID + 'CommitMessage') -Value $([Environment]::GetEnvironmentVariable($env:RUN_ID + 'CommitMessage')).Replace('!deploy', '')
              $null
              break
            }
            $($commitVer -and ([System.Version]$commitVer -gt $nextGalVer)) {
              Write-Host -ForegroundColor Green "Module Bumped version: $commitVer [from commit message]"
              [System.Version]$commitVer
              break
            }
            $($CurrentVersion -ge $nextGalVer) {
              Write-Host -ForegroundColor Green "Module Bumped version: $CurrentVersion [from manifest]"
              $CurrentVersion
              break
            }
            $(([Environment]::GetEnvironmentVariable($env:RUN_ID + 'CommitMessage')) -match '!hotfix') {
              Write-Host -ForegroundColor Green "Module Bumped version: $nextGalVer [commit message match '!hotfix']"
              $nextGalVer
              break
            }
            $(([Environment]::GetEnvironmentVariable($env:RUN_ID + 'CommitMessage')) -match '!minor') {
              $minorVers = [System.Version]("{0}.{1}.{2}" -f $nextGalVer.Major, ([int]$nextGalVer.Minor + 1), 0)
              Write-Host -ForegroundColor Green "Module Bumped version: $minorVers [commit message match '!minor']"
              $minorVers
              break
            }
            $(([Environment]::GetEnvironmentVariable($env:RUN_ID + 'CommitMessage')) -match '!major') {
              $majorVers = [System.Version]("{0}.{1}.{2}" -f ([int]$nextGalVer.Major + 1), 0, 0)
              Write-Host -ForegroundColor Green "Module Bumped version: $majorVers [commit message match '!major']"
              $majorVers
              break
            }
            Default {
              Write-Host -ForegroundColor Green "Module Bumped version: $nextGalVer [PSGallery next version]"
              $nextGalVer
            }
          }
          if (!$versionToDeploy) {
            Write-Host -ForegroundColor Yellow "No module version matched! Negating deployment to prevent errors"
            Set-Env -Name ($env:RUN_ID + 'CommitMessage') -Value $([Environment]::GetEnvironmentVariable($env:RUN_ID + 'CommitMessage')).Replace('!deploy', '')
          }
          try {
            [ValidateNotNullOrWhiteSpace()][string]$versionToDeploy = $versionToDeploy.ToString()
            $manifest = Import-PowerShellDataFile -Path $([Environment]::GetEnvironmentVariable($env:RUN_ID + 'PSModuleManifest'))
            $latest_Github_release = Invoke-WebRequest "https://api.github.com/repos/alainQtec/cliHelper.env/releases/latest" | ConvertFrom-Json
            $latest_Github_release = [PSCustomObject]@{
              name = $latest_Github_release.name
              ver  = [version]::new($latest_Github_release.tag_name.substring(1))
              url  = $latest_Github_release.html_url
            }
            $Is_Lower_PsGallery_Version = [version]$current_build_version -le $Latest_Module_Verion
            $should_Publish_ToPsGallery = ![string]::IsNullOrWhiteSpace($env:NUGETAPIKEY) -and !$Is_Lower_PsGallery_Version
            $Is_Lower_GitHub_Version = [version]$current_build_version -le $latest_Github_release.ver
            $should_Publish_GitHubRelease = ![string]::IsNullOrWhiteSpace($env:GitHubPAT) -and ($env:CI -eq "true" -and $env:GITHUB_RUN_ID) -and !$Is_Lower_GitHub_Version
            if ($should_Publish_ToPsGallery) {
              $manifestPath = Join-Path $outputModVerDir "$($([Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName'))).psd1"
              if (-not $manifest) {
                $manifest = Import-PowerShellDataFile -Path $manifestPath
              }
              if ($manifest.ModuleVersion.ToString() -eq $versionToDeploy.ToString()) {
                "    Manifest is already the expected version. Skipping manifest version update"
              } else {
                "    Updating module version on manifest to [$versionToDeploy]"
                Update-Metadata -Path $manifestPath -PropertyName ModuleVersion -Value $versionToDeploy -Verbose
              }
              Write-Host "    Publishing version [$versionToDeploy] to PSGallery..." -ForegroundColor Green
              Publish-Module -Path $outputModVerDir -NuGetApiKey $env:NUGETAPIKEY -Repository PSGallery -Verbose
              Write-Host "    Published to PsGallery successful!" -ForegroundColor Green
            } else {
              if ($Is_Lower_PsGallery_Version) { Write-Warning "SKIPPED Publishing. Module version $Latest_Module_Verion already exists on PsGallery!" }
              Write-Verbose "    SKIPPED Publish of version [$versionToDeploy] to PSGallery"
            }
            $commitId = git rev-parse --verify HEAD;
            if ($should_Publish_GitHubRelease) {
              $ReleaseNotes = [Environment]::GetEnvironmentVariable($env:RUN_ID + 'ReleaseNotes')
              [ValidateNotNullOrWhiteSpace()][string]$ReleaseNotes = $ReleaseNotes
              "    Creating Release ZIP..."
              $ZipTmpPath = [Path]::Combine($PSScriptRoot, "$($([Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName'))).zip")
              if ([IO.File]::Exists($ZipTmpPath)) { Remove-Item $ZipTmpPath -Force }
              Add-Type -Assembly System.IO.Compression.FileSystem
              [Compression.ZipFile]::CreateFromDirectory($outputModDir, $ZipTmpPath)
              [void][ModuleManager]::WriteHeading("    Publishing Release v$versionToDeploy @ commit Id [$($commitId)] to GitHub...")
              $ReleaseNotes += (git log -1 --pretty=%B | Select-Object -Skip 2) -join "`n"
              $ReleaseNotes = $ReleaseNotes.Replace('<versionToDeploy>', $versionToDeploy)
              Set-Env -Name ('{0}{1}' -f $env:RUN_ID, 'ReleaseNotes') -Value $ReleaseNotes
              $gitHubParams = @{
                VersionNumber    = $versionToDeploy
                CommitId         = $commitId
                ReleaseNotes     = [Environment]::GetEnvironmentVariable($env:RUN_ID + 'ReleaseNotes')
                ArtifactPath     = $ZipTmpPath
                GitHubUsername   = 'alainQtec'
                GitHubRepository = [Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName')
                GitHubApiKey     = $env:GitHubPAT
                Draft            = $false
              }
              Publish-GithubRelease @gitHubParams
              [void][ModuleManager]::WriteHeading("    Github release created successful!")
            } else {
              if ($Is_Lower_GitHub_Version) { Write-Warning "SKIPPED Releasing. Module version $current_build_version already exists on Github!" }
              Write-Verbose "    SKIPPED GitHub Release v$($versionToDeploy) @ commit Id [$($commitId)] to GitHub"
            }
          } catch {
            $_ | Format-List * -Force
            Write-Error $_
          }
        } else {
          Write-Host -ForegroundColor Magenta "UNKNOWN Build system"
        }
      }
    } | Set-Content -Path $this.buildFile.FullName -Encoding UTF8
  }
  [void] WriteHelp() {
    [void][ModuleManager]::WriteHeading("Getting help")
    Write-BuildLog -c '"psake" | Resolve-Module @Mod_Res -Verbose'
    Resolve-Module -Name 'psake' -ro -Verbose:$false
    Get-PSakeScriptTasks -BuildFile $this.buildFile.FullName | Sort-Object -Property Name | Format-Table -Property Name, Description, Alias, DependsOn
  }
  static [Net.SecurityProtocolType] GetSecurityProtocol() {
    $p = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::SystemDefault
    if ([Net.SecurityProtocolType].GetMember("Tls12").Count -gt 0) { $p = $p -bor [Net.SecurityProtocolType]::Tls12 }
    return $p
  }
  static [bool] removeold([string]$Name) {
    $m = Get-Module $Name -ListAvailable -All -Verbose:$false; [bool[]]$success = @()
    if ($m.count -gt 1) {
      $old = $m | Select-Object ModuleBase, Version | Sort-Object -Unique version -Descending | Select-Object -Skip 1 -ExpandProperty ModuleBase
      $success += $old.ForEach({
          try { Remove-Module $_ -Force -Verbose:$false -ErrorAction Ignore; Remove-Item $_ -Recurse -Force -ea Ignore } catch { $null }
          [Directory]::Exists("$_")
        }
      )
    }; $IsSuccess = !$success.Contains($false)
    return $IsSuccess
  }
  [string] PublishtoLocalPsRepo([string]$ModuleName) {
    [ValidateNotNullOrWhiteSpace()][string]$ModuleName = $ModuleName
    $RepoPath = [ModuleManager]::CreateLocalRepository(); ; $ModulePackage = [Path]::Combine($RepoPath, "${ModuleName}.$([Environment]::GetEnvironmentVariable($env:RUN_ID + 'BuildNumber')).nupkg")
    if ([IO.File]::Exists($ModulePackage)) {
      Remove-Item -Path $ModulePackage -ErrorAction 'SilentlyContinue'
    }
    $BuildOutput = [Environment]::GetEnvironmentVariable($env:RUN_ID + 'BuildOutput')
    $this.ModulePath = [Path]::Combine($BuildOutput, $ModuleName, $([Environment]::GetEnvironmentVariable($env:RUN_ID + 'BuildNumber')))
    [void][ModuleManager]::WriteHeading("Publish to Local PsRepository")
    $dependencies = [ModuleManager]::ReadPsModuleDataFile([Path]::Combine($this.ModulePath, "$([Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName')).psd1"), "RequiredModules")
    foreach ($item in $dependencies) {
      $md = Get-Module $item -Verbose:$false; $mdPath = $md.Path | Split-Path
      Write-Verbose "Publish RequiredModule $item ..."
      Publish-Module -Path $mdPath -Repository LocalPSRepo -Verbose:$false
    }
    Write-BuildLog -Command "Publish-Module -Path $($this.ModulePath) -Repository LocalPSRepo  "
    Publish-Module -Path $this.ModulePath -Repository LocalPSRepo
    return $this.ModulePath
  }
  static [string] CreateLocalRepository() {
    return [ModuleManager]::CreateLocalRepository('LocalPSRepo');
  }
  static [string] CreateLocalRepository([string]$Name) {
    [void][ModuleManager]::WriteHeading("Create a Local repository")
    $RepoPath = [IO.Path]::Combine([Environment]::GetEnvironmentVariable("HOME"), $Name)
    if (!(Get-Variable -Name IsWindows -ErrorAction Ignore) -or $(Get-Variable IsWindows -ValueOnly)) {
      $RepoPath = [IO.Path]::Combine([Environment]::GetEnvironmentVariable("UserProfile"), $Name)
    }; if (!(Test-Path -Path $RepoPath -PathType Container -ErrorAction Ignore)) { New-Directory -Path $RepoPath | Out-Null }
    Invoke-Command -ScriptBlock ([scriptblock]::Create("Register-PSRepository LocalPSRepo -SourceLocation '$RepoPath' -PublishLocation '$RepoPath' -InstallationPolicy Trusted -Verbose:`$false -ErrorAction Ignore; Register-PackageSource -Name LocalPsRepo -Location '$RepoPath' -Trusted -ProviderName Bootstrap -ErrorAction Ignore"))
    Write-Verbose "Verify that the new repository was created successfully"
    if ($null -eq (Get-PSRepository LocalPSRepo -Verbose:$false -ErrorAction Ignore)) {
      Throw [System.Exception]::New('Failed to create LocalPsRepo', [DirectoryNotFoundException]::New($RepoPath))
    }
    return $RepoPath
  }
  [void] FormatCode() {
    [ModuleManager]::FormatCode($this.RootPath)
  }
  static [void] FormatCode([DirectoryInfo]$repoRoot) {
    [int]$errorCount = 0
    [int]$maxRetries = 5
    $filesToCheck = Get-ChildItem -Path $repoRoot -Directory | Where-Object {
      $_.Name -ne "dist" } | ForEach-Object {
      Get-ChildItem -Path $_.FullName -Include "*.ps1", "*.psm1", "*.md" -Recurse
    }
    foreach ($fileInfo in $filesToCheck) {
      for ($i = 0; $i -lt $maxRetries; $i++) {
        try {
          $analyzerResults = Invoke-ScriptAnalyzer -Path $FileInfo.FullName -Settings $repoRoot\PSScriptAnalyzerSettings.psd1 -ErrorAction Stop
          if ($null -ne $analyzerResults) {
            $errorCount++
            $analyzerResults | Format-Table -AutoSize
          }
          break
        } catch {
          Write-Warning "Invoke-ScriptAnalyer failed on $($fileInfo.FullName). Error:"
          $_.Exception | Format-List | Out-Host
          Write-Warning "Retrying in 5 seconds."
          Start-Sleep -Seconds 5
        }
      }

      if ($i -eq $maxRetries) {
        throw "Invoke-ScriptAnalyzer failed $maxRetries times. Giving up."
      }
      if ($errorCount -gt 0) {
        throw "Failed to match formatting requirements"
      }
    }
  }
  static [string] GetInstallPath([string]$Name, [string]$ReqVersion) {
    $p = [DirectoryInfo][IO.Path]::Combine(
      $(if (!(Get-Variable -Name IsWindows -ErrorAction Ignore) -or $(Get-Variable IsWindows -ValueOnly)) {
          $_versionTable = Get-Variable PSVersionTable -ValueOnly
          $module_folder = if ($_versionTable.ContainsKey('PSEdition') -and $_versionTable.PSEdition -eq 'Core') { 'PowerShell' } else { 'WindowsPowerShell' }
          Join-Path -Path $([System.Environment]::GetFolderPath('MyDocuments')) -ChildPath $module_folder
        } else {
          Split-Path -Path ([System.Management.Automation.Platform]::SelectProductNameForDirectory('USER_MODULES')) -Parent
        }
      ), 'Modules'
    )
    if (![string]::IsNullOrWhiteSpace($ReqVersion)) {
      return [IO.Path]::Combine($p.FullName, $Name, $ReqVersion)
    } else {
      return [IO.Path]::Combine($p.FullName, $Name)
    }
  }
  static [void] UpdateModule([string]$moduleName, [string]$Version) {
    [int]$ret = 0;
    try {
      if ($Version -eq 'latest') {
        Update-Module -Name $moduleName
      } else {
        Update-Module -Name $moduleName -RequiredVersion $Version
      }
    } catch {
      if ($ret -lt 1 -and $_.ErrorRecord.Exception.Message -eq "Module '$moduleName' was not installed by using Install-Module, so it cannot be updated.") {
        Get-Module $moduleName | Remove-Module -Force; $ret++
        # TODO: fIX THIS mess by using: Invoke-RetriableCommand function
        [ModuleManager]::UpdateModule($moduleName, $Version)
      }
    }
  }
  static [void] InstallModule([string]$moduleName, [string]$Version) {
    # There are issues with pester 5.4.1 syntax, so I'll keep using -SkipPublisherCheck.
    # https://stackoverflow.com/questions/51508982/pester-sample-script-gets-be-is-not-a-valid-should-operator-on-windows-10-wo
    $IsPester = $moduleName -eq 'Pester'
    if ($IsPester) { [void][ModuleManager]::removeold($moduleName) }
    if ($Version -eq 'latest') {
      Install-Module -Name $moduleName -SkipPublisherCheck:$IsPester
    } else {
      Install-Module -Name $moduleName -RequiredVersion $Version -SkipPublisherCheck:$IsPester
    }
  }
  static [string] ManuallyInstallModule([string]$moduleName, [string]$Version) {
    # .DESCRIPTION
    #   Last resort.
    # .NOTES
    #   Before you run this, remember that
    #   sometimes you just need to apply a quick fix like this one:
    #   Unregister-PSRepository -Name PSGallery
    #   Register-PSRepository -Default
    #   if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
    #       Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    #   }
    # We manually installs the module when the normal way fails
    $Module_Path = ""; $response = $null; $downloadUrl = ''; $VerboseMsg = 'Normal Installation Failed :' + $_.Exception.Message + "`nUsing Manual Instalation ..."
    Write-Verbose $VerboseMsg -Verbose
    # For some reason Install-Module can fail (ex: on Arch). This is a manual workaround when that happens.
    $version_filter = if ($Version -eq 'latest') { 'IsLatestVersion' } else { "Version eq '$Version'" }
    $url = "https://www.powershellgallery.com/api/v2/Packages?`$filter=Id eq '$moduleName' and $version_filter"
    try {
      $response = Invoke-RestMethod -Uri $url -Method Get -Verbose:$false
      if ($null -eq $response) {
        $Error_params = @{
          ExceptionName    = 'System.InvalidOperationException'
          ExceptionMessage = "Module '$moduleName' was not found in PSGallery repository."
          ErrorId          = 'CouldNotFindModule'
          Caller           = [ModuleManager]::CallerCmdlet
          ErrorCategory    = 'InvalidResult'
        }
        Write-TerminatingError @Error_params
      }
      [ValidateNotNullOrEmpty()][string]$downloadUrl = $response.content.src
      [ValidateNotNullOrEmpty()][string]$moduleName = $response.properties.Id
      [ValidateNotNullOrEmpty()][string]$Version = $response.properties.Version
      $Module_Path = [ModuleManager]::GetInstallPath($moduleName, $Version)
    } catch {
      $Error_params = @{
        ExceptionName    = 'System.InvalidOperationException'
        ExceptionMessage = "Failed to find PsGallery release for '$moduleName' version '$Version'. Url used: '$url'. $($_.Exception.Message)"
        ErrorId          = 'RestMethod_Failed'
        Caller           = [ModuleManager]::CallerCmdlet
        ErrorCategory    = 'OperationStopped'
      }
      Write-TerminatingError @Error_params
    }
    if (!(Test-Path -Path $Module_Path -PathType Container -ErrorAction Ignore)) { New-Directory -Path $Module_Path }
    $ModuleNupkg = [IO.Path]::Combine($Module_Path, "$moduleName.nupkg")
    Write-Host "Download $moduleName.nupkg ... " -NoNewline -ForegroundColor DarkCyan
    Invoke-WebRequest -Uri $downloadUrl -OutFile $ModuleNupkg -Verbose:$false;
    if ([ModuleManager]::GetHostOs() -eq "Windows") { Unblock-File -Path $ModuleNupkg }
    Expand-Archive $ModuleNupkg -DestinationPath $Module_Path -Verbose:$false -Force
    $Items_to_CleanUp = [System.Collections.ObjectModel.Collection[System.Object]]::new()
    @('_rels', 'package', '*Content_Types*.xml', "$ModuleNupkg", "$($moduleName.Tolower()).nuspec" ) | ForEach-Object { [void]$Items_to_CleanUp.Add((Get-Item -Path "$Module_Path/$_" -ErrorAction Ignore)) }
    $Items_to_CleanUp = $Items_to_CleanUp | Sort-Object -Unique
    foreach ($Item in $Items_to_CleanUp) {
      [bool]$Recurse = $Item.Attributes -eq [FileAttributes]::Directory
      Remove-Item -LiteralPath $Item.FullName -Recurse:$Recurse -Force -ErrorAction SilentlyContinue
    }
    return $Module_Path
  }
  static [string] WriteHeading([String]$Title) {
    [validatenotnullorwhitespace()][string]$Title = $Title
    $msgList = @(
      ''
      "##[section] $([ModuleManager]::GetElapsed()) $Title"
    ) -join "`n"
    $msgList | Write-Host -ForegroundColor Cyan
    return $msgList
  }
  static [string] GetElapsed() {
    $buildstart = [Environment]::GetEnvironmentVariable($ENV:RUN_ID + 'BuildStart')
    $build_date = if ([string]::IsNullOrWhiteSpace($buildstart)) { Get-Date }else { Get-Date $buildstart }
    return [ModuleManager]::GetElapsed($build_date)
  }
  static [string] GetElapsed([DateTime]$build_date) {
    [ValidateNotNullOrEmpty()][datetime]$build_date = $build_date
    $elapse_msg = if ([bool][int]$env:IsCI) {
      "[ + $(((Get-Date) - $build_date).ToString())]"
    } else {
      "[$((Get-Date).ToString("HH:mm:ss")) + $(((Get-Date) - $build_date).ToString())]"
    }
    return "$elapse_msg{0}" -f (' ' * (30 - $elapse_msg.Length))
  }
  static [string] ShowEnvSummary() {
    return [ModuleManager]::ShowEnvSummary([string]::Empty)
  }
  static [string] ShowEnvSummary([String]$State) {
    $_psv = Get-Variable PSVersionTable -ValueOnly
    [void][ModuleManager]::WriteHeading("Build Environment Summary:`n")
    $_res = @(
      $(if ($([Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName'))) { "Project : $([Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName'))" })
      $(if ($State) { "State   : $State" })
      "Engine  : PowerShell $($_psv.PSVersion.ToString())"
      "Host OS : $([ModuleManager]::GetHostOs())"
      "PWD     : $PWD"
      ''
    )
    $_res | Write-Host
    return $_res
  }
  static [hashtable[]] FindHashKeyValue($PropertyName, $Ast) {
    return [ModuleManager]::FindHashKeyValue($PropertyName, $Ast, @())
  }
  static [hashtable[]] FindHashKeyValue($PropertyName, $Ast, [string[]]$CurrentPath) {
    if ($PropertyName -eq ($CurrentPath -Join '.') -or $PropertyName -eq $CurrentPath[-1]) {
      return $Ast | Add-Member NoteProperty HashKeyPath ($CurrentPath -join '.') -PassThru -Force | Add-Member NoteProperty HashKeyName ($CurrentPath[-1]) -PassThru -Force
    }; $r = @()
    if ($Ast.PipelineElements.Expression -is [System.Management.Automation.Language.HashtableAst]) {
      $KeyValue = $Ast.PipelineElements.Expression
      foreach ($KV in $KeyValue.KeyValuePairs) {
        $result = [ModuleManager]::FindHashKeyValue($PropertyName, $KV.Item2, @($CurrentPath + $KV.Item1.Value))
        if ($null -ne $result) {
          $r += $result
        }
      }
    }
    return $r
  }
  static [string] GetHostOs() {
    #TODO: refactor so that it returns one of these: [Enum]::GetNames([System.PlatformID])
    return $(if ($(Get-Variable PSVersionTable -Value).PSVersion.Major -le 5 -or $(Get-Variable IsWindows -Value)) { "Windows" }elseif ($(Get-Variable IsLinux -Value)) { "Linux" }elseif ($(Get-Variable IsMacOS -Value)) { "macOS" }else { "UNKNOWN" });
  }
  static [string] GetRelativePath([string]$RelativeTo, [string]$Path) {
    # $RelativeTo : The source path the result should be relative to. This path is always considered to be a directory.
    # $Path : The destination path.
    $result = [string]::Empty
    $Drive = $Path -replace "^([^\\/]+:[\\/])?.*", '$1'
    if ($Drive -ne ($RelativeTo -replace "^([^\\/]+:[\\/])?.*", '$1')) {
      Write-Verbose "Paths on different drives"
      return $Path # no commonality, different drive letters on windows
    }
    $RelativeTo = $RelativeTo -replace "^[^\\/]+:[\\/]", [IO.Path]::DirectorySeparatorChar
    $Path = $Path -replace "^[^\\/]+:[\\/]", [IO.Path]::DirectorySeparatorChar
    $RelativeTo = [IO.Path]::GetFullPath($RelativeTo).TrimEnd('\/') -replace "^[^\\/]+:[\\/]", [IO.Path]::DirectorySeparatorChar
    $Path = [IO.Path]::GetFullPath($Path) -replace "^[^\\/]+:[\\/]", [IO.Path]::DirectorySeparatorChar

    $commonLength = 0
    while ($Path[$commonLength] -eq $RelativeTo[$commonLength]) {
      $commonLength++
    }
    if ($commonLength -eq $RelativeTo.Length -and $RelativeTo.Length -eq $Path.Length) {
      Write-Verbose "Equal Paths"
      return "." # The same paths
    }
    if ($commonLength -eq 0) {
      Write-Verbose "Paths on different drives?"
      return $Drive + $Path # no commonality, different drive letters on windows
    }

    Write-Verbose "Common base: $commonLength $($RelativeTo.Substring(0,$commonLength))"
    # In case we matched PART of a name, like C:\Users\Joel and C:\Users\Joe
    while ($commonLength -gt $RelativeTo.Length -and ($RelativeTo[$commonLength] -ne [IO.Path]::DirectorySeparatorChar)) {
      $commonLength--
    }

    Write-Verbose "Common base: $commonLength $($RelativeTo.Substring(0,$commonLength))"
    # create '..' segments for segments past the common on the "$RelativeTo" path
    if ($commonLength -lt $RelativeTo.Length) {
      $result = @('..') * @($RelativeTo.Substring($commonLength).Split([IO.Path]::DirectorySeparatorChar).Where{ $_ }).Length -join ([IO.Path]::DirectorySeparatorChar)
    }
    return (@($result, $Path.Substring($commonLength).TrimStart([IO.Path]::DirectorySeparatorChar)).Where{ $_ } -join ([IO.Path]::DirectorySeparatorChar))
  }
  static [string] GetResolvedPath([string]$Path) {
    return [ModuleManager]::GetResolvedPath($((Get-Variable ExecutionContext).Value.SessionState), $Path)
  }
  static [string] GetResolvedPath([System.Management.Automation.SessionState]$session, [string]$Path) {
    $paths = $session.Path.GetResolvedPSPathFromPSPath($Path);
    if ($paths.Count -gt 1) {
      throw [IOException]::new([string]::Format([cultureinfo]::InvariantCulture, "Path {0} is ambiguous", $Path))
    } elseif ($paths.Count -lt 1) {
      throw [IOException]::new([string]::Format([cultureinfo]::InvariantCulture, "Path {0} not Found", $Path))
    }
    return $paths[0].Path
  }
  static [string] GetUnResolvedPath([string]$Path) {
    return [ModuleManager]::GetUnResolvedPath($((Get-Variable ExecutionContext).Value.SessionState), $Path)
  }
  static [string] GetUnResolvedPath([System.Management.Automation.SessionState]$session, [string]$Path) {
    return $session.Path.GetUnresolvedProviderPathFromPSPath($Path)
  }
  static hidden [ModuleManager] _Create([string]$RootPath, [ref]$o) {
    $b = [ModuleManager]::new();
    [Net.ServicePointManager]::SecurityProtocol = [ModuleManager]::GetSecurityProtocol();
    [Environment]::SetEnvironmentVariable('IsAC', $(if (![string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('GITHUB_WORKFLOW'))) { '1' } else { '0' }), [System.EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('IsCI', $(if (![string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('TF_BUILD'))) { '1' } else { '0' }), [System.EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('RUN_ID', $(if ([bool][int]$env:IsAC -or $env:CI -eq "true") { [Environment]::GetEnvironmentVariable('GITHUB_RUN_ID') }else { [Guid]::NewGuid().Guid.substring(0, 21).replace('-', [string]::Join('', (0..9 | Get-Random -Count 1))) + '_' }), [System.EnvironmentVariableTarget]::Process);
    [ModuleManager]::Useverbose = (Get-Variable VerbosePreference -ValueOnly -Scope global) -eq "continue"
    $_RootPath = [ModuleManager]::GetUnresolvedPath($RootPath);
    if ([Directory]::Exists($_RootPath)) { $b.RootPath = $_RootPath }else { throw [DirectoryNotFoundException]::new("RootPath $RootPath Not Found") }
    $b.ModuleName = [Path]::GetDirectoryName($_RootPath);
    # $currentContext = [EngineIntrinsics](Get-Variable ExecutionContext -ValueOnly);
    # $b.SessionState = $currentContext.SessionState; $b.Host = $currentContext.Host
    $b.BuildOutputPath = [Path]::Combine($_RootPath, 'BuildOutput');
    $b.TestsPath = [Path]::Combine($b.RootPath, 'Tests');
    $b.dataFile = [FileInfo]::new([Path]::Combine($b.RootPath, 'en-US', "$($b.RootPath.BaseName).strings.psd1"))
    $b.buildFile = New-Item $([Path]::GetTempFileName().Replace('.tmp', '.ps1')); $b.SetBuildScript();
    $b.RequiredModules = @(
      "PackageManagement"
      "PSScriptAnalyzer"
      "PowerShellGet"
      "Pester"
      "Psake"
    )
    if (!$b.dataFile.Exists) { throw [FileNotFoundException]::new('Unable to find the LocalizedData file.', "$($b.dataFile.BaseName).strings.psd1") }
    [ModuleManager]::LocalizedData = [scriptblock]::Create("$([IO.File]::ReadAllText($b.dataFile))").Invoke() # same as "Get-LocalizedData -DefaultUICulture 'en-US'" but the cmdlet is not always installed
    $b.SetBuildVariables();
    if ($null -ne $o) {
      $o.value.GetType().GetProperties().ForEach({
          $v = $b.$($_.Name)
          if ($null -ne $v) {
            $o.value.$($_.Name) = $v
          }
        }
      )
      return $o.Value
    }; return $b
  }
  static [LocalPsModule] FindLocalPsModule([string]$Name) {
    if ($Name.Contains([string][Path]::DirectorySeparatorChar)) {
      $rName = [ModuleManager]::GetResolvedPath($Name)
      $bName = [Path]::GetDirectoryName($rName)
      if ([Directory]::Exists($rName)) {
        return [ModuleManager]::FindLocalPsModule($bName, [Directory]::GetParent($rName))
      }
    }
    return [ModuleManager]::FindLocalPsModule($Name, "", $null)
  }
  static [LocalPsModule] FindLocalPsModule([string]$Name, [string]$scope) {
    return [ModuleManager]::FindLocalPsModule($Name, $scope, $null)
  }
  static [LocalPsModule] FindLocalPsModule([string]$Name, [version]$version) {
    return [ModuleManager]::FindLocalPsModule($Name, "", $version)
  }
  static [LocalPsModule] FindLocalPsModule([string]$Name, [DirectoryInfo]$ModuleBase) {
    [ValidateNotNullOrWhiteSpace()][string]$Name = $Name
    [ValidateNotNullOrEmpty()][DirectoryInfo]$ModuleBase = $ModuleBase
    $result = [LocalPsModule]::new(); $result.Scope = 'LocalMachine'
    $ModulePsd1 = ($ModuleBase.GetFiles().Where({ $_.Name -like "$Name*" -and $_.Extension -eq '.psd1' }))[0]
    if ($null -eq $ModulePsd1) { return $result }
    $result.Info = [ModuleManager]::ReadPsModuleDataFile($ModulePsd1.FullName)
    $result.Name = $ModulePsd1.BaseName
    $result.Psd1 = $ModulePsd1
    $result.Path = if ($result.Psd1.Directory.Name -as [version] -is [version]) { $result.Psd1.Directory.Parent } else { $result.Psd1.Directory }
    $result.Exists = $ModulePsd1.Exists
    $result.Version = $result.Info.ModuleVersion -as [version]
    $result.IsReadOnly = $ModulePsd1.IsReadOnly
    return $result
  }
  static [LocalPsModule] FindLocalPsModule([string]$Name, [string]$scope, [version]$version) {
    $Module = $null; [ValidateNotNullOrWhiteSpace()][string]$Name = $Name
    $PsModule_Paths = $([ModuleManager]::GetModulePaths($(if ([string]::IsNullOrWhiteSpace($scope)) { "LocalMachine" }else { $scope })).ForEach({ [DirectoryInfo]::New("$_") }).Where({ $_.Exists })).GetDirectories().Where({ $_.Name -eq $Name });
    if ($PsModule_Paths.count -gt 0) {
      $Get_versionDir = [scriptblock]::Create('param([IO.DirectoryInfo[]]$direcrory) return ($direcrory | ForEach-Object { $_.GetDirectories() | Where-Object { $_.Name -as [version] -is [version] } })')
      $has_versionDir = $Get_versionDir.Invoke($PsModule_Paths).count -gt 0
      $ModulePsdFiles = $PsModule_Paths.ForEach({
          if ($has_versionDir) {
            [string]$MaxVersion = ($Get_versionDir.Invoke([IO.DirectoryInfo]::New("$_")) | Select-Object @{l = 'version'; e = { $_.BaseName -as [version] } } | Measure-Object -Property version -Maximum).Maximum
            [IO.FileInfo]::New([IO.Path]::Combine("$_", $MaxVersion, $_.BaseName + '.psd1'))
          } else {
            [IO.FileInfo]::New([IO.Path]::Combine("$_", $_.BaseName + '.psd1'))
          }
        }
      ).Where({ $_.Exists })
      $Req_ModulePsd1 = $(if ($null -eq $version) {
          $ModulePsdFiles | Sort-Object -Property version -Descending | Select-Object -First 1
        } else {
          $ModulePsdFiles | Where-Object { $([ModuleManager]::GetModuleVersion($_.FullName)) -eq $version }
        }
      )
      $Module = [ModuleManager]::FindLocalPsModule($Req_ModulePsd1.Name, $Req_ModulePsd1.Directory)
    }
    return $Module
  }
  static [string[]] GetModulePaths() {
    return [ModuleManager]::GetModulePaths($null)
  }
  static [string[]] GetModulePaths([string]$scope) {
    [string[]]$_Module_Paths = [Environment]::GetEnvironmentVariable('PSModulePath').Split([IO.Path]::PathSeparator)
    if ([string]::IsNullOrWhiteSpace($scope)) { return $_Module_Paths }
    [ValidateSet('LocalMachine', 'CurrentUser')][string]$scope = $scope
    if (!(Get-Variable -Name IsWindows -ErrorAction Ignore) -or $(Get-Variable IsWindows -ValueOnly)) {
      $psv = Get-Variable PSVersionTable -ValueOnly
      $allUsers_path = Join-Path -Path $env:ProgramFiles -ChildPath $(if ($psv.ContainsKey('PSEdition') -and $psv.PSEdition -eq 'Core') { 'PowerShell' } else { 'WindowsPowerShell' })
      if ($Scope -eq 'CurrentUser') { $_Module_Paths = $_Module_Paths.Where({ $_ -notlike "*$($allUsers_path | Split-Path)*" -and $_ -notlike "*$env:SystemRoot*" }) }
    } else {
      $allUsers_path = Split-Path -Path ([Platform]::SelectProductNameForDirectory('SHARED_MODULES')) -Parent
      if ($Scope -eq 'CurrentUser') { $_Module_Paths = $_Module_Paths.Where({ $_ -notlike "*$($allUsers_path | Split-Path)*" -and $_ -notlike "*/var/lib/*" }) }
    }
    return $_Module_Paths
  }
  static [PSObject] ReadPsModuleDataFile([string]$Path) {
    [ValidateNotNullOrWhiteSpace()][string]$Path = $Path
    return [ModuleManager]::ReadPsModuleDataFile($Path, $null)
  }
  static [psobject] ReadPsModuleDataFile([string]$Path, [string]$PropertyName) {
    if ([string]::IsNullOrWhiteSpace($PropertyName)) {
      $null = Get-Item -Path $Path -ErrorAction Stop
      $data = New-Object PSObject; $text = [IO.File]::ReadAllText("$Path")
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
        Caller           = [ModuleManager]::CallerCmdlet
        ErrorCategory    = "ObjectNotFound"
      }
      Write-TerminatingError @Error_params
    }
    $AST = [Parser]::ParseFile($Path, [ref]$Tokens, [ref]$ParseErrors)
    $KeyValue = $Ast.EndBlock.Statements
    $KeyValue = @([ModuleManager]::FindHashKeyValue($PropertyName, $KeyValue))
    if ($KeyValue.Count -eq 0) {
      $Error_params = @{
        ExceptionName    = "ItemNotFoundException"
        ExceptionMessage = "Can't find '$PropertyName' in $Path"
        ErrorId          = "PropertyNotFound,Metadata\Get-Metadata"
        Caller           = [ModuleManager]::CallerCmdlet
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
          Caller           = [ModuleManager]::CallerCmdlet
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
  static [version] GetModuleVersion([string]$Psd1Path) {
    $data = [ModuleManager]::ReadPsModuleDataFile($Psd1Path)
    $_ver = $data.ModuleVersion; if ($null -eq $_ver) { $_ver = [version][IO.FileInfo]::New($Psd1Path).Directory.Name }
    return $_ver
  }
  static [bool] IsAdmin() {
    $isAdmn = switch ([ModuleManager]::GetHostOs()) {
      "Windows" { (New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator); break }
      "Linux" { (& id -u) -eq 0; break }
      "MacOsx" { Write-Warning "MacOsx !! idk how to solve this one!"; $false; break }
      Default {
        throw "UNSUPPORTED_OS"
      }
    }
    return $isAdmn
  }
}

class LocalPsModule {
  [ValidateNotNullOrWhiteSpace()][string]$Name
  [ValidateNotNullOrEmpty()][version]$version
  [ValidateNotNullOrEmpty()][IO.FileInfo]$Psd1
  [ValidateSet('LocalMachine', 'CurrentUser')][String]$Scope
  [ValidateNotNullOrEmpty()][DirectoryInfo]$Path
  [bool]$Exists = $false
  [PsObject]$Info = $null
  [bool]$IsReadOnly = $false
  [bool]$HasVersiondirs = $false

  LocalPsModule() {}
  LocalPsModule([string]$Name) {
    [void][LocalPsModule]::_Create($Name, $null, $null, [ref]$this)
  }
  LocalPsModule([string]$Name, [string]$scope) {
    [void][LocalPsModule]::_Create($Name, $scope, $null, [ref]$this)
  }
  LocalPsModule([string]$Name, [version]$version) {
    [void][LocalPsModule]::_Create($Name, $null, $version, [ref]$this)
  }
  LocalPsModule([string]$Name, [string]$scope, [version]$version) {
    [void][LocalPsModule]::_Create($Name, $scope, $version, [ref]$this)
  }
  static [LocalPsModule] Create() {
    return [LocalPsModule]::new()
  }
  static hidden [LocalPsModule] _Create([string]$Name, [string]$scope, [version]$version, [ref]$o) {
    $m = [ModuleManager]::FindLocalPsModule($Name, $scope, $version);
    if ($null -ne $o) {
      $o.value.GetType().GetProperties().ForEach({
          $v = $m.$($_.Name)
          if ($null -ne $v) {
            $o.value.$($_.Name) = $v
          }
        }
      )
      return $o.Value
    }; return $m
  }
  [void] Delete() {
    Remove-Item $this.Path -Recurse -Force -ErrorAction Ignore
  }
}
class ModuleDirs {
  [ValidateNotNullOrEmpty()] [DirectoryInfo] $root;
  [ValidateNotNullOrEmpty()] [DirectoryInfo] $tests;
  [ValidateNotNullOrEmpty()] [DirectoryInfo] $public;
  [ValidateNotNullOrEmpty()] [DirectoryInfo] $private;
  [ValidateNotNullOrEmpty()] [DirectoryInfo] $localdata;
  ModuleDirs() {}
  [void] Create() {
    $this.List() | ForEach-Object {
      if (!$_.Exists) { $_.Create() }
    }
  }
  [List[DirectoryInfo]] List() {
    $list = [List[DirectoryInfo]]::new()
    $this.PsObject.Properties.Name.ForEach({ [void]$list.Add($this.$_) })
    return $list
  }
}
class ModuleFiles {
  [ValidateNotNullOrEmpty()] [FileInfo] $Builder;
  [ValidateNotNullOrEmpty()] [FileInfo] $Manifest;
  [ValidateNotNullOrEmpty()] [FileInfo] $Localdata;
  [ValidateNotNullOrEmpty()] [FileInfo] $rootLoader;
  [ValidateNotNullOrEmpty()] [FileInfo] $ModuleTest;
  [ValidateNotNullOrEmpty()] [FileInfo] $FeatureTest;
  [ValidateNotNullOrEmpty()] [FileInfo] $IntergrationTest;

  ModuleFiles() {}
  [void] Create() {
    $this.List() | ForEach-Object {
      if (!$_.Exists) { New-Item $_.FullName -ItemType File | Out-Null }
    }
  }
  [List[FileInfo]] List() {
    $list = [List[FileInfo]]::new()
    $this.PsObject.Properties.Name.ForEach({ [void]$list.Add($this.$_) })
    return $list
  }
}
class ParseResult {
  [Token[]]$Tokens
  [ScriptBlockAst]$AST
  [ParseError[]]$ParseErrors

  ParseResult([ParseError[]]$Errors, [Token[]]$Tokens, [ScriptBlockAst]$AST) {
    $this.ParseErrors = $Errors
    $this.Tokens = $Tokens
    $this.AST = $AST
  }
}
class PSmodule {
  [ValidateNotNullOrEmpty()]
  [String]$Name;
  [String]$Author;
  [String]$CompanyName = "alainQtec";
  [String]$Description = "A longer description of the Module, its purpose, common use cases, etc.";
  [ValidateSet('2.0', '3.0', '4.0', '5.0', '6.0', '7.0')]
  [String]$PSVersion = '3.0';
  [String]$ClrVersion = '2.0.50727';
  [String]$Copyright;
  [validateSet('Desktop', 'Core')]
  [String[]] hidden $CompatiblePSEditions;
  [version] hidden $ModuleVersion = [Version]'1.0';
  [validateSet('None', 'MSIL', 'X86', 'IA64', 'Amd64', 'Arm')]
  [System.String] hidden $ProcessorArchitecture = 'None';
  [version] hidden $PowerShellHostVersion;
  [version] hidden $DotNetFrameworkVersion;
  [System.String] hidden $PowerShellHostName;
  [ModuleDirs] $ModuleDirs = [ModuleDirs]::New();
  [ModuleFiles] $ModuleFiles = [ModuleFiles]::New();
  [Object[]] hidden $RequiredModules;
  [string[]] hidden $TypesToProcess;
  [string[]] hidden $FormatsToProcess;
  [string[]] hidden $ScriptsToProcess;
  [string[]] hidden $RequiredAssemblies;
  [string[]] hidden $FileList;
  [string[]] hidden $FunctionsToExport;
  [string[]] hidden $AliasesToExport;
  [string[]] hidden $VariablesToExport;
  [Object[]] hidden $ModuleList;
  [string[]] hidden $CmdletsToExport;
  [string[]] hidden $DscResourcesToExport;
  [ValidateNotNullOrEmpty()] [FileInfo]$Path;
  [ValidateNotNullOrEmpty()] [System.Guid]$Guid;
  [Object[]] hidden $NestedModules;
  [string[]] hidden $Tags;
  [Object] hidden $PrivateData;
  [uri] hidden $ProjectUri;
  [uri] hidden $LicenseUri;
  [uri] hidden $IconUri;
  [string] hidden $ReleaseNotes;
  [string] hidden $HelpInfoUri;
  [string] hidden $DefaultCommandPrefix;
  static [PSCustomObject] $LocalizedData = [PSmodule]::Get_Localized_Data();
  static [bool] hidden $_n = $true

  PSmodule() {
    [PSmodule]::_Create($null, $null, @(), [ref]$this)
  }
  PSmodule([string]$Name) {
    [PSmodule]::_Create($Name, $null, $null, [ref]$this)
  }

  PSmodule([string]$Name, [string]$Path) {
    [PSmodule]::_Create($Name, $Path, @(), [ref]$this)
  }
  # TODO: WIP
  # PSmodule([Array]$Configuration) {
  #   $this._Create($Configuration)
  # }
  static [PSmodule] Create([string]$Name) {
    return [PSmodule]::Create($Name, $null)
  }
  static [PSmodule] Create([string]$Name, [string]$Path) {
    $ModulePath = [IO.Path]::Combine($Path, $Name);
    if ([IO.Directory]::Exists($ModulePath)) {
      if (Get-Variable -Name ErrorActionPreference -ValueOnly -ErrorAction SilentlyContinue) {
        throw [DirectoryNotFoundException]::new("Path '$ModulePath' Not Found.")
      }
      return [PSmodule]::Load($ModulePath)
    } else {
      return [PSmodule]::new($Name, $Path)
    }
  }
  static [PSmodule] _Create([string]$Name, [string]$Path, [Array]$Config, [ref]$o) {
    if ($null -ne $Config) {
      # Config includes:
      # - Build steps
      # - Params ...
    }
    if ($null -eq $o.Value -and [PSmodule]::_n) { [PSmodule]::_n = $false; $n = [PSmodule]::new(); $o = [ref]$n }
    if ([string]::IsNullOrWhiteSpace($Name)) {
      $o.Value.Name = [IO.Path]::GetFileNameWithoutExtension([IO.Path]::GetRandomFileName())
    } else {
      $o.Value.Name = $Name
    }
    if ([string]::IsNullOrWhiteSpace($Path)) { $o.Value.SetPath($Path) } else { $o.Value.SetPath() }
    $o.Value.SetScripts()
    $o.Value.Guid = [guid]::NewGuid()
    $o.Value.Tags = $o.Value.GenerateTags()
    $o.Value.Author = $o.Value.GetAuthorName()
    $o.Value.Copyright = "Copyright {0} {1} {2}. All rights reserved." -f [string][char]169, [datetime]::Now.Year, $o.Value.Author;
    if ([string]::IsNullOrWhiteSpace($o.Value.ClrVersion)) {
      $o.Value.ClrVersion = [string]::Join('.', (Get-Variable 'PSVersionTable').Value.CLRVersion.ToString().split('.')[0..2])
    }
    if ([string]::IsNullOrWhiteSpace($o.Value.PSVersion)) {
      $o.Value.PSVersion = [string]::Join('', (Get-Variable 'PSVersionTable').Value.PSVersion.Major.ToString(), '.0')
    }
    return $o.Value
  }
  [void] SetScripts() {
    if ($null -eq [PSmodule]::LocalizedData) {
      [PSmodule]::LocalizedData = [PSmodule]::Get_Localized_Data()
    }
    [PSmodule]::LocalizedData.Keys.ForEach({
        # $str = $(([PSmodule]::LocalizedData.$_).ToString().Split("`n") -as [string[]]).foreach({
        #         if ($_.Length -ge 12) { $_.Substring(12) }
        #     }
        # )
        $src = [PSmodule]::LocalizedData.$_; $tokens = $errors = $null
        $ast = [Parser]::ParseInput($src, [ref]$tokens, [ref]$errors)
        $val = [scriptBlock]::Create("$($ast.Extent.Text)")
        [PSmodule]::LocalizedData | Add-Member -Name $_ -Value $val -MemberType NoteProperty -Force
        Write-Verbose "Parsed $_"
      }
    )
    # .Replace('<ModuleName>', $this.Name)
  }
  [void] SetPath() { $this.SetPath('') }
  [void] SetPath([string]$ModulePath) {
    $ModulePath = $(
      if ([string]::IsNullOrWhiteSpace($ModulePath)) {
        if ($this.Path) {
          if ([IO.Path]::GetFileNameWithoutExtension($this.Path) -ne $this.Name) {
            $this.Path = [FileInfo][Path]::Combine(([Path]::GetDirectoryName($this.Path) | Split-Path), "$($this.Name).psd1")
          }
          [Path]::GetDirectoryName($this.Path)
        } else { [Directory]::GetCurrentDirectory() }
      } else {
        $ModulePath
      }
    );
    $this.validatePath($ModulePath)
    $this.ModuleDirs.root = [Path]::Combine($(Get-Variable ExecutionContext -ValueOnly).SessionState.Path.GetUnresolvedProviderPathFromPSPath($ModulePath), $this.Name)
    $this.ModuleDirs.tests = [Path]::Combine($this.ModuleDirs.root.FullName, 'Tests')
    $this.ModuleDirs.public = [Path]::Combine($this.ModuleDirs.root.FullName, 'Public')
    $this.ModuleDirs.private = [Path]::Combine($this.ModuleDirs.root.FullName, 'Private')
    $this.ModuleDirs.localdata = [Path]::Combine($this.ModuleDirs.root.FullName, [Thread]::CurrentThread.CurrentCulture.Name)

    $this.ModuleFiles.Manifest = [Path]::Combine($this.ModuleDirs.root.FullName, "$($this.Name).psd1")
    $this.ModuleFiles.rootLoader = [Path]::Combine($this.ModuleDirs.root.FullName, "$($this.Name).psm1")
    $this.ModuleFiles.Builder = [Path]::Combine($this.ModuleDirs.root.FullName, "build.ps1")
    $this.ModuleFiles.Localdata = [Path]::Combine($this.ModuleDirs.localdata.FullName, "$($this.Name).strings.psd1")
    $this.ModuleFiles.ModuleTest = [Path]::Combine($this.ModuleDirs.tests.FullName, "$($this.Name).Module.Tests.ps1")
    $this.ModuleFiles.FeatureTest = [Path]::Combine($this.ModuleDirs.tests.FullName, "$($this.Name).Features.Tests.ps1")
    $this.ModuleFiles.IntergrationTest = [Path]::Combine($this.ModuleDirs.tests.FullName, "$($this.Name).Intergration.Tests.ps1")
    $this.Path = $this.ModuleFiles.Manifest
  }
  [PSmodule] static Load($Path) {
    # TODO: Add some Module load~ng code Here
    return ''
  }
  [PSmodule] static Load([string]$Name, $Path) {
    # TODO: Add some Module Loading code Here
    return ''
  }
  [void] Save() {
    $this.Save([SaveOptions]::None)
  }
  [void] Save([SaveOptions]$Options) {
    # Todo: Make good use of all save Options,not just Force/OvewriteStuff/none
    Write-Host "[+] Create Module Directories ..." -ForegroundColor Green
    $this.ModuleDirs.List() | ForEach-Object {
      $nF = @(); $p = $_; while (!$p.Exists) { $nF += $p; $p = $p.Parent }
      [Array]::Reverse($nF); foreach ($d in $nF) {
        New-Item -Path $d.FullName -ItemType Directory -Force:$($Options -eq [SaveOptions]::None)
        Write-Verbose "Created Directory '$($d.FullName)'"
      }
    }
    if ($this.CompatiblePSEditions.count -eq 0) {
      $Ps_Ed = (Get-Variable 'PSVersionTable').Value.PSEdition
      $this.CompatiblePSEditions += $(if ([string]::IsNullOrWhiteSpace($Ps_Ed)) { 'Desktop' } else { $Ps_Ed })
    }
    $newModuleManifestParams = @{
      Guid                  = $this.Guid
      Tags                  = $this.Tags
      Path                  = $this.ModuleFiles.Manifest.FullName
      Author                = $this.Author
      Copyright             = $this.Copyright
      RootModule            = $this.Name + '.psm1'
      ClrVersion            = $this.ClrVersion
      CompanyName           = $this.CompanyName
      Description           = $this.Description
      ModuleVersion         = $this.ModuleVersion
      PowershellVersion     = $this.PSVersion
      # CompatiblePSEditions  = $this.CompatiblePSEditions ie: https://blog.netnerds.net/2023/03/dont-waste-your-time-with-core-versions/
      ProcessorArchitecture = $this.ProcessorArchitecture
    }
    New-ModuleManifest @newModuleManifestParams
    $FileContents = $this.GetFileContents()
    Write-Host "[+] Create Module Files ..." -ForegroundColor Green
    $FileContents.Keys.ForEach({
        New-Item -Path $this.ModuleFiles.$_.FullName -ItemType File -Value $FileContents["$_"] -Force | Out-Null
        Write-Verbose "Created $_"
      }
    )
  }
  static [PSCustomObject] Get_Localized_Data() {
    return [PSmodule]::Get_Localized_Data($(Get-Variable ExecutionContext -ValueOnly).SessionState.Path.CurrentLocation.Path);
  }
  static [PSCustomObject] Get_Localized_Data([string]$RootPath) {
    [void][Directory]::SetCurrentDirectory($RootPath)
    $dataFile = [FileInfo]::new([IO.Path]::Combine($RootPath, [System.Threading.Thread]::CurrentThread.CurrentCulture.Name, 'PsCraft.strings.psd1'))
    if (!$dataFile.Exists) { throw [FileNotFoundException]::new('Unable to find the LocalizedData file!', $dataFile) }
    return [scriptblock]::Create("$([IO.File]::ReadAllText($dataFile))").Invoke()
  }
  [hashtable] GetFileContents() {
    if ($null -eq [PSmodule]::LocalizedData) { $this.SetScripts() }
    return @{
      Builder          = [PSmodule]::LocalizedData.Builder.Ast.ToString().Trim()
      Localdata        = [PSmodule]::LocalizedData.Localdata.Ast.ToString().Trim()
      rootLoader       = [PSmodule]::LocalizedData.rootLoader.Ast.ToString().Trim()
      ModuleTest       = [PSmodule]::LocalizedData.ModuleTest.Ast.ToString().Trim()
      FeatureTest      = [PSmodule]::LocalizedData.FeatureTest.Ast.ToString().Trim()
      IntergrationTest = [PSmodule]::LocalizedData.IntergrationTest.Ast.ToString().Trim()
    }
  }
  [void] Delete() {
    Get-Module $this.Name | Remove-Module -Force -ErrorAction SilentlyContinue
    Remove-Item $this.moduleDir -Recurse -Force -ErrorAction SilentlyContinue
  }
  [void] Test() {
    $this.Save()
    # .then run tests
  }
  [void] Publish() {
    $this.Publish('LocalRepo', [IO.Path]::GetDirectoryName($Pwd))
  }
  [void] Publish($repoName, $repoPath) {
    if (Test-Path -Type Container -Path $repoPath -ErrorAction SilentlyContinue) {
      throw ""
    } else {
      New-Item -Path $repoPath -ItemType Directory | Out-Null
    }
    $this.Save()
    # If the PSrepo is not known, create one.
    if (![bool](Get-PSRepository "$repoName" -ErrorAction SilentlyContinue).Trusted) {
      $repoParams = @{
        Name               = $repoName
        SourceLocation     = $repoPath
        PublishLocation    = $repoPath
        InstallationPolicy = 'Trusted'
      }
      Register-PSRepository @repoParams
    }
    Publish-Module -Path $this.moduleDir -Repository $repoName
    Install-Module $this.Name -Repository $repoName
  }
  static [void] Publish ([string]$Path, [securestring]$ApiKey, [bool]$IncrementVersion ) {
    $moduleName = Split-Path $Path -Leaf
    $functions = Get-PsModuleFunctions $Path -PublicOnly
    if ($IncrementVersion) {
      $moduleFile = "$((Join-Path $path $moduleName)).psd1"
      $file = Import-PowerShellDataFile $moduleFile -Verbose:$false;
      [version]$version = ($file).ModuleVersion
      [version]$newVersion = "{0}.{1}.{2}" -f $version.Major, $version.Minor, ($version.Build + 1)
      Update-ModuleManifest -Path "$((Join-Path $Path $moduleName)).psd1" -FunctionsToExport $functions -ModuleVersion $newVersion;
    } else {
      Update-ModuleManifest -Path "$((Join-Path $Path $moduleName)).psd1" -FunctionsToExport $functions;
    }
    Publish-Module -Path $Path -NuGetApiKey $ApiKey;

    Write-Host "Module $moduleName Published " -f Green;
  }
  hidden [string[]] GenerateTags() {
    return $this.GenerateTags($this.Description)
  }
  hidden [string[]] GenerateTags([string]$Description) {
    # TODO: use AI to generate tags
    # This is meant to achieve Text Classification level like that of: https://learn.microsoft.com/en-us/ai-builder/text-classification-model-use-tags
    return ('Psmodule', 'PowerShell')
  }
  hidden [void] validatePath([string]$path) {
    $InvalidPathChars = [Path]::GetInvalidPathChars()
    $InvalidCharsRegex = "[{0}]" -f [regex]::Escape($InvalidPathChars)
    if ($Path -match $InvalidCharsRegex) {
      throw [InvalidEnumArgumentException]::new("The path string contains invalid characters.")
    }
  }
  hidden [string] GetAuthorName() {
    $AuthorName = [Environment]::GetEnvironmentVariable('UserName')
    try {
      $OS = [OperatingSystem]
      $AuthorName = switch ($true) {
        $OS::IsWindows() {
          Get-CimInstance -ClassName Win32_UserAccount -Verbose:$false | Where-Object { [Environment]::UserName -eq $_.Name } | Select-Object -ExpandProperty FullName
          break
        }
                ($OS::IsMacOS() -or $OS::IsLinux()) {
          $s = getent passwd "$([Environment]::UserName)"
          $s.Split(":")[4]
          break
        }
        # $OS::IsBrowser() {  }
        # $OS::IsTvOS() {  }
        # $OS::IsIOS() {  }
        # $OS::IsFreeBSD() {  }
        # $OS::IsAndroid() {  }
        # $OS::IsWatchOS() {  }
        Default {
          $msg = "OperatingSystem '{0}' is Not supported!" -f [Environment]::OSVersion.Platform
          Write-Warning -Message $msg
        }
      }
    } catch {
      throw $_
    }
    return $AuthorName
  }
}

class AliasVisitor : System.Management.Automation.Language.AstVisitor {
  [string]$Parameter = $null
  [string]$Command = $null
  [string]$Name = $null
  [string]$Value = $null
  [string]$Scope = $null
  [HashSet[String]]$Aliases = @()

  # Parameter Names
  [AstVisitAction] VisitCommandParameter([CommandParameterAst]$ast) {
    $this.Parameter = $ast.ParameterName
    return [AstVisitAction]::Continue
  }

  # Parameter Values
  [AstVisitAction] VisitStringConstantExpression([StringConstantExpressionAst]$ast) {
    # The FIRST command element is always the command name
    if (!$this.Command) {
      $this.Command = $ast.Value
      return [AstVisitAction]::Continue
    } else {
      # Nobody should use minimal parameters like -N for -Name ...
      # But if they do, our parser works anyway!
      switch -Wildcard ($this.Parameter) {
        "S*" {
          $this.Scope = $ast.Value
        }
        "N*" {
          $this.Name = $ast.Value
        }
        "Va*" {
          $this.Value = $ast.Value
        }
        "F*" {
          if ($ast.Value) {
            # Force parameter was passed as named parameter with a positional parameter after it which is alias name
            $this.Name = $ast.Value
          }
        }
        default {
          if (!$this.Parameter) {
            # For bare arguments, the order is Name, Value:
            if (!$this.Name) {
              $this.Name = $ast.Value
            } else {
              $this.Value = $ast.Value
            }
          }
        }
      }

      $this.Parameter = $null

      # If we have enough information, stop the visit
      # For -Scope global or Remove-Alias, we don't want to export these
      if ($this.Name -and $this.Command -eq "Remove-Alias") {
        $this.Command = "Remove-Alias"
        return [AstVisitAction]::StopVisit
      } elseif ($this.Name -and $this.Scope -eq "Global") {
        return [AstVisitAction]::StopVisit
      }
      return [AstVisitAction]::Continue
    }
  }

  # The [Alias(...)] attribute on functions matters, but we can't export aliases that are defined inside a function
  [AstVisitAction] VisitFunctionDefinition([FunctionDefinitionAst]$ast) {
    @($ast.Body.ParamBlock.Attributes.Where{ $_.TypeName.Name -eq "Alias" }.PositionalArguments.Value).ForEach{
      if ($_) {
        $this.Aliases.Add($_)
      }
    }
    return [AstVisitAction]::SkipChildren
  }

  # Top-level commands matter, but only if they're alias commands
  [AstVisitAction] VisitCommand([CommandAst]$ast) {
    if ($ast.CommandElements[0].Value -imatch "(New|Set|Remove)-Alias") {
      $ast.Visit($this.ClearParameters())
      $Params = $this.GetParameters()
      # We COULD just remove it (even if we didn't add it) ...
      if ($Params.Command -ieq "Remove-Alias") {
        # But Write-Verbose for logging purposes
        if ($this.Aliases.Contains($this.Parameters.Name)) {
          Write-Verbose -Message "Alias '$($Params.Name)' is removed by line $($ast.Extent.StartLineNumber): $($ast.Extent.Text)"
          $this.Aliases.Remove($Params.Name)
        }
        # We don't need to export global aliases, because they broke out already
      } elseif ($Params.Name -and $Params.Scope -ine 'Global') {
        $this.Aliases.Add($this.Parameters.Name)
      }
    }
    return [AstVisitAction]::SkipChildren
  }
  [PSCustomObject] GetParameters() {
    return [PSCustomObject]@{
      PSTypeName = "PsCraft.AliasVisitor.AliasParameters"
      Name       = $this.Name
      Command    = $this.Command
      Parameter  = $this.Parameter
      Value      = $this.Value
      Scope      = $this.Scope
    }
  }
  [AliasVisitor] ClearParameters() {
    $this.Command = $null
    $this.Parameter = $null
    $this.Name = $null
    $this.Value = $null
    $this.Scope = $null
    return $this
  }
}
#endregion Classes


#region    functions

function New-Directory {
  [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'str')]
  param (
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'str')]
    [ValidateNotNullOrEmpty()][string]$Path,
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'dir')]
    [ValidateNotNullOrEmpty()][DirectoryInfo]$Dir
  )
  $nF = @(); $p = if ($PSCmdlet.ParameterSetName.Equals('str')) { [DirectoryInfo]::New($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)) } else { $Dir }
  if ($PSCmdlet.ShouldProcess("Creating Directory '$($p.FullName)' ...", '', '')) {
    while (!$p.Exists) { $nF += $p; $p = $p.Parent }
    [Array]::Reverse($nF); $nF | ForEach-Object { $_.Create() }
  }
}

function Write-BuildLog {
  [CmdletBinding()]
  param(
    [parameter(Mandatory, Position = 0, ValueFromRemainingArguments, ValueFromPipeline)]
    [System.Object]$Message,

    [parameter()]
    [Alias('c', 'Command')]
    [Switch]$Cmd,

    [parameter()]
    [Alias('w')]
    [Switch]$Warning,

    [parameter()]
    [Alias('s', 'e')]
    [Switch]$Severe,

    [parameter()]
    [Alias('x', 'nd', 'n')]
    [Switch]$Clean
  )
  Begin {
    ($f, $l) = switch ($true) {
      $($PSBoundParameters.ContainsKey('Debug') -and $PSBoundParameters['Debug'] -eq $true) { 'Yellow', '##[debug]   '; break }
      $($PSBoundParameters.ContainsKey('Verbose') -and $PSBoundParameters['Verbose'] -eq $true) { $(if ($Host.UI.RawUI.ForegroundColor -eq 'Gray') { 'White' } else { 'Gray' }), '##[Verbose] '; break }
      $Severe { 'Red', '##[Error]   '; break }
      $Warning { 'Yellow', '##[Warning] '; break }
      $Cmd { 'Magenta', '##[Command] '; break }
      Default {
        $(if ($Host.UI.RawUI.ForegroundColor -eq 'Gray') { 'White' } else { 'Gray' }), '##[Info]    '
      }
    }
  }
  Process {
    $fmtMsg = if ($Clean) {
      $Message -split "[\r\n]" | Where-Object { $_ } | ForEach-Object {
        $l + $_
      }
    } else {
      $date = "$([ModuleManager]::GetElapsed()) "
      if ($Cmd) {
        $i = 0
        $Message -split "[\r\n]" | Where-Object { $_ } | ForEach-Object {
          $tag = if ($i -eq 0) {
            'PS > '
          } else {
            '  >> '
          }
          $l + $date + $tag + $_
          $i++
        }
      } else {
        $Message -split "[\r\n]" | Where-Object { $_ } | ForEach-Object {
          $l + $date + $_
        }
      }
    }
    Write-Host -ForegroundColor $f $($fmtMsg -join "`n")
  }
}

function Write-TerminatingError {
  # .SYNOPSIS
  #   function to throw an errorrecord
  # .DESCRIPTION
  #   Used when we don't have built-in ThrowError (ie: $PowerShellversion -lt core-6.1.0-windows)
  [CmdletBinding()]
  [OutputType([ErrorRecord])]
  param (
    [parameter(Mandatory = $false)]
    [AllowNull()]
    [PSCmdlet]$Caller = $null,

    [parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [String]$ExceptionName,

    [parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [String]$ExceptionMessage,

    [parameter(Mandatory = $false)]
    [Object]$ExceptionObject = @{},

    [parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [String]$ErrorId,

    [parameter(Mandatory = $true)]
    [ValidateNotNull()]
    [ErrorCategory]$ErrorCategory
  )
  process {
    $exception = New-Object $ExceptionName $ExceptionMessage;
    $errorRecord = [ErrorRecord]::new($exception, $ErrorId, $ErrorCategory, $ExceptionObject)
  }
  end {
    if ($null -ne $Caller) {
      $Caller.ThrowTerminatingError($errorRecord)
    } else {
      throw $errorRecord
    }
  }
}
#endregion functions