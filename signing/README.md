# 免费代码签名（自签名 + 信任脚本）

## 原理

Windows 不信任自签名证书，所以默认仍会提示“未知发布者”。
但只要把 **公开证书** 装进当前用户的「受信任的根证书」和「受信任的发布者」，签名就会被判为 `Valid`，发布者显示为证书里的名字。

- 私钥永远留在你本机，不进仓库
- 用户只需要公开证书 `.cer`，不需要私钥
- 只对“装过信任脚本”的机器生效；公开分发仍需 CA 证书

## 1. 生成证书（只做一次）

```powershell
powershell -File signing\New-DevCert.ps1
```

产物：

| 文件 | 说明 |
|---|---|
| `signing\drawer-dev.cer` | 公开证书，可提交/随包分发 |
| `%USERPROFILE%\.boxrun\signing\drawer-dev.pfx` | 私钥备份，**不要提交** |
| `%USERPROFILE%\.boxrun\signing\pfx-password.txt` | PFX 密码，**不要提交** |

脚本会打印证书指纹，签名时用。

## 2. 签名打包

```powershell
powershell -File 打包.ps1 -Version 1.2.0 -Sign -CertThumbprint <指纹>
```

打包脚本会签 `Drawer.exe` 和 `drawer-setup.exe`。

## 3. 让用户信任（每台机器一次，不需要管理员）

把 `signing\drawer-dev.cer` 和 `signing\Trust-DevCert.ps1` 一起给用户，运行：

```powershell
powershell -ExecutionPolicy Bypass -File Trust-DevCert.ps1
```

之后：

```powershell
Get-AuthenticodeSignature "$env:LOCALAPPDATA\Drawer\Drawer.exe"
# Status: Valid
# SignerCertificate.Subject: CN=Drawer Desktop (self-signed)
```

## 限制（重要）

- **只对信任过证书的机器有效**，公开用户不会自动信任
- **SmartScreen 信誉仍然独立**：即使签名有效，新软件/低下载量仍可能被提示
- 想公开分发且不提示“未知发布者”，只有两条路：
  1. 购买受信任的 OV 证书（约 ¥600/年 起）
  2. 开源项目申请 **SignPath Foundation** 免费签名（需公开仓库 + 开源许可证，审核制）

## 私钥安全

- `signing\*.pfx`、`*.pvk` 已在 `.gitignore` 中
- 不要把 PFX 或密码贴到聊天、issue、CI 明文变量里
- 换机器时从 `%USERPROFILE%\.boxrun\signing\` 迁移，或重新生成并让用户重新信任
