function Write-TerminatingError {
  # .SYNOPSIS
  #   function to throw an errorrecord
  # .DESCRIPTION
  #   Used when we don't have built-in ThrowError (ie: $PowerShellversion -lt core-6.1.0-windows)
  [CmdletBinding()]
  [OutputType([System.Management.Automation.ErrorRecord])]
  param (
    [parameter(Mandatory = $false)]
    [AllowNull()][System.Management.Automation.PSCmdlet]
    $Caller = $null,

    [parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()][String]
    $ExceptionName,

    [parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()][String]
    $ExceptionMessage,

    [parameter(Mandatory = $false)]
    [AllowNull()][Object]
    $ExceptionObject = @{},

    [parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()][String]
    $ErrorId,

    [parameter(Mandatory = $true)]
    [ValidateNotNull()][System.Management.Automation.ErrorCategory]
    $ErrorCategory
  )
  process {
    $exception = New-Object $ExceptionName $ExceptionMessage;
    $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, $ErrorId, $ErrorCategory, $ExceptionObject)
  }
  end {
    if ($null -ne $Caller) {
      $Caller.ThrowTerminatingError($errorRecord)
    } else {
      throw $errorRecord
    }
  }
}