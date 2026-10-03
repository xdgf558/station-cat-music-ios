# Production profile：本地跨仓真实实现验收

此检查使用正式 `station-native-production-v1` 配置合同，在模拟器的 Mock 测试宿主中实例化真实 `NativeAuthenticationService`、`NativeMusicAPI`、`NativeLibraryAPI`，连接固定网站源码版本的真实 `src/worker.js`。它只证明本地跨仓实现兼容，不是生产启用、真实生产数据验收、正式 HTTPS 或系统 Universal Link 验收。

仓库默认配置仍全关闭，origin 与 activation profile 留空。本检查不会生成 `Production.local.*`、读取正式 Keychain、访问真实账号、部署 Worker、安装手机或修改版本号。正式 API、web、callback 的原始 URL 始终为 `https://wwwstationcat.org`；测试不会把正式身份改成 staging host。以前的 recovery/media/library 三份 backend pin 继续保留，不被新套件替代。

## 本地边界和实际链路

网站 helper 使用完整网站、mobile、music migrations 与候选 marker，在临时 Miniflare 数据库和桶内建立合成普通/VIP 账号、密码、曲库和 MP3。仅监听随机 `127.0.0.1` 端口；临时目录为 0700，ready 文件为 0600，随机 proof 只存在于临时文件和测试进程。Worker 所有出站网络均由 fixture 拒绝。

`TestsSupport/ProductionLocalFixture.swift` 只属于测试 target。它拒绝非正式原始 origin，然后把原始请求通过带 proof 的 JSON envelope 交给 loopback `/request`；Worker 仍按正式 HTTPS URL 执行。URLSession 禁止重定向，不能回退为公网请求。Bootstrap 返回的合成密码不会写入日志，临时 xctestrun 为 0600，结束后删除。只对原生单测 target 注入连接信息。

浏览器 test double 请求真实授权表单，处理真实 flow/cookie 并提交合成账号密码；PKCE、state、token 兑换和 refresh 均由真实原生认证服务与 Worker 处理。覆盖普通账号两会话/VIP 隔离、guest 免费完整音频、普通账号 VIP 完整播放被拒但可 preview、VIP 完整播放、真实 MP3 HEAD/Range、收藏与合成收听事件同步、refresh、logout 会话和 grant 撤销。这里的合成收听事件只验证同步协议，不证明音频播放了五秒，也不重跑长时间 AVPlayer 探针。

生产销户 capability 必须为 false：原生 prepare/confirm/reauth 在传输前被拒；直接通过测试桥接请求真实 Worker 的 prepare/confirm 仍须得到 503 `SERVICE_UNAVAILABLE`。测试本身不能扩张产品 capability。

## 共享链接矩阵

`contracts/fixtures/canonical-link-cases.json` 是网站 `tests/fixtures/mobile-links/canonical-link-cases.json` 的逐字节副本，随独立 backend pin 校验。正式 host 仅接受十条已确认音乐路径，R2 仍接受两条根音乐路径；编码路径不会被解码后误接受。矩阵 74 例包含 24 个合法曲目/歌单地址，以及 callback、重复/未知/混合 query、错误 host、路径与编码别名等 50 个客户端拒绝地址。

三个原生测试分别检查 parser 和 AppModel 初始化前、初始化后的接收过程。冷/暖各跑全部 74 例，检查页面选择且保持零授权/音频请求；不调用 OS 打开链接。这些测试与网站 AASA JSON 路径合同一致，但不能证明 Apple CDN、站点 HTTPS、签名 entitlement 或设备系统投递成功。

## 运行与固定输入

```sh
PRODUCTION_BACKEND_PATH=/absolute/path/to/reviewed/website-checkout \
M1_SIMULATOR_ID=<available-iPhone-simulator-UUID> \
python3 scripts/verify_native_production.py
```

driver 只接受已安装的 iPhone simulator UUID，并使用 `platform=iOS Simulator`。`contracts/backend-production-fixture.json` 固定独立 backend commit、依赖目录的完整 Git 文件集合和每文件 SHA256；缺失、修改、新增依赖或跨仓矩阵不一致均在启动前失败。没有“忽略 pin”或联网回退参数。CI 的独立 `production-local.yml` 固定 Xcode 26.4.1、Node 24。非匹配本地 Xcode 必须显式 `M1_ALLOW_LOCAL_TOOLCHAIN=1`，结果只记为本地工具链证据。

构建和测试日志位于忽略的 `evidence/production-local-*.log`，聚合报告为 `evidence/production-local-summary.json`；不上传临时 ready/xctestrun 或 bootstrap。每次入口先失效上轮报告与固定日志，pin/构建/测试失败均不得留下旧成功报告；同一轮日志与汇总使用唯一 runId，汇总记录 UTC 起止时间。driver 要求原生 E2E 和冷暖矩阵三个成功标志，普通测试中跳过 E2E 不会被当作验收通过；同时校验真实 Worker 的会话、刷新、收藏、历史记录聚合证据和零出站请求。

## 本轮验证范围

2026-10-03 严格 driver 固定网站 commit `42e29f34d225f0ca1ef23ce27a58694f01f9a2f0` 与 472 个依赖文件 SHA256 后通过。该轮 runId 为 `7e1b8221-907a-46ac-b028-539f0c4e44d2`，UTC 起止时间为 `2026-10-03T13:09:16.627Z` 至 `2026-10-03T13:09:45.023Z`。33 项 XCTest 全部通过，包括 18 项链接初始化、10 项 production profile、3 项共享矩阵与 2 项本地跨仓测试；冷暖初始化各验证全部 74 个地址且音频请求为零。

真实本地 Worker 聚合证据为 71 次请求、3 个会话且全部撤销、1 次刷新、1 条收藏与 1 条最近收听，出站请求为零。13 项 Python driver 回归通过，包含 pin/输入失败关闭及上次成功后本次失败不得保留旧报告。源码 guard、关闭 profile 的离线校验及 Mock/Development/Staging/Production 四种模拟器配置构建通过，内嵌开关仍全部为 NO，origin/profile 为空，版本保持 `0.1.0 (4)`。

本地实际工具链为 Xcode 27.0 beta 6（`27A5252f`）、Node `24.15.0`、Python `3.9.6`，目标仅为 iPhone 17 Pro / iOS 26.5 模拟器（`6E0EA9FF-E886-45F4-B752-79C6F60B0235`）。本轮显式使用 `M1_ALLOW_LOCAL_TOOLCHAIN=1`，因此不计作固定 Xcode 26.4.1 的稳定 CI 验收。最终聚合 JSON 与三份日志保留在本地忽略的 `evidence/production-local-*`；提交中只保留以上脱敏结果与可重复运行的脚本。

网站本批另有 `docs/mobile-ios-production/resource-ownership-20261003.md`，记录平台账号可见资源与已部署版本绑定的只读比对；它与此处的合成 marker 检查分别提供证据，不能互相替代。

稳定 Xcode CI、正式 HTTPS/AASA 的响应与系统关联缓存、真实设备冷暖 Universal Link 投递、真实账号/曲库与生产 schema，以及未来发布候选绑定的再次核对仍须分别完成；此 PR 不把这些项目标为已验收，也不授权生产启用。
