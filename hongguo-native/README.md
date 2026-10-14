# hongguo-native（红果短剧本机原生版 v0.1，不用 Waydroid）

Qt Quick + mirclient 原生触摸（照 mpv-ut 路子），播放走 QtMultimedia/media-hub，
有画面有声音（HEVC/AAC 已在 mpv-ut 上实测可播）。

## 数据链

- 榜单/搜索/详情/全集 `vid_list`：官网 H5 纯 GET，无签名（`node/hgweb.js`）。
  注意：QtNetwork 会被服务端降级（残缺页），故统一走 node fetch，C++ 只做编排。
- 非可看集高清流：`node/fullfetch.js` → vendored X-Gorgon 全套签名
  （`node/vendor/app-source.js`）→ curl 下载（qznovelvod 按 TLS 指纹拦 node fetch，
  curl 正常）→ AES-CTR 解密（`node/vendor/hongguo.js`）→ 落盘
  `~/.cache/hongguo-native/<vid>.mp4`。
- 可看集：网页 360p H264 直链，免解密，最快。

## 文件

- `main.cpp`：Backend（榜单/搜索/详情/取流/历史/断点）+ mirclient 启动
- `qml/Main.qml`：榜单+搜索 / 详情选集 / 播放（连播、断点续播、缓存标记）
- `node/`：hgweb.js、fullfetch.js、vendor/（第三方签名/解密实现，见 ATTRIBUTION.md）
- `build.sh`：复用 `~/opt/qtdev` 工具链（参考 `~/mpv-ut/build.sh`）
- `hongguo-launcher.sh`、`hongguo-native.desktop`：桌面入口，图标 `hongguo-native`

## 构建安装（已完成）

```sh
./build.sh
cp hongguo-native.desktop ~/.local/share/applications/
for s in 512x512 256x256 128x128; do
  cp hongguo-native.png ~/.local/share/icons/hicolor/$s/apps/hongguo-native.png
done
```

日志：`/tmp/hongguo-native.log`。缓存：`~/.cache/hongguo-native/`。
注意：`node`（/usr/bin/node）必须存在，取流依赖它。

## 合规提醒

仅供个人学习研究。vendor/ 代码遵循原仓库 GPL-3.0-only（见 ATTRIBUTION.md）。
风控/接口变更时以官方 App 为准；签名算法来自公开研究，失效需跟进上游。
