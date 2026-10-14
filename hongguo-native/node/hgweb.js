// 官网 H5 数据层：榜单 / 搜索 / 详情 / 全集 vid_list（纯 GET，无签名）
// 用法：node hgweb.js rank <hot-drama|...> | search <关键词> | detail <sid>
// 输出 JSON 到 stdout。注意：QtNetwork 会被服务端降级返回残缺页，
// 实测 node fetch 与 curl 均正常，故统一走本 helper。
const SITE = 'https://hongguoduanju.com';
const UA = 'Mozilla/5.0 (Linux; Android 10; Volla Phone Build/QP1A.191005.007) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.144 Mobile Safari/537.36';

async function fetchText(url, headers, timeout) {
  if (typeof headers === 'number' || headers === undefined) {
    timeout = typeof headers === 'number' ? headers : 25000;
    headers = null;
  }
  timeout = timeout || 25000;
  headers = headers || {
    'User-Agent': UA,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9',
    'Referer': SITE + '/',
  };
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeout);
  try {
    const res = await fetch(url, { headers, signal: ctrl.signal });
    if (!res.ok) throw new Error('HTTP ' + res.status);
    return await res.text();
  } finally { clearTimeout(t); }
}

function unesc(s) {
  return String(s || '').replace(/\\u002F/g, '/').replace(/\\u0026/g, '&').replace(/\\\//g, '/').replace(/&amp;/g, '&');
}

function firstGroup(text, re) {
  const m = text.match(re);
  return m ? m[1] : '';
}

// <a aria-label="查看XXX" href="/detail?series_id=SID"> … <img src="COVER"
function parseCards(html) {
  const out = [];
  const seen = new Set();
  for (const m of html.matchAll(/<a\b[^>]*href="\/detail\?series_id=(\d+)"[^>]*>/g)) {
    const sid = m[1];
    if (seen.has(sid)) continue;
    seen.add(sid);
    const tag = m[0];
    const tail = html.slice(m.index + tag.length, m.index + tag.length + 3000);
    let label = ((tag.match(/aria-label="查看([^"]*)"/) || [])[1] || '').trim();
    if (!label) {
      const h3 = ((tail.match(/<h3\b[^>]*>([\s\S]{0,300}?)<\/h3>/) || [])[1] || '').trim();
      if (h3) label = h3.replace(/<[^>]+>/g, ''); // 关键词高亮 <em> 去掉
    }
    if (!label) {
      const alt = ((tail.match(/<img\b[^>]*alt="([^"]*)"/) || [])[1] || '').trim();
      label = alt.replace(/封面$/, '');
    }
    if (!label) label = sid;
    const img = tail.match(/<img\b[^>]*src="(https:\/\/[^"]+)"/);
    out.push({ sid, title: label, cover: img ? img[1] : '' });
  }
  return out;
}

async function rank(rankId) {
  return parseCards(await fetchText(`${SITE}/rank/${rankId}`));
}

async function search(keyword) {
  return parseCards(await fetchText(`${SITE}/search/${encodeURIComponent(keyword)}`));
}

async function detail(sid) {
  const d = { sid: String(sid), title: '', cover: '', intro: '', tags: [], total: '', accessible: 0, episodes: [] };
  try {
    const dh = await fetchText(`${SITE}/detail?series_id=${sid}`);
    d.title = firstGroup(dh, /"series_name"\s*:\s*"((?:[^"\\]|\\.)*)"/);
    d.cover = unesc(firstGroup(dh, /"series_cover"\s*:\s*"((?:[^"\\]|\\.)*)"/));
    d.intro = firstGroup(dh, /"series_intro"\s*:\s*"((?:[^"\\]|\\.)*)"/);
    d.total = firstGroup(dh, /"episode_cnt"\s*:\s*(\d+)/);
    const tagBody = firstGroup(dh, /"tags"\s*:\s*\[([^\]]*)\]/);
    d.tags = [...tagBody.matchAll(/"([^"]+)"/g)].map((m) => m[1]);
  } catch (_) {}
  const ph = await fetchText(`${SITE}/player/${sid}`);
  if (!d.title) d.title = firstGroup(ph, /"series_name"\s*:\s*"((?:[^"\\]|\\.)*)"/);
  if (!d.cover) d.cover = unesc(firstGroup(ph, /"series_cover"\s*:\s*"((?:[^"\\]|\\.)*)"/));
  if (!d.intro) d.intro = firstGroup(ph, /"series_intro"\s*:\s*"((?:[^"\\]|\\.)*)"/);
  const accessible = parseInt(firstGroup(ph, /"accessible_episode_cnt"\s*:\s*(\d+)/) || '0', 10);
  const vl = firstGroup(ph, /"vid_list"\s*:\s*\[([^\]]*)\]/);
  const vids = [...vl.matchAll(/"(\d+)"/g)].map((m) => m[1]);
  d.accessible = accessible;
  d.episodes = vids.map((vid, i) => ({ vid, index: i + 1, web: i < accessible }));
  if (!d.total) d.total = String(vids.length);
  return d;
}

function normUrl(raw) {
  return String(raw || '')
    .replace(/\\u002F/g, '/').replace(/\\u0026/g, '&').replace(/&amp;/g, '&')
    .replace(/([?&])Range=[^&]*/gi, '$1').replace(/[?&]$/, '');
}

// 网页免签直链：/player/<sid>/<vid> 内嵌 VideoObject.contentUrl（仅可看集数有）
// 第 1 集的官方页是 /player/<sid>（无 vid 后缀），此时只认 vid_list 首个。
async function webDirectUrl(sid, vid) {
  const html = await fetchText(`${SITE}/player/${sid}/${vid}`, {
    'User-Agent': UA, 'Accept': 'text/html,*/*;q=0.8', 'Referer': SITE + '/',
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
    const ok = pagePath === wantPath ||
      (pagePath === seriesPath && String(firstVid) === String(vid));
    if (!ok) continue;
    const u = normUrl(v.contentUrl);
    if (/^https:\/\/hongguoduanju\.com\/video\//.test(u)) return u;
  }
  return null;
}

async function main() {
  const [cmd, arg, arg2] = process.argv.slice(2);
  try {
    if (cmd === 'rank') console.log(JSON.stringify(await rank(arg)));
    else if (cmd === 'search') console.log(JSON.stringify(await search(arg)));
    else if (cmd === 'detail') console.log(JSON.stringify(await detail(arg)));
    else if (cmd === 'weburl') console.log(JSON.stringify({ url: (await webDirectUrl(arg, arg2)) || '' }));
    else throw new Error('未知命令');
  } catch (e) {
    console.log(JSON.stringify({ __error: String(e?.message || e) }));
    process.exit(1);
  }
}

if (require.main === module) main();

module.exports = { fetchText, unesc, firstGroup, parseCards, rank, search, detail, webDirectUrl, normUrl, SITE, UA };
