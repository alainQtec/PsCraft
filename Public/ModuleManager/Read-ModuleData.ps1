function script:Read-ModuleData {
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
    $ModuleName = (Split-Path (Resolve-Path ".") -LeafBase)
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
    # search the Manifest root properties, and also the nested hashtable properties.
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