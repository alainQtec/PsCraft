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
  #     Build-Module -t deploy
  #     Will build the module, test it and deploy it to PsGallery
  [cmdletbinding(DefaultParameterSetName = 'task')]
  param(
    [parameter(Position = 0, ParameterSetName = 'task')]
    [ValidateScript({
        $task_seq = [string[]]$_; $IsValid = $true
        $Tasks = @('Init', 'Clean', 'Compile', 'Test', 'Deploy')
        foreach ($name in $task_seq) {
          $IsValid = $IsValid -and ($name -in $Tasks)
        }
        if ($IsValid) {
          return $true
        } else {
          throw [System.ArgumentException]::new('Task', "ValidSet: $($Tasks -join ', ').")
        }
      }
    )][ValidateNotNullOrEmpty()][Alias('t')]
    [string[]]$Task = @('Init', 'Clean', 'Compile'),

    # Module buildRoot
    [Parameter(Mandatory = $false, ParameterSetName = 'task')]
    [ValidateScript({
        if (Test-Path -Path $_ -PathType Container -ErrorAction Ignore) {
          return $true
        } else {
          throw [System.ArgumentException]::new('Path', "Path: $_ is not a valid directory.")
        }
      })][Alias('p')]
    [string]$Path = (Get-Item -Path "." -Verbose:$false).FullName,

    [Parameter(Mandatory = $false, ParameterSetName = 'task')]
    [Alias('u')][ValidateNotNullOrWhiteSpace()]
    [string]$gitUser,

    [parameter(ParameterSetName = 'task')]
    [Alias('i')]
    [switch]$Import,

    [parameter(ParameterSetName = 'help')]
    [Alias('h', '-help')]
    [switch]$Help
  )

  Begin {
    #Requires -RunAsAdministrator
    if ($null -ne ${env:=::}) { $PSCmdlet.ThrowTerminatingError('Please Run this command as administrator') }
    #region    Variables
    [Environment]::SetEnvironmentVariable('IsAC', $(if (![string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('GITHUB_WORKFLOW'))) { '1' } else { '0' }), [System.EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('IsCI', $(if (![string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('TF_BUILD'))) { '1' }else { '0' }), [System.EnvironmentVariableTarget]::Process)
    [Environment]::SetEnvironmentVariable('RUN_ID', $(if ([bool][int]$env:IsAC -or $env:CI -eq "true") { [Environment]::GetEnvironmentVariable('GITHUB_RUN_ID') }else { [Guid]::NewGuid().Guid.substring(0, 21).replace('-', [string]::Join('', (0..9 | Get-Random -Count 1))) + '_' }), [System.EnvironmentVariableTarget]::Process);
    $LocalPSRepo = [IO.Path]::Combine([environment]::GetEnvironmentVariable("HOME"), 'LocalPSRepo')
    Set-BuildVariables -Path $Path -Prefix $env:RUN_ID
    $script:Psake_BuildFile = New-Item $([IO.Path]::GetTempFileName().Replace('.tmp', '.ps1'))
    $script:PSake_ScriptBlock = [scriptblock]::Create({
        Write-Heading "Installing Pscraft module Requirements..."
        if (!(Get-Module PsCraft -ListAvailable -ErrorAction Ignore)) { Install-Module PsCraft -Verbose:$false };
        (Get-InstalledModule PsCraft -ErrorAction Ignore).InstalledLocation | Split-Path | Import-Module -Verbose:$false
        $null = Import-PackageProvider -Name NuGet -Force
        $_req = @(
          "PackageManagement"
          "PSScriptAnalyzer"
          "PowerShellGet"
          "cliHelper.core"
          "cliHelper.env"
          "Pester"
          "Psake"
        )
        foreach ($Name in $_req) {
          $Host.UI.WriteLine();
          Resolve-Module -Name $Name -UpdateModule -Verbose:$false
        }
        $Host.UI.WriteLine()
        Write-BuildLog "Module Requirements Successfully resolved."
        Properties {
          # PSake makes variables declared in here available in other scriptblocks
          $taskList = $Task
          $Cmdlet = $PSCmdlet
          $ProjectName = [Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName')
          $BuildNumber = [Environment]::GetEnvironmentVariable($env:RUN_ID + 'BuildNumber')
          $ProjectRoot = [Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectPath')
          $outputDir = [Environment]::GetEnvironmentVariable($env:RUN_ID + 'BuildOutput')
          $Timestamp = Get-Date -UFormat "%Y%m%d-%H%M%S"
          $PSVersion = $PSVersionTable.PSVersion.ToString()
          $outputModDir = [IO.path]::Combine([Environment]::GetEnvironmentVariable($env:RUN_ID + 'BuildOutput'), $ProjectName)
          $tests = [IO.Path]::Combine($projectRoot, "Tests")
          $lines = ('-' * 70);
          $TestFile = "TestResults_PS$PSVersion`_$TimeStamp.xml"
          $outputModVerDir = [IO.path]::Combine([Environment]::GetEnvironmentVariable($env:RUN_ID + 'BuildOutput'), $ProjectName, $BuildNumber)
          $PathSeperator = [IO.Path]::PathSeparator
          $DirSeperator = [IO.Path]::DirectorySeparatorChar
          # To prevent "variable not used" warnings:
          $null = @($taskList, $Cmdlet, $tests, $getelapsed, $TestFile, $ProjectRoot, $outputDir, $outputModDir, $outputModVerDir, $lines, $DirSeperator, $PathSeperator)
        }
        #Task Default -Depends Init,Test and Compile. Deploy Has to be done Manually
        Task default -Depends Test

        Task Init {
          Set-Location $ProjectRoot
          Write-EnvironmentSummary "Build started"
          Write-Verbose "Module Build version: $BuildNumber"
          $security_protocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::SystemDefault
          if ([Net.SecurityProtocolType].GetMember("Tls12").Count -gt 0) { $security_protocol = $security_protocol -bor [Net.SecurityProtocolType]::Tls12 }
          [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]$security_protocol
          $Host.ui.WriteLine()
          Invoke-CommandWithLog { $script:DefaultParameterValues = @{
              '*-Module:Verbose'           = $false
              'Import-Module:ErrorAction'  = 'Stop'
              'Import-Module:Force'        = $true
              'Import-Module:Verbose'      = $false
              'Install-Module:ErrorAction' = 'Stop'
              'Install-Module:Scope'       = 'CurrentUser'
              'Install-Module:Verbose'     = $false
            }
          }
          Write-Heading "Prepare package feeds"
          $Host.ui.WriteLine()
          if ($null -eq (Get-PSRepository -Name PSGallery -ErrorAction Ignore)) {
            Unregister-PSRepository -Name PSGallery -Verbose:$false -ErrorAction Ignore
            Register-PSRepository -Default -InstallationPolicy Trusted
          }
          if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
            Invoke-CommandWithLog { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -Verbose:$false }
          }
          # if ((Get-Command dotnet -ErrorAction Ignore) -and ([bool](Get-Variable -Name IsWindows -ErrorAction Ignore) -and !$(Get-Variable IsWindows -ValueOnly))) {
          #     dotnet dev-certs https --trust
          # }
          Invoke-CommandWithLog { Get-PackageProvider -Name Nuget -ForceBootstrap -Verbose:$false }
          if (!(Get-PackageProvider -Name Nuget)) {
            Invoke-CommandWithLog { Install-PackageProvider -Name NuGet -Force | Out-Null }
          }
          $build_sys = [Environment]::GetEnvironmentVariable($env:RUN_ID + 'BuildSystem');
          $lastCommit = git log -1 --pretty=%B
          Write-BuildLog "Current build system is $build_sys"
          Write-Heading "Finalizing build Prerequisites and Resolving dependencies ..."

          if ($build_sys -eq 'VSTS' -or ($env:CI -eq "true" -and $env:GITHUB_RUN_ID)) {
            if ($Task -contains 'Deploy') {
              $MSG = "Task is 'Deploy' and conditions for deployment are:`n" +
              "    + GitHub API key is not null       : $(![string]::IsNullOrWhiteSpace($env:GitHubPAT))`n" +
              "    + Current branch is main           : $(($env:GITHUB_REF -replace "refs/heads/") -eq 'main')`n" +
              "    + Source is not a pull request     : $($env:GITHUB_EVENT_NAME -ne "pull_request") [$env:GITHUB_EVENT_NAME]`n" +
              "    + Commit message matches '!deploy' : $($lastCommit -match "!deploy") [$lastCommit]`n" +
              "    + Is Current PS version < 5 ?      : $($PSVersionTable.PSVersion.Major -lt 5) [$($PSVersionTable.PSVersion.ToString())]`n" +
              "    + NuGet API key is not null        : $(![string]::IsNullOrWhiteSpace($env:NUGETAPIKEY))`n"
              if ($PSVersionTable.PSVersion.Major -lt 5 -or [string]::IsNullOrWhiteSpace($env:NUGETAPIKEY) -or [string]::IsNullOrWhiteSpace($env:GitHubPAT) ) {
                $MSG = $MSG.Replace('and conditions for deployment are:', 'but conditions are not correct for deployment.')
                $MSG | Write-Host -f Yellow
                if (($([Environment]::GetEnvironmentVariable($env:RUN_ID + 'CommitMessage')) -match '!deploy' -and $([Environment]::GetEnvironmentVariable($env:RUN_ID + 'BranchName')) -eq "main") -or $script:ForceDeploy -eq $true) {
                  Write-Warning "Force Deploying detected"
                } else {
                  "Skipping Psake for this job!" | Write-Host -f Yellow
                  exit 0
                }
              } else {
                $MSG | Write-Host -f Green
              }
            }
          }
        } -Description 'Initialize build environment'

        Task -Name clean -Depends Init {
          $Host.UI.WriteLine()
          Write-Host "    Removed any installed versions of [$ProjectName]" -F Green
          $modules = Get-Module -Name $ProjectName -ListAvailable -ErrorAction Ignore
          if ($modules) { $modules | Remove-Module -Verbose:$false -Force -ErrorAction Ignore | Out-Null }
          if (Test-Path -Path $outputDir -PathType Container -ErrorAction Ignore) {
            Write-Verbose "Cleaning Previous build Output ..."
            Get-ChildItem -Path $outputDir -Recurse -Force | Remove-Item -Force -Recurse -Verbose:$false | Out-Null
          }
          Write-Host "    Removed previous Output directory [$outputDir]" -F Green
        } -Description 'Cleans module output directory'

        Task Compile -Depends Clean {
          Write-Verbose "Create module Output directory"
          New-Item -Path $outputModVerDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
          $ModuleManifest = [IO.FileInfo]::New([Environment]::GetEnvironmentVariable($env:RUN_ID + 'PSModuleManifest'))
          Write-BuildLog "Add Module files ...`nRef: https://aka.ms/nuget/authoring-best-practices"
          try {
            $d = [Environment]::GetEnvironmentVariable($env:RUN_ID + 'PSModulePath')
            @(
              "en-US"
              "Private"
              "Public"
              "LICENSE"
              "README.md"
              "$($ModuleManifest.Name)"
              "$ProjectName.psm1"
            ).ForEach({
                $p = [IO.Path]::Combine($([Environment]::GetEnvironmentVariable($env:RUN_ID + 'BuildScriptPath')), $_)
                if (Test-Path -Path $p -ErrorAction Ignore) {
                  Copy-Item -Recurse -Path $p -Destination $d
                }
              }
            )
          } catch {
            $Cmdlet.ThrowTerminatingError($_)
          }
          if (!$ModuleManifest.Exists) { $Cmdlet.ThrowTerminatingError([System.IO.FileNotFoundException]::New('Could Not Create Module Manifest!')) }
          $functionsToExport = @(); $publicFunctionsPath = [IO.Path]::Combine([Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectPath'), "Public")
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
            "<ModuleVersion>", $BuildNumber
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

        Task Test -Depends Compile {
          Write-Heading "Executing Script: ./Test-Module.ps1"
          $test_Script = [IO.FileInfo]::New([IO.Path]::Combine($ProjectRoot, 'Test-Module.ps1'))
          if (!$test_Script.Exists) { $Cmdlet.ThrowTerminatingError([System.IO.FileNotFoundException]::New($test_Script.FullName)) }
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
            $Cmdlet.WriteError("One or more Pester tests failed!")
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
                Write-Host -f Yellow "Version in commit message is $commitVer, which is less than the next Gallery version and would result in an error. Possible duplicate deployment build, skipping module bump and negating deployment"
                Set-EnvironmentVariable -Name ($env:RUN_ID + 'CommitMessage') -Value $([Environment]::GetEnvironmentVariable($env:RUN_ID + 'CommitMessage')).Replace('!deploy', '')
                $null
                break
              }
              $($commitVer -and ([System.Version]$commitVer -gt $nextGalVer)) {
                Write-Host -f Green "Module Bumped version: $commitVer [from commit message]"
                [System.Version]$commitVer
                break
              }
              $($CurrentVersion -ge $nextGalVer) {
                Write-Host -f Green "Module Bumped version: $CurrentVersion [from manifest]"
                $CurrentVersion
                break
              }
              $(([Environment]::GetEnvironmentVariable($env:RUN_ID + 'CommitMessage')) -match '!hotfix') {
                Write-Host -f Green "Module Bumped version: $nextGalVer [commit message match '!hotfix']"
                $nextGalVer
                break
              }
              $(([Environment]::GetEnvironmentVariable($env:RUN_ID + 'CommitMessage')) -match '!minor') {
                $minorVers = [System.Version]("{0}.{1}.{2}" -f $nextGalVer.Major, ([int]$nextGalVer.Minor + 1), 0)
                Write-Host -f Green "Module Bumped version: $minorVers [commit message match '!minor']"
                $minorVers
                break
              }
              $(([Environment]::GetEnvironmentVariable($env:RUN_ID + 'CommitMessage')) -match '!major') {
                $majorVers = [System.Version]("{0}.{1}.{2}" -f ([int]$nextGalVer.Major + 1), 0, 0)
                Write-Host -f Green "Module Bumped version: $majorVers [commit message match '!major']"
                $majorVers
                break
              }
              Default {
                Write-Host -f Green "Module Bumped version: $nextGalVer [PSGallery next version]"
                $nextGalVer
              }
            }
            if (!$versionToDeploy) {
              Write-Host -f Yellow "No module version matched! Negating deployment to prevent errors"
              Set-EnvironmentVariable -Name ($env:RUN_ID + 'CommitMessage') -Value $([Environment]::GetEnvironmentVariable($env:RUN_ID + 'CommitMessage')).Replace('!deploy', '')
            }
            try {
              [ValidateNotNullOrWhiteSpace()][string]$versionToDeploy = $versionToDeploy.ToString()
              $manifest = Import-PowerShellDataFile -Path $([Environment]::GetEnvironmentVariable($env:RUN_ID + 'PSModuleManifest'))
              $latest_Github_release = Invoke-WebRequest "https://api.github.com/repos/alainQtec/PsCraft/releases/latest" | ConvertFrom-Json
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
                $ZipTmpPath = [System.IO.Path]::Combine($ProjectRoot, "$($([Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName'))).zip")
                if ([IO.File]::Exists($ZipTmpPath)) { Remove-Item $ZipTmpPath -Force }
                Add-Type -Assembly System.IO.Compression.FileSystem
                [System.IO.Compression.ZipFile]::CreateFromDirectory($outputModDir, $ZipTmpPath)
                Write-Heading "    Publishing Release v$versionToDeploy @ commit Id [$($commitId)] to GitHub..."
                $ReleaseNotes += (git log -1 --pretty=%B | Select-Object -Skip 2) -join "`n"
                $ReleaseNotes = $ReleaseNotes.Replace('<versionToDeploy>', $versionToDeploy)
                Set-EnvironmentVariable -Name ('{0}{1}' -f $env:RUN_ID, 'ReleaseNotes') -Value $ReleaseNotes
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
                Write-Heading "    Github release created successful!"
              } else {
                if ($Is_Lower_GitHub_Version) { Write-Warning "SKIPPED Releasing. Module version $current_build_version already exists on Github!" }
                Write-Verbose "    SKIPPED GitHub Release v$($versionToDeploy) @ commit Id [$($commitId)] to GitHub"
              }
            } catch {
              $_ | Format-List * -Force
              if ([bool][int]$env:IsCI) {
                $Cmdlet.WriteError("##vso[task.logissue type=error; ] $($_.Exception.Message)")
              } else {
                $Cmdlet.WriteError($_)
              }
            }
          } else {
            Write-Host -f Magenta "UNKNOWN Build system"
          }
        }
      }
    )
    $script:Clean_EnvBuildvariables = [scriptblock]::Create({
        Param (
          [Parameter(Position = 0)]
          [ValidatePattern('\w*')]
          [ValidateNotNullOrEmpty()]
          [string]$build_Id
        )
        Write-Heading "CleanUp: Remove $ModuleName, env variables, and delete LocalPSRepo"
        if (![string]::IsNullOrWhiteSpace($build_Id)) {
          $OldEnvNames = [Environment]::GetEnvironmentVariables().Keys | Where-Object { $_ -like "$build_Id*" }
          if ($OldEnvNames.Count -gt 0) {
            foreach ($Name in $OldEnvNames) {
              Write-BuildLog "Remove env variable $Name"
              [Environment]::SetEnvironmentVariable($Name, $null)
            }
          } else {
            Write-BuildLog "No old Env variables to remove; Move on ...`n"
          }
        } else {
          Write-Warning "Invalid RUN_ID! Skipped 'Remove env variables' ...`n"
        }
      }
    )
    #endregion Variables
  }
  Process {
    if ($Help) {
      Write-Heading "Getting help"
      Write-BuildLog -c '"psake" | Resolve-Module @Mod_Res -Verbose'
      Resolve-Module -Name 'psake' -Verbose:$false
      Get-PSakeScriptTasks -BuildFile $Psake_BuildFile.FullName | Sort-Object -Property Name | Format-Table -Property Name, Description, Alias, DependsOn
      exit 0
    };
    try {
      $null = Set-Content -Path $script:Psake_BuildFile -Value $script:PSake_ScriptBlock
      Write-Heading "Invoking psake with task list: [ $($Task -join ', ') ]"
      $psakeParams = @{
        nologo    = $true
        buildFile = $script:Psake_BuildFile.FullName
        taskList  = $Task
      }
      if ($Task -contains 'TestOnly') {
        Set-Variable -Name ExcludeTag -Scope global -Value @('Module')
      } else {
        Set-Variable -Name ExcludeTag -Scope global -Value $null
      }
      Invoke-psake @psakeParams @verbose
    } catch {
      $PSCmdlet.ThrowTerminatingError($_)
    } finally {
      $Host.UI.WriteLine()
      Remove-Item $Psake_BuildFile -Verbose | Out-Null
      if ($psake.build_success) {
        Write-Heading "Create a Local repository"
        if (!(Get-Variable -Name IsWindows -ErrorAction Ignore) -or $(Get-Variable IsWindows -ValueOnly)) {
          $LocalPSRepo = [IO.Path]::Combine([environment]::GetEnvironmentVariable("UserProfile"), 'LocalPSRepo')
        }; if (!(Test-Path -Path $LocalPSRepo -PathType Container -ErrorAction Ignore)) { New-Directory -Path $LocalPSRepo | Out-Null }
        Register-PSRepository LocalPSRepo -SourceLocation $LocalPSRepo -PublishLocation $LocalPSRepo -InstallationPolicy Trusted -Verbose:$false -ErrorAction Ignore;
        Register-PackageSource -Name LocalPsRepo -Location $LocalPSRepo -Trusted -ProviderName Bootstrap -ErrorAction Ignore
        Write-Verbose "Verify that the new repository was created successfully"
        if ($null -eq (Get-PSRepository LocalPSRepo -Verbose:$false -ErrorAction Ignore)) {
          $PSCmdlet.ThrowTerminatingError([System.Exception]::New('Failed to create LocalPsRepo', [System.IO.DirectoryNotFoundException]::New($LocalPSRepo)))
        }
        $ModuleName = [Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName')
        $BuildNumber = [Environment]::GetEnvironmentVariable($env:RUN_ID + 'BuildNumber')
        $ModulePath = [IO.Path]::Combine($([Environment]::GetEnvironmentVariable($env:RUN_ID + 'BuildOutput')), $([Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName')), $BuildNumber)
        # Publish To LocalRepo
        $ModulePackage = [IO.Path]::Combine($LocalPSRepo, "${ModuleName}.${BuildNumber}.nupkg")
        if ([IO.File]::Exists($ModulePackage)) {
          Remove-Item -Path $ModulePackage -ErrorAction 'SilentlyContinue'
        }
        Write-Heading "Publish to Local PsRepository"
        $RequiredModules = Get-ModuleManifest ([IO.Path]::Combine($ModulePath, "$([Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName')).psd1")) RequiredModules -Verbose:$false
        foreach ($Module in $RequiredModules) {
          $mdPath = (Get-Module $Module -ListAvailable -Verbose:$false)[0].Path | Split-Path
          Write-Verbose "Publish RequiredModule $Module ..."
          Publish-Module -Path $mdPath -Repository LocalPSRepo -Verbose:$false -ErrorAction Ignore
        }
        Publish-Module -Path $ModulePath -Repository LocalPSRepo
        # Install Module
        Install-Module $ModuleName -Repository LocalPSRepo
        # Import Module
        if ($Import.IsPresent -and $(Get-Variable psake -Scope global -ValueOnly).build_success) {
          Write-Heading "Import $ModuleName to local scope"
          # Import-Module $([IO.Path]::Combine([Environment]::GetEnvironmentVariable($env:RUN_ID + 'BuildOutput'), $ModuleName))
          Import-Module $ModuleName -Verbose:$false
        }
      }
      Write-EnvironmentSummary "Build finished"
      if (![bool][int]$env:IsAC -or $Task -contains 'Clean') {
        Invoke-Command $Clean_EnvBuildvariables -ArgumentList $env:RUN_ID
        Uninstall-Module $ModuleName -MinimumVersion $BuildNumber -ErrorAction Ignore
        # Get-ModulePath $ModuleName | Remove-Item -Recurse -Force -ErrorAction Ignore
        if ([IO.Directory]::Exists($LocalPSRepo)) {
          if ($null -ne (Get-PSRepository -Name 'LocalPSRepo' -ErrorAction Ignore -Verbose:$false)) {
            Invoke-Command -ScriptBlock ([ScriptBlock]::Create("Unregister-PSRepository -Name 'LocalPSRepo' -Verbose:`$false -ErrorAction Ignore"))
          }; Remove-Item $LocalPSRepo -Verbose:$false -Force -Recurse -ErrorAction Ignore
        }
        [Environment]::SetEnvironmentVariable('RUN_ID', $null)
      }
    }
  }
  end {
    exit ([int](!$psake.build_success))
  }
}