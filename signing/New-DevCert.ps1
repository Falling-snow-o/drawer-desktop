# 生成自签名代码签名证书（免费）
# 私钥留在本机 CurrentUser\My，公开证书导出到 signing\drawer-dev.cer 供用户信任
param(
    [string] $Subject = 'CN=Drawer Desktop (self-signed)',
    [int] $Years = 5
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$signDir = Join-Path $root 'signing'
New-Item -ItemType Directory -Force -Path $signDir | Out-Null

$cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject $Subject `
    -KeyUsage DigitalSignature `
    -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears($Years) `
    -CertStoreLocation Cert:\CurrentUser\My

$cerPath = Join-Path $signDir 'drawer-dev.cer'
Export-Certificate -Cert $cert -FilePath $cerPath -Type CERT | Out-Null

# 私钥导出到仓库外，密码随机，仅本机保存
$keyDir = Join-Path $env:USERPROFILE '.boxrun\signing'
New-Item -ItemType Directory -Force -Path $keyDir | Out-Null
$pfxPath = Join-Path $keyDir 'drawer-dev.pfx'
$password = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
$secure = ConvertTo-SecureString -String $password -AsPlainText -Force
Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $secure | Out-Null
Set-Content -LiteralPath (Join-Path $keyDir 'pfx-password.txt') -Value $password -Encoding ASCII

$thumb = $cert.Thumbprint
Write-Host ('证书指纹: ' + $thumb)
Write-Host ('公开证书: ' + $cerPath)
Write-Host ('私钥备份: ' + $pfxPath + '（不要提交到仓库）')
Write-Host ''
Write-Host '打包示例:'
Write-Host ('  powershell -File 打包.ps1 -Version 1.2.0 -Sign -CertThumbprint ' + $thumb)
