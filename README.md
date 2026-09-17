# Station Cat Music · iOS

**公开可查看，非开源授权。** 项目原创内容保留所有权利；使用、修改或分发须取得相应授权，详见 [权利声明](LICENSE)。公开仓库仍允许依照 GitHub 服务条款查看与 Fork。

原生 iPhone 音乐小站：深色夜窗色调、暖金点缀，以「发现 / 曲库 / 我的」组织音乐与个人空间。计划使用同一 Station Cat 账号，并把音乐 VIP 与全站 VIP 的权益来源分开管理。

本仓库目前包含 **M1 工程基础、M2 本地隔离认证，以及 M3 曲库与授权播放第一批**。可以在模拟器浏览三首明确标注的虚构示例、搜索、临时收藏、打开播放器占位页和切换四种语言。默认仍为 Mock，尚未启用远端登录、真实曲库、音频、个人同步或购买服务；选择示例歌曲不会播放声音。

## 本轮内容

- SwiftUI 原生工程，最低 iOS 18；简体中文、繁体中文、English、日本語；动态字体、语义标签及至少 44pt 操作目标。
- 默认 Mock。Development、Staging、Production 分别写入环境字段，当前全部关闭真实网络。M2 新增系统认证窗口、PKCE、持久化刷新恢复和账号删除进度；仅 Development / Staging 可通过后续隔离配置启用，当前没有配置域名。缺失或未知环境也按关闭处理。
- 25 个首版 API 操作、OpenAPI 3.1、请求与响应样例、四语错误键。认证与删除任务接口已有配套本地隔离 Worker 实现；M3 已接入隔离目录、专辑、歌词、资格与授权媒体；个人同步等接口仍为拟定契约，不能按接口数量视为全部实现。
- M3 的实际 AVPlayer + ResourceLoader 用独立 Bearer 读取小块音频，支持播放/暂停/拖动/切歌与歌词，续期更换 URL 和硬截止。只在独立测试配置中可用，默认仍关闭；详见 [M3 交付记录](docs/M3-report.md)。
- 单一 AVPlayer 所有者、连续时钟到期边界、取消与账号作用域、Keychain 单条记录更新、刷新和删除恢复 journal。
- 本机测试、CI 定义与来源清单。最新的 A11–A13 实际进程终止证据见 [M2 恢复验收补充](docs/M2-recovery-acceptance.md)；此前结果见 [M2 本地交付记录](docs/M2-report.md)；[M1 验收记录](docs/M1-report.md)保留原阶段结果。

## 本地打开

打开 `StationCatMusic.xcodeproj`，选择 `StationCatMusic` scheme 和 iPhone 模拟器运行。默认配置为 Mock，不需要 Apple 开发者团队，也不需要网站凭据。此开发 Bundle ID 是 `org.stationcat.music.dev`，没有注册正式 App ID。

稳定 CI 固定 Xcode **26.4.1**；本机仅安装 Xcode **27 beta 6**，本轮使用该版本验证。M1/M2 已合并版本已有稳定 CI 通过记录；M3 新增媒体步骤尚未运行远端 CI，beta 模拟器结果不能视为真机/上架验收。

```sh
python3 -m venv .venv
.venv/bin/pip install -r contracts/requirements.lock
.venv/bin/python scripts/validate_contract.py
python3 scripts/check_source.py
export M1_SIMULATOR_ID='你的 iPhone 模拟器 UUID'
bash scripts/verify_configurations.sh
bash scripts/test_ios.sh
bash scripts/verify_keychain_relaunch.sh
bash scripts/verify_auth_crash_recovery.sh
```

只在本机使用其他已安装 Xcode 时，显式设置 `DEVELOPER_DIR` 和 `M1_ALLOW_LOCAL_TOOLCHAIN=1`；CI 不接受此覆盖。不会修改全局 `xcode-select`，不会申请签名权限或上传 TestFlight。

新增 Swift 文件后运行 `python3 scripts/generate_project.py`。契约源为 `scripts/generate_contract.py`；`scripts/seed_resources.py` 维护示例与界面文案，并合入四语错误文案。三份生成器均可重复生成相同文件。

## 开发边界

`Core` 提供可测试的接口和状态基础；`StationCatMusic` 是原生界面；`Tests` 与 `UITests` 验证失败边界及本机交互。所有个人收藏当前仅保留在本次进程内，退出 App 后不会宣称已云同步。

M2 已实现本地隔离原生会话、PKCE 和账号删除任务恢复；真实 HTTPS / AASA 与真机验证尚未完成，跨产品物理删除仍待保留策略确认。M3 第一批已有隔离授权媒体与原生播放联调；真实 HTTPS、M4 锁屏/后台/真机播放和完整队列仍待后续验收；M5 做个人数据同步。StoreKit 音乐包月属于后续阶段，当前没有售价、购买按钮或交易代码。

网站当前生产来源与 Git 主线存在差异，见 [来源清单](docs/baseline-inventory.json)。本项目没有覆盖网站工作区、数据库或生产配置；不要用主线直接重建并覆盖现有生产包。
