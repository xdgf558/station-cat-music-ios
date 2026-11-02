# 网易云网页收听：1.0.6 隐私差异草稿

2026-10-28（Asia/Singapore） · 候选 **1.0.6（19）** · **Prepared — not published; Apple answers not updated**。

本文是公开说明的文字补丁与问卷差异评估，不是已生效政策、已完成的第三方数据评估或法律保证。没有修改网站、既有生效日期、Apple 答复或审核状态。正文可以准备，但当前证据不足以确认新增网易云网页处理所需的全部 Apple 答复；不能靠全选类别或照搬网易云原生 App 的隐私标签完成申报。

## 基线与修改位置

基线为 **L33 2026-10-27 实际部署包**保留的四语 Station Cat Music 政策区块，生效日期 **2026-10-22**。它包含本机手记、YouTube 和抖音说明，没有网易云内嵌网页说明。L33 交付记录确认既有隐私区块字节得到保留。仓库中的 `platform-v1-privacy-policy.json` 仍是更早的草稿，不能用它替换整页或覆盖已经发布的手记／短片段落。

公开地址为 [简体中文](https://wwwstationcat.org/zh-hans/privacy/#station-cat-music-privacy)、[繁體中文](https://wwwstationcat.org/zh-hant/privacy/#station-cat-music-privacy)、[English](https://wwwstationcat.org/en/privacy/#station-cat-music-privacy)、[日本語](https://wwwstationcat.org/ja/privacy/#station-cat-music-privacy)。本次依据本机已部署包与历史交付记录检查；公开网页工具本次未能重新获取英文页，因此不将历史包核对称为实时线上核验。

仅需对这四个区块作同等修改：

- 替换“适用范围与运营者”的**第二段**，修正“App 内完全没有完整歌曲播放”的绝对表述，区分第三方网页与 Station Cat 原生播放服务。
- 替换“外部平台与分享”的**第一段**，区分内嵌网页收听和用户主动选择的外部打开；原来的第二段及已发布的短片说明保留。
- 在“外部平台与分享”之后、“按需加载的第三方短片”之前增加“网易云网页收听”一节。
- 新生效日期只在实际发布本轮政策时填写；本草稿不预设已生效。运营者、支持邮件、Cloudflare 日志与恢复期限、本机手记和短片段落不因本文被重写。

## 四语政策文字补丁

以下是准备采用的用户说明，须与最终包核对后发布。其中“可能”描述尚未完整核实的提供者处理范围，不表示已验证每一种数据用途；这类概括也不能代替 Apple 的逐项问卷评估。

### 简体中文

**替换适用范围第二段**

App 用于浏览作品、阅读已发布的歌词和创作故事、保存本机收藏与手记，以及使用作品提供的收听入口。部分网易云歌曲入口可在 App 内显示网易云官方网页；其他入口或“外部打开”由系统交给相应浏览器或 App。Station Cat 不提供自己的原生完整歌曲播放服务、后台音乐播放或新增离线歌曲下载，也不销售订阅；使用本 App 无需 Station Cat 账号。网易云网页能否播放、是否要求登录及可用地区由网易云决定。网站其他服务与第三方音乐平台另有各自的隐私规则。

**替换外部平台与分享第一段**

选择“外部打开”、其他外部收听入口或分享时，系统将链接交给你选择的应用或服务，适用其独立的网页存储、账号、地区和收听规则。选择 App 内的网易云网页入口时，网页在本 App 中载入，处理方式见下一节。Station Cat 的原生代码不会读取第三方登录表单中的凭据，也不会读取或上传第三方网页正文、购买记录或实际播放记录；你主动在第三方页面输入的内容由该服务处理。

**新增一节：网易云网页收听**

只有当你点按作品提供的网易云网页收听入口后，App 才会先向 Station Cat 重新核对该作品及收听链接，再连接网易云官方歌曲网页及该网页加载的资源。仅浏览作品详情不会预加载网易云网页。网页的资源连接可能在你按下网页内的播放按钮之前发生；页面成功载入也不表示歌曲已开始或能够完整播放。

这些连接会向相应服务提供网络请求所需的信息。网易云及其网页资源提供者可能依据各自政策处理 IP 地址、浏览器信息，以及页面请求、收听或其他使用信息；如果你在网页内登录或输入资料，相应资料会交给该服务处理。Station Cat 不替第三方决定其保存期限、关联身份、推荐或广告用途。请查阅[网易云音乐隐私政策](https://st.music.163.com/official-terms/privacy)及页面提供的说明。本站日志和支持邮件的保留期限不适用于第三方记录。

网页使用临时会话存储；关闭网页或切至后台会停止并移除当前 App 内网页会话，重新打开或重试会再次核验并建立会话。外部浏览器或网易云 App 的存储是独立的。临时存储不表示第三方不收集信息、不使用标识符、不关联数据，或立即删除其服务器记录。App 不提取、代理或下载歌曲音源，不把网页声音接入原生后台播放，也不提供新增离线歌曲保存。

你可以不打开网页、关闭当前网页，或选择外部打开。排查失败时，App 可在当前页面显示导航阶段、阻止类别及经过格式限制的主机名；不显示完整路径、查询参数、网页正文或登录凭据，也不会自动上传这项诊断。你主动通过支持邮件发送的信息仍按支持请求规则处理。

### 繁體中文

**替換適用範圍第二段**

App 用於瀏覽作品、閱讀已發布的歌詞與創作故事、儲存本機收藏與手記，以及使用作品提供的收聽入口。部分網易雲歌曲入口可在 App 內顯示網易雲官方網頁；其他入口或「外部開啟」由系統交給相應瀏覽器或 App。Station Cat 不提供自己的原生完整歌曲播放服務、背景音樂播放或新增離線歌曲下載，也不銷售訂閱；使用本 App 無須 Station Cat 帳號。網易雲網頁能否播放、是否要求登入及可用地區由網易雲決定。網站其他服務與第三方音樂平台另有各自的隱私規則。

**替換外部平台與分享第一段**

選擇「外部開啟」、其他外部收聽入口或分享時，系統將連結交給你選擇的應用程式或服務，適用其獨立的網頁儲存、帳號、地區與收聽規則。選擇 App 內的網易雲網頁入口時，網頁會在本 App 中載入，處理方式見下一節。Station Cat 的原生程式碼不會讀取第三方登入表單中的憑證，也不會讀取或上傳第三方網頁內文、購買紀錄或實際播放紀錄；你主動在第三方頁面輸入的內容由該服務處理。

**新增一節：網易雲網頁收聽**

只有當你點按作品提供的網易雲網頁收聽入口後，App 才會先向 Station Cat 重新核對該作品與收聽連結，再連線至網易雲官方歌曲網頁及該網頁載入的資源。僅瀏覽作品詳情不會預載網易雲網頁。網頁資源可能在你按下網頁內播放按鈕前就已連線；頁面成功載入也不表示歌曲已開始或能夠完整播放。

這些連線會向相應服務提供網路請求所需的資訊。網易雲及其網頁資源提供者可能依據各自政策處理 IP 位址、瀏覽器資訊，以及頁面請求、收聽或其他使用資訊；如果你在網頁內登入或輸入資料，相應資料會交給該服務處理。Station Cat 不替第三方決定其儲存期限、身分關聯、推薦或廣告用途。請查閱[網易雲音樂隱私政策](https://st.music.163.com/official-terms/privacy)及頁面提供的說明。本站日誌與支援郵件的保留期限不適用於第三方紀錄。

網頁使用暫時工作階段儲存；關閉網頁或切至背景會停止並移除目前 App 內的網頁工作階段，重新開啟或重試會再次核驗並建立工作階段。外部瀏覽器或網易雲 App 的儲存是獨立的。暫時儲存不表示第三方不蒐集資訊、不使用識別資訊、不關聯資料，或立即刪除其伺服器紀錄。App 不擷取、代理或下載歌曲音源，不將網頁聲音接入原生背景播放，也不提供新增離線歌曲儲存。

你可以不開啟網頁、關閉目前網頁，或選擇外部開啟。排查失敗時，App 可在目前頁面顯示導覽階段、阻擋類別及經過格式限制的主機名稱；不顯示完整路徑、查詢參數、網頁內文或登入憑證，也不會自動上傳這項診斷。你主動透過支援郵件傳送的資訊仍依支援請求規則處理。

### English

**Replace the second Scope and operator paragraph**

The app lets you browse releases, read published lyrics and stories, keep local favorites and notes, and use a work's listening links. Some NetEase song links can display NetEase's official webpage inside the app; other links or “Open externally” are handed to a browser or app by the system. Station Cat does not provide its own native full-song playback service, background music playback or new offline song downloads, and sells no subscriptions. No Station Cat account is required. NetEase controls whether its webpage can play a song, requires sign-in or is available in a region. Other website services and third-party music services have their own privacy rules.

**Replace the first External services and sharing paragraph**

Choosing “Open externally”, another external listening link or sharing hands the link to your chosen app or service, whose separate website storage, account, regional and listening rules apply. Choosing the in-app NetEase webpage loads it inside this app, as described below. Station Cat's native code does not read credentials entered in third-party sign-in forms, or read or upload third-party page contents, purchase records or actual playback records. Information you choose to enter on a third-party page is processed by that service.

**Add a section: Listening on NetEase webpages**

Only after you tap a work's NetEase webpage listening action does the app recheck the work and listening link with Station Cat, then connect to the official NetEase song page and resources loaded by that page. Merely viewing work details does not preload a NetEase webpage. Page resources may connect before you press the webpage's play button. A loaded page does not establish that a song has started or can play in full.

These connections provide the receiving services with information needed for network requests. NetEase and its page-resource providers may process IP addresses, browser information, and page-request, listening or other usage information under their policies. If you sign in or enter information on the webpage, that service processes the information. Station Cat does not determine a third party's retention, identity linking, recommendation or advertising purposes. See the [NetEase Music Privacy Policy](https://st.music.163.com/official-terms/privacy) and notices on its page. The Station Cat log and support-mail retention periods do not apply to third-party records.

The webpage uses temporary session storage. Closing it or backgrounding the app stops and removes the current in-app web session; reopening or retrying rechecks the link and creates a session again. External browsers and the NetEase app use separate storage. Temporary storage does not establish that a provider collects no information, uses no identifiers, links no data or immediately deletes its server records. The app does not extract, proxy or download song audio, route webpage audio into native background playback, or save new offline songs.

You can decline to open a webpage, close it, or choose external opening. To investigate failures, the current page may show a navigation stage, blocking category and a format-limited hostname. It does not show full paths, query parameters, page contents or sign-in credentials, and this diagnostic is not automatically uploaded. Information you choose to send in support mail remains subject to the support-request rules.

### 日本語

**適用範囲の第2段落を置換**

本アプリでは、作品の閲覧、公開された歌詞や物語の閲覧、端末内のお気に入りやノートの保存、作品の配信リンクの利用ができます。一部の NetEase 楽曲リンクは、アプリ内に NetEase の公式 Web ページを表示できます。その他のリンクや「外部で開く」は、システムがブラウザやアプリに渡します。Station Cat 独自のネイティブなフル楽曲再生サービス、バックグラウンド音楽再生、新規オフライン楽曲ダウンロード、サブスクリプション販売は提供しません。Station Cat アカウントは不要です。Web ページでの再生可否、ログインの必要性、利用可能地域は NetEase が決定します。ウェブサイトの他サービスと第三者の音楽サービスには、それぞれのプライバシールールがあります。

**外部サービスと共有の第1段落を置換**

「外部で開く」、その他の外部配信リンク、共有を選ぶと、システムが選択先のアプリやサービスへリンクを渡し、そのサービス独自の Web ストレージ、アカウント、地域、再生のルールが適用されます。アプリ内の NetEase Web ページを選ぶ場合は、本アプリ内にページを読み込みます。処理については次の節をご確認ください。Station Cat のネイティブコードは、第三者のログインフォームに入力された認証情報を読み取りません。また、第三者のページ本文、購入記録、実際の再生記録を読み取ったり送信したりしません。第三者のページで自ら入力した情報は、そのサービスが処理します。

**追加する節：NetEase の Web ページで聴く**

作品の NetEase Web ページを開く操作を選んだ後にのみ、アプリは Station Cat で作品と配信リンクを再確認し、NetEase の公式楽曲ページと、そのページが読み込むリソースへ接続します。作品の詳細を見るだけでは NetEase の Web ページを先読みしません。Web ページ内の再生ボタンを押す前に、ページのリソースへの接続が発生する場合があります。ページの読み込み完了は、楽曲の再生開始や全編再生の可否を示すものではありません。

これらの接続では、通信先のサービスへネットワークリクエストに必要な情報が渡ります。NetEase とページ内リソースの提供者は、それぞれのポリシーに従い、IP アドレス、ブラウザ情報、ページのリクエスト、聴取やその他の利用情報を処理する場合があります。Web ページでログインしたり情報を入力したりすると、そのサービスが情報を処理します。第三者の保存期間、本人との関連付け、推薦や広告の用途を Station Cat が決定することはありません。[NetEase Music プライバシーポリシー](https://st.music.163.com/official-terms/privacy)とページ上の説明をご確認ください。Station Cat のログやサポートメールの保存期間は、第三者の記録には適用されません。

Web ページは一時的なセッションストレージを使用します。ページを閉じるかアプリがバックグラウンドに移ると、現在のアプリ内 Web セッションを停止して破棄します。再度開く操作や再試行では、リンクを再確認してセッションを作成します。外部ブラウザや NetEase アプリのストレージは独立しています。一時的なストレージは、提供者による情報収集、識別子の利用、データの関連付けがないことや、サーバー記録が直ちに削除されることを意味しません。本アプリは楽曲音声の抽出、代理配信、ダウンロードを行わず、Web ページの音声をネイティブのバックグラウンド再生に接続せず、新たなオフライン楽曲を保存しません。

Web ページを開かない、現在のページを閉じる、外部で開く、といった操作を選べます。問題の調査用に、現在のページに遷移の段階、ブロックの分類、形式を制限したホスト名を表示する場合があります。完全なパス、クエリパラメータ、ページ本文、ログイン認証情報は表示せず、この診断情報を自動送信しません。自らサポートメールで送った情報には、サポート依頼に関するルールが適用されます。

## 代码事实与文字边界

依据 `Core/NetEaseListening.swift`、`Core/NetEaseListeningSession.swift`、`StationCatMusic/NetEaseListeningView.swift` 及 `PlatformMusicDetailView.swift`：初始歌曲必须来自已发布的网易云入口，载入及重试前重新核验；文档导航限于明确的官方主机。此限制不是第三方页面的网络子资源白名单，不能据此声称只有两个主机接收数据。

会话使用 `WKWebsiteDataStore.nonPersistent()`，要求用户操作媒体，禁止相机／麦克风捕获，关闭或进入后台销毁网页；原生代码不读取页面正文或登录表单。导航诊断保存在当前会话内，没有自动上传代码。没有观察到这些原生代码事实能证明提供者的服务器保留、分析、广告、账号关联或跨服务跟踪行为。当前没有真实完整歌曲播放结论，页面加载成功不得写成播放验收成功。

App 内已有四语简短数据处理提示，但位于网页收听页；打开该页即开始核验和载入。本次没有声称用户一定在第三方连接前读过该提示。发布前应让用户在选择内嵌入口时能够找到完整说明与提供者政策，并核对所需的具体告知／许可流程；普通“打开网页”按钮不能自动替代任何经核实确有需要的跟踪许可。

## Apple 现有八类覆盖什么

最后核对的已发布答复来自 2026-10-20，1.0.3（16）的 2026-10-23 最终交付记录明确保留这些答复，没有新保存或发布。八类均按 App Functionality、与用户关联、非 Tracking 记录。以下是它们已有的 **Station Cat 范围**，不是对网易云网页的新增分类结论。

| 现有类别 | 已有依据与范围 | 本次不能据此推导的结论 |
| --- | --- | --- |
| Name | 用户主动发送支持邮件时提供的称呼 | 不代表已覆盖网易云登录／账号用途。 |
| Email Address | 支持请求的发件与回复地址 | 不代表网易云是否收到、保留或如何使用登录联系信息已核实。 |
| Customer Support | 用户自愿提供的支持请求内容 | 不等于网页浏览或收听事件的分类。 |
| Coarse Location | Station Cat 服务日志的 IP 推导地区与可用平台选择 | 不能据此判定网易云位置处理或推荐用途。 |
| Precise Location | 既有日志保留 IP 推导坐标的保守披露 | 不是 GPS 使用或实际定位精度证据，也不是网易云收集精确位置的证据。 |
| Product Interaction | Station Cat 请求中的作品／资源标识与时间 | 不自动覆盖提供者可能保存的网页、收听、广告交互及用途。 |
| Performance Data | Station Cat 调用日志中的耗时和 CPU 时间 | 不证明网易云性能或行为分析只用于 App Functionality。 |
| Other Diagnostic Data | Station Cat 的网络来源、User-Agent、状态、错误与限流计数 | 不证明提供者没有其他标识、账号关联或数据用途。 |

旧版评估保留这八类的第三方前提是：正式短片为空，用户不能进入提供者播放器。网易云网页收听现在是可达的新路径，因此不能继续套用“没有第三方处理路径”的前提。已有类别可能与新处理重叠，但类别名称重叠不等于用途、身份关联及 Tracking 已一致。

## 完成新 WebView 申报还缺的事实

目前没有足够证据为网易云路径决定最终新增类别、用途、关联身份或 Tracking。需要完成下列具体核对，保留未知项而不是猜勾：

1. **政策适用范围与现行正文：** 能读取并核对适用于官方歌曲网页及其资源的现行政策、版本／生效日期、运营者及涉及的服务提供者。原生网易云 App 的权限清单不能直接代表本 WKWebView 的实际处理。
2. **实际数据与保留：** 区分仅满足即时请求的传输，和提供者在请求后仍可访问的记录；核对网页是否保存 Cookie／标识符、所访问歌曲或其他使用记录。临时本机存储不能回答服务器是否保留。
3. **账号与交互分支：** 核对未登录、用户自愿网页登录、按播放按钮和未播放时分别涉及什么数据。原生代码不读凭据，不代表表单的接收方不收集用户输入。
4. **实际用途、关联及 Tracking：** 核对网络／使用信息用于功能、安全、分析、推荐、广告中的哪些用途，是否与账号或其他标识关联，是否与其他公司的数据结合用于定向广告／衡量或提供给数据经纪商。出现广告本身不等于 Apple 定义的 Tracking；同样，未集成广告 SDK 也不证明网页不发生它。
5. **最终候选的一致性：** 将上述证据映射到 Apple 类别、用途、关联及 Tracking，必要时调整产品许可／拒绝路径，再核对公开政策、App 内提示、实际签名包和 Apple 保存结果。若证据仍不足，应明确记录待核实项，不能将其写为“问卷已覆盖”。

本机收藏、手记、最近查看和此次诊断没有新增自动上传，因此不因新增网页而猜报这些本机资料。也不应仅因服务商总政策提到 GPS、联系人、付款、相机或麦克风，就把那些字段全部当作本功能已收集。

## 官方引用与本次读取结果

已正常读取 [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)，其中 “Your app has web views” 指明受控 WebView 的网络收集需要申报，开放网页浏览另有例外；Data collection、Data use、Data linked to the user 和 Tracking 各节分别要求核对实际保留、用途、身份关联与跟踪。本功能只打开受限的作品页面，不能把它当成开放网页浏览来免除评估。Apple 同页也说明只在设备处理的信息与远程收集不同，并要求处理变化时更新答复。这些规则是评估依据，不是对本候选的预先批准。

本次尝试读取的网易云官方政策地址是 **https://st.music.163.com/official-terms/privacy**。该地址由公开的网易云站点条款链接指向。2026-10-28 的网页工具调用返回 `Internal Error ()`，附加说明为 `URL ... cannot be opened (non-retryable error)`；**没有返回 HTTP 状态码、政策正文或明确的安全拒绝原因**。因此只能记录为“网页工具无法获取，具体原因未确定”，不能声称是 HTTP 403、纯正文提取失败、断网或安全策略已明确拒绝。没有重复调用该地址，也没有通过镜像、代理或其他网络通道绕过。

另有先前产品页面调查中，浏览器工具对 `music.163.com` 实际歌曲页面明确报告站点安全策略拒绝。这是**不同地址、不同工具的既有记录**，不应拿来替代本次政策 URL 的错误分类。本文没有重试该被拒绝的歌曲地址，也没有发起真实网易云歌曲播放探针。

本次公开政策 `https://wwwstationcat.org/en/privacy/` 的网页工具读取返回 `Failed to fetch ...: Cache miss`；故采用 L33 部署包和交付记录作为文字基线，发布任务仍须重新核对实际线上四语页面。网易云政策链接目前是待验证可读性的引用，不能把它当作已经读取并完成分类的政策依据。

## 审核文案需要同步的最小范围

四语商店描述与审核备注应将“收听按钮只跳转第三方平台”和“App 内完全不播放完整歌曲”的旧表述改为：部分已发布网易云歌曲可在 App 内打开官方网页，播放、登录及地区条件由提供者决定；用户仍可外部打开；Station Cat 不提供自己的原生歌曲音源、后台播放或新增离线歌曲下载。审核步骤应包括进入该网页、由用户点按网页播放、遇到限制时重试／外部打开、关闭和后台停止。不能写成真实完整歌曲已验证通过。

本文完成的是四语文字草稿和差异判断；**政策尚未发布，Apple 问卷尚未更新，网易云实际数据处理映射尚未完成**。

## Additional access check (2026-10-28)

After the web extraction failure recorded above, the primary agent attempted the exact official privacy URL in the in-app browser. The browser explicitly refused access under its site-safety policy for st.music.163.com. No alternate browser, raw request or indirect execution was used after that refusal. The user has been asked to provide the relevant official policy text manually. Privacy publication and the formal review submission remain pending this factual verification; an uploaded binary alone does not close this issue.
