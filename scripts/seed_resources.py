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
# Embedded hero newlines are restored from escaped markers after splitting rows.
rows=rows.replace('A little music.\nA slower day.','A little music.\\nA slower day.').replace('听一点音乐，\n让日常慢下来。','听一点音乐，\\n让日常慢下来。').replace('聽一點音樂，\n讓日常慢下來。','聽一點音樂，\\n讓日常慢下來。').replace('音楽とともに、\nゆっくり過ごす。','音楽とともに、\\nゆっくり過ごす。')
translations={x:{} for x in ['en','zh-Hans','zh-Hant','ja']}
for row in rows.splitlines():
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
