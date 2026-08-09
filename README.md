# ContactsDeduper

ContactsDeduper 是一个使用 SwiftUI 和 Contacts 框架构建的本地通讯录去重工具，同时支持 iOS 17+ 与 macOS 14+。

[隐私说明](PRIVACY.md) · [安全审查](SECURITY_REVIEW.md) · [MIT 许可证](LICENSE)

## 功能

- 扫描姓名、电话号码或邮箱相同的联系人。
- 展示每组重复联系人的全部判定依据及命中对象。
- 手动选择保留项并合并单组联系人。
- 一键同步合并全部重复项，并显示实时进度。
- 合并完成后展示统计报告和撒花效果。
- 将通讯录导出为版本化 JSON 备份。
- 从备份中安全恢复缺失联系人，不删除或覆盖现有联系人。
- 支持删除全部联系人，并在执行前进行明确确认。

## 查重规则

应用使用以下信息建立重复关系：

1. 规范化后的电话号码相同。
2. 忽略大小写和首尾空格后的邮箱相同。
3. 姓、名和中间名组合后相同。

匹配关系会进行链式合并。例如 A 与 B 电话相同、B 与 C 姓名相同，三者会进入同一个重复组。系统通讯录中的“家人”“工作”等分组不参与查重。

## 数据安全

- 通讯录数据通过系统 Contacts 框架直接读取和修改。
- 应用不包含网络上传或远程同步逻辑。
- 批量合并会先在内存中整理全部变更，再通过一次 `CNSaveRequest` 提交。
- 导入备份只补回缺失联系人和头像，不会删除或覆盖已有联系人。
- JSON 备份可能包含电话、邮箱、地址、生日和头像等敏感信息，并且未加密，请妥善保管。
- 执行批量合并或删除操作前，建议先导出备份并确认文件可以读取。

## 运行要求

- Xcode 16 或更高版本
- iOS 17 或更高版本
- macOS 14 或更高版本

打开 `ContactsDeduper.xcodeproj`，选择 iPhone 模拟器、iOS 真机或 `My Mac` 后运行。首次启动时需要允许通讯录访问。

macOS 开发版本如果使用临时代码签名，系统可能在重新构建后再次询问通讯录权限。为稳定保留授权，请在 Xcode 的 Signing & Capabilities 中选择有效的 Personal Team。

## 构建验证

```bash
xcodebuild -project ContactsDeduper.xcodeproj \
  -scheme ContactsDeduper \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO build
```

```bash
xcodebuild -project ContactsDeduper.xcodeproj \
  -scheme ContactsDeduper \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build
```

## 项目结构

- `ContactsDeduper/ContentView.swift`：主界面、导入导出、批量操作和报告。
- `ContactsDeduper/ContactsManager.swift`：权限、查重、合并、删除和 Contacts 数据访问。
- `ContactsDeduper/ContactsBackup.swift`：版本化备份模型、校验、编码与恢复。
- `ContactsDeduper/Info.plist`：iOS 权限与应用配置。
- `ContactsDeduper/Info-macOS.plist`：macOS 权限与应用配置。

## 许可证

本项目采用 [MIT License](LICENSE)。
