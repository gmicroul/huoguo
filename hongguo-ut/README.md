# hongguo-ut（红果短剧 · 本机原生壳，不用 Waydroid）

原理：系统自带 `webapp-container`（QtWebEngine + mirclient 原生触摸），
套 `https://hongguoduanju.com/` H5。参考 `mpv-ut` 的直装模式：
二进制/脚本在 `~/hongguo-ut/`，桌面入口在 `~/.local/share/applications/`。

## 文件

- `hongguo-launcher.sh`：启动脚本（单实例、mirclient、移动端 UA、cookie 持久、media-hub 音频）
- `hongguo-ut.desktop`：桌面入口，`Icon=hongguo-ut`
- `hongguo-ut.png`：512x512 图标，已同步到 `~/.local/share/icons/hicolor/*/apps/`

## 安装（已完成）

```sh
cp hongguo-ut.desktop ~/.local/share/applications/hongguo-ut.desktop
cp hongguo-ut.png ~/.local/share/icons/hicolor/256x256/apps/hongguo-ut.png
cp hongguo-ut.png ~/.local/share/icons/hicolor/512x512/apps/hongguo-ut.png
cp hongguo-ut.png ~/.local/share/icons/hicolor/128x128/apps/hongguo-ut.png
```

桌面下拉搜索“红果”即可看到。点图标启动，日志在 `/tmp/hongguo-ut.log`。

## 说明

- 登录态靠 `--store-session-cookies` 持久，存在 `~/.local/share/hongguo-ut/`
- 站外下载跳转（ugurl.cn 等）用 overlay 打开，不会顶掉主页面
- v1 未注入 user-script，如 H5 的“下载 App”横幅挡事，下一步加 `--user-scripts` 隐藏
