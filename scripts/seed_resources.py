from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
rows='''cancel|Cancel|取消|取消|キャンセル
recent|Recently played|最近播放|最近播放|最近再生した曲
noRecent|No listening history yet.|暂无播放记录。|暫無播放記錄。|再生履歴はありません。
historyEnabled|Save listening history|保存播放历史|儲存播放歷史|再生履歴を保存
clearHistory|Clear listening history|清空播放历史|清空播放歷史|再生履歴を消去
clearHistoryConfirm|Clear this library’s listening history?|清空此音乐库的播放历史？|清空此音樂庫的播放歷史？|このライブラリの再生履歴を消去しますか？
clearCache|Clear temporary cache|清除临时缓存|清除暫存快取|一時キャッシュを消去
localCleanup|Remove other accounts’ local data|清理其他账号的本机资料|清理其他帳號的本機資料|他のアカウントの端末データを整理
localCleanupConfirm|Remove synced data for inactive accounts?|清理已退出账号的已同步资料？|清理已登出帳號的已同步資料？|未使用アカウントの同期済みデータを削除しますか？
localCleanupDetail|Only synced copies on this device are removed. Your current account, guest data and unsynced changes are kept. Server accounts are not deleted.|仅移除这台设备上的已同步副本，保留当前账号、游客资料和未同步操作，不会删除服务器账号。|僅移除這台裝置上的已同步副本，保留目前帳號、訪客資料和未同步操作，不會刪除伺服器帳號。|この端末の同期済みコピーだけを削除します。現在のアカウント、ゲストデータ、未同期の変更は保持します。サーバーのアカウントは削除しません。
localCleanupDone|Synced local copies removed. Unsent changes were kept.|已清理本机副本，未同步操作已保留。|已清理本機副本，未同步操作已保留。|端末のコピーを削除しました。未同期の変更は保持しました。
localCleanupNothing|No eligible copies to remove. Active accounts and unsynced changes were kept.|没有可清理的副本，当前账号及未同步操作已保留。|沒有可清理的副本，目前帳號及未同步操作已保留。|削除できるコピーはありません。使用中のアカウントと未同期の変更は保持しました。
localCleanupFailed|Could not finish removing local copies. Please retry.|未能完成本机资料清理，请重试。|未能完成本機資料清理，請重試。|端末データの整理を完了できませんでした。再試行してください。
localCleanupChanged|Account changed. Please review and confirm again.|账号已切换，请重新确认。|帳號已切換，請重新確認。|アカウントが変更されました。もう一度確認してください。
syncNow|Sync now|立即同步|立即同步|今すぐ同期
libraryLocal|Saved on this device.|已保存在此设备。|已儲存在此裝置。|このデバイスに保存済み。
libraryPending|Changes awaiting sync. Retry when connected.|更改待同步，联网后可重试。|變更待同步，連線後可重試。|同期待ちです。接続後に再試行してください。
librarySynced|Account library synced.|账号音乐库已同步。|帳號音樂庫已同步。|アカウントのライブラリを同期しました。
libraryConflict|A sync conflict occurred. Review the current state before retrying.|同步发生冲突，请核对当前状态后重试。|同步發生衝突，請核對目前狀態後重試。|同期が競合しました。現在の状態を確認してください。
libraryError|Could not save your library. Please retry.|音乐库保存失败，请重试。|音樂庫儲存失敗，請重試。|ライブラリを保存できませんでした。再試行してください。
privacy|Privacy|隐私说明|隱私說明|プライバシー
terms|Terms|服务条款|服務條款|利用規約
support|Support|联系支持|聯絡支援|サポート
shareMusic|Share link|分享链接|分享連結|リンクを共有
linkUnavailable|This music link is unavailable.|此音乐链接暂不可用。|此音樂連結暫不可用。|この音楽リンクは利用できません。
playing|Playing|正在播放|正在播放|再生中
queue|Play queue|播放队列|播放佇列|再生キュー
shuffle|Shuffle|随机播放|隨機播放|シャッフル
repeat|Repeat|循环|循環|リピート
repeat.off|In order|顺序播放|順序播放|順番に再生
repeat.all|Repeat all|列表循环|列表循環|すべてリピート
repeat.one|Repeat one|单曲循环|單曲循環|1 曲リピート
sleepTimer|Sleep timer|睡眠定时|睡眠定時|スリープタイマー
minutes|min|分钟|分鐘|分
on|On|开启|開啟|オン
off|Off|关闭|關閉|オフ
remove|Remove|移除|移除|削除
clearQueue|Clear and stop|清空并停止|清空並停止|消去して停止
queueSkipped|An unavailable track was skipped.|已跳过不可用的歌曲。|已跳過無法播放的歌曲。|再生できない曲をスキップしました。
queueUnavailable|No playable tracks remain. Choose another track.|队列中没有可播放歌曲，请选择其他歌曲。|佇列中沒有可播放歌曲，請選擇其他歌曲。|再生できる曲がありません。別の曲を選んでください。
headphonesDisconnected|Headphones disconnected. Playback paused.|耳机已断开，播放已暂停。|耳機已斷開，播放已暫停。|イヤホンが切断され、再生を一時停止しました。
mediaReset|Audio service restarted. Tap play to continue.|音频服务已重启，点击播放继续。|音訊服務已重新啟動，點選播放繼續。|音声サービスが再起動しました。再生ボタンで再開してください。
sleepFinished|Sleep timer ended. Playback paused.|睡眠定时结束，已暂停播放。|睡眠定時結束，已暫停播放。|タイマーが終了し、再生を一時停止しました。
discover|Discover|发现|發現|見つける
catalog|Library|曲库|曲庫|ライブラリ
library|You|我的|我的|マイページ
mockBadge|M1 · Preview|M1 · 本地预览|M1 · 本機預覽|M1 · プレビュー
heroTitle|A little music.\nA slower day.|听一点音乐，\n让日常慢下来。|聽一點音樂，\n讓日常慢下來。|音楽とともに、\nゆっくり過ごす。
heroSubtitle|Find a quiet moment with Station Cat.|与 Station Cat 一起，留一段安静时光。|與 Station Cat 一起，留一段安靜時光。|Station Cat と、穏やかなひとときを。
explore|Explore the library|探索曲库|探索曲庫|ライブラリを見る
tonight|Tonight’s selection|今夜先听|今夜先聽|今夜のセレクション
mockOnly|Sample content|示例内容|示例內容|サンプル
mockExplanation|Fictional local preview. Live music and accounts are not connected.|此预览使用虚构的本地数据，尚未连接真实曲库与账号。|此預覽使用虛構的本機資料，尚未連接真實曲庫與帳號。|架空のローカルデータです。実際の音楽やアカウントには未接続です。
search|Search sample tracks|搜索示例歌曲|搜尋示例歌曲|サンプル曲を検索
loading|Loading…|正在载入…|正在載入…|読み込み中…
unavailable|Unable to load|暂时无法载入|暫時無法載入|読み込めません
unavailableDetail|Try again later. Your membership status has not changed.|请稍后重试，会员状态没有因此改变。|請稍後重試，會員狀態沒有因此改變。|後でもう一度お試しください。会員資格は変更されていません。
refreshRetained|Refresh failed. Showing the previous list.|刷新失败，暂时显示上次的列表。|重新整理失敗，暫時顯示上次的清單。|更新できませんでした。前回のリストを表示しています。
retry|Try again|重试|重試|再試行
empty|No tracks yet|还没有歌曲|還沒有歌曲|曲はまだありません
sampleTrack|Sample · no audio|示例 · 无音频|示例 · 無音訊|サンプル · 音源なし
favorite|Favorite|收藏|收藏|お気に入り
guest|Listening as a guest|以游客身份浏览|以訪客身分瀏覽|ゲストとして表示
authNotReady|Sign-in will be connected in the authentication milestone.|账号登录将在认证阶段接入。|帳號登入將在認證階段接入。|ログイン機能は認証段階で実装します。
favorites|Your favorites|我的收藏|我的收藏|お気に入り
noFavorites|Save a sample track to find it here.|收藏一首示例歌曲，就能在这里找到。|收藏一首示例歌曲，就能在這裡找到。|サンプル曲を保存すると、ここに表示されます。
localSession|Preview favorites last for this session only. Cloud sync is not connected.|预览收藏只保留在本次会话，尚未连接云同步。|預覽收藏只保留在本次工作階段，尚未連接雲端同步。|お気に入りは今回のセッションのみ保存されます。クラウド同期は未接続です。
settings|Settings|设置|設定|設定
language|Language|语言|語言|言語
notPlaying|Not playing|尚未播放|尚未播放|未再生
playbackNotReady|This M1 preview shows the player structure. Authorized audio will be connected in a later milestone.|当前 M1 预览展示播放器结构，后续阶段再接入经过授权的音频播放。|目前 M1 預覽展示播放器結構，後續階段再接入經過授權的音訊播放。|M1ではプレーヤーの構成を確認できます。認証済み音源の再生は後の段階で接続します。
close|Close|关闭|關閉|閉じる
signedIn|Signed in|已登录|已登入|ログイン済み
isolatedAuth|Isolated authentication test environment|隔离认证测试环境|隔離認證測試環境|隔離認証テスト環境
signIn|Sign in with Station Cat|使用 Station Cat 账号登录|使用 Station Cat 帳號登入|Station Cat でログイン
signOut|Sign out|退出登录|登出|ログアウト
error.logout_unconfirmed|Signed out on this device. Server sign-out could not be confirmed.|本机已退出，服务器注销尚未确认。|本機已登出，伺服器登出尚未確認。|この端末ではログアウトしました。サーバーでのログアウトは未確認です。
authCancelled|Sign-in cancelled.|已取消登录。|已取消登入。|ログインをキャンセルしました。
authRetry|Unable to confirm the result. Try again or check deletion progress.|暂时无法确认结果，请重试或查询删除进度。|暫時無法確認結果，請重試或查詢刪除進度。|結果を確認できません。再試行するか削除の進行状況を確認してください。
deleteAccount|Delete account|删除账号|刪除帳號|アカウントを削除
queryDeletion|Check deletion progress|查询删除进度|查詢刪除進度|削除の進行状況
verifyIdentity|Verify your identity|验证身份|驗證身分|本人確認
password|Password|密码|密碼|パスワード
totpCode|Two-step code (if enabled)|二步验证码（如已绑定）|兩步驗證碼（如已綁定）|2 段階認証コード（設定済みの場合）
prepareDeletion|Verify and prepare|验证并准备删除|驗證並準備刪除|確認して削除を準備
confirmDelete|Confirm account deletion|确认删除账号|確認刪除帳號|アカウントの削除を確定
deleteScope|This affects your entire Station Cat account, including music, novels and game data. Accepted deletion signs out all devices. Preparing alone does not delete anything.|这将影响你的整个 Station Cat 账号，包括音乐、小说和游戏数据。删除受理后所有设备将退出登录；仅准备不会删除。|這將影響你的整個 Station Cat 帳號，包括音樂、小說和遊戲資料。刪除受理後所有裝置將登出；僅準備不會刪除。|音楽、小説、ゲームのデータを含む Station Cat アカウント全体が対象です。受理後は全端末がログアウトします。準備だけでは削除されません。
deleteSubscription|Deleting an account does not automatically cancel subscriptions purchased through an app store. Manage those subscriptions with the provider.|删除账号不会自动取消通过应用商店购买的订阅，请在对应平台管理订阅。|刪除帳號不會自動取消透過應用程式商店購買的訂閱，請在對應平台管理訂閱。|アカウント削除でストア経由の購読は自動解約されません。購入先で管理してください。
deleteConfirmDetail|Your progress receipt is saved on this device. Confirm only if you want to delete the entire account.|进度查询凭据已保存在本机。确定删除整个账号后再确认。|進度查詢憑據已保存在本機。確定刪除整個帳號後再確認。|進行状況の照会情報は端末に保存済みです。アカウント全体の削除を希望する場合のみ確定してください。
deleteConfirmed|Deletion request accepted.|删除请求已受理。|刪除請求已受理。|削除リクエストを受理しました。
deletion.prepared|Ready for your confirmation; nothing has been deleted.|已准备，等待你确认，尚未删除。|已準備，等待你確認，尚未刪除。|準備が完了しました。まだ削除されていません。
deletion.preparation_expired|Preparation expired; no deletion was accepted.|准备已过期，未受理删除。|準備已過期，未受理刪除。|準備の期限が切れました。削除は受理されていません。
deletion.accepted|Deletion accepted. You can check progress here.|删除已受理，可在此查询进度。|刪除已受理，可在此查詢進度。|削除が受理されました。ここで進行状況を確認できます。
deletion.processing|Deletion is being processed.|正在处理删除。|正在處理刪除。|削除を処理中です。
deletion.retrying|Processing will be retried; deletion is not complete.|处理将重试，删除尚未完成。|處理將重試，刪除尚未完成。|再試行を待っています。削除は未完了です。
deletion.attention_required|Further processing is required. Your account is blocked; deletion is not complete.|需要进一步处理。账号已停止访问，删除尚未完成。|需要進一步處理。帳號已停止存取，刪除尚未完成。|追加の処理が必要です。アカウントへのアクセスは停止中ですが、削除は未完了です。
deletion.completed|Account deletion completed.|账号删除已完成。|帳號刪除已完成。|アカウント削除が完了しました。'''
rows+='''
isolatedMusic|Isolated test catalog|隔离测试曲库|隔離測試曲庫|隔離テストライブラリ
albums|Albums|专辑|專輯|アルバム
allTracks|All songs|全部歌曲|全部歌曲|すべての曲
access.free|Free|免费|免費|無料
access.vip|VIP|VIP 专享|VIP 專享|VIP
access.preview|Preview available|可试听|可試聽|試聴可能
access.unavailable|Unavailable|暂不可用|暫不可用|利用不可
playbackDenied|Playback access expired or is unavailable. Try playing again.|播放资格已失效或暂不可用，请重新播放。|播放資格已失效或暫不可用，請重新播放。|再生権限が失効したか利用できません。再度お試しください。
play|Play|播放|播放|再生
pause|Pause|暂停|暫停|一時停止
previous|Previous song|上一首|上一首|前の曲
next|Next song|下一首|下一首|次の曲
preview|Play preview|试听|試聽|試聴
seek|Playback position|播放进度|播放進度|再生位置'''
# R3 interface, loading diagnostics, version notes and offline controls.
rows += (
 '\n'
 'noFavorites|Save a song to find it here.|收藏喜欢的歌曲，就能在这里找到。|收藏喜歡的歌曲，就能在這裡找到。|お気に入りに追加した曲がここに表示されます。\n'
 'orbitIntro|Music is another orbit.\\nFind your quiet place.|音乐是另一种轨道，\\n带你去更安静的地方。|音樂是另一種軌道，\\n帶你去更安靜的地方。|音楽は、もうひとつの軌道。\\n心が静まる場所へ。\n'
 'featuredAlbums|Featured albums|精选专辑|精選專輯|おすすめアルバム\n'
 'tracksCount|tracks|首歌曲|首歌曲|曲\n'
 'viewAll|View all|查看全部|查看全部|すべて見る\n'
 'yourMusicSpace|Your music, at your pace.|收藏喜欢，慢慢聆听。|收藏喜歡，慢慢聆聽。|好きな音楽を、自分のペースで。\n'
 'lyrics|Lyrics|歌词|歌詞|歌詞\n'
 'accountSecurity|Account & security|账号与安全|帳號與安全|アカウントとセキュリティ\n'
 'myMusic|My music|我的音乐|我的音樂|マイミュージック\n'
 'privacyStorage|Privacy & storage|隐私与存储|隱私與儲存|プライバシーとストレージ\n'
 'privacyStorageDetail|History and local data|播放历史与本机资料|播放歷史與本機資料|再生履歴と端末のデータ\n'
 'preferences|Preferences|通用设置|一般設定|一般設定\n'
 'preferencesDetail|App language|应用语言|應用程式語言|アプリの言語\n'
 'aboutSupport|About & support|关于与帮助|關於與支援|このアプリとサポート\n'
 'aboutSupportDetail|Contact, terms and privacy|联系我们、条款与隐私|聯絡我們、條款與隱私|お問い合わせ・規約・プライバシー\n'
 'accountDeletion|Account deletion|账号删除|帳號刪除|アカウントの削除\n'
 'temporaryStorage|Temporary storage|临时存储|暫存空間|一時ストレージ\n'
 'accountStorage|Account data|账号资料|帳號資料|アカウントのデータ\n'
 'cacheDetail|Clear downloaded artwork and temporary cache. Favorites and pending library changes are kept.|清除已下载的封面和临时缓存，保留收藏与待同步的资料库更改。|清除已下載的封面和暫存，保留收藏與待同步的資料庫變更。|ダウンロード済みのアートワークと一時キャッシュを消去します。お気に入りと未同期の変更は保持されます。\n'
 'historyOnDetail|Listening history is on. Manage it in Privacy & storage.|正在保存播放历史，可在“隐私与存储”中管理。|正在儲存播放歷史，可在「隱私與儲存」中管理。|再生履歴を保存しています。「プライバシーとストレージ」で管理できます。\n'
 'historyOffDetail|Listening history is off. Manage it in Privacy & storage.|已关闭播放历史，可在“隐私与存储”中管理。|已關閉播放歷史，可在「隱私與儲存」中管理。|再生履歴はオフです。「プライバシーとストレージ」で管理できます。\n'
 'startupTagline|Let music slow the world down.|让音乐，陪你慢下来。|讓音樂，陪你慢下來。|音楽と、ゆっくり過ごそう。\n'
 'startupLoading|Preparing your music…|正在准备音乐…|正在準備音樂…|音楽を準備しています…\n'
 'startupFailure|Music could not be loaded. Please retry.|音乐暂时未能载入，请重试。|音樂暫時未能載入，請重試。|音楽を読み込めませんでした。再試行してください。\n'
 'startupContinue|Enter the app|先进入 App|先進入 App|アプリを開く\n'
 'startupFailure.timeout|The music connection timed out. Try another Wi-Fi network or cellular data.|连接音乐服务超时，请尝试切换 Wi-Fi 或使用蜂窝网络。|連線音樂服務逾時，請嘗試切換 Wi-Fi 或使用行動網路。|音楽サービスへの接続がタイムアウトしました。別の Wi-Fi またはモバイル通信をお試しください。\n'
 'startupFailure.offline|No network connection is available to this app. Check Wi-Fi or cellular access.|App 当前无法使用网络，请检查 Wi-Fi 或蜂窝网络权限。|App 目前無法使用網路，請檢查 Wi-Fi 或行動網路權限。|アプリがネットワークを利用できません。Wi-Fi またはモバイル通信の設定をご確認ください。\n'
 'startupFailure.connection|Cannot connect to the music service. Try another Wi-Fi network or cellular data.|无法连接音乐服务，请尝试其他 Wi-Fi 或蜂窝网络。|無法連線音樂服務，請嘗試其他 Wi-Fi 或行動網路。|音楽サービスに接続できません。別の Wi-Fi またはモバイル通信をお試しください。\n'
 'startupFailure.service|The music service could not complete the request. Please try again later.|音乐服务暂时无法完成请求，请稍后重试。|音樂服務暫時無法完成請求，請稍後重試。|音楽サービスがリクエストを処理できませんでした。しばらくしてから再試行してください。\n'
 'startupFailure.configuration|Music access is not enabled in this build.|当前版本尚未启用音乐服务。|目前版本尚未啟用音樂服務。|このビルドでは音楽サービスが有効になっていません。\n'
 'startupFailure.payload|The music response could not be read. Please retry.|音乐数据未能正确读取，请重试。|音樂資料未能正確讀取，請重試。|音楽データを読み取れませんでした。再試行してください。\n'
 'startupFailure.unknown|Music could not be loaded. Please retry.|音乐暂时未能载入，请重试。|音樂暫時未能載入，請重試。|音楽を読み込めませんでした。再試行してください。\n'
 'appVersion|Version|版本号|版本號|バージョン\n'
 'releaseNotes|What’s new|更新内容|更新內容|更新内容\n'
 'thisUpdate|In this update|本次更新|本次更新|今回の更新\n'
 'releaseArtwork|Faster artwork loading with shared requests and reusable thumbnails.|优化封面加载，多个页面共用图片请求与缩略图缓存。|改善封面載入，多個頁面共用圖片請求與縮圖快取。|画像リクエストとサムネイルを共有し、ジャケット表示を高速化。\n'
 'releasePlayback|Improved playback startup and authorization renewal; fixed the system artwork crash.|改善起播速度和播放续期，修复系统封面导致的闪退。|改善起播速度與播放續期，修復系統封面造成的閃退。|再生開始と再認証を改善し、システムのジャケット表示によるクラッシュを修正。\n'
 'releaseInterface|Refreshed launch screen and a clearer, grouped My Library.|更新启动展示页，将「我的」整理为清晰的分级页面。|更新啟動展示頁，將「我的」整理為清楚的分級頁面。|起動画面を更新し、マイライブラリを階層別に整理。\n'
 'offlineMusic|Offline music|离线缓存|離線快取|オフライン音楽\n'
 'offlineSummary|Saved songs and storage|已缓存的歌曲与空间管理|已快取的歌曲與空間管理|保存済みの曲とストレージ\n'
 'offlineSpace|Storage used|已用空间|已用空間|使用容量\n'
 'offlineAuto|Auto-save permanently free songs I play|自动缓存听过的长期免费歌曲|自動快取聽過的長期免費歌曲|再生した常時無料の曲を自動保存\n'
 'offlineDetail|Only permanently free songs can be saved. Enable auto-save to download after playback begins, including over cellular. A complete, verified song works offline for up to 7 days; reconnect and save again to renew. VIP and limited-time free songs stay online.|仅缓存长期免费歌曲。开启自动缓存后，开始播放便会下载，可能使用移动数据。完整校验后可离线听最多 7 天，到期请联网重新缓存。VIP 和限时免费歌曲仍需联网。|僅快取長期免費歌曲。開啟自動快取後，開始播放便會下載，可能使用行動數據。完整校驗後可離線聽最多 7 天，到期請連網重新快取。VIP 和限時免費歌曲仍需連網。|常時無料の曲のみ保存できます。自動保存は再生開始後にモバイル通信でもダウンロードします。検証済みの曲は最大7日間オフラインで再生可能。期限後は接続して再保存してください。VIP・期間限定無料の曲には通信が必要です。\n'
 'offlineEmpty|No complete downloads yet. Save a permanently free song from its player.|暂无完整缓存，可在长期免费歌曲的播放器中保存。|暫無完整快取，可在長期免費歌曲的播放器中儲存。|まだ保存済みの曲はありません。常時無料の曲のプレーヤーから保存できます。\n'
 'offlineUntil|Available until|可用至|可用至|有効期限\n'
 'offlineClear|Clear downloaded audio|清除已缓存音频|清除已快取音訊|保存した音声を削除\n'
 'offlineSave|Save for offline listening|缓存供离线收听|快取供離線收聽|オフライン用に保存\n'
 'offlineSaving|Downloading and verifying…|正在下载并校验…|正在下載並校驗…|ダウンロード・検証中…\n'
 'offlineSaved|Available offline|可离线播放|可離線播放|オフライン再生可能\n'
 'offlinePlaying|Playing saved audio|正在离线播放|正在離線播放|保存した音声を再生中\n'
 'offlineFailed|Could not save this song. Check your connection and try again.|缓存未完成，请检查网络后重试。|快取未完成，請檢查網路後重試。|保存できませんでした。接続を確認して再試行してください。\n'
 'offlineFull|Offline storage is full. Remove some downloads and try again.|缓存空间已满，请删除部分已缓存歌曲后重试。|快取空間已滿，請刪除部分已快取歌曲後重試。|容量が不足しています。保存した曲を削除して再試行してください。\n'
 'releaseOffline|Resume interrupted playback after tapping play. Save permanently free songs for offline listening and manage downloads.|播放中断后点击播放可从原进度继续；支持长期免费歌曲离线缓存及空间管理。|播放中斷後點擊播放可從原進度繼續；支援長期免費歌曲離線快取及空間管理。|中断後は再生をタップすると元の位置から再開。常時無料曲のオフライン保存と容量管理に対応。\n'
)
rows += '\nofflineUnavailable|Expired or unavailable · Remove to free space|已过期或不可用 · 可删除以释放空间|已過期或無法使用 · 可刪除以釋放空間|期限切れ・利用不可 · 削除して空き容量を確保\n'
# Embedded hero newlines are restored from escaped markers after splitting rows.
rows=rows.replace('A little music.\nA slower day.','A little music.\\nA slower day.').replace('听一点音乐，\n让日常慢下来。','听一点音乐，\\n让日常慢下来。').replace('聽一點音樂，\n讓日常慢下來。','聽一點音樂，\\n讓日常慢下來。').replace('音楽とともに、\nゆっくり過ごす。','音楽とともに、\\nゆっくり過ごす。')
translations={x:{} for x in ['en','zh-Hans','zh-Hant','ja']}
for row in rows.splitlines():
 if not row: continue
 key,*values=row.split('|');assert len(values)==4,key
 for lang,value in zip(translations,values):translations[lang][key]=value.replace('\\n','\n')
(root/'Resources/Localizations.json').write_text(json.dumps(translations,ensure_ascii=False,indent=2)+'\n')
fixture={'data':{'items':[{'id':'sample-night-window','title':'夜窗 · Night Window','artist':'Station Cat · Sample','durationSeconds':180,'audioVersion':1,'access':'free'},{'id':'sample-slow-morning','title':'慢一点的清晨 · Slow Morning','artist':'Station Cat · Sample','durationSeconds':210,'audioVersion':1,'access':'vip'},{'id':'sample-paper-moon','title':'纸月亮 · Paper Moon','artist':'Station Cat · Sample','durationSeconds':200,'audioVersion':1,'access':'preview'}],'nextCursor':None},'requestId':'fixture-catalog','serverNow':'2026-09-16T00:00:00Z'}
(root/'contracts/fixtures/catalog.json').write_text(json.dumps(fixture,ensure_ascii=False,indent=2)+'\n')

errors=json.loads((root/"contracts/error-localizations.json").read_text())
path=root/"Resources/Localizations.json"
values=json.loads(path.read_text())
for locale, entries in errors.items(): values[locale].update(entries)
path.write_text(json.dumps(values,ensure_ascii=False,indent=2)+"\n")
