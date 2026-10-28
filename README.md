# Video Saver Maker

將一個或多個影片包成可安裝的 macOS `.saver` 屏保。

## 靈感來源✨
自定義牆紙：
https://jingyuan-zheng.github.io/zh/p/macos-custom-video-wallpaper-snoopy/

snoopy屏保程式
https://github.com/hitnology/snoopy


## 使用

1. 雙擊工作資料夾內的 **Video Saver Maker.app**。
2. 將影片拖到上方區域，或按「加入影片…」多選。支援 MP4、MOV、M4V 容器；實際影像編碼須能由 macOS AVFoundation 播放。
3. 設定名稱、播放順序及畫面比例。可移除影片，或選取一列後按「上移／下移」。
4. 按「輸出 .saver…」，選擇輸出資料夾。
5. 完成後按「安裝屏保」，或在 Finder 雙擊輸出的 `.saver`，依系統指示安裝，再到系統設定選擇屏保並預覽。

多個影片會合成**一個屏保**。依序模式照列表循環；隨機模式在每次屏保啟動時打亂順序，再循環播放。所有影片靜音。填滿模式維持比例並裁切邊緣，完整顯示模式維持比例並可能留黑邊。

影片以原始品質複製到屏保內，不轉碼；安裝後可移動或刪除原始影片。輸出大小約為所有影片大小總和。同名輸出不會被覆寫；請改名或選其他資料夾。重新製作同名屏保時，系統可將它視作同一屏保的更新。

這是傳統 macOS 屏保，沒有系統影片桌布的解鎖減速定格效果。

## 系統需求及驗證

- 建置目標：macOS 12 及以上，Apple Silicon 和 Intel 通用版本。使用者執行製作工具與安裝輸出屏保不需 Xcode。
- 製作工具和輸出使用本機 ad-hoc 簽章，未使用 Apple Developer ID 或公證。跨機散佈後，可能需要透過「系統設定 → 隱私權與安全性」允許開啟。
- 已驗證：單影片／多影片輸出、影片內容完整性、中文名稱、重名影片、防覆寫、錯誤處理、清理暫存、簽章及多個屏保同時載入時的資源隔離。
- 本次執行環境無法開啟 Mac 圖形介面，因此拖放、視窗版面及系統屏保播放尚未做桌面實測。先前 `Sky.mp4` 的 AVFoundation 解碼測試也回傳解碼器錯誤；此工具不會透過轉碼修復原影片，請在系統預覽確認效果。

## 重新建置

需要 Apple Command Line Tools：

```sh
bash VideoSaverMaker-source/build.sh
python3 VideoSaverMaker-source/test_export.py Sky.mp4
```

`App.m` 是原生 AppKit 介面；`SaverExporter.m` 是 UI 與命令列共用的輸出器；`VideoScreenSaver.m` 是屏保引擎。

程式內嵌預先編譯的通用屏保引擎，輸出時複製影片、建立播放清單、設定名稱並重新簽章。輸出器將引擎中固定長度的類別名稱替換成由屏保名稱產生的獨立名稱，讓系統預覽同時載入不同屏保時不會混用資源。此步驟不需在使用者電腦上編譯。

## 命令列輸出

```sh
"./Video Saver Maker.app/Contents/MacOS/VideoSaverMaker" \
  --export --name "My Video Saver" --output "/path/to/output" \
  "/path/to/first.mp4" "/path/to/second.mov"
```

加上 `--shuffle` 啟用隨機順序；`--fit` 啟用完整顯示。
