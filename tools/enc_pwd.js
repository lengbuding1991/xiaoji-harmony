// hvigor 口令加解密：复刻 hvigor-ohos-plugin 的 DecipherUtil
// 密文格式：[4 字节 BE = 密文+tag 长度][IV][密文][16 字节 tag]，hex 大写
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const component = new Int8Array([49,243,9,115,214,175,91,184,211,190,177,88,101,131,192,119]);

function readDirBytes(p) {
  const e = fs.readdirSync(p);
  return new Int8Array(fs.readFileSync(path.resolve(p, e[0])));
}
function readFd(dir) {
  return fs.readdirSync(dir).filter(f => f !== '.DS_Store').map(f => readDirBytes(path.resolve(dir, f)));
}
function xor(a, b) {
  const i = new Int8Array(a.byteLength);
  for (let e = 0; e < a.byteLength; e++) i[e] = a[e] ^ b[e];
  return i;
}
function xorComponents(arr) {
  let e = xor(arr[0], arr[1]);
  for (let i = 2; i < arr.length; i++) e = xor(e, arr[i]);
  return Buffer.from(e);
}
function getRealKey() {
  const mat = path.resolve(process.env.HOME, '.ohos/config/material');
  const root = new Int8Array(crypto.pbkdf2Sync(
    xorComponents(readFd(path.resolve(mat, 'fd')).concat([component])).toString(),
    readDirBytes(path.resolve(mat, 'ac')), 10000, 16, 'sha256'));
  return gcmDecrypt(root, readDirBytes(path.resolve(mat, 'ce')));
}
function gcmDecrypt(key, blob) {
  const r = new Int8Array(blob);
  const e = ((255 & r[0]) << 24 | (255 & r[1]) << 16 | (255 & r[2]) << 8 | 255 & r[3]) >>> 0;
  const ivLen = r.length - 4 - e;                       // IV 长度
  const iv = Buffer.from(r.slice(4, 4 + ivLen));
  const tag = Buffer.from(r.slice(r.length - 16));
  const d = crypto.createDecipheriv('aes-128-gcm', key, iv);
  d.setAuthTag(tag);
  return Buffer.concat([d.update(Buffer.from(r.subarray(4 + ivLen, r.length - 16))), d.final()]);
}
function gcmEncrypt(key, plain) {
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-128-gcm', key, iv);
  const ct = Buffer.concat([c.update(Buffer.from(plain, 'utf-8')), c.final()]);
  const tag = c.getAuthTag();
  const head = Buffer.alloc(4);
  head.writeUInt32BE(ct.length + tag.length, 0);         // 头 = 密文+tag 长度
  return Buffer.concat([head, iv, ct, tag]).toString('hex').toUpperCase();
}

const key = getRealKey();
if (process.argv[2] === 'decrypt') {
  console.log(gcmDecrypt(key, Buffer.from(process.argv[3], 'hex')).toString('utf-8'));
} else if (process.argv[2] === 'key') {
  console.log(Buffer.from(key).toString('hex'));
} else {
  console.log(gcmEncrypt(key, process.argv[3]));
}
