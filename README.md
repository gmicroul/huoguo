# huoguo（红果短剧 · Ubuntu Touch 本机版，不用 Waydroid）

| 目录 | 说明 |
|---|---|
| `hongguo-native/` | 原生 App（Qt Quick + mirclient，QtMultimedia/media-hub 播放），全集选集 + 高清，正式版 |
| `hongguo-ut/` | 旧 H5 壳（webapp-container 套官网），备用 |
| `hongguo-api/` | 逆向实验场（签名验证、解密测试脚本） |

数据链：官网 H5 免签（榜单/搜索/详情/全集 vid_list）+ X-Gorgon 签名取高清流 +
AES-CTR 解密落盘。第三方签名/解密实现见 `hongguo-native/ATTRIBUTION.md`
（GPL-3.0-only）。

仅供个人学习研究。
