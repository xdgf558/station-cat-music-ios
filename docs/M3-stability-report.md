# M3 第二批：长曲与授权续期稳定性

2026-09-18。基于已合并的 iOS PR #4（93ced205）与网站 PR #174（d71327a）。本批仅本地实现与隔离验证，尚未推送或运行本批稳定 CI，不表示生产启用或整个 M3/M4 完成。

## 实现与修复

续期更换 AVPlayerItem、暂停恢复及拖动时先完成精确 seek，再播放。记录当前 item、播放序号和 seek 序号，旧 seek 回调不能恢复已暂停、切换或失效的播放；seek 未完成时不会将临时零进度写回界面。暂停和续期前从旧 item 捕获实际位置。试听暂停后默认恢复试听，不会隐式请求完整版。

媒体读取在等待凭据刷新后重新检查任务取消、账号作用域和连续时钟截止，再开始 HEAD/Range；响应返回后同样核对。过期、退出或取消后的迟到凭据不能启动新的音频请求。产品媒体操作仍共用原五秒预算，不扩大服务端 grant、120 秒认证恢复窗口或权限。

网站侧仅新增测试服务、fixture 与生成器，未更改 Worker 产品运行时。三分钟正弦波由 FFmpeg 7.1 本机生成，64 kbps 单声道，独立解码验证与清单记录时长 180.036 秒、大小 1,440,539 字节及 SHA-256。原短音频保留，继续验收自然结束后从头重播。

## 验证方法

真实模拟器 AVPlayer / URLSession → 随机 loopback 测试桥 → 本机 workerd、临时 D1/R2。测试桥要求临时 proof、禁用出站网络。每个场景创建新的合成账号；没有真实用户账号或歌曲。媒体 fixture 固定网站提交 `0ed8e6ae86adf7ac846a4df1588430563521910e`，驱动核对提交和文件 SHA-256。M2 A11–A13 继续固定原 backend-recovery-fixture，不混用本批后端。

长曲正向测试保留真实服务端 60 秒 revalidate 周期，连续两次续期，不改时钟。每个媒体请求额外等待 120 ms，记录新 grant 数、进度倒退及停顿采样；播放前还执行 seek 与暂停恢复。通过门槛为两次新授权、进度增长超过 115 秒、最大倒退小于 0.4 秒、单次停顿采样小于 5 秒。此测量不等于声学无缝播放保证。

失败场景覆盖续期 503、不响应取消的迟到授权、暂停/切歌/退出后迟到结果、快速连续 seek、试听恢复和离线 Range。部分故障测试仅收紧客户端期限至最多九秒并提前发起续期，以缩短测试时间；不延长或修改服务端授权。限时免费与 VIP 到期测试则在真实临时数据库中设置 12/10 秒期限，验证缓冲 item 被移除，真实期限过后重新请求完整版返回 403。

凭据延迟单元测试分别取消、过期和撤销作用域，断言延迟返回后媒体传输调用为零。测试服务在 ready 前准备推荐与长音频，fixture 控制请求使用独立 30 秒超时；这只适用于测试准备/证据接口，不改变产品五秒网络预算。

## 本机结果

- Swift 套件：68 项，11 项专用探针按设计跳过，其余 57 项通过；UI 2/2 通过。新增凭据迟到检查覆盖三种失效原因。
- 专用真实媒体探针：最终复测 7/7 通过（214.640 秒），包括五项稳定性测试及已有推荐与短曲重播两项。长曲累计使用四个不同 grant（初播、暂停恢复、两次续期），采样最大倒退约 0.0013 秒、最大停顿约 0.829 秒。真实到期后的完整版请求均返回 403。默认套件中的跳过不计为这些探针通过。
- 四种配置：Mock、Development、Staging、Production 构建通过；认证与音乐开关均为 NO，origin 为空，无 ATS 例外。
- 契约：25 个操作，63 个正向 fixture、10 个拒绝用例通过。源码边界检查通过。
- 网站原生音乐测试 16/16 通过；空小说内容构建通过 153 页及 postbuild。这是本机验证包，不得部署生产。

本机 Xcode 27 beta 6。真实媒体驱动已接入现有固定 Xcode 26.4.1 CI 步骤，要求全部七个成功标记；本批远端尚未执行，不能将本机结果称为稳定 CI 通过。三个生成器重新运行得到相同文件；git diff --check 通过。M2 A11–A13 本轮未在本地重复执行，其既有 CI 步骤保留。

## 复现与后续边界

先取得配套网站固定提交并安装依赖，然后在 iOS 仓库运行：

```sh
export M3_BACKEND_PATH=/absolute/path/to/website-checkout
export M1_SIMULATOR_ID=your-iphone-simulator-uuid
bash scripts/test_ios.sh
python3 scripts/verify_native_media.py
bash scripts/verify_configurations.sh
.venv/bin/python scripts/validate_contract.py
python3 scripts/check_source.py
```

仅本机非固定工具链需显式设置 DEVELOPER_DIR 与 M1_ALLOW_LOCAL_TOOLCHAIN=1；CI 不使用覆盖。原始日志为忽略跟踪的 evidence/M3-media-integration.log、evidence/M3-media-service.log；临时带 proof 的 xctestrun 退出时删除。不提交 token、真实媒体 URL 或用户数据。

先推送网站 fixture 提交，再推送 iOS 分支，远端 CI 才能检出固定基线。后续审查与稳定 CI 通过后再决定合并，不部署、不打开网络开关。本批没有验收超过五分钟的真实 NativeAuth token 轮换、真实 HTTPS/AASA、实体 iPhone 后台/锁屏/来电中断、完整队列、跨设备同步、销户执行或 StoreKit。M4 系统播放控制与实体机验收仍属下一阶段。
