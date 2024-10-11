@{
  ModuleName       = 'PsCraft'
  ModuleVersion    = [version]::new(0, 1, 0)
  rootLoader       = [scriptBlock]::create({
      #!/usr/bin/env pwsh
      #region    Classes
      #endregion Classes
      $Private = Get-ChildItem ([IO.Path]::Combine($PSScriptRoot, 'Private')) -Filter "*.ps1" -ErrorAction SilentlyContinue
      $Public = Get-ChildItem ([IO.Path]::Combine($PSScriptRoot, 'Public')) -Filter "*.ps1" -ErrorAction SilentlyContinue
      # Load dependencies
      $PrivateModules = [string[]](Get-ChildItem ([IO.Path]::Combine($PSScriptRoot, 'Private')) -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | Select-Object -ExpandProperty FullName)
      if ($PrivateModules.Count -gt 0) {
        foreach ($Module in $PrivateModules) {
          Try {
            Import-Module $Module -ErrorAction Stop
          } Catch {
            Write-Error "Failed to import module $Module : $_"
          }
        }
      }
      # Dot source the files
      foreach ($Import in ($Public, $Private)) {
        Try {
          . $Import.fullname
        } Catch {
          Write-Warning "Failed to import function $($Import.BaseName): $_"
          $host.UI.WriteErrorLine($_)
        }
      }
      # Export Public Functions
      $Param = @{
        Function = $Public.BaseName
        Variable = '*'
        Cmdlet   = '*'
        Alias    = '*'
      }
      Export-ModuleMember @Param -Verbose
    }
  )
  Builder          = [scriptBlock]::create({})
  ModuleTest       = [scriptBlock]::create({
      $script:ModuleName = (Get-Item "$PSScriptRoot/..").Name
      $script:ModulePath = Resolve-Path "$PSScriptRoot/../BuildOutput/$ModuleName" | Get-Item
      $script:moduleVersion = ((Get-ChildItem $ModulePath).Where({ $_.Name -as 'version' -is 'version' }).Name -as 'version[]' | Sort-Object -Descending)[0].ToString()

      Write-Host "[+] Testing the latest built module:" -ForegroundColor Green
      Write-Host "      ModuleName    $ModuleName"
      Write-Host "      ModulePath    $ModulePath"
      Write-Host "      Version       $moduleVersion`n"

      Get-Module -Name $ModuleName | Remove-Module # Make sure no versions of the module are loaded

      Write-Host "[+] Reading module information ..." -ForegroundColor Green
      $script:ModuleInformation = Import-Module -Name "$ModulePath" -PassThru
      $script:ModuleInformation | Format-List

      Write-Host "[+] Get all functions present in the Manifest ..." -ForegroundColor Green
      $script:ExportedFunctions = $ModuleInformation.ExportedFunctions.Values.Name
      Write-Host "      ExportedFunctions: " -ForegroundColor DarkGray -NoNewline
      Write-Host $($ExportedFunctions -join ', ')
      $script:PS1Functions = Get-ChildItem -Path "$ModulePath/$moduleVersion/Public/*.ps1"

      Describe "Module tests for $($([Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName')))" {
        Context " Confirm valid Manifest file" {
          It "Should contain RootModule" {
            ![string]::IsNullOrWhiteSpace($ModuleInformation.RootModule) | Should -Be $true
          }

          It "Should contain ModuleVersion" {
            ![string]::IsNullOrWhiteSpace($ModuleInformation.Version) | Should -Be $true
          }

          It "Should contain GUID" {
            ![string]::IsNullOrWhiteSpace($ModuleInformation.Guid) | Should -Be $true
          }

          It "Should contain Author" {
            ![string]::IsNullOrWhiteSpace($ModuleInformation.Author) | Should -Be $true
          }

          It "Should contain Description" {
            ![string]::IsNullOrWhiteSpace($ModuleInformation.Description) | Should -Be $true
          }
        }
        Context " Should export all public functions " {
          It "Compare the number of Function Exported and the PS1 files found in the public folder" {
            $status = $ExportedFunctions.Count -eq $PS1Functions.Count
            $status | Should -Be $true
          }

          It "The number of missing functions should be 0 " {
            If ($ExportedFunctions.count -ne $PS1Functions.count) {
              $Compare = Compare-Object -ReferenceObject $ExportedFunctions -DifferenceObject $PS1Functions.Basename
              $($Compare.InputObject -Join '').Trim() | Should -BeNullOrEmpty
            }
          }
        }
        Context " Confirm files are valid Powershell syntax " {
          $_scripts = $(Get-Item -Path "$ModulePath/$moduleVersion").GetFiles(
            "*", [System.IO.SearchOption]::AllDirectories
          ).Where({ $_.Extension -in ('.ps1', '.psd1', '.psm1') })
          $testCase = $_scripts | ForEach-Object { @{ file = $_ } }
          It "ie: each Script/Ps1file should have valid Powershell sysntax" -TestCases $testCase {
            param($file) $contents = Get-Content -Path $file.fullname -ErrorAction Stop
            $errors = $null; [void][System.Management.Automation.PSParser]::Tokenize($contents, [ref]$errors)
            $errors.Count | Should -Be 0
          }
        }
        Context " Confirm there are no duplicate function names in private and public folders" {
          It ' Should have no duplicate functions' {
            $Publc_Dir = Get-Item -Path ([IO.Path]::Combine("$ModulePath/$moduleVersion", 'Public'))
            $Privt_Dir = Get-Item -Path ([IO.Path]::Combine("$ModulePath/$moduleVersion", 'Private'))
            $funcNames = @(); Test-Path -Path ([string[]]($Publc_Dir, $Privt_Dir)) -PathType Container -ErrorAction Stop
            $Publc_Dir.GetFiles("*", [System.IO.SearchOption]::AllDirectories) + $Privt_Dir.GetFiles("*", [System.IO.SearchOption]::AllDirectories) | Where-Object { $_.Extension -eq '.ps1' } | ForEach-Object { $funcNames += $_.BaseName }
                        ($funcNames | Group-Object | Where-Object { $_.Count -gt 1 }).Count | Should -BeLessThan 1
          }
        }
      }
      Remove-Module -Name $ModuleName -Force
    }
  )
  FeatureTest      = [scriptBlock]::create({
      Describe "Feature tests: PsCraft" {
        Context "Feature 1" {
          It "Does something expected" {
            # Write tests to verify the behavior of a specific feature.
            # For instance, if you have a feature to change the console background color,
            # you could simulate the invocation of the related function and check if the color changes as expected.
          }
        }

        Context "Feature 2" {
          It "Performs another expected action" {
            # Write tests for another feature.
          }
        }

        # TODO: Add more contexts and tests to cover various features and functionalities.
      }

    }
  )
  IntergrationTest = [scriptBlock]::create({
      # verify the interactions and behavior of the module's components when they are integrated together.
      Describe "Integration tests: PsCraft" {
        Context "Functionality Integration" {
          It "Performs expected action" {
            # Here you can write tests to simulate the usage of your functions and validate their behavior.
            # For instance, if your module provides cmdlets to customize the command-line environment,
            # you could simulate the invocation of those cmdlets and check if the environment is modified as expected.
          }
        }

        # TODO: Add more contexts and tests as needed to cover various integration scenarios.
      }

    }
  )
  Localdata        = [scriptblock]::Create({
      @{
        ModuleName    = '<ModuleName>'
        ModuleVersion = [version]::new(0, 1, 0)
        ReleaseNotes  = '<Release_Notes_Template>'
      }

    }
  )
  ReleaseNotes     = '<Release_Notes>'
}