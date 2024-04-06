function Write-CommandLog {
    [CmdletBinding()]
    param(
        [parameter(Mandatory, Position = 0, ValueFromRemainingArguments, ValueFromPipeline)]
        [System.Object]$Message,

        [parameter()]
        [Alias('c', 'Command')]
        [Switch]$Cmd,

        [parameter()]
        [Alias('w')]
        [Switch]$Warning,

        [parameter()]
        [Alias('s', 'e')]
        [Switch]$Severe,

        [parameter()]
        [Alias('x', 'nd', 'n')]
        [Switch]$Clean
    )
    Begin {
        if ($PSBoundParameters.ContainsKey('Debug') -and $PSBoundParameters['Debug'] -eq $true) {
            $fg = 'Yellow'
            $lvl = '##[debug]   '
        } elseif ($PSBoundParameters.ContainsKey('Verbose') -and $PSBoundParameters['Verbose'] -eq $true) {
            $fg = if ($Host.UI.RawUI.ForegroundColor -eq 'Gray') {
                'White'
            } else {
                'Gray'
            }
            $lvl = '##[Verbose] '
        } elseif ($Severe) {
            $fg = 'Red'
            $lvl = '##[Error]   '
        } elseif ($Warning) {
            $fg = 'Yellow'
            $lvl = '##[Warning] '
        } elseif ($Cmd) {
            $fg = 'Magenta'
            $lvl = '##[Command] '
        } else {
            $fg = if ($Host.UI.RawUI.ForegroundColor -eq 'Gray') {
                'White'
            } else {
                'Gray'
            }
            $lvl = '##[Info]    '
        }
    }
    Process {
        $fmtMsg = if ($Clean) {
            $Message -split "[\r\n]" | Where-Object { $_ } | ForEach-Object {
                $lvl + $_
            }
        } else {
            $date = "$(Get-Elapsed) "
            if ($Cmd) {
                $i = 0
                $Message -split "[\r\n]" | Where-Object { $_ } | ForEach-Object {
                    $tag = if ($i -eq 0) {
                        'PS > '
                    } else {
                        '  >> '
                    }
                    $lvl + $date + $tag + $_
                    $i++
                }
            } else {
                $Message -split "[\r\n]" | Where-Object { $_ } | ForEach-Object {
                    $lvl + $date + $_
                }
            }
        }
        Write-Host -ForegroundColor $fg $($fmtMsg -join "`n")
    }
}