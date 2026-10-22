# Combined notebook and video privacy readiness

2026-10-22 (Asia/Singapore) · Development candidate **1.0.3 (16)** · **Prepared, not saved or published**.

This document brings the [YouTube 1.0.1 draft](../app-store/youtube-1.0.1-privacy-delta.md), [Douyin 1.0.2 draft](../app-store/douyin-1.0.2-privacy-delta.md) and the new local notebook into one release checklist. It does not change the existing policy's effective date or certify that the current Apple questionnaire covers the new players. Existing service logging and voluntary support mail remain separate from local notes. No Apple answers, production privacy pages or logging settings are changed by committing this document.

## Local notebook handling

The store retains user-authored note titles/text, note IDs and timestamps, user-created topic names/IDs and an optional work ID/slug. It does not automatically persist public lyrics/stories, artwork, platform URLs or campaign parameters. The note store has no network transport, telemetry or cross-device sync. Search happens locally. Saving or displaying a linked note may refresh the website-authorized presentation bookmark or cover; these requests contain the work reference, not the note title, body or topic. Opening the linked work is a separate online action subject to the existing website requests and logging.

Notes are stored in protected local files, separated by environment/account scope and excluded from system backup. They remain until the user deletes them, clears the notebook or removes the app; there is no timed expiry or cache eviction. Deleting a topic keeps its notes under Uncategorized. Clearing the cover cache does not clear notes. Failed storage operations must not be reported as successful, and stale editors must not recreate cleared data. Verify these behaviors against the final package before publishing the wording below. Local storage is not a claim that the device is accessible only to its owner, nor a guarantee about copies a user may independently make.

## YouTube and Douyin handling

| User action | New connection | Disclosure boundary |
| --- | --- | --- |
| Open a song or Clips tab | Station Cat content and cover requests | No provider player/thumbnail is preloaded by these screens. |
| Tap Load YouTube player | YouTube official embedded player | Google may receive IP, device/browser and video usage information and show ads under its rules. |
| Tap Load Douyin player | Douyin official iframe API, then official player when available | The API request itself reaches Douyin even if playback never succeeds. |
| Choose an external provider fallback | System browser or corresponding app | That service's separate storage, sign-in and policies apply. |

Each load or fallback rechecks current Station Cat publication first. The players use temporary WebView storage and stop/discard their in-app session when dismissed, backgrounded or navigated away from under the existing lifecycle rules. Station Cat does not add viewing/click telemetry, extract the soundtrack or download these videos. Temporary storage and `youtube-nocookie.com` do **not** establish no provider data collection, no cookies, no tracking, or immediate erasure of provider records. Provider-controlled subresources and advertising require evidence-based review beyond the app's document-navigation allowlist.

Published short clips are currently empty. Local test IDs and load callbacks do not prove actual provider practices. The [YouTube terms](https://www.youtube.com/t/terms), [Google privacy policy](https://policies.google.com/privacy) and [Douyin privacy policy](https://www.douyin.com/privacy/) are review inputs, not proof that a particular video is authorized or playable.

## Proposed notebook policy addition

**简体中文**

“我的手记”保存你输入的标题、正文、主题，以及创建和修改时间、可选的作品标识。手记仅保存在此设备的受保护本机文件中，App 不上传手记、不跨设备同步，并将手记目录排除在系统备份之外。你可以删除单篇手记或清空全部手记和主题；删除主题会保留其中的手记，清理封面缓存不会删除手记。手记不会自动复制公开歌词、故事、封面或收听链接。打开关联作品仍需联网核验，并适用网站请求的现有处理说明。卸载 App 会移除本机手记，App 不提供云端恢复。

**繁體中文**

「我的手記」儲存你輸入的標題、內文、主題，以及建立和修改時間、可選的作品識別資訊。手記僅儲存在此裝置受保護的本機檔案中，App 不上傳手記、不跨裝置同步，並將手記目錄排除於系統備份之外。你可以刪除單篇手記或清空所有手記與主題；刪除主題會保留其中的手記，清理封面快取不會刪除手記。手記不會自動複製公開歌詞、故事、封面或收聽連結。開啟關聯作品仍需連網核驗，並適用網站請求的既有處理說明。解除安裝 App 會移除本機手記，App 不提供雲端還原。

**English**

My notebook stores your titles, text and topics, creation and modification times, and an optional work reference. Notes stay in protected local files on this device. The app does not upload notes or sync them across devices, and excludes the notebook directory from system backup. You can delete individual notes or clear all notes and topics. Deleting a topic keeps its notes; clearing the cover cache does not delete notes. The notebook does not automatically copy published lyrics, stories, artwork or listening links. Opening a linked work still requires online verification and follows the existing handling of website requests. Uninstalling the app removes local notes; the app offers no cloud recovery.

**日本語**

「マイノート」は、入力したタイトル、本文、テーマに加え、作成・更新日時と任意の作品識別情報を保存します。ノートはこの端末の保護されたローカルファイルのみに保存されます。アプリはノートをアップロードせず、端末間で同期しません。ノートのフォルダはシステムバックアップの対象から除外します。個別のノートの削除、またはすべてのノートとテーマの消去ができます。テーマを削除してもノートは残り、カバー画像のキャッシュを消去してもノートは削除されません。公開された歌詞、ストーリー、画像、配信リンクを自動コピーすることはありません。関連作品を開くには引き続きオンライン確認が必要で、既存のウェブサイトリクエストに関する説明が適用されます。アプリを削除すると端末内のノートは削除され、クラウドからの復元機能はありません。

## Remaining before distribution

1. Check the final signed package's note storage, backup exclusion, no-upload path, deletion controls and four-language labels. Record results without including a user's note text in logs or screenshots. Keep fixtures clearly labelled.
2. Obtain real, owner-authorized YouTube/Douyin clips and inspect actual provider connections, playback, advertisements, identifiers, retention and account/region behavior. Preserve a redacted evidence summary. No such real-video result is claimed here.
3. Map actual third-party behavior to [Apple App Privacy guidance](https://developer.apple.com/app-store/app-privacy-details/), including purposes, linking and tracking. Do not inherit 1.0's answers automatically, assert that local notes are remotely collected merely because they exist, or add an ATT declaration from assumption alone. Resolve uncertain classifications before distribution.
4. Consolidate both provider additions and the notebook wording into the effective four-language privacy policy, verify the public URLs, then save/publish matching Apple answers through the authorized release workflow. Record the effective date and publication result separately from this draft.
5. Deploy the reviewed website API before the client, retaining existing production content and privacy overlays. Recheck `include=youtube,douyin`, fresh-publication denial and player navigation/fallback behavior over real HTTPS. Signing, installing, TestFlight upload and App Store resubmission remain separately recorded release actions.

These steps describe technical evidence and disclosures to complete; they are not legal assurances or a guarantee of App Store approval. They do not resolve the separate cover-art provenance request.
