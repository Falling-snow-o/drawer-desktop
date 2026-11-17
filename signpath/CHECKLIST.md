# SignPath 申请清单（你来做，代码侧已就绪）

## 申请前

- [ ] 建一个 **公开** GitHub 仓库（MIT 许可证已就绪）
- [ ] 推送代码，确认 `README.en.md`、`CODE_SIGNING_POLICY.md`、`PRIVACY.md`、`LICENSE` 都在
- [ ] 在仓库里发一个 Release，附上 `dist\drawer-setup.exe` 和 `latest.json`
- [ ] 给 GitHub 账号开启 **双因素认证**
- [ ] 确认 `.github/workflows/release-sign.yml` 能在 Actions 里手动跑通（不启用签名时只构建）

## 提交申请

1. 打开 <https://signpath.org/apply>
2. 按 `signpath/APPLICATION.md` 里的内容填写
3. 仓库地址、维护者、联系方式替换成真实值
4. 说明“构建由 GitHub Actions 完成、每次签名人工审批”

## 通过之后（SignPath 后台配置）

- [ ] 创建 project：`drawer-desktop`
- [ ] 创建 signing policy：`release-signing`（要求 manual approval）
- [ ] 创建 artifact configuration：`installer`
  - 允许文件：`drawer-setup.exe`
  - 元数据限制：`ProductName = Drawer Desktop`、`ProductVersion = <发布版本>`
- [ ] 在 GitHub 仓库配置：
  - Secret：`SIGNPATH_API_TOKEN`
  - Variables：`SIGNPATH_ENABLED=true`、`SIGNPATH_ORGANIZATION_ID`、`SIGNPATH_PROJECT_SLUG=drawer-desktop`、`SIGNPATH_POLICY_SLUG=release-signing`
- [ ] 触发 `release-sign` 工作流，在 SignPath 里手动批准一次
- [ ] 下载签名后的安装包，验证：

```powershell
Get-AuthenticodeSignature .\drawer-setup.exe | Format-List
# Status: Valid
# SignerCertificate.Subject: CN=SignPath Foundation, ...
```

## 注意事项

- SignPath 要求 **公开可信的项目**；仓库刚建、没有下载量时可能被拒。先积累一个 release 和少量用户/star，再申请成功率更高。
- 签名产物必须来自 **CI 构建**，本地打的包不能提交签名。
- 每次发布都要人工批准；不要把 API token 写进代码或日志。
- 通过后可以把 `signing/` 下的自签名流程保留，作为本地测试用。

## 如果被拒

| 原因 | 应对 |
|---|---|
| 项目太新/无信誉 | 先发布 1–2 个版本，积累 star/下载，再申请 |
| 构建不可验证 | 确保 CI 从源码构建，不在本地打包后上传 |
| 文档不完整 | 补齐英文 README、隐私政策、卸载说明 |
| 含第三方二进制 | 安装包内只放自己的产物；第三方组件单独说明 |

被拒不影响现有自签名方案，只是公开分发仍会提示未知发布者。
