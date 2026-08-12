# App Store 上架准备 / App Store Preparation

这份清单记录可以随代码交付的上架配置，以及需要在 Apple Developer / App Store Connect 中手动完成的账号侧事项。

## 已纳入工程

- `ContactsDeduper/Icon.icon`：由 SVG 矢量图层组成的多层图标，交由 Xcode Icon Composer 自动生成 iOS/macOS 变体。
- `ContactsDeduper/PrivacyInfo.xcprivacy`：声明不跟踪、不收集数据，并为应用自身的 `UserDefaults` 使用 `CA92.1` required-reason API 理由。
- `ContactsDeduper/Info.plist` 与 `Info-macOS.plist`：加入 `ITSAppUsesNonExemptEncryption = NO`，声明应用不使用非豁免加密。
- `Info-macOS.plist`：设置 `LSApplicationCategoryType = public.app-category.utilities`。
- `PRIVACY*.md`：提供 8 种语言的隐私政策，可作为 App Store Connect 的隐私政策页面内容。
- `AppStoreMetadata.json`：提供简体中文、繁体中文、英语、日语、韩语、西班牙语、法语和德语的名称、副标题、描述、关键词及隐私政策链接；各语言隐私政策位于对应的 `PRIVACY.*.md`。

## App Store Connect 建议填写

| 项目 | 建议值 |
| --- | --- |
| iOS 主分类 | Utilities（实用工具） |
| iOS 次分类 | Productivity（效率） |
| macOS 分类 | Utilities（需与工程中的 `LSApplicationCategoryType` 保持一致） |
| 隐私政策 URL | `https://github.com/gewill/ContactsDeduper/blob/main/PRIVACY.md`，或部署后的稳定 HTTPS 页面 |
| 支持网址 | `https://github.com/gewill/ContactsDeduper/issues` |
| 应用名称 / 副标题 | `ContactsDeduper` / 按目标商店语言填写不超过 30 字符的副标题 |
| 数据收集 | 不收集；联系人数据只在设备本地处理，不上传服务器 |
| 跟踪 | 不跟踪；无广告、分析、遥测或第三方追踪 SDK |
| 出口合规 | 本工程已声明 `ITSAppUsesNonExemptEncryption = NO`；首次上传仍按 App Store Connect 问卷确认 |

分类和隐私标签属于 App Store Connect 元数据，无法仅通过 Xcode 工程文件完成。主分类应与 macOS 的 Info.plist 分类一致，并以应用的核心功能为准。

## 上传前仍需完成

1. 在 App Store Connect 创建 App，确认最终 Bundle ID 为 `org.gewill.ContactsDeduper` 或替换为已注册的正式 Bundle ID。
2. 填写名称、副标题、描述、关键词、支持网址、隐私政策 URL、年龄分级和销售地区。
3. 上传 iPhone/iPad 与 macOS 截图；确认截图不包含真实联系人信息。
4. 在 App Privacy 中确认联系人信息不会被收集或与身份关联，并逐项核对 Apple 问卷。
5. 配置有效的 Distribution Certificate、Provisioning Profile、Team 和签名能力后再 Archive/上传。
6. 首次上传后检查 TestFlight 的 Export Compliance 状态；若出现 Missing Compliance，按 App Store Connect 提示完成问卷。

## App Review 备注建议

- 无需登录、账号或测试凭据。
- 首次启动后允许 Contacts 权限；选择账户即可开始扫描。
- 所有联系人处理均在本机完成，不需要网络连接。
- 合并和删除操作均会先展示预览并要求明确确认。
- 审核截图和备注不得包含真实联系人姓名、电话、邮箱或备份文件。

## 本地验证

- Xcode 26.6：iOS Release Simulator build ✅
- Xcode 26.6：macOS Release build ✅
- 归档上传前仍需使用有效 Team、Distribution 证书和正式 provisioning profile。

## English checklist

The repository includes the app icon, privacy manifest, non-exempt-encryption declarations, macOS Utilities category, and bilingual privacy policy. In App Store Connect, use Utilities as the primary category and Productivity as the secondary category, publish a stable HTTPS privacy-policy URL, answer “not collected” and “not tracked” only if they still match the shipped binary, complete age-rating and metadata forms, upload redacted screenshots, and configure distribution signing before archiving.
