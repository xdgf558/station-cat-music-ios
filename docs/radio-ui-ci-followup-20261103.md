# 电台改版 CI 跟进 · 2026-11-03

原审查 head `f8d5fe7e95dbe85f6bf47ba3e88bcc1863900612` 曾因以下远端验证失败而未满足合并条件。本记录保留原始失败、测试驱动修正及本机补测的范围；本机专项或另一条工作流成功，不能替代修正提交完整的远端验证。

[push Native 运行 41631121374](https://github.com/xdgf558/station-cat-music-ios/actions/runs/41631121374) 的 `contracts` 成功，前置退出恢复及媒体验证已通过，随后 `test_ios.sh` 失败。该步骤实际运行 57 分 11 秒，完整执行后报告 414 项单元零失败、23 项按条件跳过；62 项 UI 中 3 失败、5 跳过。后续 Keychain 重启与认证恢复步骤被跳过，不能记为已验收。

三条 UI 失败分别为：

- `PlatformNotebookUITests.testPastedMultilineTitlePreservesWordsAsSingleLine`、`testTitleNextMovesTypingToBodyAndSavesSingleLineTitle`：保存和重开断言之前，在展开写作说明的测试辅助流程失败。辅助函数将 `isHittable` 等同于完全位于键盘上方可视区域，提前返回；之后又读取尚不存在的 `notebookTextLimits` 节点 frame，触发快照失败。
- `YouTubeClipUITests.testFourLocalesLargeTextCanReachSourceFallbackAndListening`：英文最大辅助字号下，辅助函数未将整个加载预览定位到导航栏与固定收听栏之间。失败时控件存在且可点击，但上沿仍位于导航栏覆盖区域。仅凭这份结果不能认定产品控件无法滚动到可见位置，也不能将它解释为真实 YouTube 播放失败。

[PR Native attempt 2](https://github.com/xdgf558/station-cat-music-ios/actions/runs/41631129739/attempts/2) 也在 `test_ios.sh` 失败：62 项 UI 中 6 失败、5 跳过，包含上述三条，并新增：

- `DouyinClipUITests.testFourLocalesLargeTextCanReachSourceFallbackAndListening`：同类英文最大辅助字号的 `douyinLoad` 完整可达断言失败，控件上沿停在导航栏覆盖区；不能将它写成真实抖音播放验证失败。
- `NetEaseListeningUITests.testApprovedMobileDocumentLoadsFromLocalFixture`：网页已加载标记已经出现，随后立即检查 WebView 正文是否存在的断言失败。正文可访问树的出现是另一异步阶段，本次补充对正文节点的等待，保留已加载与受控来源检查；这不是对真实网易云播放的结论。
- `PlatformCatalogUITests.testAlbumGalleryFourLanguagesAndAccessibilityText`：大字号专辑页点击曲目后，未在等待期内出现作品详情。实际可访问树中，专辑固定底栏的 Button 继承了 `platformAlbumDetail` 标识，测试原先只查 `radioAlbumChooseTrack`，没有正确扣除该底栏。辅助函数现按 Button 类型兼容识别这两个标识，再判断曲目是否完整位于可视区域；v5 的四语大字号用例已通过。这是测试定位边界的修正，不据此认定产品导航缺陷。

[PR Native 原 attempt 1](https://github.com/xdgf558/station-cat-music-ios/actions/runs/41631129739/attempts/1) 另有前置媒体验证失败，原始证据已保留，根因尚未确认。它与上述 push UI 失败是不同阶段；后续重跑通过该前置步骤，也不能反向证明原失败可以忽略。

修正现已扩到五个 UI 测试文件：`PlatformNotebookUITests`、`YouTubeClipUITests`、`DouyinClipUITests`、`NetEaseListeningUITests`、`PlatformCatalogUITests`。笔记辅助函数先扣除固定顶部控制区及键盘遮挡，目标完整可见后才返回，缺失节点不读取 frame。网易云正文增加异步等待，目录辅助函数按实际可访问树核对固定底栏边界。没有修改产品源码、播放逻辑、版本、配置或守卫。

本机 v2 中，原失败的两条笔记用例已通过；扩展整类回归另发现选曲器返回后主题选项可能留在屏幕外，调用方现先定位选项再点击。YouTube v2 的最终目标实际上已完整可见，但辅助函数在最后一次拖动后未再次检查就报失败，现补一次末态只读检查及缺失节点的有限等待，不增加拖动次数。这些是测试驱动的进一步修正，不作为已经完成全部回归的声明。

后续短片驱动试验中的小步慢速拖动和结束停留曾误触加载预览：用例没有点击加载，末态仍选中短片，却出现了播放器 WebView。相关失败日志和可访问树已保留，不能将这些结果写成产品自动播放或真实视频播放失败。最终视频辅助函数恢复原先的详情区域中心起手、按住 0.05 秒、默认拖动速度及无结束停留的事件方式，按目标位置将距离限定为 80–160 点。隐私弹层则匹配包含目标 identifier 的真实 ScrollView，使用该元素的 `swipeUp()`／`swipeDown()`，避免手势推动背景详情而弹层正文不动。两处分支继续缓存 identifier、等待缺失节点、保留末态只读检查、完整可达断言与原拖动次数上限。

本机原代码对照结果有设备差异：iPhone 17 Pro / iOS 26.4 上两条笔记用例失败、YouTube 四语大字号用例通过；iPhone 16e / iOS 26.4 上原两条笔记用例通过。这些结果支持继续修正测试定位边界，不能单凭通过的一台设备宣布问题已关闭。

本机最终补测在 iPhone 17 Pro / iOS 26.4 上按执行快照分两组完成：v7 中专辑目录 5 项、笔记 3 项（包含两条原失败用例及中文主题用例）、网易云正文 1 项通过；v8 中两个完整短片 UI 类 6 项通过，包含四语最大辅助字号下的详情控件及隐私弹层可达检查。合计 15 项是分批实际通过的结果；v7 整体仍有短片失败，不能记为整轮通过。分组结果以对应执行快照为依据，提交前逐文件核对最终五个测试文件与各组快照的 SHA-256。产品源码字节仍与原审查 head 一致。

## 2026-11-04：预览区域的滚动手势对照

`01fda55` 的 [Native push attempt 2](https://github.com/xdgf558/station-cat-music-ios/actions/runs/41662215028/attempts/2) 已通过前置恢复、媒体、双会话及四配置检查，但完整测试仍失败：414 项单元零失败、23 跳过；62 项 UI 中 1 失败、5 跳过，后续 Keychain 重启和认证恢复被跳过。唯一失败为繁中最大辅助字号下 `DouyinClipUITests.testFourLocalesLargeTextCanReachSourceFallbackAndListening` 的无 WebView 断言。没有主动 `tap()` 加载，但定位辅助函数的合成按住拖动从预览 Button 内部起手，之后原始可访问树出现 `douyinOfficialPlayer`。这份失败及校验过的 xcresult 已保留；不能仅凭没有 `tap()` 命令就将真实触摸事件称为自动加载或环境波动。

本机 v9 改用详情 ScrollView 的原生整幅 swipe 作对照：YouTube 四语通过，Douyin 因一次大幅滑动越过大字号 Tab，定位在有限次数内未收敛而失败；该轮没有出现原无 WebView 断言失败。v9 不能写成整轮通过，也不能代替实体机手势验证。

v10 保留 80–160 点的有限定位距离，将详情滚动起手点移至 ScrollView 左侧空白区。实际详情外框从 x=0 开始，内容水平内边距为 20 点，起点为外框 minX+14，避开整卡预览 Button。隐私弹层继续使用目标 ScrollView 的原生 swipe。预览、外部入口和隐私入口定位后各增加一次无 WebView 断言，原末态无加载、显式点击加载、停止与后台清理断言均保留，没有通过清空播放器状态掩盖失败。两个完整短片类已实际通过 6 项、零失败、零跳过。

v11 又给 Douyin 类增加预览内部向上滑动的四语最大字号对照。该手势刻意从预览 Button 内部发出，要求预览位置实际上移、详情与选中 Tab 保持、无 WebView；之后主动点击同一预览才必须出现本机播放器夹具。完整 Douyin 类 4 项通过、零失败、零跳过。最终 Douyin 文件与 v11 快照一致、YouTube 文件与 v10 快照一致，两个类合计 7 项分批通过；不能把 v10 的旧 Douyin 文件当成最终文件的测试依据。没有修改产品源码、配置或版本，也没有执行真实第三方视频或实体机验证。

## 首次原生起播的诊断边界

`8d71897` 的 [Native PR](https://github.com/xdgf558/station-cat-music-ios/actions/runs/41687131980) 在前置媒体验证失败，尚未进入 UI 回归。唯一失败是 `NativeMediaIntegrationTests.testRealAVPlayerRangeAndHardStopAgainstIsolatedWorker` 第一次起播的 `position > 0.15` 断言；50 次、每次 100ms 的原等待结束后仍为 0。授权返回 200、首音频 GET 返回 206，服务已正常就绪；另外 11 项媒体测试通过，包含真实五分钟认证轮换。它与旧 `f8d5fe7` 的一次失败处于同一边界，但不能据此认定两次内部原因相同，或归为可忽略的环境波动。

`isPlaying` 读取的是 AVPlayer 的期望 rate，不能替代真实媒体时钟。因此本次只在 `DEBUG` 编译条件下增加只读、有限快照，区分原始 currentTime、已发布 position、item/player/timeControl 状态、有效 timebase rate、seeking 与进度任务是否仍存在。错误仅记录白名单 domain 与数值 code，不记录 URL、凭据、账号标识、描述或 userInfo。原始 50×100ms 迭代、0.15 阈值、后续 seek／暂停／重播／期限／撤销断言均保留，没有加等待、重新请求播放或跳过检查。快照记录本身有同步观测开销，不把任务引用存在误写成采样循环已经执行。

本机使用固定后端 `4d51e1a5b9f9f41945a918e21cf1f8ff9aab1fa8`、19 项文件摘要、真实隔离 D1/R2 与合成音频验证了这条测试，结果通过；第一轮已发布进度超过阈值约为 0.95 秒。工具链为 Xcode 27.2 beta、iOS 26.4.1 Simulator、Node 24.15.0，不能代替失败运行的固定 Xcode 26.4.1／iOS 26.5，也不能据此宣布原始失败根因已解决。初次本机清单路径失败没有执行测试，保留为输入失败记录，不计通过。

正常 Production 应用构建已成功，实际模拟器应用中不存在新增诊断类型和 getter。去掉两个 `DEBUG` 块及新增分隔空行后，`Core/Playback.swift` 与原产品代码逐字节一致；测试文件去掉诊断块、还原循环排版后也与原版本一致。此处是非分发的构建与静态排除核对；实际归档和 IPA 仍需各自校验。诊断尚不等于重复失败已定位，后续若再次发生，应根据快照继续处理，不靠增大时限放行。

修正提交后仍需完成对应 `push`、`pull_request` 的全部必需验证，最终远端结果以 [PR #24 最新 head 的官方 Checks](https://github.com/xdgf558/station-cat-music-ios/pull/24/checks) 为准。本文不提前声明远端成功；全部必需检查成功后才可正常合并，再进入已授权的 Apple 更新流程。

## 资源交付与等待边界的进一步诊断

`0fd00d1` 的 [Native push](https://github.com/xdgf558/station-cat-music-ios/actions/runs/41696285010) 再次在首次进度断言失败。51 个样本中已发布 position、原始 mediaTime 和 timebase rate 始终为 0，最后 itemStatus 仍为 unknown；约 5.124 秒内没有观察到媒体时钟推进。授权及服务端首个 206 较早完成，不足以证明客户端已读完正文或交付给 AVFoundation。同一 head 的 PR 运行通过了媒体阶段，不能据此撤销 push 的失败或直接归因环境。

为区分这些边界，NativeMediaLoader 增加 DEBUG-only、线程安全的前 96 条事件，覆盖请求、响应头、完整正文／退出时部分字节、元数据、respond 返回、finishLoading、取消和固定错误类别／数值码。无 URL、凭据、账号、正文或自由文本错误。上限达到 96 时后续事件被丢弃，因此缺少事件不能据此推断未执行；并发事件也不能仅凭相邻顺序绑定为同一请求。

测试在原循环结束立刻冻结 hasAudioSource、isPlaying、position，之后输出诊断并断言这些已冻结值，避免日志开销将边界后的迟到起播算作通过。只在原等待之后读取音频会话类别、模式、采样率与输出数量；没有提前激活、预热、重新播放或放宽 50×100ms／0.15。Apple 的默认会话支持前台播放，未显式激活本身不能当作根因。

本机固定后端的新增 trace 用例实际通过，正文与两次 loader finish 均约在 0.121 秒内，已发布 position 首次越过阈值约在 1.029 秒；原始输出保留为 loader-clock-snapshot-v3。会话为默认 SoloAmbient、48kHz、一个输出。这仍是 Xcode27.2 beta／26.4.1 单次检查，没有复现托管 26.5 的停滞，不能宣称解决远端失败。线程安全、96 上限、reset 和 JSON 字段另通过 Foundation 自检。正式 Production 构建及最终 archive／IPA 必须继续检查诊断类型完全排除。

## 首个媒体夹具与实际原生入口对齐

`fd29c0d` 的 [Native PR attempt 2](https://github.com/xdgf558/station-cat-music-ios/actions/runs/41704247226/attempts/2) 仍在首次起播推进断言失败。这次 18 条 loader 事件确认：206 正文 65,245 字节读完，2 字节元数据探测及完整资源请求均已回应并 finishLoading，最后一次完成在首样本后约 0.427 秒；无加载取消或错误。随后约 5.204 秒的 51 个播放器样本仍为 mediaTime／timebaseRate／position 全零、item unknown。故这次失败已可排除客户端正文消费或字节交付停滞，但尚不能解释 AVFoundation 内部未就绪原因。

首个 M3 夹具此前直接构造 PlaybackService，没有像 StationCatMusicApp 的受开关控制原生分支一样连接 SystemPlayback。现在仅修改该测试，使用真实系统适配器，并仍由原 requestPlay 在授权及边界确认后 activate；不单独提前 setActive、不预播放、不增加等待。原 50×100ms／0.15、边界值冻结及后续 seek、暂停、重播、期限和撤销断言保持，另断言有效类别为 playback、模式 default、选项为空。测试 defer 停止播放器、移除系统适配器的命令与观察者，并恢复先前类别／模式／选项；不能声称恢复未知的先前 active 状态。两个执行脚本均禁止并行测试，避免共享音频会话冲突。

本机独立 XCTest 进程的 v4 用例实际通过（8.484 秒），首次已发布进度过阈值约 1.029 秒，会话为 Playback／Default／48kHz。对照的旧夹具本机也能通过，因此本机结果不构成托管失败的复现或内部根因证明。默认音频会话本身支持播放；SystemPlayback 的系统媒体服务注册也可能影响初始化时序。后续只能依据新 head 的完整托管验证声明“对齐实际产品链路后通过原门槛”，不能声称 SoloAmbient 必然不能播放。正式 App 产品源码、配置、版本和开关未因这次夹具对齐而改变。
