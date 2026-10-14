// 取完整播放信息并存 JSON（含全 URL、key、全部清晰度变体）
const fs = require('fs');
const { fetchAppPlayUrl } = require('./vendor/app-source.js');

(async () => {
  const vid = process.argv[2];
  if (!vid) { console.error('usage: node fetch-ep.js <vid>'); process.exit(2); }
  const r = await fetchAppPlayUrl(vid, { quality: 'auto' });
  const out = {
    vid: r.vid, source: r.source, codec: r.codec, quality: r.quality,
    url: r.url, contentKey: r.contentKey || null,
    userAgent: r.userAgent, referer: r.referer,
    variants: (r.variants || []).map((v) => ({
      url: v.url, codec: v.codec, quality: v.quality,
      contentKey: v.contentKey || null, width: v.width, height: v.height,
    })),
  };
  fs.writeFileSync(`ep-${vid}.json`, JSON.stringify(out, null, 1));
  console.log('saved ep-' + vid + '.json variants=' + out.variants.length);
  for (const v of out.variants) console.log(' -', v.codec, v.quality, v.width + 'x' + v.height, 'key=' + !!v.contentKey);
})().catch((e) => { console.error('FAIL:', e.message); process.exit(1); });
