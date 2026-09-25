# 真实曲目封面导致闪退：2026-09-24

用户报告进入真实歌曲后 App 退出。从目标 iPhone Air 读取的两份 StationCatMusic 崩溃日志均为 `EXC_BREAKPOINT / SIGTRAP`，触发线程为 MediaPlayer `*/accessQueue`。栈由 `MPMediaItemArtwork jpegDataWithSize:` 进入 `SystemPlayback.publish(_:)` 内的图片回调，随后命中 Swift actor 隔离检查及 `_dispatch_assert_queue_fail`。

原始日志保留在忽略目录 `.build/r3-crashes/`，不提交完整设备诊断信息。两次日志时间为手机本地 06:27:58、06:28:10（Mac 时区显示约 21:27、21:28）。

## 修复

`SystemPlayback` 是 MainActor 类型；原封面闭包在其 Task 内创建，继承了 MainActor 隔离。MediaPlayer 实际从后台队列请求图片，触发运行时断言。

将封面 request handler 显式标为 `@Sendable`，只返回已解码、不可变的 UIImage；不访问播放器和界面状态，不同步派发回主线程。Now Playing 写入、取消和旧 URL 检查继续留在 MainActor。两个系统媒体指令回调也显式使用 `@Sendable`，仍只通过既有 MainActor Task 执行播放器指令。

未更改音频授权、缓存容量、下载限制、生产配置、账户或付款。

## 回归

新增测试使用实际 `SystemPlayback.publish`、有界 ArtworkLoader、合成 PNG 和实际 MPMediaItemArtwork。等待图片发布后，在独立后台执行器调用图片请求接口（32、128、512 点），确认返回有效图像并检查 shutdown 清理。测试不使用远端服务或真实曲目文件。

模拟器 `.build/r3-artwork-fix.xcresult`：ArtworkLoaderTests 3/3、PlaybackSystemTests 14/14，共 17 项通过，包含新后台请求回归；源码边界检查与 `git diff --check` 通过。

真机隔离真实歌曲测试额外要求系统 Now Playing 已实际收到封面，再继续超过 70 秒播放、授权续期、暂停/恢复、拖动及清理。其结果另记于 R3 真机报告。

首次修复版真机测试 `.build/r3-real-artwork-fixed.xcresult` 已越过真实封面检查，未再崩溃；但在 `continuous_renewal` 等待条件超时（总计 107.544 秒）。旧测试把本机等待超时抛为 `APIError.unavailable`，日志显示 `service`，这不能证明服务端返回了错误。保留该失败，并把探针等待超时单独分类、增加当前进度/状态/授权次数及脱敏授权失败类别；不输出媒体地址和凭据，也不延长授权或测试期限。

修复版正常启动并打开真实歌曲链接后，进程仍存活；手机崩溃目录仍为上述两份旧日志，没有新增同类报告。这项为进入歌曲路径的存活检查，不代表全部播放场景通过。

第二次诊断运行 `.build/r3-real-artwork-diagnostic.xcresult`：同样越过实际封面检查且没有闪退，85 秒条件等待结束时 `position=69.589507723`、`state=playing`、成功授权 2 次、授权失败类别为空；未达到 `position>70` 的原有断言，后续暂停/拖动阶段未执行。这表明本次封面回调修复和获得续期授权有效，但不证明连续无缓冲播放、网络无延迟或整项 R3 验收通过。保留两份失败结果，不放宽测试阈值或生产授权时限。后续需单独分析真实 MP3 分段加载/重新 seek 的缓冲时间。

修复包已通过真机测试安装至同一 Staging App，随后以正常启动方式打开《把那年还给风》供用户操作，没有卸载 App、清理 Keychain 或个人资料。尚未开 PR 或启用生产服务。

后续进展：起播与续期缓冲单独优化后，最终 `.build/r3-final-physical.xcresult` 的真实歌曲完整用例通过，包含 Now Playing 实际封面、70 秒以上播放、两次授权、暂停/继续及拖动。以上两次早期失败不删除，性能修改及最终实测范围见 `R3-startup-renewal-20260924.md`。
