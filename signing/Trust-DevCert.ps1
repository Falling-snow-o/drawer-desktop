# 让当前用户信任 Drawer 的自签名证书（不需要管理员）
# 导入到「受信任的根证书颁发机构」和「受信任的发布者」，之后签名校验为 Valid
$ErrorActionPreference = 'Stop'
$cer = Join-Path $PSScriptRoot 'drawer-dev.cer'
if (-not (Test-Path -LiteralPath $cer)) { throw ('找不到证书: ' + $cer) }

$root = Import-Certificate -FilePath $cer -CertStoreLocation Cert:\CurrentUser\Root
$pub = Import-Certificate -FilePath $cer -CertStoreLocation Cert:\CurrentUser\TrustedPublisher
Write-Host ('已信任根证书: ' + $root.Thumbprint)
Write-Host ('已信任发布者: ' + $pub.Thumbprint)
Write-Host ''
Write-Host '验证:'
Write-Host '  Get-AuthenticodeSignature "C:\Users\<你>\AppData\Local\Drawer\Drawer.exe" | Format-List'
