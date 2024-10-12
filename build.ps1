# .SYNOPSIS
#   Module builder build script
# .DESCRIPTION
#   A build script that uses its own module. 🗿
# .LINK
#   https://github.com/alainQtec/PsCraft/blob/main/build.ps1
# .NOTES
#   Normaly, this file would only be one line:
#   Import-Module PsCraft; Build-Module -Task Test -Verbose
[cmdletbinding(DefaultParameterSetName = 'task')]
param(
  [parameter(Position = 0, ParameterSetName = 'task')]
  [ValidateScript({
      $task_seq = [string[]]$_; $IsValid = $true
      $Tasks = @('Init', 'Clean', 'Compile', 'Import', 'Test', 'Deploy')
      foreach ($name in $task_seq) {
        $IsValid = $IsValid -and ($name -in $Tasks)
      }
      if ($IsValid) {
        return $true
      } else {
        throw [System.ArgumentException]::new('Task', "ValidSet: $($Tasks -join ', ').")
      }
    }
  )][ValidateNotNullOrEmpty()]
  [string[]]$Task = @('Init', 'Clean', 'Compile', 'Import'),

  [parameter(ParameterSetName = 'help')]
  [Alias('-Help')]
  [switch]$Help
)

Import-Module PsCraft
Build-Module -Task $Task