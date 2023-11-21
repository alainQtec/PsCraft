function Format-Code {
    [CmdletBinding()]
    param (
        # Parameter help description
        [Parameter(Mandatory = $false)]
        [ValidateNotNull][Alias('Directory', 'Path')]
        [System.IO.DirectoryInfo]$repoRoot = $(Get-Item "$PSScriptRoot\.."),
        [Switch]$Save
    )

    begin {
        #Requires -Version 5
        [int]$errorCount = 0
        [int]$maxRetries = 5
    }

    process {
        $filesToCheck = Get-ChildItem -Path $repoRoot -Directory | Where-Object {
            $_.Name -ne "dist" } | ForEach-Object {
                Get-ChildItem -Path $_.FullName -Include "*.ps1", "*.psm1", "*.md" -Recurse
            }

            foreach ($fileInfo in $filesToCheck) {
                for ($i = 0; $i -lt $maxRetries; $i++) {
                    try {
                        $analyzerResults = Invoke-ScriptAnalyzer -Path $FileInfo.FullName -Settings $repoRoot\PSScriptAnalyzerSettings.psd1 -ErrorAction Stop
                        if ($null -ne $analyzerResults) {
                            $errorCount++
                            $analyzerResults | Format-Table -AutoSize
                        }
                        break
                    } catch {
                        Write-Warning "Invoke-ScriptAnalyer failed on $($fileInfo.FullName). Error:"
                        $_.Exception | Format-List | Out-Host
                        Write-Warning "Retrying in 5 seconds."
                        Start-Sleep -Seconds 5
                    }
                }

                if ($i -eq $maxRetries) {
                    throw "Invoke-ScriptAnalyzer failed $maxRetries times. Giving up."
                }
            }

        }

        end {
            if ($errorCount -gt 0) {
                throw "Failed to match formatting requirements"
            }
        }
    }