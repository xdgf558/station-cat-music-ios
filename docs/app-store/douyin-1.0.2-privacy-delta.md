# Douyin embed privacy delta — prepared, not published

2026-10-22 · Development candidate **1.0.2 (15)**. The user has deferred deployment until 1.0 is formally live. This document does not replace the effective 1.0 policy, save Apple answers, or change the submitted 1.0 (13) binary. It supplements the separate YouTube draft; neither draft is evidence of published policy.

Opening a song reads Station Cat metadata and its cover. A tap on **Load Douyin player** first rechecks the current Station Cat publication, then requests Douyin's official iframe API with the video ID. An available response allows a temporary WKWebView to load the official player. The API request itself contacts Douyin even if the video cannot subsequently play. No Station Cat authentication headers, share tokens or user account details are sent. Choosing **Open in Douyin** separately rechecks Station Cat and hands a canonical URL to the system; the external browser/app uses its own storage and policies.

Douyin can receive the IP address, browser/device and video-request/use information through these connections. The complete provider behavior, advertising, linking/tracking purposes and final App Store category mapping have not been measured in this task. Nonpersistent WebView storage does not establish that Douyin collects no data, uses no cookies, or immediately deletes its records. Station Cat adds no viewing/click telemetry and does not extract, proxy or download the video. Leaving the page, changing tabs or backgrounding stops and discards the embed.

The in-app information sheet links the [official Douyin privacy policy](https://www.douyin.com/privacy/). The implementation follows the [official iframe API](https://developer.open-douyin.com/docs/resource/zh-CN/dop/develop/openapi/video-management/douyin/iframe-player/get-iframe-by-video) and never executes returned HTML. An iframe load event only establishes document load, not successful video playback. Availability can still depend on the provider, region, account, age, network and current embedding settings.

## Proposed policy addition

**简体中文**

当作品提供抖音短片时，只有在你点按“加载抖音播放器”后，App 才会向抖音查询该视频的官方嵌入信息，并在可用时加载官方播放器。因此，即使视频最终未能播放，查询也已经连接抖音。抖音可能按其政策处理你的 IP 地址、设备及浏览器信息，以及视频请求和使用信息。我们不提取音源，不提供视频下载，也不向抖音传送 Station Cat 账号凭据。播放器使用临时网页存储，离开页面或进入后台会停止；这不代表抖音不收集数据或即时删除记录。你也可以选择“在抖音打开”，届时适用该浏览器或 App 的独立规则。详情请阅读[抖音隐私政策](https://www.douyin.com/privacy/)。

**繁體中文**

當作品提供抖音短片時，只有在你點按「載入抖音播放器」後，App 才會向抖音查詢該影片的官方嵌入資訊，並在可用時載入官方播放器。因此，即使影片最後未能播放，查詢也已連線至抖音。抖音可能依其政策處理你的 IP 位址、裝置及瀏覽器資訊，以及影片請求和使用資訊。我們不擷取音源，不提供影片下載，也不向抖音傳送 Station Cat 帳號憑證。播放器使用暫時網頁儲存，離開頁面或進入背景會停止；這不代表抖音不蒐集資料或立即刪除紀錄。你也可以選擇「在抖音開啟」，屆時適用該瀏覽器或 App 的獨立規則。詳情請閱讀[抖音隱私權政策](https://www.douyin.com/privacy/)。

**English**

When a work includes a Douyin clip, tapping “Load Douyin player” queries Douyin's official embed API for that video and loads its official player if available. The query contacts Douyin even if the video ultimately cannot play. Douyin may process your IP address, device/browser information and video request/use information under its policies. We do not extract audio, offer video downloads or send Station Cat account credentials to Douyin. The player uses temporary website storage and stops when you leave the page or background the app; this does not mean Douyin collects no data or immediately deletes its records. You may instead choose “Open in Douyin”, where the external browser or app's separate rules apply. See the [Douyin privacy policy](https://www.douyin.com/privacy/).

**日本語**

作品に抖音（Douyin）の動画がある場合、「抖音プレーヤーを読み込む」をタップした後にのみ、アプリは公式埋め込み API で動画を照会し、利用可能な場合に公式プレーヤーを読み込みます。動画が再生できない場合でも、この照会は抖音へ接続します。抖音は、そのポリシーに従って IP アドレス、端末・ブラウザ情報、動画のリクエストや利用情報を処理する場合があります。当アプリは音声の抽出や動画のダウンロードを提供せず、Station Cat のアカウント認証情報を抖音へ送りません。プレーヤーは一時的な Web ストレージを使用し、ページを離れたりアプリがバックグラウンドになったりすると停止します。これは抖音によるデータ収集がないことや、記録が直ちに削除されることを意味しません。「抖音で開く」を選ぶと、外部ブラウザやアプリの独自の規則が適用されます。詳しくは[抖音プライバシーポリシー](https://www.douyin.com/privacy/)をご確認ください。

## Before distribution

Review actual provider traffic and policies using a real, authorized video; map the results to the Apple privacy questionnaire, and update the published policy and store answers consistently. This task provides technical disclosure drafts, not a completed privacy assessment or legal certification. No production policy, Apple questionnaire, ATT declaration, subscription or native-service setting is changed.
