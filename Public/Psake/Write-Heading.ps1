function Write-Heading {
  param(
    [parameter(Position = 0)]
    [String]$Title,

    [parameter(Position = 1)]
    [Switch]$Passthru
  )
  $msgList = @(
    ''
    "##[section] $(Get-Elapsed) $Title"
  ) -join "`n"
  if ($Passthru) {
    $msgList
  } else {
    $msgList | Write-Host -f Green
  }
}