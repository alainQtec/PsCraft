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
    [ValidateNotNullOrWhiteSpace()][Alias('f')][string]
    $File,

    [Parameter(Position = 1, Mandatory = $false)]
    [AllowNull()][string]
    $Property,

    [Parameter(Position = 2, Mandatory = $false)]
    [ValidateScript({
        $p = (Resolve-Path $_ -ea Ignore)
        if ((Test-Path -Path $p -PathType Container -ea Ignore)) {
          return $true
        } else {
          throw [System.ArgumentException]::new("directory '$_' does not exist.", 'Path')
        }
      }
    )][string]
    $Path = (Resolve-Path .).Path
  )
  begin {
    $Path = Resolve-Path $Path
    if (!$PSCmdlet.MyInvocation.BoundParameters.ContainsKey('File')) {
      $File = [IO.Path]::Combine($Path, (Get-Culture).Name, "$([IO.DirectoryInfo]::New($Path).BaseName).strings.psd1");
    }; $File = Resolve-Path $File;
    $IsValidPsd1file = (Test-Path -Path $File -PathType Leaf -ea Ignore) -and ([IO.Path]::GetExtension($File) -eq ".psd1")
    if (!$IsValidPsd1file) {
      throw [System.ArgumentException]::new("File '$File' is not valid. Please provide a valid path/to/<modulename>.Strings.psd1", 'Path')
    }
  }
  process {
    if (!(Test-Path $File)) {
      $Error_params = @{
        ExceptionName    = "ItemNotFoundException"
        ExceptionMessage = "Can't find file $File"
        ErrorId          = "PathNotFound,Metadata\Import-Metadata"
        Caller           = $PSCmdlet
        ErrorCategory    = "ObjectNotFound"
      }
      Write-TerminatingError @Error_params
    }
    if ([string]::IsNullOrWhiteSpace($Property)) {
      $null = Get-Item -Path $File -ErrorAction Stop
      $data = New-Object PsObject; $text = [IO.File]::ReadAllText("$File")
      $data = [scriptblock]::Create("$text").Invoke()
      return $data
    }
    $Tokens = $Null; $ParseErrors = $Null
    # Search the Manifest root properties, and also the nested hashtable properties.
    if ([IO.Path]::GetExtension($_) -ne ".psd1") { throw "Path must point to a .psd1 file" }
    $AST = [Parser]::ParseFile($File, [ref]$Tokens, [ref]$ParseErrors)
    $KeyValue = $Ast.EndBlock.Statements
    $KeyValue = @([PsCraft]::FindHashKeyValue($Property, $KeyValue))
    if ($KeyValue.Count -eq 0) {
      $Error_params = @{
        ExceptionName    = "ItemNotFoundException"
        ExceptionMessage = "Can't find '$Property' in $File"
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
          ExceptionMessage = "Found more than one '$Property' in $File. Please specify a dotted path instead. Matching paths include: '{0}'" -f ($KeyValue.HashKeyPath -join "', '")
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