import Foundation

extension DouyinClipSession {
    static func forCurrentEnvironment() -> DouyinClipSession {
        #if DEBUG && targetEnvironment(simulator)
        if Bundle.main.object(forInfoDictionaryKey: "StationEnvironment") as? String == "mock",
           ProcessInfo.processInfo.arguments.contains("--platform-music-fixture"),
           ["douyin-clips", "douyin-error"].contains(ProcessInfo.processInfo.environment["STATION_PLATFORM_FIXTURE"] ?? "") {
            let failure = ProcessInfo.processInfo.environment["STATION_PLATFORM_FIXTURE"] == "douyin-error"
            return DouyinClipSession(document: { _, token in
                """
                <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
                <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-\(token)'">
                <style>body{margin:0;background:#10152c;color:#ddd8ff;font:16px -apple-system;height:100vh;display:flex;align-items:center;justify-content:center;text-align:center}small{display:block;margin-top:20px;color:#a6b0c9}</style></head>
                <body><div>本机界面测试<small>未连接 Douyin · 无真实视频</small></div>
                <script nonce="\(token)">window.webkit.messageHandlers.douyin.postMessage({token:'\(token)',event:'\(failure ? "error" : "loaded")',code:\(failure ? 150 : 0)});</script></body></html>
                """
            }, verifyEmbed: { _ in })
        }
        #endif
        return DouyinClipSession()
    }
}
