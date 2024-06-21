function New-PSModule {

    # .SYNOPSIS
    #   Creates/Writes a psmodule Object On disk
    # .DESCRIPTION
    #   A longer description of the function, its purpose, common use cases, etc.
    # .NOTES
    #   Information or caveats about the function e.g. 'This function is not supported in Linux'
    # .LINK
    #   Specify a URI to a help page, this will show when Get-Help -Online is used.
    # .EXAMPLE
    #   New-PSModule -Verbose
    #   Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines
    # .OUTPUTS
    #   [PSmodule]
    [CmdletBinding(SupportsShouldProcess, DefaultParametersetName = 'ByName')]
    param (
        # The Name Of your Module; note that it Should always match BaseName of its path.
        [Parameter(Position = 0, ParameterSetName = 'ByName')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Position = 0, ParameterSetName = 'ByConfig')]
        [ValidateNotNullOrEmpty()]
        [Array]$Configuration,

        # The FullPath Of your Module.
        [Parameter(Position = 1, ParameterSetName = '__AllParameterSets')]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    begin {
        $ModuleOb = $null
    }

    process {
        Write-Verbose "Creating Module ..."
        if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey("Path")) {
            $ModuleOb = Get-PsModule -Name $Name -Path $Path
        } else {
            $ModuleOb = Get-PsModule -Name $Name
        }
        if ($PSCmdlet.ShouldProcess("", "", "Creating Module folder Structure")) {
            $ModuleOb.Save()
        }
    }

    end {
        Write-Verbose "Done"
        return $ModuleOb
    }
}