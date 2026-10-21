# YouTube embed privacy delta — prepared, not published

2026-10-21 · Candidate 1.0.1 (14). This is a proposed addition for the new embedded YouTube player. It does not replace the existing 1.0 policy, change its effective date, save Apple answers, or claim a new disclosure is already live.

The new connection begins only when a user taps “Load YouTube player” or chooses the external fallback. Opening a song only reads Station Cat content and its existing cover. The app uses YouTube's official player without suppressing its branding, controls or advertising. Google may process the IP address, device/browser and playback/usage information according to its policies; this has not been exhaustively measured or mapped to final App Store data categories. `youtube-nocookie.com` and nonpersistent WKWebView storage do not justify “no data collected”, “no cookies” or “no tracking” claims about Google. The app adds no click/watch telemetry or account credentials, but provider data handling requires its own review.

The in-app information sheet links [YouTube Terms](https://www.youtube.com/t/terms) and [Google Privacy Policy](https://policies.google.com/privacy) before and after loading. Using ephemeral storage limits what this WebView persists locally; it cannot erase Google's records or the system browser/YouTube app's separate storage. The user closes the embed by leaving the page or switching tabs/backgrounding. External services control age, territory, account requirements and embedding availability. No video is downloaded for offline use.

## Proposed policy wording

**简体中文**

当作品提供 YouTube 短片时，只有在你点按加载播放器后，App 才会连接 YouTube 并使用其官方嵌入播放器。YouTube／Google 可能按其政策处理你的 IP 地址、设备及浏览器信息，以及视频使用信息，并可能在播放器中展示广告。我们不提供这些视频的下载，也不提取其中的音频。播放器使用临时网页存储，离开页面或进入后台会停止；这不代表 Google 不收集数据或即时删除其记录。你也可以选择在 YouTube 打开，届时适用该服务的独立规则。[YouTube 服务条款](https://www.youtube.com/t/terms)与 [Google 隐私政策](https://policies.google.com/privacy)进一步说明其处理方式。

**繁體中文**

當作品提供 YouTube 短片時，只有在你點按載入播放器後，App 才會連線至 YouTube 並使用其官方嵌入播放器。YouTube／Google 可能依其政策處理你的 IP 位址、裝置及瀏覽器資訊，以及影片使用資訊，並可能在播放器中顯示廣告。我們不提供這些影片的下載，也不擷取其中的音訊。播放器使用暫時網頁儲存，離開頁面或進入背景會停止；這不代表 Google 不蒐集資料或立即刪除其紀錄。你也可以選擇在 YouTube 開啟，屆時適用該服務的獨立規則。[YouTube 服務條款](https://www.youtube.com/t/terms)與 [Google 隱私權政策](https://policies.google.com/privacy)進一步說明其處理方式。

**English**

When a work includes a YouTube clip, the app connects to YouTube's official embedded player only after you tap to load it. YouTube/Google may process your IP address, device and browser information, and video usage under its policies, and may show advertising inside the player. We do not provide video downloads or extract audio. The player uses temporary website storage and stops when you leave the page or background the app; this does not mean Google collects no data or immediately deletes its records. You may also choose to open the video on YouTube, where that service's separate rules apply. See the [YouTube Terms of Service](https://www.youtube.com/t/terms) and [Google Privacy Policy](https://policies.google.com/privacy).

**日本語**

作品に YouTube 動画がある場合、読み込みボタンをタップした後にのみ、アプリは YouTube の公式埋め込みプレーヤーへ接続します。YouTube／Google は、そのポリシーに従って IP アドレス、端末・ブラウザ情報、動画の利用情報を処理し、プレーヤー内に広告を表示する場合があります。当アプリは動画のダウンロードや音声の抽出を提供しません。プレーヤーは一時的な Web ストレージを使用し、ページを離れたりアプリがバックグラウンドになったりすると停止します。これは Google によるデータ収集がないことや、記録が直ちに削除されることを意味しません。YouTube で開くこともでき、その場合は同サービス独自の規則が適用されます。詳しくは [YouTube 利用規約](https://www.youtube.com/t/terms)と [Google プライバシーポリシー](https://policies.google.com/privacy)をご確認ください。

## Distribution review

Before distributing the candidate, compare the actual player and provider practices with [Apple's App Privacy guidance](https://developer.apple.com/app-store/app-privacy-details/) and [YouTube developer policies](https://developers.google.com/youtube/terms/developer-policies). Decide final data categories, purposes, linking/tracking treatment from evidence; do not copy 1.0's answers or add ATT solely on an assumption. Update the published policy and store answers consistently. No Apple questionnaire changes or legal compliance certification are made by this draft.
