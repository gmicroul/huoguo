#!/bin/sh
# 对照测试 B1：去掉 --enable-media-hub-audio，让 Chromium 音频直走 PulseAudio
# （本机 uvideo 这个 QtWebEngine 应用就是直走 pulse 且有声的）
# 用法：先把红果关掉，在终端跑：/home/phablet/huoguo/hongguo-ut/test-b1.sh
HOME_DIR=/home/phablet
APP_DIR="$HOME_DIR/huoguo/hongguo-ut"
LOG=/tmp/hongguo-ut-b1.log
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export QT_QPA_PLATFORM=ubuntumirclient
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-mir}"
HOMEPAGE="https://hongguoduanju.com/"
URL_PATTERNS="https://hongguoduanju.com/*,https://*.hongguoduanju.com/*,https://*.byteimg.com/*,https://*.bytegecko.com/*,https://*.fqnovelstatic.com/*,https://*.toutiao.com/*,https://*.douyincdn.com/*,https://*.snssdk.com/*,https://*.toutiaocdn.com/*,https://*.qznovelvod.com/*"
UA="Mozilla/5.0 (Linux; Android 10; Volla Phone Build/QP1A.191005.007) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.144 Mobile Safari/537.36"
echo "=== B1 启动 $(date '+%H:%M:%S') ===" >> "$LOG"
exec /usr/bin/webapp-container \
  --app-id=hongguo-ut \
  --name="红果短剧" \
  --homepage="$HOMEPAGE" \
  --webappUrlPatterns="$URL_PATTERNS" \
  --user-agent-string="$UA" \
  --store-session-cookies \
  --enable-back-forward \
  --open-external-url-in-overlay \
  --fullscreen \
  "$HOMEPAGE" >> "$LOG" 2>&1
