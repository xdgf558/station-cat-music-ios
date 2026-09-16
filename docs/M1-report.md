# M1 本地交付与验收记录

日期：2026-09-16。范围为用户批准的 M1 工程骨架、契约、Mock、状态机与测试基础。没有启动 M2 真实认证、M3 授权音频、账号删除后端或 StoreKit。

## 交付

| M1 任务 | 本轮交付 |
|---|---|
| 01 基线 | PR #170 已合入的主线 `05e27342`；另保留 20260916 播放统计生产来源及 17 个跟踪文件差异。来源和 SHA-256 见 baseline-inventory.json。 |
| 02 正式工程 | 独立本地 SwiftUI 项目；iOS18；Mock/Development/Staging/Production 四配置。显式 Info.plist 注入环境，缺失/未知配置关闭。无正式团队签名、远端仓库或部署。 |
| 03 契约 | OpenAPI3.1：24 个拟定首版操作，58 个 schema，59 个正向 fixture 和 10 个负向 fixture，四语错误键及 receipt 编码/hash 验证。 |
| 04 网络/作用域 | 依赖注入 MockTransport；所有非 Mock 请求、所有写操作关闭；目录取消、操作序号与账号 scope；503 不映射会员过期。 |
| 05 基础服务 | 唯一 AVPlayer 所有者；连续时钟边界/停止/旧 sequence 拒绝；Keychain 单 item 更新；刷新与删除 journal；未接入的认证/权益服务显式不可用。 |
| 06 原生界面 | 发现/曲库/我的、加载/空/失败状态、示例搜索、临时收藏、播放器占位页、四语和动态字体；深色与暖金设计。 |
| 07 测试/交付 | Swift/XCUITest、四配置构建检查、Keychain 独立进程恢复脚本、OpenAPI/源码 guard、固定稳定工具链 CI 定义、说明及预览图。 |

## 实际验证

本地工具链为 **Xcode 27 beta 6 / 27A5252f，iPhone 17 Pro / iOS27 模拟器**；最低构建目标 iOS18。

- 四配置构建成功；逐一读取实际应用包确认 environment 为 mock/development/staging/production、MinimumOSVersion=18.0、没有 HTTP ATS 例外。
- 32 个 Swift 单元测试和 2 个 XCUITest（其中一个遍历四语言最大辅助字号）；覆盖目录解码/取消、迟到账号结果、未知权限拒绝、播放所有权/截止、刷新 journal、删除恢复及真实 Keychain。
- Keychain 在正式 Xcode 测试宿主下写、读、替换、删除成功；另外分两次独立 xcodebuild 测试进程保存/读取同一合成记录。M0 手工探针的 `-34018` 没有复现。
- OpenAPI 和所有 fixtures 通过标准 validator；生成器可字节级复现。源码 guard 检查已知凭据模式、HTTP 例外、播放器唯一性及四语键一致性。
- 原有封面优化分支的隔离工作区：认证/媒体/目录/分享图等 **101 项通过**；网站构建使用 `ALLOW_EMPTY_SERIAL_CONTENT=1` 成功，该包不可部署。
- 最新本地生产来源副本：同一套 **101 项通过**，无跳过。原封存来源未修改。

本机使用标准 validator 时，系统 Python3.9 的 LibreSSL 会产生 urllib3 兼容提示；验证只读取本地 schema/fixture，不发起网络请求。CI 使用 Python3.11。没有把这条提示当作线上服务验收。

## 调试中发现并处理

正式构建需要在允许 Xcode 子进程运行的环境中执行；最初沙箱内宏插件无法返回结果，属于本机执行约束。正式工程成功构建后，真实 Keychain 测试通过。

最大动态字号时，横排品牌与预览徽标互相挤压，已改为纵排并固定装饰图标大小。截图检查发现迷你播放器遮挡 iOS27 浮动标签栏，已调整到页面安全区，并增加几何不重叠断言。

现有共享模拟器安装了自定义输入法，影响 UI 自动化焦点；另建独立「Station Cat M1 QA」模拟器复核，没有修改原模拟器键盘配置。测试同时适配原生搜索关闭控件在不同系统中的 Close/Cancel 名称。

刷新退出竞态测试原先用两次 Task.yield 猜测调度，曾偶发先完成刷新才开始退出。测试现明确等待退出 epoch 改变，再释放挂起写入，验证的是确定发生的竞态，不依赖调度运气。

Xcode 自动生成 Info.plist 没有保留自定义环境字段，已改用显式 plist，并以实际构建包断言复核；不能仅靠源码中的环境枚举认为切换已经生效。

## 网站来源与测试补丁

M0 记录的 9 个生产差异已增加到 17 个，最新本地来源还含另一个任务的播放统计改动。该清单是本地部署记录与源码快照，本轮没有查询或改变线上运行版本。

历史封面优化分支的测试仍期望原图 URL，本轮在独立 `codex/music-ios-m1-baseline` 工作区修正展示版期望，并增加海报必须读取原始 artwork 对象的断言。最新生产来源已经含 `size=display` 的期望修正，所以对最新来源只需要额外原图断言。

`website-cover-test-fix.patch` 是历史分支的完整测试补丁；`latest-source-share-cover-assertion.patch` 是最新来源的增量测试补丁。两者不是生产运行时补丁，不应把旧分支整包覆盖线上。原来主工作区未提交 README 和依赖链接保留。

## 尚未验收

稳定 **Xcode26.4.1 远端 CI 尚未运行**，本机没有安装该版本；CI 定义会固定版本并在缺失时失败。本轮结果不能代替稳定工具链、最低 iOS18 运行时或实体 iPhone 验收。

没有真实账号/PKCE/AASA/recent-auth/TOTP 联调，没有 D1/R2 迁移、真实授权媒体、后台/锁屏/耳机、Keychain 设备锁定及系统回收压力验收。当前仅停止无音源的 AVPlayer 和注入 loader；不能据此声称真机缓冲音频已被安全切断。

没有真实收藏/历史持久化及同步，没有购买、订阅或账号删除服务。M0 的服务器/文件故障实验仍是模型；Swift 本轮移植客户端 journal 和边界相关案例，不替代服务器原子事务/幂等矩阵。

## 下一阶段

审查 M1 后进入 M2：在隔离后端实现原生会话、系统浏览器 PKCE、Keychain 凭据实际接线、recent-auth/TOTP、注销及删除任务/只读 receipt 查询；先明确 AASA 域名/测试账号/隔离数据库和保留政策。真实媒体和锁屏继续在 M3/M4，购买仍不属于该阶段。

预览：[繁中发现页](previews/discover-zh-hant.png)、[英文发现页](previews/discover-en.png)、[我的](previews/account-en.png)、[最大辅助字号](previews/discover-zh-hant-large.png)。
