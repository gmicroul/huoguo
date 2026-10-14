// 全集取流 + 下载 + 解密：node fullfetch.js <sid> <vid> <outdir>
// 输出：最后一行 stdout 为 JSON {file, via, codec} 或 {error}
// 进度打到 stderr（ST:xxx），C++ 端实时读来更新界面。
// 优先级：网页免签 360p 直链（快、无加密）→ App 签名高清流（需解密）。
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const SITE = 'https://hongguoduanju.com';
const WEB_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

const st = (s) => { try { fs.writeSync(2, 'ST:' + s + '\n'); } catch (_) {} };
const done = (obj) => { console.log(JSON.stringify(obj)); };

function normUrl(raw) {
  return String(raw || '')
    .replace(/\\u002F/g, '/').replace(/\\u0026/g, '&').replace(/&amp;/g, '&')
    .replace(/([?&])Range=[^&]*/gi, '$1').replace(/[?&]$/, '');
}

async function fetchText(url, headers, timeout = 25000) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeout);
  try {
    const res = await fetch(url, { headers, signal: ctrl.signal, redirect: 'follow' });
    if (!res.ok) throw new Error('HTTP ' + res.status);
    return await res.text();
  } finally { clearTimeout(t); }
}

async function downloadToFile(url, headers, dest, timeout = 180) {
  // 注意：qznovelvod CDN 会按 TLS 指纹拦 undici(node fetch) → 403，
  // curl 则正常。用 curl 落盘，避免大文件进内存。
  const args = ['-sS', '-L', '--max-time', String(timeout), '-o', dest,
    '-A', headers['User-Agent'] || WEB_UA];
  if (headers['Referer']) args.push('-e', headers['Referer']);
  args.push(url);
  const r = spawnSync('curl', args, { encoding: 'utf8' });
  if (r.status !== 0) throw new Error('下载失败：' + (r.stderr || ('curl exit ' + r.status)).trim().slice(0, 120));
  let sz = 0;
  try { sz = fs.statSync(dest).size; } catch (_) {}
  if (sz < 100 * 1024) throw new Error('下载内容过小(' + sz + 'B)，可能已失效');
  return dest;
}

// 网页免签直链：/player/<sid>/<vid> 内嵌 VideoObject.contentUrl（仅可看集数有）
async function webDirectUrl(sid, vid) {
  const html = await fetchText(`${SITE}/player/${sid}/${vid}`, {
    'User-Agent': WEB_UA, 'Accept': 'text/html,*/*;q=0.8', 'Referer': SITE + '/',
  }, 20000);
  const wantPath = `/player/${sid}/${vid}`;
  const seriesPath = `/player/${sid}`;
  const vl = html.match(/"vid_list"\s*:\s*\[([^\]]*)\]/);
  const firstVid = vl ? (vl[1].match(/"(\d+)"/) || [])[1] : null;
  for (const m of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi)) {
    if (!/\btype\s*=\s*["']application\/ld\+json["']/i.test(m[1])) continue;
    let v;
    try { v = JSON.parse(m[2]); } catch (_) { continue; }
    if (v?.['@type'] !== 'VideoObject' || !v.contentUrl) continue;
    let pagePath = '';
    try { pagePath = new URL(v.url).pathname; } catch (_) { continue; }
    // 第 1 集的官方页就是 /player/<sid>（无 vid 后缀），此时只认 vid_list 首个
    const ok = pagePath === wantPath ||
      (pagePath === seriesPath && String(firstVid) === String(vid));
    if (!ok) continue; // 只认当前集绑定的，不拿推荐位的
    const u = normUrl(v.contentUrl);
    if (/^https:\/\/hongguoduanju\.com\/video\//.test(u)) return u;
  }
  return null;
}

(async () => {
  const [sid, vid, outdir] = process.argv.slice(2);
  if (!sid || !vid || !outdir) { done({ error: '参数不足' }); process.exit(1); }
  fs.mkdirSync(outdir, { recursive: true });
  const out = path.join(outdir, `${vid}.mp4`);
  try {
    const cur = fs.statSync(out);
    if (cur.size > 1024 * 1024) { done({ file: out, via: 'cache' }); return; }
  } catch (_) {}

  // 1) 网页直链
  try {
    st('正在取网页直链…');
    const wurl = await webDirectUrl(sid, vid);
    if (wurl) {
      st('直链下载中…');
      const tmp = out + '.part';
      await downloadToFile(wurl, { 'User-Agent': WEB_UA, 'Referer': SITE + '/' }, tmp);
      fs.renameSync(tmp, out);
      done({ file: out, via: 'web', codec: 'h264' });
      return;
    }
    st('本集网页无直链，转 App 签名流…');
  } catch (e) { st('网页直链失败(' + e.message + ')，转 App 签名流…'); }

  // 2) App 签名流（偶发被拒则 2 秒后重试一次）
  const { fetchAppPlayUrl } = require('./vendor/app-source.js');
  let info = null;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      if (attempt > 0) {
        st('签名重试…');
        await new Promise((r) => setTimeout(r, 2000));
      } else {
        st('签名取流中…');
      }
      info = await fetchAppPlayUrl(String(vid), { quality: 'auto' });
      if (info && info.url) break;
      info = null;
    } catch (e) {
      st('签名失败(' + String(e?.message || e).slice(0, 60) + ')…');
      info = null;
    }
  }
  if (!info || !info.url) throw new Error('签名接口未返回片源');
  st('高清下载中(' + (info.quality || info.codec || '') + ')…');
  const tmp = out + '.part';
  await downloadToFile(info.url, { 'User-Agent': info.userAgent, 'Referer': info.referer }, tmp);
  if (info.contentKey) {
    st('解密中…');
    const { decryptMp4Buffer } = require('./vendor/hongguo.js');
    const key = Buffer.from(info.contentKey, 'hex');
    const plain = decryptMp4Buffer(fs.readFileSync(tmp), key);
    fs.writeFileSync(out, plain);
    fs.unlinkSync(tmp);
  } else {
    fs.renameSync(tmp, out);
  }
  done({ file: out, via: 'app', codec: info.codec || '' });
})().catch((e) => { done({ error: String(e?.message || e) }); process.exit(1); });
