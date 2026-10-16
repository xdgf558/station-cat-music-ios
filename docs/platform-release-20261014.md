# 平台版发布准备 · 2026-10-14

基线：iOS `37d409fb20296085b53c44a817ddd0a5a0cc1c61`（#15 合并）。分支：`codex/platform-release-acceptance`。本批候选 **0.1.0（7）**。10 月 14 日完成本地发布准备；10 月 15 日 09:47（Asia/Singapore）使用正式版 Xcode 上传 TestFlight 成功，Apple 返回处理中，详见文末。没有向手机安装、提交 App Store 审核或修改网站配置。

## 变更与原因

生产包仍继承旧播放器的后台音频声明，且缺少使用本机缓存文件时间和偏好 API 所需的隐私清单。生成器现在为 Production 使用专门生成的 `Config/PlatformRelease-Info.plist`，去掉后台音频；使用优化编译、dSYM，并关闭 testability。其余配置继续保留隔离播放探针的背景音频条件。四种默认配置的原生认证、音频、同步、正式 activation 和公开目录开关均未打开。

隐私清单已加入 App 资源。Required Reason 声明仅对应文件时间与本应用 UserDefaults，不声称隐私问卷已经完成。新增包检查读取实际 Info.plist、PrivacyInfo.xcprivacy 和四语更新说明，区分默认关闭包与显式开启公开目录的候选；原生能力或错误 origin、后台音频、缺失清单、版本/说明不一致均拒绝。CI 四配置构建增加 Production 包检查。

只读检查现网发现 `/music/` 已不包含 `music-privacy`、`music-listening` 锚点。App 的帮助入口改为四语独立隐私与条款页面；构建号升为 7，四语更新说明同步补齐，build 6 及更早记录保留。四语页面和支持候选链接共九个 URL 均返回 HTTP 200。链接可访问不代表政策内容已经完成平台版适配。

[四语商店文案与审核说明](app-store/platform-v1-metadata.json)和[隐私政策准备稿](app-store/platform-privacy-draft.md)已保存。文案依据当前原生浏览、作品、搜索、收藏和外链功能，不宣传 App 内播放、会员或离线听歌。现网政策主要描述旧网页播放器，仍需平台 App 专用政策及服务器数据处理事实确认。

## 本地验证

| 检查 | 结果 |
| --- | --- |
| 发布检查回归 | 7/7，通过，覆盖默认关闭、显式公开目录、错误来源、原生开关、后台音频及缺少隐私/说明。 |
| Production 真机架构归档 | 成功；`org.stationcat.music`，0.1.0（7），公开元数据 YES，其余原生能力 NO；未签名。 |
| Production 模拟器关闭态构建 | 成功；公开目录与原生能力全部 NO，包检查通过。 |
| 平台 UI | 4/4，通过：平台页面无原生播放、收藏分级入口、详情失败/外链拒绝后的复制、四语最大动态字体。 |
| 版本与帮助 UI | 1/1 复跑通过；确认 build 7、新说明及隐私/条款控件。更新说明截图已目视检查。 |
| 图标 | 1024×1024 PNG，无 alpha 通道；沿用用户选定图标。 |
| 资源与源码 | 生成器一致性、四语 parity、源码守卫与 diff 检查通过。 |

首次 UI 执行中上述四项平台测试已经通过；版本测试的两条新增断言错误地把 SwiftUI Link 限定为 XCTest Link 类型，因而失败。改为保留相同 accessibilityIdentifier、使用任意控件类型查找后，该测试独立复跑通过。没有降低其余断言，原失败日志保留。

本机为 **Xcode 27 beta 6，模拟器 iOS 26.5**；未在本轮运行固定稳定 Xcode 的远端 CI。归档使用 `CODE_SIGNING_ALLOWED=NO`，没有分发证书、profile 或上传验证，不能直接视为可提交的 IPA。稳定工具链与分发签名须在后续候选中完成。

## 真机记录

用户于本轮明确表示“**不用真机测试了，我已经实际测试过了**”。按用户实测确认记录，并停止手机自动化。未提供逐项耗时或具体平台清单，不将其扩展成每个平台/网络场景的自动化证据。

停止前的预备测试等待手机解锁达 360 秒后超时，没有运行缓存断言。私密记录保留在本机忽略的 `evidence/platform-device-32790ddf-9c5f-433a-b738-087f0fa04668/`，摘要 `success=false`。未交付那些未完成的设备探针，本分支不包含设备测试驱动。用户要求停止后未再次操作手机、修改网络或安装应用。

## 本机产物与待办

本机忽略目录 `.build/platform-release-20261014/` 保存未签名归档、两个包检查 JSON、UI 日志/xcresult、截图及公开 URL 状态；脱敏摘要在 [verification.json](platform-release-20261014/verification.json)。这些只证明所列本地范围。

本批代码审查及完整稳定 CI、平台版隐私政策仍需完成。正式签名与 TestFlight 上传已于 10 月 15 日按用户后续要求完成，服务器处理结果由用户人工确认。商店 App Privacy、权利证明、年龄分级、审核联系方式、真实作品截图及最低功能审核仍按实际候选完成，不由此次本地打包自动关闭。

## 同日 TestFlight 上传准备进展

用户随后明确要求开始上传 TestFlight。已创建 App Store Connect 的 Station Cat Music 记录，Apple ID 为 `6822797145`，Bundle ID 为 `org.stationcat.music`，主要语言为简体中文，SKU 为 `station-cat-music-ios`。没有提交 App Store 审核、邀请测试人员或打开原生账号、播放、同步服务。

新增生产包 `ITSAppUsesNonExemptEncryption=false`：本候选仅使用 Apple 系统 HTTPS、Keychain 和 CryptoKit 哈希，无第三方或自有加密实现。依据 [Apple 关于系统加密的说明](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)，包检查要求显式布尔声明；相应回归现为 8/8。该声明不代替商店 App Privacy 问卷。

正式 Bundle ID、Team `2AM5S7BM2N` 的开发签名归档成功，实际包仍为 0.1.0（7），四语更新说明、隐私清单和公开目录边界检查通过。[Apple 2026-08-25 发布记录](https://developer.apple.com/help/app-store-connect/release-notes/)曾允许 Xcode 27 beta 6 上传 TestFlight；这只是当时的支持记录，不能替代上传时的服务器校验。10 月 15 日的实际拒绝结果见下文。

当日签名归档保存在本机忽略目录 `.build/testflight-20261014/StationCatMusic-Final.xcarchive`。当时分发导出被 `No Accounts` 和缺少 `org.stationcat.music` 的 App Store profile 阻断；浏览器登录并未完成 Xcode 的独立认证，当时没有上传成功凭据。用户已授权安装的 Xcode 必需组件已完成安装。私密日志、哈希及这次尝试的状态保留在 `.build/testflight-20261014/upload-status.json`；该文件已标注后续成功记录的位置。先前未签名验证摘要保留为历史记录，不能代替最终上传结果。

## 10 月 15 日：签名已恢复，旧工具链被拒绝

用户重新登录 Xcode 后，自动分发签名与 App Store IPA 导出成功。实际分发 profile 属于 Team `2AM5S7BM2N` 和 `org.stationcat.music`，`get-task-allow=false`、`beta-reports-active=true`，没有设备白名单；代码签名及实际 IPA 的版本、四语说明和能力边界检查通过。

09:08 的实际上传被 Apple 返回 `Unsupported SDK or Xcode version` 拒绝（错误 ID `L6UB5XAA4OHB2NEEH5NIKMTK4A`）。此结果不属于账号或 profile 失败，也没有上传成功。拒绝日志保留于 `.build/testflight-20261014/upload-20261015.log`；之后使用 Apple 官方正式版工具链重新构建，没有修改构建元数据伪装 SDK。

用户明确选择在上传完成后自行核对 App Store Connect 网页处理结果。因此，本轮以 Apple 上传回执判断上传是否成功；服务器后续处理、测试人员分发及 App Store 发布均另行区分。

## 10 月 15 日 09:47：TestFlight 上传成功

从 Mac App Store 安装 Apple 官方 **Xcode 27.0（27A266a）**，使用独立 DerivedData 重新归档。实际包的 `DTXcodeBuild=27A266a`、`DTSDKName=iphoneos27.0`、`DTSDKBuild=24A430`，最低 iOS 18.0；归档、分发导出和严格签名验证通过。产品源码与上一候选一致，版本仍为 **0.1.0（7）**，四语更新说明和隐私清单检查通过。公开元数据连接现网，其余原生服务继续关闭。

09:47:52 的 Xcode 日志明确返回 `Uploaded package is processing.`、`Upload succeeded.` 和 `EXPORT SUCCEEDED`，进程退出码为 0。已成功交付 Apple 的上传阶段；未读取 App Store Connect 网页确认后续处理完成，也未邀请测试人员或提交正式审核。

新归档、验证用 IPA、签名摘要和上传日志保存在本机忽略目录 `.build/testflight-20261015-stable/`；[脱敏上传记录](platform-release-20261014/testflight-upload-20261015.json)保存版本、工具链、源码与上传日志摘要。记录中的 `verificationIPASHA256` 对应单独导出的验证 IPA，不声称它是 Xcode 临时上传封装的字节摘要。正式版归档成功不等于本批完整稳定 CI 已执行；没有重新运行用户已要求停止的真机测试。
