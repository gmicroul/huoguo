#!/bin/sh
# 对照测试 B2：绕过旧 Chromium 的 CORS 预检（Range 头被 qznovelvod.com 拒绝的问题），
# 让 DASH 音频分段能经 fetch+MSE 加载。只改 flag，其它和正式版一致。
# 用法：先把红果关掉，在终端跑：/home/phablet/huoguo/hongguo-ut/test-b2.sh
HOME_DIR=/home/phablet
APP_DIR="$HOME_DIR/huoguo/hongguo-ut"
LOG=/tmp/hongguo-ut-b2.log
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export QT_QPA_PLATFORM=ubuntumirclient
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-mir}"
export QTWEBENGINE_CHROMIUM_FLAGS="--disable-web-security --autoplay-policy=no-user-gesture-required"
HOMEPAGE="https://hongguoduanju.com/"
URL_PATTERNS="https://hongguoduanju.com/*,https://*.hongguoduanju.com/*,https://*.byteimg.com/*,https://*.bytegecko.com/*,https://*.fqnovelstatic.com/*,https://*.toutiao.com/*,https://*.douyincdn.com/*,https://*.snssdk.com/*,https://*.toutiaocdn.com/*,https://*.qznovelvod.com/*"
UA="Mozilla/5.0 (Linux; Android 10; Volla Phone Build/QP1A.191005.007) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.144 Mobile Safari/537.36"
echo "=== B2 启动 $(date '+%H:%M:%S') ===" >> "$LOG"
exec /usr/bin/webapp-container \
  --app-id=hongguo-ut \
  --name="红果短剧" \
  --homepage="$HOMEPAGE" \
  --webappUrlPatterns="$URL_PATTERNS" \
  --user-agent-string="$UA" \
  --store-session-cookies \
  --enable-back-forward \
  --enable-media-hub-audio \
  --open-external-url-in-overlay \
  --fullscreen \
  "$HOMEPAGE" >> "$LOG" 2>&1
