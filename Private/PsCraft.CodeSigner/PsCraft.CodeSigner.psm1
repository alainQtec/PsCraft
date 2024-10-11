using namespace System.Reflection
using namespace System.Management.Automation
using namespace System.Security.Cryptography.X509Certificates
class CodeSigner {
  CodeSigner() {}

  static [void] AddSignature([string]$File) {
    $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Select-Object -First 1
    [CodeSigner]::SetAuthenticodeSignature($File, $cert)
  }

  static [void] SetAuthenticodeSignature($FilePath, $Certificate) {
    $params = @{
      FilePath        = $FilePath
      Certificate     = $Certificate
      TimestampServer = "http://timestamp.digicert.com"
    }
    $result = Set-AuthenticodeSignature @params
    if ($result.Status -ne "Valid") {
      throw "Failed to sign $FilePath. Status: $($result.Status)"
    }
  }

  # .SYNOPSIS
  # Export your signing key and certificate to a .pfx file
  # .DESCRIPTION
  # If you have a private key and certificate on your computer,
  # malicious programs might be able to sign scripts on your behalf, which authorizes PowerShell to run them.
  # To prevent automated signing on your behalf, use
  # [CodeSigner]::ExportCertificate to export your signing key and certificate to a .pfx file.
  static [string] ExportCertificate([string]$CertPath, [string]$ExportPath, [SecureString]$Password) {
    $cert = Get-ChildItem -Path $CertPath
    Export-PfxCertificate -Cert $cert -FilePath $ExportPath -Password $Password
    return $ExportPath
  }

  static [void] ImportCertificate([string]$PfxPath, [SecureString]$Password) {
    Import-PfxCertificate -FilePath $PfxPath -CertStoreLocation Cert:\CurrentUser\My -Password $Password
  }

  static [bool] VerifySignature([string]$FilePath) {
    $signature = Get-AuthenticodeSignature -FilePath $FilePath
    return $signature.Status -eq "Valid"
  }

  static [void] RemoveSignature([string]$FilePath) {
    $content = Get-Content -Path $FilePath -Raw
    $newContent = $content -replace '# SIG # Begin signature block[\s\S]*# SIG # End signature block', ''
    Set-Content -Path $FilePath -Value $newContent
  }

  static [void] SignDirectory([string]$DirectoryPath, [string]$CertPath, [string]$Filter = "*.ps1") {
    $cert = Get-ChildItem -Path $CertPath
    Get-ChildItem -Path $DirectoryPath -Filter $Filter -Recurse | ForEach-Object {
      [CodeSigner]::SetAuthenticodeSignature($_.FullName, $cert)
    }
  }

  static [X509Certificate2] GetCodeSigningCert() {
    return Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Select-Object -First 1
  }
}

