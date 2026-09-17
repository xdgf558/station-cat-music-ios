# M1 契约与实现边界

输入：主规格 v1.0.1 与 PR #170 的 ADR-001/ADR-002。`contracts/openapi.json` 是待 M2/M3 实现的版本化契约，服务器地址为保留域 `mock.invalid`，不是现网接口目录。旧的 `/api/music/*` 和网站 Cookie 行为不变。

所有成功 JSON 带 `data/requestId/serverNow`；时间采用 UTC ISO8601，音频时间采用秒；分页默认 50、上限 100。TrackDetail 额外提供歌词类型、版本、秒时间轴和预览原曲起点；实际媒体不能由元数据授权。

`PlaybackGrant` 在规格示例字段基础上明确增加 `accountId` 与 `trackId`，便于客户端核对账号、会话、曲目、音频版本与变体。`serverNow` 位于外层 envelope，Swift 验证必须显式传入。媒体 URL 仅 HTTPS 和批准的主机/路径，不能携带 token 查询参数、用户信息或片段。未知 authMode 解码失败，未知访问策略为 unavailable；未知能力不能默认为 true。

`public` 仅用于有效免费歌曲或允许的试听；`session_bearer` 的每个真实 GET/HEAD/Range 仍需服务端校验当前 session 和账号。M1 没有实现 loader、播放 grant 发放或音频源安装，不得把客户端状态机当作服务端权限边界。

刷新 journal 保留旧 token、generation、固定请求 ID 和本机请求摘要；写入失败不能开始下一步。完成后只更新同一 Keychain item，并在发布成功前检查操作 epoch。退出登录先失效 epoch，再等待在途持久化并删除登录记录，避免迟到成功复活。服务端仍须自行计算规范请求摘要、120 秒结果保留和更长 tombstone；M1 不实现这些服务器行为。

删除 journal 与登录记录分开存储；receipt 为 32 随机字节，传输为无填充 base64url，SHA-256 对解码字节计算。prepare 前持久化；确认前读取凭据、范围和已知期限，再持久化 confirmRequestId/confirmAttempted。重启仅返回 queryStatus 指令，不自动确认。时间判断仍须由 M2 的服务端时间投影约束；本机 journal 的 `now` 参数不是服务器授权。

删除 status 输出是封闭的最小 schema，不含账号、交易或会员资料。receipt 只读，不能换取登录或执行确认。真实 recent-auth、TOTP、outbox、数据保留/匿名化都在 M2，M1 没有破坏性入口。

SwiftUI 不持有第二个 AVPlayer；页面开合/切换仅改变视图。连续时钟边界扣除完整 RTT 和 2 秒余量；到期暂停、清除 item、取消 loader 与自动续播，旧 sequence 不可安装新边界。M1 无真实音频缓存，因此这里通过的是状态与停止调用测试，并非实体机后台音频验收。

全局、游客和账号作用域隔离；取消目录任务和操作序号共同阻止旧结果覆盖新状态。身份与个人数据接口没有接入。示例收藏仅内存保存，不隐式合并游客到账号，不冒充 M5 同步。

## CI 与工具链

CI 固定 Xcode 26.4.1 并显式检查路径，缺失时失败，不自动换版本。参考：[GitHub runner toolset](https://github.com/actions/runner-images/blob/main/images/macos/toolsets/toolset-26.json)、[Apple release notes](https://developer.apple.com/documentation/xcode-release-notes)。本机 Xcode 27 beta 6 通过显式覆盖执行，单独记入验收记录。

CI 只做 schema/fixtures、四配置构建、Swift/XCUITest 和合成 Keychain 跨进程记录验证；没有 deploy、archive、TestFlight 或签名账号修改步骤。稳定工具链 CI 与实体 iPhone 仍是后续验收项。

## M3 第一批增量（2026-09-17）

M1 边界描述保留为历史。本批目录、推荐、专辑、资料、歌词与 grant/media 已在隔离后端实现。Track 新增可选 coverUrl；音乐 JSON GET 支持 locale；集合使用 limit/cursor 分页。grant path 固定 43 字节字符的 base64url 不透明随机值。歌词 text 上限与既有 128 KiB 资产限制对齐，时间轴响应不重复传全文。资格与媒体失败均不能变成新播放许可。

NativeAuthContext 新增只读 sessionID；播放授权可要求至少 65 秒 token 余量，仍复用既有刷新 journal。Range 的 401 最多刷新一次，其余错误直接停止；整个媒体请求最多等待五秒，迟到刷新结果不能交付音频。前台定期续期会重新安装 URL 和连续时钟截止，旧截止在等待续期时仍然有效。正常暂停也移除音源，恢复时新授权并回到相同变体的位置。

以上仅在隔离配置中可用，默认 Mock/Development/Staging/Production 全部 STATION_NATIVE_MUSIC_ENABLED=NO，无正式 origin、无 ATS 例外。真实域名、AASA、实体机和 StoreKit 未验收。完整记录见 M3-report.md。
