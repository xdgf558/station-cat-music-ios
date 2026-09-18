# M4：系统播放、队列与认证轮换

2026-09-18。本批从已合并的 iOS #5 / 网站 #175 开始。实现本地系统播放与队列能力，继续使用隔离测试服务；四配置网络开关保持关闭，默认 Mock 不激活系统音频、不播放示例声音。本机实现不等于 M4 全部真机验收或可上架。

## 播放与系统边界

同一个 PlaybackService 处理 App、控制中心与耳机的播放、暂停、切歌和进度操作。新增 AVAudioSession playback 配置及 UIBackgroundModes audio；只在原生音乐客户端的独立开关与隔离配置全部有效时安装系统桥，并在成功取得授权后激活会话。没有申请 Apple Music 曲库权限。

Now Playing 显示公开标题、艺名、展示封面、实际变体时长、进度与速率。封面只允许配置的 HTTPS 主机、拒绝重定向、无 Cookie/缓存、限五秒/2 MiB，并缩略为最多 256 像素；失败不阻塞音频、不自动重试。认证 token、grant URL 不进入系统展示。退出、切账号、删除确认或清空队列均清理播放器与系统信息；shutdown 移除事件观察者和命令 target。

中断开始清除当前源，保留进度及当时播放意图；中断结束仅在系统允许、原授权截止尚未过去且用户期间未暂停/切歌时申请新授权恢复。用户主动播放可以尝试恢复缺失 ended 通知的场景，由音频会话激活和重新授权决定是否成功。耳机断开暂停，不自动外放。媒体服务重置重建唯一播放器，保留歌曲/进度，等待用户操作。

跨 actor 的账号检查完成后再次核对取消、播放序号及当前曲目，防止已暂停的请求激活系统音频。原来的 seek 完成检查、硬截止、Range/Bearer、失败不自动重试机制继续保留。禁用 AVPlayer 远端外部播放，不把付费 URL 交给接收端直接获取；AirPlay 路由兼容性仍待真机单独验证。

## 队列与界面

队列保存选曲时的列表快照，不依赖之后的搜索或专辑筛选。支持最多 500 项、顺序播放、列表循环、单曲循环、随机、选择/移除队列项和清空停止。相同歌曲的不同队列项有独立 ID；随机开关不跳离当前曲目，上一首使用实际历史，超过三秒先回到开头。自然结束才自动切到下一项，每首和每次循环均取新授权。

明确不可用或初次授权 403/404 可跳过，单次尝试最多访问各队列项一次；全部失败时停止。503、网络失败、续期失败、硬截止不触发自动跳歌。目录标为可试听的项目按真实账号音乐权益选择完整版或独立 preview；游客只选 preview，已登录但资格查询失败不会降级伪装成游客。明确点击试听及试听恢复保留变体。续期固定既有变体，到期不会自动切到试听。暂停时拖动仅更新恢复位置，不读取音频。

播放器增加四语队列、随机/循环与 15/30/60 分钟睡眠菜单。睡眠使用连续时钟，独立停止任务和前台复核，不因修改系统日期延长；结束后等待明确播放操作。大字号下选项纵向布局。自动切歌触发详情/歌词重新载入，并继续按曲目和版本限制迟到结果。

歌曲及专辑支持独立配置的公开音乐网站 HTTPS 链接解析和系统分享链接（StationMusicWebOrigin，与认证 API origin 分开；当前四配置均为空，不生成指向认证服务的假分享地址），严格限制路径、标识符及单一查询参数。解析歌曲只打开资料，专辑只打开列表，不自动取授权或播放；账号/请求序号切换后忽略迟到结果。没有绑定 Associated Domains 或伪造 AASA，因此系统 Universal Link 唤起仍待真实配置验收。

## 隔离真实认证轮换

网站测试服务新增合成刷新凭据及脱敏证据接口，全部在随机 loopback、临时 proof 和临时 D1/R2 内。iOS 使用真实 NativeAuthenticationService、Keychain 单记录 journal、NativeMusicAPI 和 Worker refresh 路由，循环本机三分钟合成音频超过 315 秒。

探针要求同一个账号/session/family，绝对期限不变，generation 增长且 pending 清空。超过原五分钟窗口后播放继续，并直接验证旧 Bearer 返回 401、新 Bearer 返回 200。服务端五分钟 access 有效期及 120 秒重放窗口未改，未伪造时钟，也没有定时重新创建账号绕过轮换。初始凭据由测试服务写入合成 session，不能称为真实浏览器登录验收。

配套网站提交由 `contracts/backend-media-fixture.json` 固定，核对源码哈希。测试驱动要求 M3 七个成功标记及 M4 四个成功标记。长探针执行上限提升至 900 秒，仅改变测试总时长上限，不改变产品网络超时。M2 A11–A13 保持独立旧后端清单与现有 CI 步骤。

## 验证记录

本机 Xcode 27 beta 6 / iPhone 模拟器，2026-09-18：

- 真实 AVPlayer / 隔离 Worker 联调 **11/11** 通过，543.367 秒。M3 七组及 M4 四组成功标记齐全。
- M3 长曲使用四个 grant，两次实际 60 秒续期；采样最大进度倒退约 0.00087 秒、最大停顿约 0.832 秒。这些不是声学级无缝证明。
- M4 超过 315 秒真实认证轮换：generation 到 2，同账号/session/family/绝对期限，旧 Bearer 401、新 Bearer 200，播放继续。显式试听的循环没有自动升级为 VIP 完整版。
- 完整探针之后，仅把公开链接域名与 API 域名分开；最终代码另跑真实服务链接测试 **1/1**，确认不同域名的歌曲/专辑解析与分享、不自动播放。
- 恢复驱动回归 **9/9** 通过。沙箱内初跑两项因禁止 `ps` 无法执行，随后沙箱外正常通过；本轮未重跑 M2 A11–A13 实际崩溃探针，仍由 PR 的固定稳定 CI 执行。
- 网站原生音乐测试 **17/17** 通过；153 页构建及 postbuild 通过。该本机构建使用空小说内容开关，仅作验证，不能部署。
- OpenAPI 25 操作、63 正向/10 反向 fixture，四语及源码边界检查通过；工程、契约、资源可重复生成，`git diff --check` 通过。

最终常规 Swift 套件 85 项中 **70 通过、15 项专用探针按设计跳过**，UI **2/2** 通过；Mock / Development / Staging / Production 四配置构建及 plist 断言全部通过。全部网络开关仍为 NO、认证及公开分享 origin 为空，没有 ATS 例外，仅声明 audio 后台模式。配套网站 fixture 为 `4d51e1a5b9f9f41945a918e21cf1f8ff9aab1fa8`，没有改产品服务端实现。原始日志为忽略跟踪的 `evidence/M3-media-integration.log`、`evidence/M4-links-integration.log` 及本机临时构建日志；不提交可用凭据。

## PR #6 复审修复（2026-09-18）

收藏区用同一份 `favoriteTracks` 快照渲染按钮并建立队列，与曲库搜索/专辑筛选无关。没有明确传入列表的选曲只建立单曲队列。回归覆盖只有 B 被收藏、无关专辑和搜索存在、多首收藏及选曲后收藏列表变化。

新增独立 `ArtworkLoader` actor，承担 URLSession 有界下载、逐字节消费和 ImageIO 缩略图解码。MainActor 只在返回后复核任务取消、当前 URL 和适配器状态，并更新系统媒体信息。仍拒绝重定向、关闭 Cookie/缓存、限制五秒和 2 MiB，要求原始 Content-Type 为图片；每次请求在成功、失败或超限后关闭自己的会话。

新增本地 URLProtocol 合成 PNG 测试，连续三次读取每张 2,097,136 字节并生成 256px 缩略图；主线程每 10ms 心跳，最终专项运行最大间隔约 17.4ms（断言上限 100ms）。另测无 Content-Length 的超限流和错误类型。临时改回 MainActor 的反向验证出现超时/取消失败；测试后已恢复 actor，没有保留变异代码。

本地完整回归 88 项：73 通过、15 项专用探针按设计跳过，UI 2/2。收紧心跳断言后最终专项 16/16 通过。契约、源码边界和 diff 检查通过。本次未改授权播放器或网站 fixture，长音频与 A11–A13 由新 head 的远端 CI 重新执行；旧 head 的 CI 通过不能代替修复提交的验证。

## 发布前仍需完成

- 固定 Xcode 26.4.1 远端 CI；本机使用 Xcode 27 beta 6，二者不可混称。
- 真实 HTTPS 登录/回调、AASA、Team ID、正式签名；当前仍缺配置。
- 实体 iPhone 锁屏连续两小时、耳机/控制中心真实指令、电话/Siri 中断、蓝牙断开和 Wi-Fi/蜂窝切换。
- 真机后台硬截止及音频预缓冲残余测量、系统挂起与 Keychain 锁定、AirPlay 路由。模拟系统通知不代表真的来电或后台调度已验收。
- M4 全阶段尚需在真实域名与设备验收 Universal Link 唤起、系统分享面板及基础性能。个人数据同步、完整销户执行与 StoreKit 属于后续任务。

不得因模拟器通过而打开生产开关、部署网站或上传 TestFlight。本轮不改变网站产品 Worker、支付、生产迁移或现网账号。

## 参考与复现

实现依据 Apple 的 [音频中断处理](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions)、[媒体服务重置](https://developer.apple.com/documentation/avfaudio/avaudiosession/mediaserviceswereresetnotification)及 [系统远程命令中心](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter)。系统重置后等待用户操作，不能默认自动播放。

```sh
# 先检出 backend-media-fixture.json 的网站固定提交并安装依赖
export M3_BACKEND_PATH=/absolute/path/to/isolated-website-checkout
export M1_SIMULATOR_ID=your-iphone-simulator-uuid
bash scripts/test_ios.sh
python3 scripts/verify_native_media.py
bash scripts/verify_configurations.sh
.venv/bin/python scripts/validate_contract.py
python3 scripts/check_source.py
```

只有本机 beta 工具链使用 `DEVELOPER_DIR` 与 `M1_ALLOW_LOCAL_TOOLCHAIN=1`；CI 仍固定稳定版本。先推送配套网站 fixture，再推送 iOS 分支，确保 CI 可取到固定提交；本批通过 iOS PR #6 与网站 PR #176 审查；提交 PR 不代表部署或生产开关授权。

## 2026-09-19：探针启动与捕获修复

已审查提交 a33673f 的 PR run 35357729517 全部通过，但 push run 35357719701 首次及重跑均在 A11 只留下启动 PID，没有检查点标记。日志不足以断定是 App 启动失败还是 console 捕获丢失，不能把任意退出当作成功，或用另一组绿色结果掩盖失败。

本次仅改测试宿主/共享测试场景及 Python 驱动：探针从 UIApplicationDelegate 启动回调执行，显式支持 UIScene；不再依赖 SwiftUI view 的 task 或 simctl console 附加。每次 CRASH/RECOVER 生成独立 UUID，把启动、检查点、最终清理完成标记原子写入探针容器文件并 synchronize；文件不写入凭据，复制到 CI evidence 后删除。

驱动校验新文件、阶段/模式、启动 PID 与标记 PID 一致，再确认进程确实退出。RECOVER 必须出现最终完成标记、使用不同 PID；实际账号、family、请求 ID、绝对期限、撤销状态及删除回执断言未改。检查点刚写入与 ps 检查之间的竞态会重新读取文件；缺失/错误标记、失败标记、存活进程仍失败。不自动重启场景、不延长固定 120 秒期限、不改服务端 fixture 或产品 Core。

本机 Xcode 27 beta 6 最终真实探针：A11 8602→8618（0.470 秒）、A12 8634→8651（0.488 秒）、A13 8667→8683（0.480 秒），全部通过。驱动回归 20/20，通过旧文件、错误阶段/PID、启动器先退出、进程仍存活、缺少最终清理及写入/退出竞态测试。固定 Xcode 26.4.1 必须按修复后的新提交重新验证；本机通过不是稳定 CI 或实体 iPhone 验收。

本次共享测试场景编译及常规回归 88 项：73 通过、15 项专用探针按设计跳过；UI 2/2 通过。源码边界与 diff 检查通过。
