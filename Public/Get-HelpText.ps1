function Get-HelpText {
    <#
    .SYNOPSIS
        convert a help XML file for a PowerShell module (such as MymoduleName.psm1-Help.xml) into a string that can be displayed as help text
    .DESCRIPTION
        This function takes a single parameter, $Path, which specifies the path to the help XML file.
        The function loads the XML file using the Get-Content cmdlet, and then parses it into an XML object using the [xml] type accelerator.
        The function then loops through each <command> element in the XML file, extracting the command name, synopsis, and description from the XML, and adding them to the help text string.
        It also loops through each <parameter> element in the <parameters> element, adding the parameter name and description to the help text.
    .NOTES
        Information or caveats about the function e.g. 'This function is not supported in Linux'
    .LINK
        https://github.com/alainQtec/devHelper/blob/main/Private/PsModuleGen/Public/Get-HelpText.ps1
    .EXAMPLE
        $helpText = Get-HelpText -Path "MymoduleName.psm1-Help.xml"
        Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # The path to the help XML file
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    begin {
        # Load the help XML file
        $helpXml = [xml](Get-Content $Path)
        # Initialize an empty string to hold the help text
        $helpText = [string]::Empty
    }
    Process {
        # Loop through each <command> element in the XML file
        foreach ($command in $helpXml.commands.command) {
            # Add the command name to the help text
            $helpText += $command.name + "`n"

            # Add the command synopsis to the help text
            $helpText += $command.synopsis + "`n`n"

            # Add the command description to the help text
            $helpText += $command.description + "`n`n"

            # Loop through each <parameter> element in the <parameters> element
            foreach ($parameter in $command.parameters.parameter) {
                # Add the parameter name and description to the help text
                $helpText += "`t" + $parameter.name + ": " + $parameter.description + "`n"
            }
            # Add a newline after each command
            $helpText += "`n"
        }
    }
    end {
        # Return the help text
        return $helpText
    }
}
