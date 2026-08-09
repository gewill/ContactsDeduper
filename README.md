# ContactsDeduper

ContactsDeduper 是一个使用 SwiftUI 和 Contacts 框架构建的本地通讯录去重工具，同时支持 iOS 17+ 与 macOS 14+。

[隐私说明](PRIVACY.md) · [安全审查](SECURITY_REVIEW.md) · [MIT 许可证](LICENSE)

## 功能

- 首屏按本机、iCloud、Google 等通讯录账户列出容器，进入账户后再独立查重。
- 扫描名称、电话号码或邮箱相同的联系人，公司类联系人按公司名比对。
- 提供四档判定标准（两项相同 / 任一项 / 仅名称 / 仅电话），可随时切换。
- 展示每组重复联系人的全部判定依据及命中对象。
- 扫描并合并同一通讯录账户内的同名 List，同时保留全部成员。
- 手动选择保留项并合并单组联系人。
- 一键合并前先预览每组的保留项、删除项和补齐字段，可逐组取消后再执行。
- 合并完成后展示统计报告和撒花效果。
- 将通讯录导出为版本化 JSON 备份。
- 从备份中安全恢复缺失联系人，不删除或覆盖现有联系人。
- 支持删除全部联系人，并在执行前进行明确确认。

## 查重规则

应用比对以下三类信息：

1. **名称**：姓、名和中间名组合后相同。公司类联系人（没有填写姓名，只有公司）改用公司名比对。公司名只在没有姓名时作为回退，不会附加到已有姓名上——否则同一家公司的不同同事会被误判为同一个人。
2. **电话**：规范化后的号码相同。
3. **邮箱**：忽略大小写和首尾空格后相同。

判定标准可在账户页顶部随时切换，切换后立即重算，无需重新读取通讯录：

| 标准 | 含义 |
| --- | --- |
| 两项（默认） | 名称、电话、邮箱中至少两项同时相同才算重复 |
| 任一项 | 三项中任意一项相同就算重复 |
| 仅名称 | 只看名称，忽略电话与邮箱 |
| 仅电话 | 只看电话，忽略名称与邮箱 |

达到标准的两个联系人会建立关联，关联关系再进行链式合并。例如在「任一项」下，A 与 B 电话相同、B 与 C 名称相同，三者会进入同一个重复组。注意「两项」判定的是**联系人两两之间**的证据数量：共处同一个电话分桶只算一项证据，不足两项不会建立关联。

系统通讯录中的“家人”“工作”等分组不参与查重。

联系人 List 使用独立规则处理：名称忽略大小写和首尾空格后相同，并且属于同一个 Contacts 容器时，才会显示为可合并。跨 iCloud、Google 或其他账户的同名 List 不会自动合并。

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

- `ContactsDeduper/ContentView.swift`：账户路由、账户内查重、导入导出、批量操作和报告。
- `ContactsDeduper/ContactsManager.swift`：权限、容器级查询、查重、合并、删除和 Contacts 数据访问。
- `ContactsDeduper/ContactsBackup.swift`：版本化备份模型、校验、编码与恢复。
- `ContactsDeduper/Info.plist`：iOS 权限与应用配置。
- `ContactsDeduper/Info-macOS.plist`：macOS 权限与应用配置。

## 许可证

本项目采用 [MIT License](LICENSE)。
