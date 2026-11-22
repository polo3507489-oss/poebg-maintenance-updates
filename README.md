# PoeBG 維護版更新

[下載最新版](https://github.com/polo3507489-oss/poebg-maintenance-updates/releases/latest)

第一次請下載 `PoeBG-friends-autoupdate-版本.zip`，完整解壓到可寫入的新資料夾，執行 `PoeBGFriendsUpdater.exe`。設定自己的主人名稱及行走鍵，再按需求勾選功能。

之後啟動時會檢查維護版更新。確認下載、儲存設定並正常關閉 PoeBG 後，更新器會備份、驗證、安裝並重新開啟。原版更新通知仍保留。

更新保留 Role、勞工設定、INI、日誌及 *.settings 功能開關；失敗會還原。從舊版搬移設定時，請先關閉兩份 PoeBG，再複製自己的 Role 資料夾和 PoeBG-maintenance 下的 *.settings。

`PoeBG-maintenance.zip`、`update.json`、`update.sig` 供自動更新使用；第一次安裝請選朋友完整 ZIP。

更新檔採 RSA-SHA256 簽章及 SHA256 檢查。不需要 GitHub 登入或權杖，更新器只向 GitHub 查詢及下載，不附帶遊戲帳號或角色設定。這不代表對原版軟體其他網路功能做出保證。

新增功能或修正必須由維護者發布新的 Release，朋友才能取得；未發布的本機改動不會同步。

這是維護版發佈來源，並非原作者的官方儲存庫。
