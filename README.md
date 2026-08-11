# ContactsDeduper

本地优先的 iOS/macOS 通讯录查重与安全合并工具，使用 SwiftUI 和 Apple Contacts 框架构建。

[![CI](https://github.com/gewill/ContactsDeduper/actions/workflows/ci.yml/badge.svg)](https://github.com/gewill/ContactsDeduper/actions/workflows/ci.yml)

[简体中文](README.md) · [English](README.en.md)

[隐私说明](PRIVACY.md) · [安全审查](SECURITY_REVIEW.md) · [MIT 许可证](LICENSE)

## 功能

- 按本机、iCloud、Google 等通讯录账户列出容器，在选定账户内独立扫描。
- 根据名称、电话号码和邮箱识别重复联系人，并提供四档判定标准：两项相同、任一项、仅名称、仅电话。
- 展示每组联系人的判定依据，支持链式关联（传递性重复组）。
- 合并同一 Contacts 容器内的同名 List，保留全部成员；跨账户 List 不会自动合并。
- 手动选择保留项并合并单组联系人。
- 一键合并前预览保留项、删除项和补齐字段，可逐组取消后再执行。
- 合并完成后展示统计报告。
- 将通讯录导出为版本化 JSON 备份，并安全恢复缺失联系人或头像。
- 支持删除全部联系人，执行前需要明确确认。
- 已包含 AppIcon、隐私清单和出口合规声明，可按清单准备 App Store Connect 上架资料。

## 查重规则

应用使用三类信息建立联系人之间的关联：

1. **名称**：姓、名和中间名组合后相同。没有姓名、只有公司名的联系人使用公司名作为回退；已有姓名时不会把公司名附加到匹配条件中。
2. **电话**：规范化后的号码相同。
3. **邮箱**：忽略大小写和首尾空格后相同。

| 标准 | 含义 |
| --- | --- |
| 两项（默认） | 名称、电话、邮箱中至少两项同时相同 |
| 任一项 | 三项中任意一项相同 |
| 仅名称 | 只比较名称 |
| 仅电话 | 只比较电话 |

达到标准的联系人会建立关联，关联关系再组成重复组。例如在“任一项”下，A 与 B 电话相同、B 与 C 名称相同，三者会进入同一组。“两项”仍按联系人两两之间的证据数量判断，不会把同一电话分桶误算为多项证据。

系统通讯录中的“家人”“工作”等分组不参与联系人查重。List 只有在名称（忽略大小写和首尾空格）及 Contacts 容器均相同的情况下才可合并。

## 数据安全与隐私

- 数据通过系统 Contacts 框架直接读取和修改，应用不包含网络上传、远程同步或分析逻辑。
- 批量合并会先整理全部变更，再通过一次 `CNSaveRequest` 提交。
- 导入备份只新增缺失联系人或恢复缺失头像，不会删除或覆盖已有联系人。
- JSON 备份可能包含电话、邮箱、地址、生日和头像等敏感信息，且未加密，请妥善保管。
- 执行批量合并或删除前，请先确认预览，并建议保留一份可读取的备份。

## 快速开始

要求：iOS 17 或更高版本、macOS 14 或更高版本。目前仅在 Xcode 26（本地验证版本为 Xcode 26.6）上验证；其他 Xcode 版本尚未验证，不保证兼容。

打开 `ContactsDeduper.xcodeproj`，选择 iPhone 模拟器、iOS 真机或 `My Mac` 后运行。首次启动需要允许通讯录访问。

macOS 开发版本若使用临时代码签名，重新构建后系统可能再次询问通讯录权限。需要稳定保留授权时，请在 Xcode 的 Signing & Capabilities 中选择有效的 Personal Team。

## 构建与测试

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

测试包直接调用查重与备份逻辑，不访问 `CNContactStore`，不需要通讯录权限，也不会启动 App（刻意不设置 `TEST_HOST`）：

```bash
xcodebuild test -project ContactsDeduper.xcodeproj \
  -scheme ContactsDeduper \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO
```

GitHub Actions 会在 macOS 上执行构建和完整单元测试，并在 iOS 模拟器上执行功能测试。

## 项目结构

- `ContactsDeduper/ContentView.swift`：账户路由、查重界面、导入导出、批量操作和报告。
- `ContactsDeduper/ContactsManager.swift`：权限、容器级查询、查重、合并、删除和 Contacts 数据访问。
- `ContactsDeduper/ContactsBackup.swift`：版本化备份模型、校验、编码与恢复。
- `ContactsDeduper/Assets.xcassets`、`ContactsDeduper/PrivacyInfo.xcprivacy`：应用图标与 Apple 隐私清单。
- `ContactsDeduperTests/`：查重、合并、备份及性能测试。
- `ContactsDeduper/Info.plist`、`ContactsDeduper/Info-macOS.plist`：平台权限与应用配置。
- `APP_STORE_PREP.md`：App Store Connect 分类、隐私和上传前检查清单。

## 已知限制

- 电话归一化目前主要覆盖北美常见格式，部分国际号码可能无法自动识别为重复。
- JSON 备份未加密；请将导出文件视为敏感资料保存。

## 许可证

本项目采用 [MIT License](LICENSE)。
