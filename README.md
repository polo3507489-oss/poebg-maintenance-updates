# PoeBG 維護版更新

[下載最新版](https://github.com/polo3507489-oss/poebg-maintenance-updates/releases/latest)

第一次請下載 `PoeBG-friends-autoupdate-版本.zip`，完整解壓到可寫入的新資料夾，執行 `PoeBGFriendsUpdater.exe`。設定自己的主人名稱及行走鍵，再按需求勾選功能。

之後啟動時會檢查維護版更新。確認下載、儲存設定並正常關閉 PoeBG 後，更新器會備份、驗證、安裝並重新開啟。原版更新通知仍保留。

更新保留 Role、勞工設定、INI、日誌及 *.settings 功能開關；失敗會還原。從舊版搬移設定時，請先關閉兩份 PoeBG，再複製自己的 Role 資料夾和 PoeBG-maintenance 下的 *.settings。

`PoeBG-maintenance.zip`、`update.json`、`update.sig` 供自動更新使用；第一次安裝請選朋友完整 ZIP。

更新檔採 RSA-SHA256 簽章及 SHA256 檢查。不需要 GitHub 登入或權杖，更新器只向 GitHub 查詢及下載，不附帶遊戲帳號或角色設定。這不代表對原版軟體其他網路功能做出保證。

新增功能或修正必須由維護者發布新的 Release，朋友才能取得；未發布的本機改動不會同步。

這是維護版發佈來源，並非原作者的官方儲存庫。

## 維護者自動發布

將已簽章的五個更新附件以 `scripts/Stage-Release.ps1` 驗證並放入 `release-input`，一次提交並推送到 `main`，GitHub Actions 就會開始發布。流程會檢查 RSA 簽章、附件雜湊及 ZIP 內每個已簽章檔案，先上傳到草稿，下載核對全部五個附件後才發布為最新版。失敗時保留原本的最新版。

簽章私鑰留在維護者電腦，不放到 GitHub；Actions 使用 GitHub 提供的暫時權杖。`verify` 模式只驗證；`smoke` 模式會測試上傳但保留為草稿，不通知朋友更新。朋友仍透過原有更新器接收已發布的版本，自己的設定保留。
