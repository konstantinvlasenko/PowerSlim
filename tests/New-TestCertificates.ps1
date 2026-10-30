<#
.SYNOPSIS
  Creates a throwaway certificate authority and a certificate it signs, for PowerSlim's tests.

.DESCRIPTION
  Writes ca.cer (the CA certificate) and powerslim.pfx (certificate and private key, valid for
  localhost and 127.0.0.1, usable as TLS server and client certificate) into -Path, and returns
  their paths and the random PFX password. -Name adds files for a second, independent CA.
  For real agents use certificates from your own PKI; see README.md.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$Path,

  [string]$Name = 'powerslim',

  [string[]]$DnsName = @('localhost'),

  [string[]]$IPAddress = @('127.0.0.1')
)

$ErrorActionPreference = 'Stop'
$crypto = 'System.Security.Cryptography'
$x509 = "$crypto.X509Certificates"
$sha256 = [System.Security.Cryptography.HashAlgorithmName]::SHA256
$pkcs1 = [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
$now = [DateTimeOffset]::UtcNow
New-Item -ItemType Directory -Force -Path $Path | Out-Null

# Certificate authority
$caKey = [System.Security.Cryptography.RSA]::Create(2048)
$caRequest = New-Object "$x509.CertificateRequest" "CN=PowerSlim test CA ($Name)", $caKey, $sha256, $pkcs1
$caRequest.CertificateExtensions.Add((New-Object "$x509.X509BasicConstraintsExtension" $true, $true, 0, $true))
$caRequest.CertificateExtensions.Add((New-Object "$x509.X509KeyUsageExtension" ([System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]'KeyCertSign, CrlSign'), $true))
$ca = $caRequest.CreateSelfSigned($now.AddMinutes(-5), $now.AddDays(2))

# Certificate for agents and runners, signed by the CA
$key = [System.Security.Cryptography.RSA]::Create(2048)
$request = New-Object "$x509.CertificateRequest" "CN=PowerSlim test ($Name)", $key, $sha256, $pkcs1
$request.CertificateExtensions.Add((New-Object "$x509.X509BasicConstraintsExtension" $false, $false, 0, $true))
$request.CertificateExtensions.Add((New-Object "$x509.X509KeyUsageExtension" ([System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]'DigitalSignature, KeyEncipherment'), $true))
$usages = New-Object "$crypto.OidCollection"
[void]$usages.Add((New-Object "$crypto.Oid" '1.3.6.1.5.5.7.3.1')) # server authentication
[void]$usages.Add((New-Object "$crypto.Oid" '1.3.6.1.5.5.7.3.2')) # client authentication
$request.CertificateExtensions.Add((New-Object "$x509.X509EnhancedKeyUsageExtension" $usages, $false))
$names = New-Object "$x509.SubjectAlternativeNameBuilder"
foreach ($dns in $DnsName) { $names.AddDnsName($dns) }
foreach ($ip in $IPAddress) { $names.AddIpAddress([System.Net.IPAddress]::Parse($ip)) }
$request.CertificateExtensions.Add($names.Build())
$serial = New-Object byte[] 16
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($serial)
$signed = $request.Create($ca, $now.AddMinutes(-5), $now.AddDays(1), $serial)
$certificate = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::CopyWithPrivateKey($signed, $key)

$password = [Convert]::ToBase64String($serial) # random, only for this throwaway file
$caPath = Join-Path $Path "$Name-ca.cer"
$pfxPath = Join-Path $Path "$Name.pfx"
[IO.File]::WriteAllBytes($caPath, $ca.Export('Cert'))
[IO.File]::WriteAllBytes($pfxPath, $certificate.Export('Pfx', $password))

[pscustomobject]@{ CertificateAuthority = $caPath; Certificate = $pfxPath; Password = $password }
