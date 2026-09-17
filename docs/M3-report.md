# M3 第一批：原生曲库与隔离授权播放

2026-09-17。本批交付本地隔离实现，不代表整个 M3/M4 完成、正式服务启用或可上架。四种配置的认证和音乐开关均保持关闭，origin 为空；默认方案继续使用 Mock。本次未部署、未连接生产账号或远端 D1/R2，未修改支付、StoreKit、Apple 签名或 ATS 配置。

## 已实现

原生客户端接入四语曲库、搜索、推荐、专辑分页、歌曲资料、展示版封面和普通/LRC 歌词。目录与详情结果受账号作用域和请求序号约束，过期结果不会覆盖新账号。歌词绑定音频版本，试听以原曲偏移计算当前句；时间轴高亮并跟随播放，普通文本直接显示。

播放器继续只有一个 AVPlayer。播放、暂停后恢复和切歌均取得新授权；暂停、退出、切换账号或授权失效会清除音源、取消加载，不保留可继续播放的旧 item。ResourceLoader 使用每个 asset 独立的内部 URL，将真实网络读取限定为受验证 grant URL 的 HEAD 和不超过 64 KiB 的 Range；音频不落盘。VIP 每次请求独立带原生 Bearer，public 不附加身份。Cookie 不参与原生资格。

服务端选择免费完整曲、有效限时免费、VIP 完整曲或独立试听变体。客户端验证歌曲、版本、账号/session、主机、路径、变体、时长和期限。当前音乐 VIP 尚无独立销售或账本；既有全站 VIP 只读映射为音乐播放权益，不反向授予小说权限。

每次媒体操作包含最多一次 401 刷新，共用五秒等待预算；403、版本变化、错误 Range/ETag、重定向等直接停止。迟到刷新不能交付音频。连续时钟按服务端有效期扣除请求往返与两秒余量，截止后清空音源。前台续期更换 URL，等待期间保留旧截止；授权 token 预留 65 秒余量，仍复用 M2 刷新 journal。到期失败后刷新目录，避免保留旧免费展示。

后端实现和隔离迁移说明见配套网站仓库 `docs/mobile-ios-m3/README.md`。本批客户端联调固定后端提交 `08fad16ccecff34b6254c0c979825862ca7b0725`，并核验源码 SHA-256。新增 grant 表仅位于 `migrations-mobile`；销户盘点增加到 87 表，保留策略仍未批准、执行仍关闭。无生产迁移或配置变更。

## 实际验证

| 检查 | 本机结果 |
| --- | --- |
| Swift 单元套件 | 62 项，6 项专用探针按设计跳过，其余通过；包括媒体五秒预算、Range/ETag、401 单次刷新、public 无凭据、过期/撤销拒绝、迟到授权及歌词偏移。 |
| UI | 2/2 通过，覆盖默认 Mock 导航、语言和大字号；不冒充真实登录界面验收。 |
| 实际音频联调 | 专用测试 2/2 通过。真实模拟器 AVPlayer + URLSession 连接本机 workerd 与临时 D1/R2，验证进度、seek、HEAD/Range Bearer、暂停/硬截止清除音源、撤销后拒绝且无 R2 读取。 |
| 四种配置 | Mock、Development、Staging、Production 构建通过；认证和音乐均 NO，正式 origin 空，无 ATS 例外。 |
| M2 崩溃恢复 | A11、A12、A13 再次通过真实独立进程和模拟器 Keychain。服务请求间隔分别为 3.732、1.176、1.140 秒，仍使用原固定 120 秒窗口及旧后端基线。 |
| 驱动回归 | 9/9 通过。 |
| 契约与源码 | OpenAPI 25 操作、62 schema；63 个有效 fixture 和 10 个拒绝用例通过；四语、单播放器、Mock/Keychain 检查通过。三个生成器再生成一致，workflow YAML 与 diff 检查通过。 |
| 配套后端 | 76/76 原生音乐、认证和原网页媒体/会员测试通过；销户审计 11/11。 |
| 网站构建 | 空小说内容的本机验证构建通过 153 页及 postbuild；不得作为生产包部署。 |

本机工具链为 Xcode 27 beta 6 / iOS 模拟器。原审查提交已通过稳定 Xcode 26.4.1 CI；本次审查修复需按新 head 重跑，不能用原提交结果代替。六项默认跳过的专用探针不能计为常规套件通过；媒体及 A11–A13 的结论来自单独驱动。

音频为仓库生成的正弦波，账号和会员为临时合成数据。HTTP loopback 桥只属于测试 target，以随机端口和临时 proof 保护；产品 URL 校验仍要求 HTTPS。日志放在不跟踪的 `evidence/`，临时带 proof 的 xctestrun 在退出时删除，不提交凭据或用户数据。

## 复现

本机普通检查：

```sh
python3 scripts/generate_contract.py
python3 scripts/seed_resources.py
python3 scripts/generate_project.py
.venv/bin/python scripts/validate_contract.py
python3 scripts/check_source.py
python3 scripts/test_crash_probe_runner.py
bash scripts/test_ios.sh
bash scripts/verify_configurations.sh
```

媒体联调需先将网站仓库检出到 `contracts/backend-media-fixture.json` 中的固定提交并安装依赖，再设置 `M3_BACKEND_PATH` 和 `M1_SIMULATOR_ID` 执行 `python3 scripts/verify_native_media.py`。驱动会核对提交、源码哈希和工作树，再构建测试宿主、启动临时服务和实际 AVPlayer 测试。M2 A11–A13 继续使用 `backend-recovery-fixture.json` 的旧提交与 `verify_native_crash_boundaries.py`，不要用 M3 后端覆盖其基线。

本机需显式设置 `DEVELOPER_DIR=/Applications/Xcode-27-beta-6.app/Contents/Developer` 与 `M1_ALLOW_LOCAL_TOOLCHAIN=1`；CI 不使用这一覆盖。原始结果见 `evidence/M3-media-integration.log`、`evidence/M2-boundaries-summary.json`，普通测试和四配置日志分别在 `/private/tmp/station-m3-ios-tests.log`、`/private/tmp/station-m3-config.log`。

## 后续验收范围

真实 HTTPS 登录/回调、AASA、Apple Team/App ID、实体 iPhone 锁屏 Keychain、后台音频/系统控制/来电中断、长曲弱网续期、完整队列、跨设备收藏同步、完整销户执行和 StoreKit 均未完成本批验收。下一批应先完成两个仓库代码审查和稳定 CI，再继续长曲及授权续期故障验证；域名和签名条件齐备后才进行真实 HTTPS 与实体机验证。生产开关不能因本机联调通过而开启。

PR 推送顺序：先推送配套网站固定提交，再推送 iOS 分支，保证 CI 能获取媒体测试基线；这不代表合并或部署授权。

## PR #4 审查修复（2026-09-17）

发现页改为单独保存和展示 `featuredTracks`，不再复用普通曲库、搜索结果或当前专辑；推荐清空和加载失败分别显示空状态与不可用状态，重新加载与切换账号清除旧推荐。后端按已配置主推荐、次推荐和集合顺序投影，不额外添加“最新六首”。真实 Worker → NativeMusicAPI → AppModel 探针用七首歌曲验证最早发布的主推荐仍出现在发现页，且搜索/选择专辑不覆盖推荐、清空后不保留旧内容。

自然结束监听当前 AVPlayerItem 的结束通知，并核对 item 和播放序号；完成时清除音源、重置位置为零，进入独立 completed 状态。手动暂停仍保留恢复位置。切歌、续期和停止会移除旧结束观察者。真实短音频测试完整播放到自然结束，再点击播放，验证进度从开头重新增长；同时保留手动暂停恢复、seek、硬截止和撤销回归。

本次本机结果：Swift 62 项（6 项专用探针在默认套件跳过），其余通过；UI 2/2；专用跨仓库/音频测试 2/2；后端 76/76、网站 153 页构建通过。未修改认证、资格计算、开关或生产配置；后端固定版本已同步至修复提交。
