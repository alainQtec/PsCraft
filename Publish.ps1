
<#PSScriptInfo

.VERSION 0.1.0

.GUID e9a8524e-3c3f-4d88-af66-bf57f104c339

.AUTHOR Alain Herve

.COMPANYNAME alainQtec

.COPYRIGHT alainQtec

.TAGS PowershelGallery

.LICENSEURI

.PROJECTURI https://github.com/alainQtec/PsModuleGen

.ICONURI

.EXTERNALMODULEDEPENDENCIES

.REQUIREDSCRIPTS ./build.ps1

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES


.PRIVATEDATA

#>

<#

.DESCRIPTION
 Publish Script

#>
Param()

# $BuildScript = [IO.Path]::Combine($PSScriptRoot, 'build.ps1')
$NugetApiKey = $Env:NUGETAPIKEY
if (!$Env:GITHUB_ACTION_PATH) {
    # Means, We are on local pc so we'll have to decrypt the env variable
    #region    AzureHSM
    class AzConfig : Ordered {
        AzConfig() {}
        [void]Add($key, $value) {
            [ValidateNotNullOrEmpty()][string]$key = $key
            [ValidateNotNullOrEmpty()][System.Object]$value = $value
            $this.PsObject.Properties.Add([psnoteproperty]::new($key, $value))
        }
        [Ordered] ToOrdered() {
            $dict = [Ordered]@{}; $Keys = $this.Psobject.Properties.Where({ $_.MemberType -eq 'NoteProperty' }).Name
            $Keys | ForEach-Object { [void]$dict.Add($_, $this."$_") }
            return $dict
        }
    }
    # .SYNOPSIS
    #  A class to Interact with Azure's HSM Service
    # .DESCRIPTION
    #  Used to Retrieve AES Keys from Azure Key Vault. ie: https://www.gavsto.com/msp-powershell-for-beginners-part-2-securely-store-credentials-passwords-api-keys-and-secrets/
    class AzureHSM {
        [AzConfig]$config = [AzConfig]::New()
        static hidden [bool]$IsSetup = [bool][int]$env:Is_AzureHSM_Setup

        AzureHSM() {
            $cfg = $this::ReadEnv("$(Get-Location)/.env")
            $cfg.Keys.Foreach({ $this.config.Add($_, $cfg["$_"]) })
            if (![AzureHSM]::IsSetup) { $this.Setup() }
            Write-Host "[HSM] Login AzAccount ..." -ForegroundColor Green
            Login-AzAccount
        }
        [void] Setup() {
            Write-Host 'Setting up an Azure Key Vault (One time only) ...' -ForegroundColor Green
            if ($null -eq (Get-Module -ListAvailable az)[0]) {
                Install-Module -Name Az -AllowClobber -Scope AllUsers -Force
            }
            Enable-AzureRmAlias # Enable Aliases from the previous Azure RM
            Connect-AzAccount # will open in the Browser
            Set-AzContext -SubscriptionName $this.config.AzureSubscriptionName
            # https://learn.microsoft.com/en-us/azure/key-vault/managed-hsm/quick-create-powershell
            Write-Host "Creating a resource group ..." -ForegroundColor Green
            New-AzResourceGroup -Name $this.config.AzureResourceGroup -Location $this.config.location
            Write-Host "Getting your principal ID ..." -ForegroundColor Green
            $principalId = (Get-AzADUser -UserPrincipalName $this.config.Email).Id
            Write-Host "Creating a managed HSM .." -ForegroundColor Green
            New-AzKeyVaultManagedHsm -AzureResourceGroup $this.config.AzureResourceGroup -Name $this.config.hsmName -Location $this.config.location -Sku Standard_B1 -Administrators $principalId
            # Generate a certificate locally which will be used to Authenticate
            $cert = New-SelfSignedCertificate -CertStoreLocation "cert:\CurrentUser\My" -Subject "CN=ImpactKeyVault" -KeySpec KeyExchange -NotAfter (Get-Date).AddMonths(36)
            $keyValue = [System.Convert]::ToBase64String($cert.GetRawCertData())
            # Generate a service principal (Application) that we will use to Authenticate with
            $sp = New-AzADServicePrincipal -DisplayName $this.config.AzureServicePrincipalAppName -CertValue $keyValue -EndDate $cert.NotAfter -StartDate $cert.NotBefore
            Start-Sleep 20 # Allow for the service principal to propagate in Azure
            # Assign the appropriate role to the service principal
            New-AzRoleAssignment -RoleDefinitionName Reader -ServicePrincipalName $sp.ApplicationId -ResourceGroupName $this.config.AzureResourceGroup -ResourceType "Microsoft.KeyVault/vaults" -ResourceName $this.config.hsmName
            # Set the appropriate access to the secrets for the application
            Set-AzKeyVaultAccessPolicy -VaultName $this.config.hsmName -ObjectId $sp.id -PermissionsToSecrets Get, Set

            Set-Item -Path ([IO.Path]::Combine('Env:', 'Is_AzureHSM_Setup')) -Value 1 -Force
            Write-Host -BackgroundColor Green -ForegroundColor Black "!!You will need to save these details. This is the Tenant ID and Application ID!!"
            Write-Host -BackgroundColor Yellow -ForegroundColor Black "Tenant ID: $((Get-AzSubscription -SubscriptionName $this.config.AzureSubscriptionName).TenantId)"
            Write-Host -BackgroundColor Yellow -ForegroundColor Black "Application ID: $($sp.ApplicationId.Guid)"
            Write-Host -BackgroundColor Yellow -ForegroundColor Black "Azure Key Vault Name: $($this.config.hsmName)"
            Write-Host -BackgroundColor Yellow -ForegroundColor Black "Certificate Subject Name: 'CN=ImpactKeyVault'"
            Disconnect-AzAccount
        }
        static [ordered] ReadEnv([string]$EnvFile) {
            if (!(Test-Path -Path $EnvFile -PathType Leaf -ErrorAction Ignore)) {
                throw [System.IO.FileNotFoundException]::New()
            }
            $result = [ordered]::New(); [IO.File]::ReadAllLines($EnvFile).ForEach({
                    if (![string]::IsNullOrWhiteSpace($_) -and $_[0] -notin ('#', '//')) {
                        ($m, $d ) = switch -Wildcard ($_) {
                            "*:=*" { "Prefix", ($_ -split ":=", 2); Break }
                            "*=:*" { "Suffix", ($_ -split "=:", 2); Break }
                            "*=*" { "Assign", ($_ -split "=", 2); Break }
                            Default {
                                throw 'Unable to find Key value pair in line'
                            }
                        }
                        [void]$result.Add($d[0].Trim(), $d[1].Trim())
                    }
                }
            )
            return $result
        }
        [void] Createkey([string]$keyName) {
            Write-Host "[HSM] Creating HSM key ..." -ForegroundColor Green
            Add-AzKeyVaultKey -HsmName $this.config.hsmName -Name $keyName -Destination HSM
        }
        [object] CreateSecret() {
            $private:secretvalue = $this::ConvertToSecureString('mySUPERsecretAPIkey!')
            $secret = Set-AzKeyVaultSecret -VaultName 'YourMSP-CredsKeyVault' -Name 'ExamplePassword' -SecretValue $secretvalue
            return $secret
        }
        [Byte[]] RetrieveKey() {
            $keyName = $this.config.keyName; [ValidateNotNullOrEmpty()][string]$keyName = $keyName
            return $this.RetrieveKey($keyName)
        }
        [string] RetrieveSecret() {
            # .EXAMPLE
            # $AdminUser = Get-AzKeyVaultSecret -VaultName $this.config.AzureVaultName -Name $AdminUserName
            # $AdminPass = Get-AzKeyVaultSecret -VaultName $this.config.AzureVaultName -Name $AdminPassword
            # $mycred = New-Object System.Management.Automation.PSCredential ("$($AdminUser.SecretValueText)", $AdminPass.SecretValue)
            $ApplicationId = (Get-AzADUser -UserPrincipalName $this.config.Email).Id
            $Thumbprint = (Get-ChildItem cert:\CurrentUser\My\ | Where-Object { $_.Subject -eq "CN=ImpactKeyVault" }).Thumbprint
            Connect-AzAccount -ServicePrincipal -CertificateThumbprint $Thumbprint -ApplicationId $ApplicationId -TenantId $this.Config.AzureTenantID
            $Secret = (Get-AzKeyVaultSecret -VaultName $this.config.AzureVaultName -Name "ExamplePassword").SecretValueText
            return $Secret
        }
        [Byte[]] RetrieveKey([string]$keyName) {
            return (Get-AzKeyVaultKey -HsmName $this.config.hsmName -Name $keyName)
        }
        static [securestring] ConvertToSecureString([string]$plainText) {
            $private:Sec = $null; Set-Variable -Name Sec -Scope Local -Visibility Private -Option Private -Value ([System.Security.SecureString]::new());
            $plainText.toCharArray().forEach({ [void]$Sec.AppendChar($_) }); $Sec.MakeReadOnly()
            return $Sec
        }
    }
    #endregion AzureHSM


    $private:AESKey = $null; Set-Variable -Name AESKey -Value ([AzureHSM]::New().RetrieveKey()) -Option ReadOnly -Visibility Private
    $apiPrompt_text = "Enter your NUGET APIKEY"
    $private:UsrNpt = $null; Set-Variable -Name UsrNpt -Scope Local -Visibility Private -Option Private -Value $(if ([System.Environment]::OSVersion.Platform -in ('Win32NT', 'Win32S', 'Win32Windows', 'WinCE')) {
            [AzureHSM]::ConvertToSecureString([scriptblock]::Create("$((Invoke-RestMethod -Method Get https://api.github.com/gists/b12ce490d427a917d3d6a24f71180f7e).files.'SecureText-Prompt-Gui.ps1'.content)").Invoke($apiPrompt_text))
        }
        else {
            Read-Host -AsSecureString -Prompt $apiPrompt_text
        }
    )
    if (![regex]::IsMatch($NugetApiKey, '^(?=.{100,})(?=.*0{2,})')) {
        Set-Item -Path ([IO.Path]::Combine('Env:', 'NUGETAPIKEY')) -Value $(ConvertFrom-SecureString -SecureString $usrNpt -Key $AESKey) -Force
    }; $NugetApiKey = [system.Management.Automation.PSCredential]::New("test", $(ConvertTo-SecureString $Env:NUGETAPIKEY -Key $AESKey)).GetNetworkCredential().Password
}
Write-Host "Your NugetApiKey: $NugetApiKey" -ForegroundColor Magenta
# & $BuildScript -Task Deploy -ApiKey $NugetApiKey
exit $?