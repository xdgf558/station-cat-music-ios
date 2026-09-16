# M2 本地隔离认证交付记录

日期：2026-09-16。状态：本地实现与测试完成，**M2 整体验收未完成，不可部署或上架**。

用户确认暂时没有隔离 HTTPS 域名与 Apple Developer Team ID，先完成本地隔离实现。此次没有申请签名、关联域名、远端数据库、真实账号或支付操作，也没有部署。默认 scheme 仍为 Mock；四配置均 `STATION_NATIVE_AUTH_ENABLED = NO`，认证 origin 为空。

## 代码边界

客户端基于 `4cbdec03f34659411640a660f39034a123e1fe7c`，分支 `codex/m2-auth`。配套网站基于 `df20f70dddf53f091aa8b68abebdab72dc9f3ecf`，分支 `codex/music-ios-m2`；路径为相邻的 `landing-site-music-ios-m2` 工作树。网站生产冻结来源及其他工作树的未提交修改均未覆盖。

- `Core/NativeAuthentication.swift`：系统浏览器协议、随机 PKCE S256/state、严格 HTTPS 回调、独立无 Cookie 认证 API、单次共享刷新、账号 epoch、连续时钟 token 到期。
- `SystemAuthenticationBrowser.swift`：ASWebAuthenticationSession HTTPS 回调与取消。尚未通过实际 AASA / Apple Team 签名验证。
- `Core/Credentials.swift`：刷新前写 pending，固定 requestId；新代落盘成功后才发布内存成功；退出先失效旧工作，再删除认证记录。
- `Core/NativeDeletion.swift`：近期认证、准备、用户显式确认、独立只读 receipt；重启只查原任务，不自动确认，不借新账号的登录态操作旧任务。
- `NativeAccountModel` 与“我的”：四语认证、退出、全站账号删除影响说明和进度查询。生产配置无法启用；默认 Mock 的浏览/搜索/播放器占位仍保持原逻辑。

OpenAPI 现有 25 个操作、62 个 schema。仅原生认证、用户基本资料与删除任务子集有此次隔离服务实现；媒体 grant、曲库、收藏/历史同步及购买仍未连接。没有新增远程音源，M3 播放资格不是本轮成果。

## 本地验证

| 验证 | 实际结果与范围 |
| --- | --- |
| Swift / XCUITest | 30 个 Core + 2 个原 Keychain + 15 个原生认证测试通过；2 个 UI 测试通过。普通套件另外列出的 2 个强制退出探针有意跳过，在专用脚本运行。 |
| 强制结束进程 | `verify_auth_crash_recovery.sh` 先写真实模拟器 Keychain pending 与删除 receipt，再 `_exit(73)`；新测试宿主进程恢复完全相同的 requestId、旧代和 receipt，且返回仅查询操作。脚本通过。首次环境变量注入尝试被跳过且被脚本判失败，已改为 xctestrun 显式注入后重跑通过。 |
| 四配置构建 | Mock / Development / Staging / Production 构建通过，包内认证开关均 NO、origin 为空，最低 iOS 18，没有 ATS 放宽。 |
| 契约 | OpenAPI 校验、63 个有效 fixture、10 个拒绝用例、四语 key 对齐通过。 |
| 生成器 | 工程、契约、资源再生成的 SHA-256 与生成前一致。源码检查通过。 |
| 配套 Worker | Miniflare / workerd / D1 的 29 个测试通过；执行真实网站 fetch 入口，所有外部请求均被测试配置拒绝。 |
| 网站回归 | `npm test` 通过（包含旧认证 / TOTP / 支付 / 音乐等既有测试）；最初在沙箱内监听端口遭 EPERM，允许本机监听后重跑通过。 |
| 网站构建 | `ALLOW_EMPTY_SERIAL_CONTENT=1 npm run build` 与构建断言通过：153 页面、111 公开 sitemap 路由。此空小说内容构建仅验证，不是生产包。 |

本机工具链是 Xcode 27 beta 6 / iOS 27 模拟器。CI 仍固定 Xcode 26.4.1，M2 尚未远端运行。模拟器 Keychain 成功不替代实体机首次解锁前、锁屏或签名验证。UI 测试覆盖默认 Mock 导航与字体；新系统网页登录没有冒充真实浏览器端到端验收。

## 安全与恢复决策

服务端仍使用现有 reader 账号、密码派生和 TOTP 核验，不复制身份库。Native 路径要求已绑定 TOTP；注册和 TOTP 找回成功后不创建网站 Cookie，需回到登录。Bearer 无效不会降级 Cookie。邮件找回没有擅自开启；未绑定 TOTP 的恢复仍受旧系统规则约束。

刷新凭据是随机 opaque token，D1 保存哈希。会话家族稳定；access 5 分钟，refresh 滚动 30 天，家族绝对 90 天。120 秒结果用版本化 AES-GCM 加密，并绑定家族、请求 ID 与服务端摘要；清理后仍保留操作墓碑与旧 token 哈希到家族绝对期限。D1 CAS 零行用 CHECK 断言让整个 batch 回滚。重启和保留旧解密 key 的轮换已验证；密钥提供与轮换运行手册仍是远端启用前事项。

退出登录用仅撤销能力的 refresh-token proof 处理“刷新已提交、旧 access 已失效”的竞态；未知凭据返回相同确认，不产生登录身份。客户端先清本机凭据，网络失败明确报告服务器撤销未确认，不能当远端退出成功。旧 A 账号的迟到结果不能清除 B 账号。

删除范围是整个 Station Cat 账号。prepare 前保存随机 receipt；确认前再持久化确认 ID。确认受理在同一 D1 batch 中冻结账号、撤销网站与原生会话并写 outbox。receipt 只能查询最小任务状态，不能登录或确认。查询失败不推断删除完成。

**物理清理未实施**：outbox 消费后标记 `attention_required / retention_policy_review`，保留被冻结账号。支付、积分、小说、游戏存档等数据保留/匿名化规则尚未批准，不能假报 completed。此实现不能作为已符合完整账号删除要求的产品上线。

## 主规格验收对应与尚缺证据

| 编号 | 此次证据 / 后续缺口 |
| --- | --- |
| A01–A04 | 合成的既有 reader 账号 ID、S256、单次授权码、state / 回调路径校验已测；实体系统窗口取消与真实域名回调待测。 |
| A05–A07 | 单次共享刷新、固定 ID 重试、旧 token 新 ID 仅撤销所属家族、未知 token 不撤销均通过；尚无实际媒体请求重试链路。 |
| A08–A09 | 本地退出竞态、密码/TOTP 配置变更、blocked 账号、A/B 作用域已测；真实播放和跨设备个人同步属于后续阶段。 |
| A10–A13 | pending 写入后真实结束测试宿主并恢复通过；响应丢失/结果写失败/新代恢复有单元与服务端故障证据。A11–A13 各时间点与真实服务相连的进程终止尚未逐项执行。 |
| A14–A15 | 结果过期保留墓碑、pending 写失败零请求、结果写失败保留旧状态已测。 |
| A16 | 不可读存储注入与记录保留通过；实体 iPhone 首次解锁前 Keychain 待测。 |
| A17–A21 | 迟到结果、CAS / batch 回滚、superseded、摘要冲突、撤销/清理后的旧请求通过；真实多设备压力仍待联调。 |
| S02–S03 | 全站影响说明、确认/只读进度与 attention_required 已实现；订阅集成及物理删除完成不在此次证据内。 |
| S04–S07 | prepare / confirm 响应丢失、重启仅查询、账号隔离、存储失败禁止确认已测。 |
| S08–S10 | receipt 越权、准备过期、确认与 outbox 事务回滚、503 不假报完成通过。 |
| S11–S14 | receipt 过期拒绝、账号行删除后仍可查、其他设备任务冲突、退出保留 receipt 已测；人工支持核验、真正双设备竞争和用户清理回执流程仍待验收。 |

下一步是补齐上述缺口，完成独立审查，再用隔离域名、受信任 HTTPS、明确 Team/App ID 与 AASA 做端到端和实体机验证；同时确认删除保留策略。当前不切换到 M3 远程音频或 StoreKit。

## 复现与记录

按 README 的本机命令执行；强制退出探针必须通过专用脚本，不能把其第一次非零退出单独看成回归失败，也不能只看到套件 skip 就宣称通过。日志在忽略跟踪的 `evidence/M2-acceptance.log`、`M2-four-configurations.log`、`M2-crash-exit.log`、`M2-crash-recovery.log`。配套服务日志位于本机 `/private/tmp/m2-backend-final.log`、`m2-website-regression-r2.log`、`m2-website-final-build.log`。仓库收录无凭据的摘要与源码哈希，不提交原始凭据、真实用户或 simulator 数据。

## 审查后 CI 可移植性修复

首次稳定工具链 PR CI（35101280637）已通过四配置、普通测试与 Keychain relaunch，在强制退出脚本的日志检查处因 runner 缺少 rg 失败。仅把两处匹配改为系统自带 grep，保留非零退出与恢复成功两项判定；产品代码未改。新提交须重新通过 CI 后合并。
