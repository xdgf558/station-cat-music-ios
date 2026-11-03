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

修正提交后仍需完成对应 `push`、`pull_request` 的全部必需验证，最终远端结果以 [PR #24 最新 head 的官方 Checks](https://github.com/xdgf558/station-cat-music-ios/pull/24/checks) 为准。本文不提前声明远端成功；全部必需检查成功后才可正常合并，再进入已授权的 Apple 更新流程。
