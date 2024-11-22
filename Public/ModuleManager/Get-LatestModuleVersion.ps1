function Get-LatestModuleVersion {
  [CmdletBinding()][OutputType([version])]
  param (
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$Name,

    [Parameter(Position = 1, Mandatory = $false)]
    [ValidateSet('LocalMachine', 'PsGallery')]
    [string]$Source = 'PsGallery'
  )

  begin {
    $latest_Version = [version]::New()
  }
  process {
    if ($Source -eq 'LocalMachine') {
      $_Local_Module = Find-InstalledModule $Name
      if ($null -ne $_Local_Module) {
        if ((Test-Path -Path $_Local_Module.Psd1 -PathType Leaf -ErrorAction Ignore)) {
          $latest_Version = $_Local_Module.Version
        }
      }
    } else {
      $url = "https://www.powershellgallery.com/packages/$Name/?dummy=$(Get-Random)"; $request = [System.Net.WebRequest]::Create($url)
      # U can also use api: [version]$Version = (Invoke-RestMethod -Uri "https://www.powershellgallery.com/api/v2/Packages?`$filter=Id eq '$PackageName' and IsLatestVersion" -Method Get -Verbose:$false).properties.Version
      $latest_Version = [version]::new(); $request.AllowAutoRedirect = $false
      try {
        $response = $request.GetResponse()
        $latest_Version = $response.GetResponseHeader("Location").Split("/")[-1] -as [Version]
        $response.Close(); $response.Dispose()
      } catch [System.Net.WebException], [System.Net.Http.HttpRequestException], [System.Net.Sockets.SocketException] {
        $Error_params = @{
          ExceptionName    = $_.Exception.GetType().FullName
          ExceptionMessage = "No Internet! " + $_.Exception.Message
          ErrorId          = 'WebException'
          Caller           = $PSCmdlet
          ErrorCategory    = 'ConnectionError'
        }
        Write-TerminatingError @Error_params
      } catch {
        $Error_params = @{
          ExceptionName    = $_.Exception.GetType().FullName
          ExceptionMessage = "PackageName '$PackageName' was Not Found. " + $_.Exception.Message
          ErrorId          = 'UnexpectedError'
          Caller           = $PSCmdlet
          ErrorCategory    = 'OperationStopped'
        }
        Write-TerminatingError @Error_params
      }
    }
  }
  end {
    return $latest_Version
  }
}