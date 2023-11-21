function Get-PsModule {
    <#
    .SYNOPSIS
    Gets a psmodule object, by creating one from scratch or Loading One from already Existing Files
    .DESCRIPTION
    A longer description of the function, its purpose, common use cases, etc.
    .NOTES
    Information or caveats about the function e.g. 'This function is not supported in Linux'
    .LINK
    Specify a URI to a help page, this will show when Get-Help -Online is used.
    .EXAMPLE
    Get-PsModule -Verbose
    Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines
    #>
    [CmdletBinding(DefaultParametersetName = 'ByName')]
    [OutputType([PSmodule])]
    param (
        [Parameter(Position = 0, Mandatory = $true, ParameterSetName = 'ByName')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(ParameterSetName = '__AllParameterSets')]
        [ValidateNotNullOrEmpty()]
        [string]$Path = $(Get-Variable -Name ExecutionContext -ValueOnly).SessionState.Path.CurrentFileSystemLocation.ProviderPath
    )

    begin {
        $ModulObject = $null
        $ErrorAction = $PSCmdlet.MyInvocation.BoundParameters["ErrorAction"]
    }

    process {
        $ModulePath = [IO.Path]::Combine($Path, $Name);
        try {
            if (Test-Path -Type Container -Path $ModulePath -ErrorAction SilentlyContinue) {
                # Try loading Module named $Name Fom That path
                $ModulObject = [PSmodule]::Load($ModulePath)
                if ($ErrorAction -ne 'SilentlyContinue') {
                    throw [System.IO.DirectoryNotFoundException]::new("Path '$ModulePath' Not Found.")
                }
            } else {
                $ModulObject = [PSmodule]::new($Name, $Path)
            }
        } catch {
            throw $_
        }
    }

    end {
        return $ModulObject
    }
}