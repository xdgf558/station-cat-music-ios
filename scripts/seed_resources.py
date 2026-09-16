from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
rows='''discover|Discover|发现|發現|見つける
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
