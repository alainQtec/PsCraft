function Write-EnvironmentSummary {
  param(
    [parameter(Position = 0, ValueFromRemainingArguments)]
    [String]$State
  )
  Write-Heading -Title "Build Environment Summary:`n"
  @(
    $(if ($([Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName'))) { "Project : $([Environment]::GetEnvironmentVariable($env:RUN_ID + 'ProjectName'))" })
    $(if ($State) { "State   : $State" })
    "Engine  : PowerShell $($PSVersionTable.PSVersion.ToString())"
    "Host OS : $(if($PSVersionTable.PSVersion.Major -le 5 -or $IsWindows){"Windows"}elseif($IsLinux){"Linux"}elseif($IsMacOS){"macOS"}else{"[UNKNOWN]"})"
    "PWD     : $PWD"
    ''
  ) | Write-Host
}