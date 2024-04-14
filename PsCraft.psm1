using namespace System.Collections.Generic
using namespace System.Management.Automation.Language

#region    Classes
enum SaveOptions {
    AcceptAllChangesAfterSave # After changes are saved, we resets change tracking.
    DetectChangesBeforeSave # Before changes are saved, the DetectChanges method is called to synchronize Objects.
    None # Changes are saved without the DetectChanges or the AcceptAllChangesAfterSave methods being called. This can be equivalent of Force, as it can ovewrite objects.
}
class ModuleDirs {
    [ValidateNotNullOrEmpty()] [System.IO.DirectoryInfo] $root;
    [ValidateNotNullOrEmpty()] [System.IO.DirectoryInfo] $tests;
    [ValidateNotNullOrEmpty()] [System.IO.DirectoryInfo] $public;
    [ValidateNotNullOrEmpty()] [System.IO.DirectoryInfo] $private;
    [ValidateNotNullOrEmpty()] [System.IO.DirectoryInfo] $localdata;
    ModuleDirs() {}
    [void] Create() {
        $this.List() | ForEach-Object {
            if (!$_.Exists) { $_.Create() }
        }
    }
    [System.Collections.Generic.List[System.IO.DirectoryInfo]] List() {
        $list = [System.Collections.Generic.List[System.IO.DirectoryInfo]]::new()
        $this.PsObject.Properties.Name.ForEach({ [void]$list.Add($this.$_) })
        return $list
    }
}

class ModuleFiles {
    [ValidateNotNullOrEmpty()] [System.IO.FileInfo] $Builder;
    [ValidateNotNullOrEmpty()] [System.IO.FileInfo] $Manifest;
    [ValidateNotNullOrEmpty()] [System.IO.FileInfo] $Localdata;
    [ValidateNotNullOrEmpty()] [System.IO.FileInfo] $rootLoader;
    [ValidateNotNullOrEmpty()] [System.IO.FileInfo] $ModuleTest;
    [ValidateNotNullOrEmpty()] [System.IO.FileInfo] $FeatureTest;
    [ValidateNotNullOrEmpty()] [System.IO.FileInfo] $IntergrationTest;

    ModuleFiles() {}
    [void] Create() {
        $this.List() | ForEach-Object {
            if (!$_.Exists) { New-Item $_.FullName -ItemType File | Out-Null }
        }
    }
    [System.Collections.Generic.List[System.IO.FileInfo]] List() {
        $list = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
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
    [System.String]$Name;
    [System.String]$Author;
    [System.String]$CompanyName = "alainQtec";
    [System.String]$Description = "A longer description of the Module, its purpose, common use cases, etc.";
    [ValidateSet('2.0', '3.0', '4.0', '5.0', '6.0', '7.0')]
    [System.String]$PSVersion = '3.0';
    [System.String]$ClrVersion = '2.0.50727';
    [System.String]$Copyright;
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
    [ValidateNotNullOrEmpty()] [System.IO.FileInfo]$Path;
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

    PSmodule() {
        $this.Name = [IO.Path]::GetFileNameWithoutExtension([IO.Path]::GetRandomFileName())
        $this.SetPath()
        $this._init_($null);
    }

    PSmodule([string]$Name) {
        $this.Name = $Name
        $this.SetPath()
        $this._init_($null);
    }

    PSmodule([string]$Name, [string]$Path) {
        $this.Name = $Name
        $this.SetPath($Path)
        $this._init_($null);
    }

    PSmodule([Array]$Configuration) {
        $this._init_($Configuration)
    }

    [void]hidden _init_([Array]$Config) {
        if ($null -ne $Config) {
            <#
            # Config includes:
            # - Build steps
            # - Params ...
            #>
        }
        $this.SetScripts()
        $this.Guid = [guid]::NewGuid()
        $this.Tags = $this.GenerateTags()
        $this.Author = $this.GetAuthorName()
        $this.Copyright = "Copyright {0} {1} {2}. All rights reserved." -f [string][char]169, [datetime]::Now.Year, $this.Author;
        if ([string]::IsNullOrWhiteSpace($this.ClrVersion)) {
            $this.ClrVersion = [string]::Join('.', (Get-Variable 'PSVersionTable').Value.CLRVersion.ToString().split('.')[0..2])
        }
        if ([string]::IsNullOrWhiteSpace($this.PSVersion)) {
            $this.PSVersion = [string]::Join('', (Get-Variable 'PSVersionTable').Value.PSVersion.Major.ToString(), '.0')
        }
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
                $ast = [System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$tokens, [ref]$errors)
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
                        $this.Path = [System.IO.FileInfo][System.IO.Path]::Combine(([System.IO.Path]::GetDirectoryName($this.Path) | Split-Path), "$($this.Name).psd1")
                    }
                    [System.IO.Path]::GetDirectoryName($this.Path)
                } else { [System.IO.Directory]::GetCurrentDirectory() }
            } else {
                $ModulePath
            }
        );
        $this.validatePath($ModulePath)
        $this.ModuleDirs.root = [System.IO.Path]::Combine($(Get-Variable ExecutionContext -ValueOnly).SessionState.Path.GetUnresolvedProviderPathFromPSPath($ModulePath), $this.Name)
        $this.ModuleDirs.tests = [System.IO.Path]::Combine($this.ModuleDirs.root.FullName, 'Tests')
        $this.ModuleDirs.public = [System.IO.Path]::Combine($this.ModuleDirs.root.FullName, 'Public')
        $this.ModuleDirs.private = [System.IO.Path]::Combine($this.ModuleDirs.root.FullName, 'Private')
        $this.ModuleDirs.localdata = [System.IO.Path]::Combine($this.ModuleDirs.root.FullName, [System.Threading.Thread]::CurrentThread.CurrentCulture.Name)

        $this.ModuleFiles.Manifest = [System.IO.Path]::Combine($this.ModuleDirs.root.FullName, "$($this.Name).psd1")
        $this.ModuleFiles.rootLoader = [System.IO.Path]::Combine($this.ModuleDirs.root.FullName, "$($this.Name).psm1")
        $this.ModuleFiles.Builder = [System.IO.Path]::Combine($this.ModuleDirs.root.FullName, "build.ps1")
        $this.ModuleFiles.Localdata = [System.IO.Path]::Combine($this.ModuleDirs.localdata.FullName, "$($this.Name).strings.psd1")
        $this.ModuleFiles.ModuleTest = [System.IO.Path]::Combine($this.ModuleDirs.tests.FullName, "$($this.Name).Module.Tests.ps1")
        $this.ModuleFiles.FeatureTest = [System.IO.Path]::Combine($this.ModuleDirs.tests.FullName, "$($this.Name).Features.Tests.ps1")
        $this.ModuleFiles.IntergrationTest = [System.IO.Path]::Combine($this.ModuleDirs.tests.FullName, "$($this.Name).Intergration.Tests.ps1")
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
        [void][System.IO.Directory]::SetCurrentDirectory($RootPath)
        $dataFile = [System.IO.FileInfo]::new([IO.Path]::Combine($RootPath, [System.Threading.Thread]::CurrentThread.CurrentCulture.Name, 'PsCraft.strings.psd1'))
        if (!$dataFile.Exists) { throw [System.IO.FileNotFoundException]::new('Unable to find the LocalizedData file!', $dataFile) }
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
            $file = Import-PowerShellDataFile $moduleFile;
            [version]$version = ($file).ModuleVersion
            [version]$newVersion = "{0}.{1}.{2}" -f $version.Major, $version.Minor, ($version.Build + 1)
            Update-ModuleManifest -Path "$((Join-Path $Path $moduleName)).psd1" -FunctionsToExport $functions -ModuleVersion $newVersion;
        } else {
            Update-ModuleManifest -Path "$((Join-Path $Path $moduleName)).psd1" -FunctionsToExport $functions;
        }
        Publish-Module -Path $Path -NuGetApiKey $ApiKey;

        Write-Host "Module $moduleName published";
    }
    hidden [string[]] GenerateTags() {
        return $this.GenerateTags($this.Description)
    }
    hidden [string[]] GenerateTags([string]$Description) {
        # use AI to generate tags
        # This is meant to achieve Text Classification level like that of: https://learn.microsoft.com/en-us/ai-builder/text-classification-model-use-tags
        return ('Psmodule', 'PowerShell')
    }
    hidden [void] validatePath([string]$path) {
        $InvalidPathChars = [System.IO.Path]::GetInvalidPathChars()
        $InvalidCharsRegex = "[{0}]" -f [regex]::Escape($InvalidPathChars)
        if ($Path -match $InvalidCharsRegex) {
            throw [System.ComponentModel.InvalidEnumArgumentException]::new("The path string contains invalid characters.")
        }
    }
    hidden [string] GetAuthorName() {
        $AuthorName = [System.Environment]::GetEnvironmentVariable('UserName')
        try {
            $OS = [System.OperatingSystem]
            $AuthorName = switch ($true) {
                $OS::IsWindows() {
                    Get-CimInstance -ClassName Win32_UserAccount -Verbose:$false | Where-Object { [environment]::UserName -eq $_.Name } | Select-Object -ExpandProperty FullName
                    break
                }
                ($OS::IsMacOS() -or $OS::IsLinux()) {
                    $s = getent passwd "$([environment]::UserName)"
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

class dotEnv {
    [Array]static Read([string]$EnvFile) {
        $content = Get-Content $EnvFile -ErrorAction Stop
        $res_Obj = [System.Collections.Generic.List[string[]]]::new()
        foreach ($line in $content) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                Write-Verbose "[GetdotEnv] Skipping empty line"
                continue
            }
            if ($line.StartsWith("#") -or $line.StartsWith("//")) {
                Write-Verbose "[GetdotEnv] Skipping comment: $line"
                continue
            }
            ($m, $d ) = switch -Wildcard ($line) {
                "*:=*" { "Prefix", ($line -split ":=", 2); Break }
                "*=:*" { "Suffix", ($line -split "=:", 2); Break }
                "*=*" { "Assign", ($line -split "=", 2); Break }
                Default {
                    throw 'Unable to find Key value pair in line'
                }
            }
            $res_Obj.Add(($d[0].Trim(), $d[1].Trim(), $m));
        }
        return $res_Obj
    }
    [void]static Write([string]$EnvFile) {}
    [void]static Set([string]$EnvFile) {}
    [void]static Set([string]$EnvFile, [string]$RootDir, [bool]$Force) {
        if ($(Get-Variable -Name "PreviousDir" -Scope Global -ErrorAction SilentlyContinue) -eq $RootDir) {
            if (-not $Force) {
                Write-Verbose "[setdotEnv] Skipping same dir"
                return
            }
        } else {
            Set-Variable -Name "PreviousDir" -Scope Global -Value $RootDir
        }

        #return if no env file
        if (!(Test-Path $EnvFile)) {
            Write-Verbose "[setdotEnv] No .env file"
            return
        }

        #read the local env file
        $content = [dotEnv]::Read($EnvFile)
        Write-Verbose "[setdotEnv] Parsed .env file"
        foreach ($value in $content) {
            switch ($value[2]) {
                "Assign" {
                    [Environment]::SetEnvironmentVariable($value[0], $value[1], "Process") | Out-Null
                }
                "Prefix" {
                    $value[1] = "{0};{1}" -f $value[1], [System.Environment]::GetEnvironmentVariable($value[0])
                    [Environment]::SetEnvironmentVariable($value[0], $value[1], "Process") | Out-Null
                }
                "Suffix" {
                    $value[1] = "{1};{0}" -f $value[1], [System.Environment]::GetEnvironmentVariable($value[0])
                    [Environment]::SetEnvironmentVariable($value[0], $value[1], "Process") | Out-Null
                }
                Default {
                    throw [System.IO.InvalidDataException]::new()
                }
            }
        }
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
    [pscustomobject] GetParameters() {
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
class PsCraft {
    static [ParseResult] ParseCode($Code) {
        # Parses the given code and returns an object with the AST, Tokens and ParseErrors
        Write-Debug "    ENTER: ConvertToAst $Code"
        $ParseErrors = $null
        $Tokens = $null
        if ($Code | Test-Path -ErrorAction SilentlyContinue) {
            Write-Debug "      Parse Code as Path"
            $AST = [System.Management.Automation.Language.Parser]::ParseFile(($Code | Convert-Path), [ref]$Tokens, [ref]$ParseErrors)
        } elseif ($Code -is [System.Management.Automation.FunctionInfo]) {
            Write-Debug "      Parse Code as Function"
            $String = "function $($Code.Name) {`n$($Code.Definition)`n}"
            $AST = [System.Management.Automation.Language.Parser]::ParseInput($String, [ref]$Tokens, [ref]$ParseErrors)
        } else {
            Write-Debug "      Parse Code as String"
            $AST = [System.Management.Automation.Language.Parser]::ParseInput([String]$Code, [ref]$Tokens, [ref]$ParseErrors)
        }
        return [ParseResult]::new($ParseErrors, $Tokens, $AST)
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
        return [PsCraft]::GetResolvedPath($((Get-Variable ExecutionContext).Value.SessionState), $Path)
    }
    static [string] GetResolvedPath([System.Management.Automation.SessionState]$session, [string]$Path) {
        $paths = $session.Path.GetResolvedPSPathFromPSPath($Path);
        if ($paths.Count -gt 1) {
            throw [System.IO.IOException]::new([string]::Format([cultureinfo]::InvariantCulture, "Path {0} is ambiguous", $Path))
        } elseif ($paths.Count -lt 1) {
            throw [System.IO.IOException]::new([string]::Format([cultureinfo]::InvariantCulture, "Path {0} not Found", $Path))
        }
        return $paths[0].Path
    }
    static [string] GetUnResolvedPath([string]$Path) {
        return [PsCraft]::GetUnResolvedPath($((Get-Variable ExecutionContext).Value.SessionState), $Path)
    }
    static [string] GetUnResolvedPath([System.Management.Automation.SessionState]$session, [string]$Path) {
        return $session.Path.GetUnresolvedProviderPathFromPSPath($Path)
    }
    static [void] CreateModuleFolderStructure([PSmodule]$Module) {
        #TODO: Do stuff before saving the module. (fs preparation & cheking requirements)
        $Module.Save()
    }
    static [void] Create_Dir([string]$Path) {
        [PsCraft]::Create_Dir([System.IO.DirectoryInfo]::new($Path))
    }
    static [void] Create_Dir([System.IO.DirectoryInfo]$Path) {
        [ValidateNotNullOrEmpty()][System.IO.DirectoryInfo]$Path = $Path
        $nF = @(); $p = $Path; while (!$p.Exists) { $nF += $p; $p = $p.Parent }
        [Array]::Reverse($nF); $nF | ForEach-Object { $_.Create(); Write-Verbose "Created $_" }
    }
    static [HashSet[String]] GetCommandAlias([System.Management.Automation.Language.Ast]$Ast) {
        $Visitor = [AliasVisitor]::new(); $Ast.Visit($Visitor)
        return $Visitor.Aliases
    }
}
#endregion Classes

$CurrentCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture.Name
$script:localizedData = if ($null -ne (Get-Command Get-LocalizedData -ErrorAction SilentlyContinue)) {
    Get-LocalizedData -DefaultUICulture $CurrentCulture
} else {
    $dataFile = [System.IO.FileInfo]::new([IO.Path]::Combine((Get-Location), $CurrentCulture, 'PsCraft.strings.psd1'))
    if (!$dataFile.Exists) { throw [System.IO.FileNotFoundException]::new('Unable to find the LocalizedData file.', 'PsCraft.strings.psd1') }
    [scriptblock]::Create("$([IO.File]::ReadAllText($dataFile))").Invoke()
}

$Private = Get-ChildItem ([IO.Path]::Combine($PSScriptRoot, 'Private')) -Filter "*.ps1" -ErrorAction SilentlyContinue
$Public = Get-ChildItem ([IO.Path]::Combine($PSScriptRoot, 'Public')) -Filter "*.ps1" -ErrorAction SilentlyContinue
# Load dependencies
$PrivateModules = [string[]](Get-ChildItem ([IO.Path]::Combine($PSScriptRoot, 'Private')) -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | Select-Object -ExpandProperty FullName)
if ($PrivateModules.Count -gt 0) {
    foreach ($Module in $PrivateModules) {
        Try {
            if ([string]::IsNullOrWhiteSpace($Module)) { continue }
            Import-Module $Module -ErrorAction Stop
        } Catch {
            Write-Error "Failed to import module $Module : $_"
        }
    }
}
# Dot source the files
foreach ($Import in ($Public, $Private)) {
    Try {
        if ([string]::IsNullOrWhiteSpace($Import.fullname)) { continue }
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