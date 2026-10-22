from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
rows='''notebookTextLimits|Titles can contain up to 120 characters and note text up to 8,000.|标题最多 120 字，正文最多 8,000 字。|標題最多 120 字，內文最多 8,000 字。|タイトルは120文字、本文は8,000文字まで入力できます。
notebookTopicLimits|Topic names can contain up to 40 characters and must be unique.|主题名称最多 40 字，且不能与已有主题重名。|主題名稱最多 40 字，且不能與既有主題重名。|テーマ名は40文字以内で、既存のテーマと異なる名前にしてください。
releaseNotebook|Write your own notes from a song page or the notebook, with an optional link to a work.|可从歌曲页或“我的手记”记录自己的想法，并按需关联作品。|可從歌曲頁或「我的手記」記錄自己的想法，並依需要關聯作品。|曲のページやマイノートから自分の言葉を記録し、必要に応じて作品に関連付けられます。
releaseNotebookOrganization|Organize notes into your own topics and search titles or text to find them again.|按自建主题整理手记，通过标题或正文搜索，找回写下的内容。|依自建主題整理手記，透過標題或內文搜尋，找回寫下的內容。|自分で作ったテーマでノートを整理し、タイトルや本文から検索できます。
releaseNotebookLocal|Read, edit and delete saved notes offline. Notes stay on this device and are not uploaded or synced across devices.|已保存的手记可离线查看、编辑和删除，仅保存在本机，不上传或跨设备同步。|已儲存的手記可離線查看、編輯及刪除，僅儲存在本機，不上傳或跨裝置同步。|保存したノートはオフラインでも閲覧・編集・削除できます。この端末のみに保存され、アップロードや端末間同期は行いません。
releaseBundledClips|This update also includes YouTube and Douyin players. Tap to connect when a clip is published; no videos are downloaded. Listening still opens your music platform.|本次同时包含 YouTube 与抖音短片播放器，有已发布内容时点击后才连接，不提供视频下载；歌曲仍前往音乐平台收听。|本次同時包含 YouTube 與抖音短片播放器，有已發佈內容時點擊後才連線，不提供影片下載；歌曲仍前往音樂平台收聽。|YouTube と Douyin のプレーヤーも含みます。公開動画がある場合にタップして接続し、動画はダウンロードしません。楽曲は引き続き外部の音楽サービスで聴けます。
notebookTitle|My notebook|我的手记|我的手記|マイノート
notebookIntro|Keep your thoughts about music for yourself.|把听歌时的想法，留给自己。|把聽歌時的想法，留給自己。|音楽から生まれた思いを、自分のために。
notebookSearch|Search notes|搜索手记|搜尋手記|ノートを検索
notebookAll|All|全部|全部|すべて
notebookUncategorized|Uncategorized|未分类|未分類|未分類
notebookNew|New note|新建手记|新增手記|ノートを作成
notebookManageTopics|Manage topics|管理主题|管理主題|テーマを管理
notebookEmpty|No notes yet|还没有手记|還沒有手記|ノートはまだありません
notebookEmptyDetail|Start with a song and write down your own thoughts.|从一首歌开始，记下属于你的想法。|從一首歌開始，記下屬於你的想法。|一曲をきっかけに、自分の思いを書き留めましょう。
notebookNoResults|No matching notes|没有匹配的手记|沒有符合的手記|一致するノートがありません
notebookNoResultsDetail|Try another keyword or topic.|试试其他关键词或主题。|試試其他關鍵字或主題。|別のキーワードやテーマをお試しください。
notebookLoading|Loading notes…|正在读取手记…|正在讀取手記…|ノートを読み込み中…
notebookEdit|Edit note|编辑手记|編輯手記|ノートを編集
notebookNoteTitle|Note title|手记标题|手記標題|ノートのタイトル
notebookBodyPlaceholder|Write your thoughts…|写下你的想法…|寫下你的想法…|思いを書き留めましょう…
notebookBody|Your thoughts|你的想法|你的想法|あなたの思い
notebookWork|Linked work|关联作品|關聯作品|関連する作品
notebookChooseWork|Choose a song|选择歌曲|選擇歌曲|曲を選択
notebookNoWork|No linked song|不关联歌曲|不關聯歌曲|曲を関連付けない
notebookWorkUnavailable|Connect to update the linked work|关联作品待联网更新|關聯作品待連網更新|接続後に関連作品を更新
notebookOpenWork|View song|查看歌曲|查看歌曲|曲を表示
notebookTopic|Topic|主题|主題|テーマ
notebookSave|Save note|保存手记|儲存手記|ノートを保存
notebookLocalOnly|Notes stay on this device. They are not uploaded or synced across devices.|手记仅保存在此设备，不上传或跨设备同步。|手記僅儲存在此裝置，不上傳或跨裝置同步。|ノートはこの端末のみに保存されます。アップロードや端末間同期は行いません。
notebookDelete|Delete note|删除手记|刪除手記|ノートを削除
notebookDeleteConfirm|Delete this note?|删除这篇手记？|刪除這篇手記？|このノートを削除しますか？
notebookDeleteDetail|This cannot be undone.|删除后无法恢复。|刪除後無法復原。|削除後は元に戻せません。
notebookDiscardConfirm|Discard unsaved changes?|放弃未保存的修改？|放棄未儲存的修改？|未保存の変更を破棄しますか？
notebookDiscard|Discard changes|放弃修改|放棄修改|変更を破棄
notebookKeepEditing|Keep editing|继续编辑|繼續編輯|編集を続ける
notebookNewTopic|New topic|新建主题|新增主題|テーマを作成
notebookRenameTopic|Rename topic|重命名主题|重新命名主題|テーマ名を変更
notebookTopicName|Topic name|主题名称|主題名稱|テーマ名
notebookDeleteTopic|Delete topic|删除主题|刪除主題|テーマを削除
notebookDeleteTopicConfirm|Delete this topic?|删除这个主题？|刪除這個主題？|このテーマを削除しますか？
notebookDeleteTopicDetail|Its notes move to Uncategorized. The notes will not be deleted.|主题中的手记会移到“未分类”，不会删除手记。|主題中的手記會移至「未分類」，不會刪除手記。|このテーマのノートは「未分類」に移動し、削除されません。
notebookNoTopics|No topics yet|还没有主题|還沒有主題|テーマはまだありません
notebookClear|Clear all notes|清空全部手记|清空所有手記|すべてのノートを消去
notebookClearConfirm|Clear all notes and topics?|清空全部手记和主题？|清空所有手記與主題？|すべてのノートとテーマを消去しますか？
notebookClearDetail|All notes and topics on this device will be deleted. This cannot be undone.|此设备上的所有手记和主题将被删除，无法恢复。|此裝置上的所有手記與主題將被刪除，無法復原。|この端末のすべてのノートとテーマを削除します。元に戻せません。
notebookUntitled|Untitled note|未命名手记|未命名手記|無題のノート
notebookWriteForSong|Write a song note|写歌曲手记|寫歌曲手記|曲のノートを書く
notebookSongSearch|Search songs|搜索歌曲|搜尋歌曲|曲を検索
notebookNoSongs|No songs to link right now|当前没有可关联的歌曲|目前沒有可關聯的歌曲|関連付けられる曲がありません
notebookNoSongsDetail|You can still write a note and link a work when connected.|你仍可先写手记，联网后再关联作品。|你仍可先寫手記，連網後再關聯作品。|先にノートを書き、接続後に作品と関連付けることもできます。
notebookPrivacy|Stored on this device|本机保存|本機儲存|この端末に保存
notebookStaleDetail|The data has changed or was cleared. Close and reopen this page. Your unsaved text is still here.|资料已更改或清空。请关闭后重新打开，未保存的文字仍留在本页。|資料已變更或清空。請關閉後重新開啟，未儲存的文字仍留在本頁。|データが変更または消去されました。この画面を閉じて開き直してください。未保存の文章はまだこの画面に残っています。
notebookRename|Rename|重命名|重新命名|名前を変更
notebookSaveTopic|Save topic|保存主题|儲存主題|テーマを保存
notebookError|Could not read or save your notes. Please retry.|手记读取或保存失败，请重试。|手記讀取或儲存失敗，請重試。|ノートの読み込みまたは保存に失敗しました。再試行してください。
notebookInvalid|Check the text length and linked work, then retry.|请检查文字长度及关联作品后重试。|請檢查文字長度及關聯作品後重試。|文章の長さと関連作品を確認して再試行してください。
notebookLimit|Notebook storage is full. Delete some content and retry.|本机手记容量已满，请删除部分内容后重试。|本機手記容量已滿，請刪除部分內容後重試。|ノートの保存容量がいっぱいです。一部を削除して再試行してください。
notebookStale|The data changed. Reopen this page before editing.|资料已更改，请重新打开后再编辑。|資料已變更，請重新開啟後再編輯。|データが変更されました。画面を開き直してから編集してください。
releaseDouyinClips|Song pages can open published Douyin clips in the official player after you tap. Available clips depend on publication.|歌曲短片页增加抖音来源，点击后可加载官方播放器，内容以实际发布为准。|歌曲短片頁增加抖音來源，點擊後可載入官方播放器，內容以實際發佈為準。|曲の動画ページが Douyin に対応しました。タップして公式プレーヤーを読み込めます。表示内容は公開状況によります。
releaseDouyinControl|Douyin clips are checked again before opening. Leaving the page stops the player; an external link is available if it cannot play.|打开前再次核验短片，离开页面即停止；无法播放时可前往抖音查看。|開啟前再次核驗短片，離開頁面即停止；無法播放時可前往抖音查看。|開く前に動画を再確認します。ページを離れると停止し、再生できない場合は Douyin で開けます。
douyinName|Douyin|抖音|抖音|Douyin
douyinLoad|Load Douyin player|加载抖音播放器|載入抖音播放器|Douyin プレーヤーを読み込む
douyinCoverHint|Song artwork · tap to connect to Douyin|歌曲封面 · 点击后连接抖音|歌曲封面 · 點擊後連線至抖音|楽曲のアートワーク · タップすると Douyin に接続
douyinOpen|Open in Douyin|在抖音打开|在抖音開啟|Douyin で開く
douyinLoadFailure|Douyin could not load. Retry or open it in Douyin.|抖音暂时无法载入，可重试或在抖音打开。|抖音暫時無法載入，可重試或在抖音開啟。|Douyin を読み込めません。再試行するか Douyin で開いてください。
douyinVerifyFailure|Could not verify this clip. Connect to the internet and retry.|暂时无法核验短片，请联网后重试。|暫時無法核驗短片，請連網後重試。|動画を確認できません。インターネットに接続して再試行してください。
douyinUnavailable|This clip is no longer available for embedding. You can check it on Douyin.|短片暂不可嵌入或已不公开，可前往抖音核对。|短片暫不可嵌入或已不公開，可前往抖音確認。|埋め込みを利用できないか、動画が非公開です。Douyin でご確認ください。
douyinPlayerHint|Use the player's controls to start. If playback is unavailable, open in Douyin.|请在播放器内点按播放；若无法观看，可在抖音打开。|請在播放器內點按播放；若無法觀看，可在抖音開啟。|プレーヤー内の操作で再生してください。視聴できない場合は Douyin で開けます。
douyinPrivacyInfo|Douyin privacy information|抖音隐私说明|抖音隱私說明|Douyin のプライバシー情報
douyinPrivacy|Douyin Privacy Policy|抖音隐私政策|抖音隱私權政策|Douyin プライバシーポリシー
douyinPrivacyNotice|Loading connects to Douyin's official video service, which may process your IP address, device/browser and usage information under its policies and show ads. No Station Cat account data is sent. Playback requires the internet. Temporary web storage does not mean Douyin collects no data. Videos are not downloaded; leaving the page stops the player.|加载后会连接抖音官方视频服务，可能按其政策处理 IP 地址、设备／浏览器及使用信息，并展示广告。不发送 Station Cat 账号资料。播放需要联网；临时网页存储不代表抖音不收集数据。不提供视频下载，离开页面即停止播放器。|載入後會連線至抖音官方影片服務，可能依其政策處理 IP 位址、裝置／瀏覽器及使用資訊，並顯示廣告。不傳送 Station Cat 帳號資料。播放需要網路；暫時網頁儲存不代表抖音不蒐集資料。不提供影片下載，離開頁面即停止播放器。|読み込み後は Douyin の公式動画サービスに接続します。同サービスはそのポリシーに従い IP アドレス、端末・ブラウザ、利用情報を処理し、広告を表示する場合があります。Station Cat のアカウント情報は送信しません。通信が必要で、一時的な Web ストレージは Douyin がデータを収集しないことを意味しません。動画のダウンロードはできず、ページを離れると停止します。
releaseYouTubeClips|Watch published YouTube clips in the song page using the official player. Clips appear when they are published.|歌曲短片页支持通过官方播放器观看已发布的 YouTube 视频，内容以实际发布为准。|歌曲短片頁支援透過官方播放器觀看已發佈的 YouTube 影片，內容以實際發佈為準。|曲の動画ページで、公開された YouTube 動画を公式プレーヤーで視聴できます。表示内容は公開状況によります。
releaseYouTubeControl|YouTube loads only after you tap. Leaving the page stops the video; unavailable embeds offer a YouTube link.|点击后才连接 YouTube，离开页面即停止；无法嵌入时可前往 YouTube 查看。|點擊後才連線至 YouTube，離開頁面即停止；無法嵌入時可前往 YouTube 查看。|タップ後に YouTube に接続し、ページを離れると停止します。埋め込みが利用できない場合は YouTube で開けます。
selectedClips|Selected clips|精选短片|精選短片|ピックアップ動画
youtubeLoad|Load YouTube player|加载 YouTube 播放器|載入 YouTube 播放器|YouTube プレーヤーを読み込む
youtubeCoverHint|Song artwork · tap to connect to YouTube|歌曲封面 · 点击后连接 YouTube|歌曲封面 · 點擊後連線至 YouTube|楽曲のアートワーク · タップすると YouTube に接続
youtubePrivacyNotice|Loading connects to YouTube, which may process device and usage data under its policies. Playback needs the internet; no video is downloaded.|加载后会连接 YouTube，可能按其政策处理设备与使用数据。播放需要联网，不提供视频下载。|載入後會連線至 YouTube，可能依其政策處理裝置與使用資料。播放需要網路，不提供影片下載。|読み込み後は YouTube に接続し、そのポリシーに従って端末や利用データが処理される場合があります。通信が必要で、動画のダウンロードはできません。
youtubeOpen|Open in YouTube|在 YouTube 打开|在 YouTube 開啟|YouTube で開く
youtubeLoadFailure|YouTube could not load. Retry or open it in YouTube.|YouTube 暂时无法载入，可重试或在 YouTube 打开。|YouTube 暫時無法載入，可重試或在 YouTube 開啟。|YouTube を読み込めません。再試行するか YouTube で開いてください。
youtubeVerifyFailure|Could not verify this clip. Connect to the internet and retry.|暂时无法核验短片，请联网后重试。|暫時無法核驗短片，請連網後重試。|動画を確認できません。インターネットに接続して再試行してください。
youtubeUnavailable|This video is unavailable or embedding is disabled. You can check it on YouTube.|视频不可用或禁止嵌入，可前往 YouTube 核对。|影片無法使用或禁止嵌入，可前往 YouTube 確認。|動画を利用できないか、埋め込みが無効です。YouTube でご確認ください。
youtubePrivacyInfo|YouTube privacy and terms|YouTube 隐私与条款|YouTube 隱私與條款|YouTube のプライバシーと利用規約
youtubeTerms|YouTube Terms|YouTube 条款|YouTube 條款|YouTube 利用規約
youtubePrivacy|Google Privacy|Google 隐私政策|Google 隱私權政策|Google プライバシーポリシー
releaseV1Catalog|Version 1.0 brings together published singles and albums, with search, album introductions and track lists.|1.0 首发版本汇集已发布单曲与专辑，支持搜索、专辑介绍和曲目浏览。|1.0 首發版本匯集已發佈單曲與專輯，支援搜尋、專輯介紹與曲目瀏覽。|1.0 は公開済みのシングルとアルバムをまとめ、検索、アルバム紹介、収録曲の閲覧に対応します。
releaseV1Reading|Read available lyrics and creative stories, adjust the lyric text size and expand the full text.|阅读作品已发布的歌词与创作故事，支持歌词字号调整和全文展开。|閱讀作品已發佈的歌詞與創作故事，支援歌詞字級調整與全文展開。|公開された歌詞と作品のストーリーを読めます。歌詞の文字サイズ変更と全文表示に対応します。
releaseV1Personal|Keep favorites, recent views and your preferred listening platform on this device. Viewing history can be turned off or cleared.|收藏、最近查看和常用音乐平台偏好保存在本机，浏览记录可关闭或清空。|收藏、最近查看與常用音樂平台偏好儲存在本機，瀏覽紀錄可關閉或清空。|お気に入り、最近見た作品、配信サービスの設定を端末に保存します。閲覧履歴は停止・消去できます。
releaseV1Listening|Follow verified links to listen on external music services. No Station Cat login or subscription is required; this app does not provide full-song audio.|通过已核验的入口前往音乐平台收听，无需 Station Cat 登录或订阅；App 内不提供完整歌曲播放。|透過已核驗的入口前往音樂平台收聽，無須 Station Cat 登入或訂閱；App 內不提供完整歌曲播放。|確認済みのリンクから音楽配信サービスで聴けます。Station Cat のログインや購読は不要です。アプリ内ではフル楽曲を再生しません。
contentTab.lyrics|Lyrics|歌词|歌詞|歌詞
contentTab.clips|Clips|短片|短片|動画
contentTab.story|Story|故事|故事|ストーリー
contentLyricsTitle|Lyrics|全部歌词|全部歌詞|歌詞
contentStoryTitle|The story behind the song|创作故事|創作故事|曲にまつわるストーリー
listenOnPlatform|Listen on {platform}|在{platform}收听|在{platform}收聽|{platform}で聴く
lyricsEmpty|Lyrics have not been published for this song yet.|这首歌暂未发布歌词。|這首歌暫未發佈歌詞。|この曲の歌詞はまだ公開されていません。
clipsEmpty|No clips yet. You can still listen on a music platform.|暂无短片，可通过音乐平台收听。|暫無短片，可透過音樂平台收聽。|動画はまだありません。配信サービスから曲を聴けます。
storyEmpty|The story behind this song has not been published yet.|这首歌的创作故事暂未发布。|這首歌的創作故事暫未發佈。|この曲のストーリーはまだ公開されていません。
contentLoading|Loading content…|正在载入内容…|正在載入內容…|コンテンツを読み込み中…
contentLoadFailure|Could not load this content. Please retry.|内容暂时未能载入，请重试。|內容暫時無法載入，請重試。|コンテンツを読み込めませんでした。再試行してください。
contentWithdrawn|This content is no longer available. Retry to check for updates.|此内容已不可用，可重试检查更新。|此內容已無法使用，可重試檢查更新。|このコンテンツは現在利用できません。再試行して最新の状態を確認してください。
lyricTextSize|Lyrics text size|歌词字号|歌詞字級|歌詞の文字サイズ
lyricSize.18|Standard|标准|標準|標準
lyricSize.21|Large|大|大|大
lyricSize.24|Extra large|更大|更大|特大
lyricsExpand|Read all lyrics|展开全部歌词|展開全部歌詞|歌詞をすべて表示
lyricsCollapse|Show less|收起歌词|收起歌詞|折りたたむ
clipWatch|Watch clip|观看短片|觀看短片|動画を見る
clipUnmute|Turn sound on|开启声音|開啟聲音|音声をオン
clipMute|Mute|静音|靜音|消音
clipStop|Close video|关闭视频|關閉影片|動画を閉じる
clipMutedHint|Uploaded clips start only when tapped, with sound off. They stop when you leave this page.|本站短片需点击观看，初始静音；离开页面后停止。|本站短片需點擊觀看，初始靜音；離開頁面後停止。|当サイトの動画はタップすると消音で始まり、この画面を離れると停止します。
clipPlayFailure|This clip could not be played. Please retry.|短片暂时无法播放，请重试。|短片暫時無法播放，請重試。|動画を再生できませんでした。再試行してください。
releaseSongContent|Song details now separate lyrics, clips and stories, while keeping your listening platform close.|歌曲详情新增歌词、短片、故事分栏，保留清晰的平台收听入口。|歌曲詳情新增歌詞、短片、故事分欄，保留清楚的平台收聽入口。|曲の詳細を歌詞・動画・ストーリーに分け、配信サービスへの入口もわかりやすく配置しました。
releaseLyricsReader|Read published lyrics with adjustable text size and expand or collapse the full text.|已发布歌词支持原生阅读、字号调整和展开收起。|已發佈歌詞支援原生閱讀、字級調整及展開收起。|公開済みの歌詞をアプリ内で読めます。文字サイズの変更と全文の展開・折りたたみに対応しました。
releaseContentStates|Each content section has its own empty and retry states. Clips start only after a tap and are muted initially.|各栏目分别显示暂无内容和重试状态；短片需点击观看，初始静音。|各欄目分別顯示暫無內容與重試狀態；短片需點擊觀看，初始靜音。|各欄に未公開と再試行の状態を用意。動画はタップした場合のみ、最初は消音で再生します。
cancel|Cancel|取消|取消|キャンセル
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
platformWorkMissing|This work is no longer available at this address. Your favorite is kept.|此地址的作品不存在或已撤回，收藏仍保留。|此位址的作品不存在或已撤回，收藏仍保留。|このアドレスの作品は存在しないか、公開が終了しています。お気に入りは保持します。
platformWorkRemoved|This work has been withdrawn. Your favorite is kept.|作品已撤回，收藏仍保留。|作品已撤回，收藏仍保留。|作品の公開が終了しました。お気に入りは保持します。
favoritePlaceholder|Saved work|已收藏的作品|已收藏的作品|保存した作品
favoriteAwaitingUpdate|Saved · connect to update details|已收藏 · 联网后更新作品资料|已收藏 · 連線後更新作品資料|保存済み · 接続後に情報を更新
favoriteOpenDetails|Open details to check listening platforms|打开详情，核验收听平台|開啟詳情，核驗收聽平台|詳細を開いて配信先を確認
removeFavorite|Remove favorite|取消收藏|取消收藏|お気に入りから削除
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
deletion.completed|Server account deletion is complete.|服务器账号删除已完成。|伺服器帳號刪除已完成。|サーバー側のアカウント削除が完了しました。'''
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
 'previousUpdates|Previous updates|此前更新|先前更新|これまでの更新\n'
 'releaseSaveStability|Catalog refreshes and language changes no longer interrupt eligible offline saves.|修复刷新曲库或切换语言时，合格的离线保存意外中断的问题。|修復重新整理曲庫或切換語言時，符合資格的離線儲存意外中斷的問題。|曲一覧の更新や言語の切り替えで、保存可能な曲のダウンロードが中断される問題を修正。\n'
 'releaseClockProtection|A clock rollback no longer deletes intact, unexpired saved songs. Playback is available again when the clock is correct.|系统时间回退不再误删完整且未过期的缓存，时间恢复正常后可继续播放。|系統時間倒退不再誤刪完整且未過期的快取，時間恢復正常後可繼續播放。|端末の時計が戻っても、有効期限内の正常な保存曲は削除されません。時刻が戻ると再び再生できます。\n'
 'releaseCacheCleanup|Improved expired-song removal and storage cleanup without interrupting other saves.|完善过期歌曲与缓存空间清理，删除其他歌曲不再中断正在进行的保存。|完善過期歌曲與快取空間清理，刪除其他歌曲不再中斷進行中的儲存。|期限切れの曲とストレージの整理を改善。他の曲を削除しても保存中の曲は中断されません。\n'
 'releaseRefreshRetry|Failed refreshes keep the previous list and show a clear message with a retry option.|刷新失败时保留原有列表，并显示清晰的错误提示和重试入口。|重新整理失敗時保留原有清單，並顯示清楚的錯誤提示與重試入口。|更新に失敗しても前回のリストを保持し、エラーと再試行ボタンを表示します。\n'
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

rows += '\n'.join(['',
'deleteRetention|Public comments remain anonymously. Balances and disputes are reviewed separately; deletion does not automatically refund or reset them.|公开评论匿名保留；余额和交易争议另行处理，删除账号不会自动退款或清零。|公開評論匿名保留；餘額和交易爭議另行處理，刪除帳號不會自動退款或歸零。|公開コメントは匿名で残ります。残高・取引の問題は別途確認し、削除による自動返金や残高のリセットは行いません。',
'deletion.previous|Earlier deletion requests|先前的删除申请|先前的刪除申請|以前の削除リクエスト',
'deletion.previousResult|Showing an earlier deletion request.|正在显示先前删除申请的结果。|正在顯示先前刪除申請的結果。|以前の削除リクエストの結果です。',
'deletion.receiptUntil|Progress lookup available until|可查询至|可查詢至|進行状況の照会期限',
'deletion.local.completed|This account’s favorites and listening history have been cleared from this device.|该账号在本机的收藏与播放历史已清理。|該帳號在本機的收藏與播放歷史已清理。|このアカウントのお気に入りと再生履歴を端末から削除しました。',
'deletion.local.retry|Confirmed account deletions still need local cleanup. Check deletion progress to retry.|已确认删除的账号资料尚未在本机全部清理完成，请点击查询删除进度重试。|已確認刪除的帳號資料尚未在本機全部清理完成，請點擊查詢刪除進度重試。|削除確認済みのアカウントデータが端末に一部残っています。進行状況を確認して再試行してください。',
'deletion.stage.queued|Waiting to start account cleanup.|等待开始账号清理。|等待開始帳號清理。|アカウントの削除開始を待っています。',
'deletion.stage.credentials|Removing sign-in credentials and sessions.|正在清理登录凭据和会话。|正在清理登入憑據與連線階段。|ログイン情報とセッションを削除しています。',
'deletion.stage.private_data|Removing private account data.|正在清理账号私人资料。|正在清理帳號私人資料。|アカウントの個人データを削除しています。',
'deletion.stage.comments|Removing author associations from retained comments.|正在移除保留评论的作者关联。|正在移除保留評論的作者關聯。|残すコメントと投稿者の関連を解除しています。',
'deletion.stage.identity|Removing account identity details.|正在清理账号身份资料。|正在清理帳號身分資料。|アカウントの識別情報を削除しています。',
'deletion.stage.verify|Checking the account cleanup result.|正在核验账号清理结果。|正在核驗帳號清理結果。|アカウントの削除結果を確認しています。',
'deletion.stage.retention_policy_review|Required retention review remains pending. Deletion is not complete.|必要的保留规则仍待核验，删除尚未完成。|必要的保留規則仍待核驗，刪除尚未完成。|必要な保持ルールの確認が残っています。削除は未完了です。',
'deletion.stage.financial_review|Reviewing the required transaction records.|正在核验必要的交易记录。|正在核驗必要的交易紀錄。|必要な取引記録を確認しています。',
'deletion.stage.external_cleanup|Processing related service cleanup.|正在处理关联服务清理。|正在處理關聯服務清理。|関連サービスのデータ削除を処理しています。',
'deletion.stage.backup_review|Checking backup cleanup requirements.|正在核验备份清理要求。|正在核驗備份清理要求。|バックアップの削除要件を確認しています。',
'deletion.stage.completed|All required server cleanup checks have passed.|服务器必要清理检查已通过。|伺服器必要清理檢查已通過。|サーバー側の必要な削除確認を完了しました。',
''])

rows += '''
platformListening|Listen on a platform|平台收听|平台收聽|配信サービスで聴く
platformDiscoverIntro|Keep the music you love close. Listen on your favorite platform.|收藏喜欢的作品，选择熟悉的平台慢慢听。|收藏喜歡的作品，選擇熟悉的平台慢慢聽。|好きな作品をそばに。いつもの配信サービスで聴こう。
platformFeatured|Featured work|主推作品|主推作品|おすすめの作品
platformWorks|Music works|音乐作品|音樂作品|音楽作品
platformOpenWebsite|View on the website|前往网站|前往網站|ウェブサイトで見る
platformPreviewWebsite|Preview on the website|前往网站试听|前往網站試聽|ウェブサイトで試聴
platformLinksPending|Platform links will be announced later.|平台入口稍后公开。|平台入口稍後公開。|配信リンクは後日公開します。
platformUnavailable|Platform links are currently unavailable.|平台入口暂不可用。|平台入口暫時無法使用。|配信リンクは現在利用できません。
platformRegionLimited|Platform availability depends on your region.|平台可用性因所在地区而异。|平台可用性依所在地區而異。|配信サービスの利用可否は地域により異なります。
platformDetailLoading|Loading work details…|正在载入作品信息…|正在載入作品資訊…|作品の情報を読み込んでいます…
platformDetailFailure|Work details could not be loaded.|作品信息暂时未能载入。|作品資訊暫時未能載入。|作品の情報を読み込めませんでした。
platformOpenFailure|This link could not be opened. Copy it to open in your browser.|未能打开链接，可复制后在浏览器中打开。|無法開啟連結，可複製後在瀏覽器中開啟。|リンクを開けませんでした。コピーしてブラウザで開いてください。
platformCopyLink|Copy link|复制链接|複製連結|リンクをコピー
platformCopied|Link copied.|链接已复制。|連結已複製。|リンクをコピーしました。
platformWorkIntro|About this work|作品介绍|作品介紹|作品について
platformCacheManagement|Previously saved music|已有缓存管理|既有快取管理|以前保存した音楽
platformCacheSummary|View and remove earlier downloads|查看与清理之前保存的歌曲|查看與清理先前儲存的歌曲|以前保存した曲を確認・削除
platformLegacyCacheDetail|Earlier downloads are preserved. This version uses music platforms for listening; you can remove existing files here.|旧版本保存的文件会保留；当前版本通过音乐平台收听，可在这里删除已有缓存。|舊版本儲存的檔案會保留；目前版本透過音樂平台收聽，可在這裡刪除既有快取。|以前保存したファイルは保持されます。このバージョンでは配信サービスで聴くことができます。保存済みファイルはここで削除できます。
platformLegacyCacheSaved|Previously saved on this device|以前保存于此设备|先前儲存於此裝置|以前この端末に保存済み
platformFixture|Sample works for local interface preview.|示例作品，仅用于本机界面预览。|示例作品，僅供本機介面預覽。|端末内の画面プレビュー用サンプル作品です。
platformAccountDetail|Browse works and save favorites on this device without signing in. Account features are not available in this version.|无需登录即可浏览作品并在本机收藏，当前版本暂不提供账号功能。|無需登入即可瀏覽作品並在本機收藏，目前版本暫不提供帳號功能。|ログインなしで作品の閲覧と端末へのお気に入り保存ができます。このバージョンではアカウント機能は利用できません。
platformHistoryDetail|Listening on external platforms is recorded by those platforms. Earlier in-app history is kept and can be cleared in Privacy & storage.|外部平台的收听记录由平台管理。旧版本的本机记录会保留，可在“隐私与存储”中清理。|外部平台的收聽紀錄由平台管理。舊版本的本機紀錄會保留，可在「隱私與儲存」中清理。|外部サービスの再生履歴は各サービスが管理します。以前のアプリ内履歴は保持され、「プライバシーとストレージ」で消去できます。
platform.netease|NetEase Music|网易云音乐|網易雲音樂|NetEase Music
platform.qishui|Qishui Music|汽水音乐|汽水音樂|Qishui Music
platform.apple_music|Apple Music|Apple Music|Apple Music|Apple Music
platform.youtube|YouTube|YouTube|YouTube|YouTube
platform.spotify|Spotify|Spotify|Spotify|Spotify
artworkCacheSpace|Cover cache storage|封面缓存占用|封面快取空間|カバー画像のキャッシュ容量
artworkCacheFiles|Cached covers|已缓存封面|已快取封面|保存済みのカバー画像
catalogCategory.all|All|全部|全部|すべて
catalogCategory.singles|Singles|单曲|單曲|シングル
catalogCategory.albums|Albums|专辑|專輯|アルバム
catalogCategories|Browse by category|作品分类|作品分類|カテゴリ
catalogSearch|Search songs and albums|搜索歌曲、专辑|搜尋歌曲、專輯|曲・アルバムを検索
catalogClearSearch|Clear search|清除搜索|清除搜尋|検索をクリア
catalogAlbumWorks|Albums|专辑作品|專輯作品|アルバム作品
catalogTrackCount|%d songs|%d 首|%d 首|%d 曲
catalogNoAlbums|No albums yet|暂无专辑|暫無專輯|アルバムはまだありません
catalogNoSingles|No singles in this list|暂无单曲|暫無單曲|シングルはまだありません
catalogBrowseAll|Browse all works to find something you like.|可以先到全部作品中看看。|可以先到全部作品中看看。|すべての作品から探してみましょう。
catalogClassificationUnavailable|Some category information is unavailable. You can still browse all works.|部分分类资料暂时无法载入，仍可查看全部作品。|部分分類資料暫時無法載入，仍可查看全部作品。|一部の分類を取得できません。すべての作品は引き続き表示できます。
catalogAlbumUnavailable|This album has changed or is no longer available.|此专辑已更新或暂不可用。|此專輯已更新或暫不可用。|このアルバムは更新されたか、現在表示できません。
personalIntro|Save what you love. Discover at your pace.|收藏喜欢，慢慢发现。|收藏喜歡，慢慢發現。|好きな作品を残して、自分のペースで。
viewFavorites|View favorites|查看收藏|查看收藏|お気に入りを見る
recentlyViewed|Recently viewed|最近查看|最近查看|最近見た作品
noViewed|Open a work to find it here next time.|打开作品详情，下次在这里找到。|開啟作品詳情，下次在這裡找到。|作品の詳細を開くと、ここに表示されます。
viewedPlaceholder|Previously viewed work|查看过的作品|查看過的作品|閲覧した作品
viewedAwaitingUpdate|Connect to update work details|联网后更新作品资料|連線後更新作品資料|接続後に作品情報を更新
viewedToday|Today|今天|今天|今日
viewedYesterday|Yesterday|昨天|昨天|昨日
saveViewed|Save browsing history|保存浏览记录|儲存瀏覽記錄|閲覧履歴を保存
clearViewed|Clear browsing history|清空浏览记录|清空瀏覽記錄|閲覧履歴を消去
clearViewedConfirm|Clear recently viewed works on this device?|清空本机的最近查看记录？|清空本機的最近查看記錄？|この端末の閲覧履歴を消去しますか？
viewingHistoryOff|Browsing history is off.|浏览记录已关闭。|瀏覽記錄已關閉。|閲覧履歴はオフです。
viewingPrivacy|Only on this device: up to 100 works viewed in the last 30 days. Turning this off also clears these entries. This is separate from listening history and does not record plays on other platforms. Names are shown only while their permitted cache is valid; opening always checks online.|仅在本机保留最近 30 天、最多 100 首查看记录；关闭时会清空。与播放历史分开，不记录外部平台的实际播放。名称仅在允许的缓存期内展示，打开作品时会重新联网核验。|僅在本機保留最近 30 天、最多 100 首查看記錄；關閉時會清空。與播放歷史分開，不記錄外部平台的實際播放。名稱僅在允許的快取期內顯示，開啟作品時會重新連線核驗。|過去30日間、最大100件をこの端末だけに保存します。オフにすると消去されます。再生履歴とは別で、外部サービスの再生は記録しません。作品名は許可されたキャッシュ期間のみ表示し、開く際はオンラインで再確認します。
preferredPlatform|Preferred music platform|常用音乐平台|常用音樂平台|よく使う音楽サービス
platformDefault|Follow website order|跟随网站排序|跟隨網站排序|サイトの順序に従う
platformPreferenceDetail|Your choice is saved on this device and shown first when a work has a verified link to that platform. Other available platforms remain visible. This setting does not open another app or start playback.|偏好仅保存在本机。作品有已核验的对应链接时会优先显示，仍保留其他可用平台。选择偏好不会打开外部 App 或开始播放。|偏好僅儲存在本機。作品有已核驗的對應連結時會優先顯示，仍保留其他可用平台。選擇偏好不會開啟外部 App 或開始播放。|設定はこの端末に保存します。確認済みのリンクがある場合に先頭へ表示し、他の配信先も残します。設定するだけで外部アプリを開いたり再生したりすることはありません。
preferredPlatformMissing|This work has no confirmed link for your preferred platform. Choose another available platform below.|这首作品暂无常用平台的已确认入口，可选择下方其他平台。|這首作品暫無常用平台的已確認入口，可選擇下方其他平台。|この作品には設定したサービスの確認済みリンクがありません。下の配信先から選べます。
yourPreferredPlatform|Your preferred platform|你的常用平台|你的常用平台|よく使うサービス
settingsHelp|Settings & help|设置与帮助|設定與說明|設定とヘルプ
legacyData|Earlier local data|历史资料|歷史資料|以前の端末内データ
legacyListeningHistory|Earlier listening history|旧播放记录|舊播放記錄|以前の再生履歴
legacyRecordedWork|Earlier recorded work · details unavailable|旧记录作品 · 资料暂不可用|舊記錄作品 · 資料暫不可用|以前の記録 · 作品情報を取得できません
personalSaveError|Local preferences or browsing history could not be read or saved. Retry, then check your selection.|本机偏好或浏览记录读取、保存失败。请重试后核对设置。|本機偏好或瀏覽記錄讀取、儲存失敗。請重試後核對設定。|端末の設定や閲覧履歴を読み込み、保存できませんでした。再試行して設定を確認してください。
releasePersonalHub|A new Me page highlights favorites, with recently viewed works and settings one step away. Earlier account data and files stay available where applicable.|“我的”改为收藏焦点布局，最近查看与设置分层进入，已有账号资料与旧文件按实际情况保留管理入口。|「我的」改為收藏焦點版面，最近查看與設定分層進入，既有帳號資料與舊檔案依實際情況保留管理入口。|「マイ」をお気に入り中心の画面に刷新。最近見た作品や設定へ移動しやすくし、既存データの管理入口は必要な場合に残します。
releaseRecentlyViewed|Recently viewed works are stored locally, separately from listening history. Keep up to 100 entries for 30 days, with controls to turn saving off or clear them.|新增独立的本机“最近查看”，保留最近 30 天、最多 100 首，可关闭或清空，不把浏览计作播放。|新增獨立的本機「最近查看」，保留最近 30 天、最多 100 首，可關閉或清空，不將瀏覽計作播放。|再生履歴とは別に「最近見た作品」を端末へ保存。過去30日間、最大100件を保持し、保存の停止や消去ができます。
releasePlatformPreference|Choose a preferred music platform. Its verified links appear first; when absent, other available platforms remain visible.|可设置常用音乐平台，优先显示已核验的对应入口；未发布到该平台时仍显示其他可用平台。|可設定常用音樂平台，優先顯示已核驗的對應入口；未發佈至該平台時仍顯示其他可用平台。|よく使う音楽サービスを設定し、確認済みリンクを先頭に表示。対応リンクがない作品でも他の配信先を選べます。
releaseCatalogCategories|Browse All, Singles and Albums. Open an album to see its songs in order, and search within each category.|曲库新增全部、单曲和专辑分类；专辑以双列封面展示，点开查看有序曲目，并支持分类搜索。|曲庫新增全部、單曲和專輯分類；專輯以雙欄封面展示，點開查看依序排列的曲目，並支援分類搜尋。|ライブラリに「すべて・シングル・アルバム」を追加。アルバムの収録曲を曲順で表示し、カテゴリ内で検索できます。
releaseUniversalLinks|Open supported Station Cat song links from other apps directly in the matching work page. Opening behavior depends on iOS and the source app.|支持从其他 App 的 Station Cat 歌曲链接进入对应作品页面；具体打开方式由 iOS 和来源 App 决定。|支援從其他 App 的 Station Cat 歌曲連結進入對應作品頁面；實際開啟方式由 iOS 和來源 App 決定。|他のアプリから対応する Station Cat の曲リンクで作品ページを開けます。開き方は iOS とリンク元のアプリによって異なります。
releaseSongLinks|Song links can load a work directly, including supported campaign tags, even before it appears in your catalog.|歌曲链接可直接查询作品，并支持限定的推广来源参数，无需等待作品进入本机曲库。|歌曲連結可直接查詢作品，並支援限定的推廣來源參數，無需等待作品進入本機曲庫。|対応するキャンペーン情報付きの曲リンクから、一覧にまだない作品も直接読み込めます。
releaseFavoriteReliability|Favorites remain visible offline. Permitted saved names appear while fresh; otherwise a saved-work placeholder stays available.|断网时收藏数量和条目仍保留；有效期内显示已保存的作品名称，否则显示收藏占位。|離線時收藏數量和項目仍保留；有效期內顯示已儲存的作品名稱，否則顯示收藏佔位。|オフラインでもお気に入りの件数と項目を保持。有効な保存情報があれば作品名を表示し、期限後も保存済みの項目を残します。
releaseDetailErrors|Song details distinguish network failures and unavailable addresses, with a retry option.|歌曲详情区分网络失败和地址失效，并提供重试入口。|歌曲詳情區分網路失敗和位址失效，並提供重試入口。|曲の詳細で通信エラーと無効なアドレスを区別し、再試行できます。
releasePrivacyLinks|Privacy and terms now open the current website pages in your selected language.|隐私政策和服务条款现在会打开与你所选语言对应的新版网站页面。|隱私政策與服務條款現在會開啟與所選語言對應的新版網站頁面。|プライバシーポリシーと利用規約のリンクを、選択した言語の現在のウェブページに更新しました。
releaseCoverCache|Versioned covers can be reused from memory and local storage while valid. View usage and clear them in Privacy & storage.|封面按版本缓存在本机，有效期内直接复用，可在“隐私与存储”查看占用并清理。|封面依版本快取於本機，有效期內直接重用，可在「隱私與儲存」查看空間並清理。|バージョンごとにカバー画像を端末へ保存し、有効期間内は再利用します。「プライバシーとストレージ」で容量の確認と削除ができます。
releaseImageLoading|Recommendations load in parallel, and music lists use smaller cover thumbnails.|推荐信息并行载入，歌曲列表使用更轻的封面缩略图。|推薦資訊平行載入，歌曲清單使用更輕量的封面縮圖。|おすすめ情報を並列で読み込み、曲の一覧には軽量なカバー画像を表示します。
releaseImageRetries|Retrying a failed refresh also retries missing covers, while already displayed images stay visible.|刷新失败后重试也会重新加载未显示的封面，已经显示的图片保持可见。|更新失敗後重試也會重新載入未顯示的封面，已顯示的圖片保持可見。|更新に失敗した後の再試行で未表示の画像も再読み込みします。表示済みの画像はそのまま保持します。
releasePlatforms|Discovery and song details now put verified music-platform links first, with an option to copy links if opening fails.|发现页与歌曲详情改为平台收听优先，打不开时可复制链接。|發現頁與歌曲詳情改為平台收聽優先，無法開啟時可複製連結。|発見画面と曲の詳細は配信リンクを優先表示。開けない場合はリンクをコピーできます。
releaseWebsiteCatalog|Works and featured picks follow the website's public release catalog. Website previews appear only when available.|作品与推荐对齐网站公开目录，仅在有试听配置时显示网站试听入口。|作品與推薦對齊網站公開目錄，僅在有試聽設定時顯示網站試聽入口。|作品とおすすめをウェブサイトの公開情報に統一。試聴がある場合のみサイトへの入口を表示します。
releaseLocalData|Favorites and existing local files are kept. Full playback and new offline saves are no longer main-screen actions.|保留收藏与已有本机文件，主界面不再提供完整播放与新增离线缓存入口。|保留收藏與既有本機檔案，主介面不再提供完整播放與新增離線快取入口。|お気に入りと既存の端末内ファイルを保持。全曲再生と新しいオフライン保存の入口はメイン画面から外しました。
'''

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
