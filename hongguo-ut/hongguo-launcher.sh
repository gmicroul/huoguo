#!/bin/sh
# hongguo-ut 启动脚本（红果短剧 H5 壳，不用 Waydroid）
# 原理：系统自带的 webapp-container（QtWebEngine + mirclient 原生触摸）
# 照 mpv-ut-launcher.sh 的三条经验：mirclient 平台、单实例、日志落盘。

HOME_DIR=/home/phablet
APP_DIR="$HOME_DIR/huoguo/hongguo-ut"
LOG=/tmp/hongguo-ut.log

# 单实例：桌面图标每点一次就多一个进程，旧的先清掉
for pid in $(pgrep -f "webapp-container.*hongguo-ut" 2>/dev/null); do
    [ "$pid" = "$$" ] && continue
    kill "$pid" 2>/dev/null
done
sleep 0.4

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export QT_QPA_PLATFORM=ubuntumirclient
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-mir}"
[ -S /run/user/$(id -u)/bus ] || sleep 1

HOMEPAGE="https://hongguoduanju.com/"
# 站内 + 图片/视频 CDN 放行，其它站外链接用 overlay 打开，不会把 webapp 顶掉
URL_PATTERNS="https://hongguoduanju.com/*,https://*.hongguoduanju.com/*,https://*.byteimg.com/*,https://*.bytegecko.com/*,https://*.fqnovelstatic.com/*,https://*.toutiao.com/*,https://*.douyincdn.com/*,https://*.snssdk.com/*,https://*.toutiaocdn.com/*"
# 移动端 UA，拿到手机版 H5 布局（竖屏短剧流）
UA="Mozilla/5.0 (Linux; Android 10; Volla Phone Build/QP1A.191005.007) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.144 Mobile Safari/537.36"

echo "=== 启动 $(date '+%H:%M:%S') pid=$$ ===" >> "$LOG"
exec /usr/bin/webapp-container \
  --app-id=hongguo-ut \
  --name="红果短剧" \
  --icon="$APP_DIR/hongguo-ut.png" \
  --homepage="$HOMEPAGE" \
  --webappUrlPatterns="$URL_PATTERNS" \
  --user-agent-string="$UA" \
  --store-session-cookies \
  --enable-back-forward \
  --enable-media-hub-audio \
  --open-external-url-in-overlay \
  --fullscreen \
  "$HOMEPAGE" >> "$LOG" 2>&1
