#requires -Module ModuleManager
filter Convert-FolderSeparator {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, ValueFromPipeline)]
    [string]$Path,
    [switch]$Relative,
    [switch]$Validate
  )

  $Path = try {
    Microsoft.PowerShell.Management\Convert-Path $Path -EA Stop
  } catch [System.Management.Automation.DriveNotFoundException] {
    if ($Validate) { throw }
    $Drive = $Path -replace ":.*"
    $Path = $Path -replace "\w*:", (Get-PSDrive -PSProvider FileSystem)[0].Root
    try {
      Microsoft.PowerShell.Management\Convert-Path $Path -EA Stop
    } catch [System.Management.Automation.ItemNotFoundException] {
      $_.TargetObject
    }
  } catch [System.Management.Automation.ItemNotFoundException] {
    if ($Validate) { throw }
    $_.TargetObject
  }

  Write-Verbose "Path: $Path"
  if ($Relative) {
    $ConvertedPath = $Path
    while ($ConvertedPath -and -not ($Result = Resolve-Path $ConvertedPath -Relative -ErrorAction SilentlyContinue)) {
      $ConvertedPath = Split-Path $ConvertedPath
      Write-Verbose "ConvertedPath: $ConvertedPath"
    }

    Write-Verbose "Result: $Result"
    $Path = $Path -replace ([regex]::escape($ConvertedPath)), $Result
  }
  # if it's a testdrive path, it should be a testdrive path
  $Path = $Path.Replace($TestDrive, "TestDrive:")
  if ($Drive) {
    $Path -replace "\w*:", "$($Drive):"
  } else {
    $Path
  }
}

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

Describe "When we call Build-Module" -Tag Integration {
  $Output = Build-Module $PSScriptRoot\Source1\build.psd1 -Passthru
  $Module = [IO.Path]::ChangeExtension($Output.Path, "psm1")

  It "Should not put the module's DefaultCommandPrefix into the psm1 as code. Duh!" {
    $Module | Should -Not -FileContentMatch '^Source$'
  }

  $Metadata = Import-Metadata $Output.Path

  It "Should update FunctionsToExport in the manifest" {
    $Metadata.FunctionsToExport | Should -Be @("Get-Source", "Set-Source")
  }

  It "Should update AliasesToExport in the manifest" {
    $Metadata.AliasesToExport -match "GS" | Should -Not -BeNullOrEmpty
  }

  It "Should de-dupe and move using statements to the top of the file" {
    Select-String -Pattern "^using" -Path $Module | ForEach-Object LineNumber | Should -Be 1
  }

  It "Will comment out the original using statements in their original positions" {
        (Select-String -Pattern "^#\s*using" -Path $Module).Count | Should -Be 3
  }
}

Describe "Regression test for #55: I can pass SourceDirectories" -Tag Integration, Regression {
  $Output = Build-Module $PSScriptRoot\Source1\build.psd1 -SourceDirectories "Private" -Passthru
  $Module = [IO.Path]::ChangeExtension($Output.Path, "psm1")

  It "Should not put the module's DefaultCommandPrefix into the psm1 as code. Duh!" {
    $Module | Should -Not -FileContentMatch '^Source$'
  }

  $Metadata = Import-Metadata $Output.Path

  It "Should not have any FunctionsToExport if SourceDirectories don't match the PublicFilter" {
    $Metadata.FunctionsToExport | Should -Be @()
  }

  It "Should de-dupe and move using statements to the top of the file" {
    Select-String -Pattern "^using" -Path $Module | ForEach-Object LineNumber | Should -Be 1
  }

  It "Will comment out the original using statement in the original positions" {
        (Select-String -Pattern "^#\s*using" -Path $Module).Count | Should -Be 2
  }
}

Describe "Regression test for #55: I can pass SourceDirectories and PublicFilter" -Tag Integration, Regression {
  BeforeAll {
    $Output = Build-Module $PSScriptRoot\Source1\build.psd1 -SourceDirectories "Private" -PublicFilter "Pub*\*" -Passthru
    $Module = [IO.Path]::ChangeExtension($Output.Path, "psm1")
    $Metadata = Import-Metadata $Output.Path
  }

  It "Should not put the module's DefaultCommandPrefix into the psm1 as code. Duh!" {
    $Module | Should -Not -FileContentMatch '^Source$'
  }

  It "Should not have any FunctionsToExport if SourceDirectories don't match the PublicFilter" {
    $Metadata.FunctionsToExport | Should -BeNullOrEmpty
  }

  It "Should update AliasesToExport in the manifest" {
    $Metadata.AliasesToExport | Should -Be @("Get-MyAlias")
  }

  It "Should de-dupe and move using statements to the top of the file" {
    Select-String -Pattern "^using" -Path $Module | ForEach-Object LineNumber | Should -Be 1
  }

  It "Will comment out the original using statement in the original positions" {
        (Select-String -Pattern "^#\s*using" -Path $Module).Count | Should -Be 2
  }
}

Describe "Regression test for #84: Multiple Aliases per command will Export" -Tag Integration, Regression {
  $Output = Build-Module $PSScriptRoot\Source1\build.psd1 -Passthru

  $Metadata = Import-Metadata $Output.Path

  It "Should update AliasesToExport in the manifest" {
    $Metadata.AliasesToExport | Should -Be @("Get-MyAlias", "GS", "GSou", "SS", "SSou")
  }
}

Describe "Supports building without a build.psd1" -Tag Integration {
  Copy-Item $PSScriptRoot\Source1 TestDrive:\Source1 -Recurse
  # This is the old build, with a build.psd1
  $Output = Build-Module TestDrive:\Source1\build.psd1 -Passthru
  $ManifestContent = Get-Content $Output.Path
  $ModuleContent = Get-Content ([IO.Path]::ChangeExtension($Output.Path, ".psm1"))
  Remove-Item (Split-Path $Output.Path) -Recurse

  # Then remove the build.psd1 and rebuild it
  Remove-Item TestDrive:\Source1\build.psd1

  $Build = @{ }

  It "No longer fails if there's no build.psd1" {
    $BuildParameters = @{
      SourcePath               = "TestDrive:\Source1\Source1.psd1"
      OutputDirectory          = "TestDrive:\Result1"
      VersionedOutputDirectory = $true
    }

    $Build.Output = Build-Module @BuildParameters -Passthru
  }

  It "Works even based on current path" {
    $BuildParameters = @{
      OutputDirectory          = "TestDrive:\Result1"
      VersionedOutputDirectory = $true
    }
    Push-Location TestDrive:\Source1
    try {
      $Build.Output = Build-Module @BuildParameters -Passthru
    } finally {
      Pop-Location
    }
  }

  # This test case for coverage of "If we found more than one module info"
  It "Ignores extra manifest files" {
    $BuildParameters = @{
      OutputDirectory          = "TestDrive:\Result1"
      VersionedOutputDirectory = $true
    }
    Push-Location TestDrive:\Source1
    New-Item SubModule -ItemType Directory
    Copy-Item Source1.psd1 .\SubModule\SubModule.psd1

    try {
      $Build.Output = Build-Module @BuildParameters -Passthru
    } finally {
      Pop-Location
    }
  }

  It "Creates the same module as with a build.psd1" {
    $Build.Metadata = Import-Metadata $Build.Output.Path
    Get-Content $Build.Output.Path | Should -Be $ManifestContent
    Get-Content ([IO.Path]::ChangeExtension($Build.Output.Path, ".psm1")) | Should -Be $ModuleContent
  }

  It "Should update AliasesToExport in the manifest" {
    $Build.Metadata.AliasesToExport | Should -Be @("Get-MyAlias", "GS", "GSou", "SS", "SSou")
  }

  It "Should update FunctionsToExport in the manifest" {
    $Build.Metadata.FunctionsToExport | Should -Be @("Get-Source", "Set-Source")
  }
}

Describe "Defaults to VersionedOutputDirectory" -Tag Integration {
  Copy-Item $PSScriptRoot\Source1 TestDrive:\Source1 -Recurse
  # This is the old build, with a build.psd1
  $Output = Build-Module TestDrive:\Source1\build.psd1 -Passthru
  $ManifestContent = Get-Content $Output.Path
  $ModuleContent = Get-Content ([IO.Path]::ChangeExtension($Output.Path, ".psm1"))
  Remove-Item (Split-Path $Output.Path) -Recurse

  # Then remove the build.psd1 and rebuild it
  Remove-Item TestDrive:\Source1\build.psd1

  $Build = @{ }

  It "Builds into a folder with version by default" {
    $BuildParameters = @{
      SourcePath      = "TestDrive:\Source1\Source1.psd1"
      OutputDirectory = "TestDrive:\Output1"
    }

    $Build.Output = Build-Module @BuildParameters -Passthru
        (Convert-FolderSeparator $Build.Output.Path) | Should -Be (Convert-FolderSeparator "TestDrive:\Output1\Source1\1.0.0\Source1.psd1")
  }

  It "Builds into a folder with no version when UnversionedOutputDirectory" {
    $BuildParameters = @{
      SourcePath                 = "TestDrive:\Source1\Source1.psd1"
      OutputDirectory            = "TestDrive:\Output2"
      UnversionedOutputDirectory = $true
    }

    $Build.Output = Build-Module @BuildParameters -Passthru
        (Convert-FolderSeparator $Build.Output.Path) | Should -Be (Convert-FolderSeparator "TestDrive:\Output2\Source1\Source1.psd1")
  }

  It "Creates the same module as with a build.psd1" {
    $Build.Metadata = Import-Metadata $Build.Output.Path
    Get-Content $Build.Output.Path | Should -Be $ManifestContent
    Get-Content ([IO.Path]::ChangeExtension($Build.Output.Path, ".psm1")) | Should -Be $ModuleContent
  }

  It "Should update AliasesToExport in the manifest" {
    $Build.Metadata.AliasesToExport | Should -Be @("Get-MyAlias", "GS", "GSou", "SS", "SSou")
  }

  It "Should update FunctionsToExport in the manifest" {
    $Build.Metadata.FunctionsToExport | Should -Be @("Get-Source", "Set-Source")
  }
}

Describe "Supports building discovering the module without a build.psd1" -Tag Integration {
  Copy-Item $PSScriptRoot\Source1 TestDrive:\source -Recurse

  # This is the old build, with a build.psd1
  $Output = Build-Module TestDrive:\source\build.psd1 -Passthru
  $ManifestContent = Get-Content $Output.Path
  $ModuleContent = Get-Content ([IO.Path]::ChangeExtension($Output.Path, ".psm1"))
  Remove-Item (Split-Path $Output.Path) -Recurse

  # Then remove the build.psd1 and rebuild it
  Remove-Item TestDrive:\source\build.psd1

  Push-Location -StackName 'IntegrationTest' -Path TestDrive:\

  $Build = @{ }

  It "No longer fails if there's no build.psd1" {
    $Build.Output = Build-Module -Passthru
  }

  It "Creates the same module as with a build.psd1" {
    $Build.Metadata = Import-Metadata $Build.Output.Path
    Get-Content $Build.Output.Path | Should -Be $ManifestContent
    Get-Content ([IO.Path]::ChangeExtension($Build.Output.Path, ".psm1")) | Should -Be $ModuleContent
  }

  It "Should update AliasesToExport in the manifest" {
    $Build.Metadata.AliasesToExport | Should -Be @("Get-MyAlias", "GS", "GSou", "SS", "SSou")
  }

  It "Should update FunctionsToExport in the manifest" {
    $Build.Metadata.FunctionsToExport | Should -Be @("Get-Source", "Set-Source")
  }

  Pop-Location -StackName 'IntegrationTest'
}

Describe "Regression test for #88 not copying prefix files" -Tag Integration, Regression {
  $Output = Build-Module $PSScriptRoot\build.psd1 -Passthru

  $Metadata = Import-Metadata $Output.Path

  It "Should update AliasesToExport in the manifest" {
    $Module = [IO.Path]::ChangeExtension($Output.Path, "psm1")
    $ModuleInfo = Get-Content $Module
    $ModuleInfo[0] | Should -Be "using module Configuration"
  }
}

Describe "Regression test for #40.2 not copying suffix if prefix" -Tag Integration, Regression {
  Copy-Item $PSScriptRoot\Source1 TestDrive:\Source1 -Recurse

  New-Item TestDrive:\Source1\_GlobalScope.ps1 -Value '$Global:Module = "Testing"'

  $metadata = Import-Metadata TestDrive:\Source1\build.psd1
  $metadata += @{
    Prefix = "./_GlobalScope.ps1"
    Suffix = "./_GlobalScope.ps1"
  }
  $metadata | Export-Metadata TestDrive:\Source1\build.psd1

  $Output = Build-Module TestDrive:\Source1 -Passthru

  $Metadata = Import-Metadata $Output.Path

  It "Should inject the content of the _GlobalScope file at the TOP and BOTTOM" {
    $Module = [IO.Path]::ChangeExtension($Output.Path, "psm1")
    $Code = Get-Content $Module
    $Code[0] | Should -Be "using module ModuleManager" # because we moved it, from GetFinale
    $Code[1] | Should -Be "#Region '$('./_GlobalScope.ps1' -replace '/', ([IO.Path]::DirectorySeparatorChar))' 0"
    $Code[2] | Should -Be '$Global:Module = "Testing"'

    $Code[-3] | Should -Be '$Global:Module = "Testing"'
    $Code[-2] | Should -Be "#EndRegion '$('./_GlobalScope.ps1' -replace '/', ([IO.Path]::DirectorySeparatorChar))' 2"
    $Code[-1] | Should -Be ""
  }
}

# There's no such thing as a drive root on unix
if ($PSVersionTable.Platform -eq "Win32NT") {
  Describe "Able to build from the drive root" {
    $null = New-ModuleManifest "TestDrive:/MyModule.psd1" -ModuleVersion "1.0.0" -Author "Tester"
    $null = New-Item "TestDrive:/Public/Test.ps1" -Type File -Value 'MATCHING TEST CONTENT' -Force

    $Result = Build-Module -SourcePath 'TestDrive:/MyModule.psd1' -Version "1.0.0" -OutputDirectory './output' -Encoding UTF8 -SourceDirectories @('Public') -Target Build -Passthru

    It "Builds the Module in the designated output folder" {
      $Result.ModuleBase | Convert-FolderSeparator | Should -Be (Convert-FolderSeparator "TestDrive:/Output/MyModule/1.0.0")
      'TestDrive:/Output/MyModule/1.0.0/MyModule.psm1' | Convert-FolderSeparator | Should -FileContentMatch 'MATCHING TEST CONTENT'
    }
  }
}

Describe "Copies additional items specified in CopyPaths" {

  $null = New-Item "TestDrive:/build.psd1" -Type File -Force -Value "@{
        SourcePath      = 'TestDrive:/MyModule.psd1'
        SourceDirectories = @('Public')
        OutputDirectory = './output'
        CopyPaths       = './lib', './MyModule.format.ps1xml'
    }"
  $null = New-ModuleManifest "TestDrive:/MyModule.psd1" -ModuleVersion "1.0.0" -Author "Tester"
  $null = New-Item "TestDrive:/Public/Test.ps1" -Type File -Value 'MATCHING TEST CONTENT' -Force
  $null = New-Item "TestDrive:/MyModule.format.ps1xml" -Type File -Value '<Configuration />' -Force
  $null = New-Item "TestDrive:/lib/imaginary1.dll" -Type File -Value '1' -Force
  $null = New-Item "TestDrive:/lib/subdir/imaginary2.dll" -Type File -Value '2' -Force

  $Result = Build-Module -SourcePath 'TestDrive:/build.psd1' -OutputDirectory './output' -Version '1.0.0' -Passthru -Target Build

  It "Copies single files that are in CopyPaths" {
        (Convert-FolderSeparator $Result.ModuleBase) | Should -Be (Convert-FolderSeparator "$TestDrive/output/MyModule/1.0.0")
    'TestDrive:/output/MyModule/1.0.0/MyModule.format.ps1xml' | Should -Exist
    'TestDrive:/output/MyModule/1.0.0/MyModule.format.ps1xml' | Should -FileContentMatch '<Configuration />'
  }

  It "Recursively copies all the files in folders that are in CopyPaths" {
    'TestDrive:/output/MyModule/1.0.0/lib/imaginary1.dll' | Should -FileContentMatch '1'
    'TestDrive:/output/MyModule/1.0.0/lib/subdir/imaginary2.dll' | Should -FileContentMatch '2'
  }
}
