function Get-ModuleManifest {
    <#
        .SYNOPSIS
            Reads a specific value from a PowerShell metdata file (e.g. a module manifest)
        .DESCRIPTION
            By default Get-ModuleManifest gets the ModuleVersion, but it can read any key in the metadata file
        .EXAMPLE
            Get-ModuleManifest .\Configuration.psd1
            Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines
        .Example
            Get-ModuleManifest .\Configuration.psd1 ReleaseNotes
            Returns the release notes!
        #>
    [CmdletBinding()]
    param(
        # The path to the module manifest file
        [Parameter(ValueFromPipelineByPropertyName = "True", Position = 0)]
        [Alias("PSPath")]
        [ValidateScript({ if ([IO.Path]::GetExtension($_) -ne ".psd1") { throw "Path must point to a .psd1 file" } $true })]
        [string]$Path,

        # The property (or dotted property path) to be read from the manifest.
        # Get-ModuleManifest searches the Manifest root properties, and also the nested hashtable properties.
        [Parameter(ParameterSetName = "Overwrite", Position = 1)]
        [string]$PropertyName = 'ModuleVersion',

        [switch]$Passthru
    )
    Begin {
        $eap = $ErrorActionPreference
        $ErrorActionPreference = "Stop"
        $Tokens = $Null; $ParseErrors = $Null
    }
    Process {
        if (!(Test-Path $Path)) {
            Write-Error -Exception System.Management.Automation.ItemNotFoundException -Message "Can't find file $Path" -ErrorId "PathNotFound,Metadata\Import-Metadata" -Category "ObjectNotFound"
            return
        }
        $Path = Convert-Path $Path
        $AST = [System.Management.Automation.Language.Parser]::ParseFile( $Path, [ref]$Tokens, [ref]$ParseErrors )

        $KeyValue = $Ast.EndBlock.Statements
        $KeyValue = @(FindHashKeyValue $PropertyName $KeyValue)
        if ($KeyValue.Count -eq 0) {
            Write-Error -Exception System.Management.Automation.ItemNotFoundException -Message "Can't find '$PropertyName' in $Path" -ErrorId "PropertyNotFound,Metadata\Get-Metadata" -Category "ObjectNotFound"
            return
        }
        if ($KeyValue.Count -gt 1) {
            $SingleKey = @($KeyValue | Where-Object { $_.HashKeyPath -eq $PropertyName })

            if ($SingleKey.Count -gt 1) {
                Write-Error -Exception System.Reflection.AmbiguousMatchException -Message ("Found more than one '$PropertyName' in $Path. Please specify a dotted path instead. Matching paths include: '{0}'" -f ($KeyValue.HashKeyPath -join "', '")) -ErrorId "AmbiguousMatch,Metadata\Get-Metadata" -Category "InvalidArgument"
                return
            } else {
                $KeyValue = $SingleKey
            }
        }
        $KeyValue = $KeyValue[0]

        if ($Passthru) { $KeyValue } else {
            # # Write-Debug "Start $($KeyValue.Extent.StartLineNumber) : $($KeyValue.Extent.StartColumnNumber) (char $($KeyValue.Extent.StartOffset))"
            # # Write-Debug "End   $($KeyValue.Extent.EndLineNumber) : $($KeyValue.Extent.EndColumnNumber) (char $($KeyValue.Extent.EndOffset))"
            $KeyValue.SafeGetValue()
        }
    }
    End {
        $ErrorActionPreference = $eap
    }
}