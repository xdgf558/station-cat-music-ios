# M2 恢复验收补充

2026-09-16。本轮基于 iOS #2 合并 `3a6bd1d94e6ae4fb9aff3c522c412542a4ffa4f5`、网站 #172 合并 `0b8c2d4ada7945c1b01c3e706fd8a075d14b6501`。补足 A11–A13 的本机真实进程终止证据；未启用远端认证、媒体、同步或购买。

## 实际验证

测试运行真实 `NativeAuthenticationService`、刷新 journal 和模拟器 Keychain。HTTP 传输替换只存在于测试目标，将虚构 HTTPS origin 的 refresh 请求转到 loopback 桥接器；桥接器运行真实隔离 Worker、临时 D1，合成账号走实际授权码兑换。没有产品故障钩子、ATS 例外、假时钟或延长服务器 120 秒重放期限。

| 用例 | 真实退出位置 | 下一进程验证 |
| --- | --- | --- |
| A11 | 服务端已提交第 1 代，HTTP 响应被桥接器扣留；原生仍保存第 0 代 pending | 使用原 request ID 重放同一结果；仅一次服务端操作；Keychain 原子安装第 1 代 |
| A12 | 客户端已收到第 1 代，在 SecureStore 实际写入前退出 | 原 request ID 与第 0 代保留；重新取得相同结果指纹；仅一次服务端操作 |
| A13 | 第 1 代已写入真实 Keychain，在内存成功状态发布前退出 | 重启读到第 1 代且无旧 pending；正常新 ID 刷到第 2 代，没有重放第 0 代 |

每组先以 `_exit(73)` 终止测试宿主，再用新的 xcodebuild 测试宿主恢复。修订后的驱动监控带 PID 的崩溃标记，确认该宿主已退出或成为 zombie 后停止独立进程组中的 xcodebuild，避免等待 XCTest 自动重启收尾；恢复阶段仍要求恢复标记及成功测试退出；普通测试跳过这些专用方法。A11/A12 断言两次服务端请求落在原 120 秒窗口内。三组均验证同账号/家族、绝对到期点不变、未误撤销家族，独立删除 receipt 保留且恢复动作仅为查询。

本机三组全部通过，耗时分别 51.40 / 52.06 / 58.21 秒（包含退出及新宿主恢复）。另有 47 项 Swift 测试、2 项 UI 测试通过；4 个破坏性专用探针在常规套件中有意跳过。本轮新驱动执行其中新增的 A11–A13 两阶段方法，旧 Keychain/relaunch 探针继续由既有独立脚本与 CI 执行。本轮网站 29 项隔离认证和 10 项销户审计测试通过；153 页空小说编译验证通过，不是部署包。

脱敏结果见 [M2-recovery-test-summary.json](M2-recovery-test-summary.json)。原始日志与 xcresult 在本机忽略目录 `evidence/`、`.build/`；摘要不含 token、邮箱或测试桥接密钥。源码指纹见 [M2-recovery-source-sha256.json](M2-recovery-source-sha256.json)。

## 可重复执行

后端测试来源锁定于 [backend-recovery-fixture.json](../contracts/backend-recovery-fixture.json)：提交 `0d7f6281c0d1d187298b6b6852ace18f3b3ce0f5`。驱动在启动前核验提交、关键源码指纹及工作树；更新来源必须重新审查。后端依赖从该提交的 lockfile 安装。

```sh
# 在配套网站 checkout 中运行 npm ci；回到此原生仓库后：
export M1_SIMULATOR_ID='专用 iPhone 模拟器 UUID'
export M2_BACKEND_PATH='/配套网站 checkout 的绝对路径'
python3 scripts/verify_native_crash_boundaries.py
```

Node 24；稳定 CI 固定 Xcode 26.4.1。本机仅有 Xcode 27 beta 6，使用显式 `DEVELOPER_DIR`、`M1_ALLOW_LOCAL_TOOLCHAIN=1`；本机结果不能替代稳定 CI。新增 CI 步骤 checkout 固定后端提交后运行驱动。固定的后端测试提交已推送；原生恢复验收和网站销户盘点分别审查，不要求一起合并。 本轮仅本地验证，尚未运行新增远端 CI。

临时 bridge 只监听 127.0.0.1，随机密钥限制路由，拒绝跳转，屏蔽外部网络；退出后销毁临时 D1。测试不用正常 App 的 Keychain namespace，成功后清除专用凭据。桥接器与 fixture 路由绝不能作为生产入口部署。

## 尚未完成

真实 HTTPS、AASA、ASWebAuthenticationSession 全链路、实体 iPhone 锁屏/首次解锁前 Keychain、后台音频均未验收。生产配置及四个原生认证开关保持关闭；原生源代码本轮没有改动。

配套网站 `docs/mobile-ios-m2/deletion-plan/README.md` 提供 86 张表的销户方案草案，明确财务级联、RESTRICT、软关联、支付回调防复活、备份和回执最小化。评论处置及有余额/争议时的流程仍待业务确认，财务字段和保留期限尚待确定；approved/executionEnabled 为 false，现有消费者继续 attention_required。本轮没有完整销户清理器、真实账号操作或数据库迁移执行。


## 复审修复（2026-09-17）

稳定 CI 35158222776 暴露旧驱动等待 XCTest 崩溃收尾与二次启动合计耗时过长，A11 请求间隔约 136 秒，超过真实 120 秒期限。此前本机摘要仅代表本机运行，不能证明稳定 CI 已通过。产品认证实现未修改。

修复以宿主真实退出作为启动恢复阶段的依据，停止 xcodebuild 专用进程组并在 2 秒后必要时强制终止；不改服务端期限或时钟，不把驱动自己终止进程当作宿主崩溃。新增 4 项驱动回归覆盖长收尾、宿主仍存活、无标记失败与错误阶段标记。CI 继续执行三组真实模拟器测试，并记录宿主退出确认、收尾停止延迟及两次服务端请求间隔。原生 CI 的最终结果需独立确认，网站 PR #173 可单独处理。
