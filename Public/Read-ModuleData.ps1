function Read-ModuleData {
  # .SYNOPSIS
  #   Reads a specific value from a PowerShell metdata file (e.g. a module manifest)
  # .DESCRIPTION
  #   By default Get-ModuleManifest gets the ModuleVersion, but it can read any key in the metadata file
  # .LINK
  #   https://github.com/alainQtec/PsCraft/blob/main/Public/Read-ModuleData.ps1
  # .EXAMPLE
  #   Read-ModuleData .
  #   Reads the Moduledata from the current directory, assumes that the module name is the same as the directory name
  [CmdletBinding()]
  [OutputType([PsObject])]
  param (
    [Parameter(Position = 0, Mandatory = $false, ValueFromPipeline = $true)]
    [ValidateNotNullOrWhiteSpace()][string]
    $Path,

    [Parameter(Position = 1, Mandatory = $false)]
    [Alias('r')][string]
    $RootPath = (Resolve-Path .).Path,

    [Parameter(Position = 2, Mandatory = $false)]
    [AllowNull()][Alias('p')][string]
    $Property = $null,

    [Parameter(Position = 3, Mandatory = $false)]
    [ValidateNotNullOrEmpty()][Alias('m')][string]
    $ModuleName = [IO.Directory]::GetParent([IO.Directory]::GetFiles((Get-Location))[0]).Name
  )
  begin {
    if (!$PSBoundParameters.ContainsKey("Path")) {
      $CultureName = [System.Threading.Thread]::CurrentThread.CurrentCulture.Name
      $Path = [IO.Path]::Combine($RootPath, $CultureName, "$ModuleName.strings.psd1")
    }
  }
  process {
    if (!(Test-Path $Path)) {
      $Error_params = @{
        ExceptionName    = "ItemNotFoundException"
        ExceptionMessage = "Can't find file $Path"
        ErrorId          = "PathNotFound,Metadata\Import-Metadata"
        Caller           = $PSCmdlet
        ErrorCategory    = "ObjectNotFound"
      }
      Write-TerminatingError @Error_params
    }
    if ([string]::IsNullOrWhiteSpace($Property)) {
      $null = Get-Item -Path $Path -ErrorAction Stop
      $data = New-Object PsObject; $text = [IO.File]::ReadAllText("$Path")
      $data = [scriptblock]::Create("$text").Invoke()
      return $data
    }
    $Tokens = $Null; $ParseErrors = $Null
    # Search the Manifest root properties, and also the nested hashtable properties.
    if ([IO.Path]::GetExtension($_) -ne ".psd1") { throw "Path must point to a .psd1 file" }
    $AST = [Parser]::ParseFile($Path, [ref]$Tokens, [ref]$ParseErrors)
    $KeyValue = $Ast.EndBlock.Statements
    $KeyValue = @([PsCraft]::FindHashKeyValue($Property, $KeyValue))
    if ($KeyValue.Count -eq 0) {
      $Error_params = @{
        ExceptionName    = "ItemNotFoundException"
        ExceptionMessage = "Can't find '$Property' in $Path"
        ErrorId          = "PropertyNotFound,Metadata\Get-Metadata"
        Caller           = $PSCmdlet
        ErrorCategory    = "ObjectNotFound"
      }
      Write-TerminatingError @Error_params
    }
    if ($KeyValue.Count -gt 1) {
      $SingleKey = @($KeyValue | Where-Object { $_.HashKeyPath -eq $Property })
      if ($SingleKey.Count -gt 1) {
        $Error_params = @{
          ExceptionName    = "System.Reflection.AmbiguousMatchException"
          ExceptionMessage = "Found more than one '$Property' in $Path. Please specify a dotted path instead. Matching paths include: '{0}'" -f ($KeyValue.HashKeyPath -join "', '")
          ErrorId          = "AmbiguousMatch,Metadata\Get-Metadata"
          Caller           = $PSCmdlet
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
}