// 签名取流冒烟测试：对超出网页可看范围的分集（ep6）取 App 播放地址
const { fetchAppPlayUrl } = require('./vendor/app-source.js');

(async () => {
  const vid = process.argv[2] || '7686715400607779902'; // 首辅娇娘 ep6（网页只放前几集）
  const t0 = Date.now();
  const r = await fetchAppPlayUrl(vid, { quality: 'auto' });
  console.log('OK ms=' + (Date.now() - t0), 'source=' + r.source, 'codec=' + r.codec, 'quality=' + r.quality);
  console.log('url=' + String(r.url || '').slice(0, 160));
  console.log('hasKey=' + !!r.contentKey, 'variants=' + (r.variants ? r.variants.length : 0));
})().catch((e) => { console.error('FAIL:', e.message); process.exit(1); });
