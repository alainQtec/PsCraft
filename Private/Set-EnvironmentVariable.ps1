function Set-EnvironmentVariable {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [parameter(Position = 0)]
        [String]$Name,

        [parameter(Position = 1, ValueFromRemainingArguments)]
        [String[]]$Value
    )
    $FullVal = $Value -join " "
    Write-BuildLog "Setting env variable '$Name' to '$fullVal'"
    Set-Item -Path ([IO.Path]::Combine('Env:', $Name)) -Value $FullVal -Force
}