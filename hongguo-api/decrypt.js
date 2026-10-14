// 解密已下载的加密分集：node decrypt.js <vid>
const fs = require('fs');
const { deriveKey, decryptMp4File } = require('./vendor/hongguo.js');

const vid = process.argv[2];
if (!vid) { console.error('usage: node decrypt.js <vid>'); process.exit(2); }
const info = JSON.parse(fs.readFileSync(`ep-${vid}.json`, 'utf8'));
if (!info.contentKey) { console.error('no contentKey, nothing to decrypt'); process.exit(1); }
const key = Buffer.from(info.contentKey, 'hex');
decryptMp4File('/tmp/hg-ep6-enc.mp4', `/tmp/hg-ep6-dec.mp4`, key);
console.log('decrypted, size=' + fs.statSync('/tmp/hg-ep6-dec.mp4').size);
