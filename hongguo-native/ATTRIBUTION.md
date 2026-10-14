# 第三方代码归属（node/vendor/）

本目录下签名与解密实现 vendored 自公开研究项目，仅供学习研究：

- `app-source.js`、`sm3.js`、`download-quality.js`、`hongguo.js`、`web-media-guard.js`
  来源：https://github.com/jackotom/hongguo-drama （`src/native/`）
  许可：GPL-3.0-only（见各文件头 SPDX 标识）
- 其中签名算法（X-Gorgon / X-Medusa / X-Helios / spade_a）据其文件头注释
  改编自 woshishiq1/drpys，经 N3urda/hongguoTV 流传的公开实现。
- `node_modules/axios/` 下的 `index.js` + `package.json` 是本项目自写
  的最小兼容垫片（基于 Node 全局 fetch，无第三方依赖），非 axios 本体。

上游更新（接口/签名变更）时，优先同步上游仓库后再 vendor。
