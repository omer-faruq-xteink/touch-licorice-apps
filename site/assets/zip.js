// Reading and writing zip files with the platform's own (de)compression streams: no library.
// Works in browsers and in Node 18+ (the tests run it there).
//
//   const files = await readZip(bytes)            -> [{ name, bytes }]  (stored and deflated entries)
//   const blob  = await writeZip([{ name, data }]) -> Uint8Array          (data: string or Uint8Array)
//   gunzip(bytes), untar(bytes)

const enc = new TextEncoder();

async function pipe(bytes, stream) {
  const out = new Response(new Blob([bytes]).stream().pipeThrough(stream));
  return new Uint8Array(await out.arrayBuffer());
}
export const inflateRaw = (b) => pipe(b, new DecompressionStream('deflate-raw'));
export const deflateRaw = (b) => pipe(b, new CompressionStream('deflate-raw'));
export const gunzip = (b) => pipe(b, new DecompressionStream('gzip'));

let CRC;
function crc32(b) {
  if (!CRC) {
    CRC = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      CRC[n] = c >>> 0;
    }
  }
  let c = 0xffffffff;
  for (let i = 0; i < b.length; i++) c = CRC[(c ^ b[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

export async function readZip(bytes) {
  const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let eocd = -1;
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 65557); i--) {
    if (dv.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error('not a zip file');
  let count = dv.getUint16(eocd + 10, true);
  let p = dv.getUint32(eocd + 16, true);
  const out = [];
  const dec = new TextDecoder();
  while (count-- > 0 && dv.getUint32(p, true) === 0x02014b50) {
    const method = dv.getUint16(p + 10, true);
    const csize = dv.getUint32(p + 20, true);
    const nlen = dv.getUint16(p + 28, true), xlen = dv.getUint16(p + 30, true), clen = dv.getUint16(p + 32, true);
    const local = dv.getUint32(p + 42, true);
    const name = dec.decode(bytes.subarray(p + 46, p + 46 + nlen));
    p += 46 + nlen + xlen + clen;
    if (name.endsWith('/')) continue;
    const start = local + 30 + dv.getUint16(local + 26, true) + dv.getUint16(local + 28, true);
    const raw = bytes.subarray(start, start + csize);
    if (method === 0) out.push({ name, bytes: raw.slice() });
    else if (method === 8) out.push({ name, bytes: await inflateRaw(raw) });
    else throw new Error(`${name}: unsupported zip compression (${method})`);
  }
  return out;
}

export async function writeZip(files) {
  const parts = [], central = [];
  let offset = 0;
  const now = new Date();
  const dtime = (now.getHours() << 11) | (now.getMinutes() << 5) | (now.getSeconds() >> 1);
  const ddate = ((now.getFullYear() - 1980) << 9) | ((now.getMonth() + 1) << 5) | now.getDate();
  for (const f of files) {
    const data = typeof f.data === 'string' ? enc.encode(f.data) : f.data;
    const name = enc.encode(f.name);
    const comp = await deflateRaw(data);
    const store = comp.length >= data.length;
    const body = store ? data : comp;
    const crc = crc32(data);
    const head = new Uint8Array(30 + name.length);
    const h = new DataView(head.buffer);
    h.setUint32(0, 0x04034b50, true); h.setUint16(4, 20, true); h.setUint16(6, 0x0800, true);
    h.setUint16(8, store ? 0 : 8, true); h.setUint16(10, dtime, true); h.setUint16(12, ddate, true);
    h.setUint32(14, crc, true); h.setUint32(18, body.length, true); h.setUint32(22, data.length, true);
    h.setUint16(26, name.length, true); head.set(name, 30);
    const cen = new Uint8Array(46 + name.length);
    const c = new DataView(cen.buffer);
    c.setUint32(0, 0x02014b50, true); c.setUint16(4, 20, true); c.setUint16(6, 20, true); c.setUint16(8, 0x0800, true);
    c.setUint16(10, store ? 0 : 8, true); c.setUint16(12, dtime, true); c.setUint16(14, ddate, true);
    c.setUint32(16, crc, true); c.setUint32(20, body.length, true); c.setUint32(24, data.length, true);
    c.setUint16(28, name.length, true); c.setUint32(42, offset, true); cen.set(name, 46);
    parts.push(head, body);
    central.push(cen);
    offset += head.length + body.length;
  }
  const csize = central.reduce((n, b) => n + b.length, 0);
  const end = new Uint8Array(22);
  const e = new DataView(end.buffer);
  e.setUint32(0, 0x06054b50, true); e.setUint16(8, files.length, true); e.setUint16(10, files.length, true);
  e.setUint32(12, csize, true); e.setUint32(16, offset, true);
  const all = [...parts, ...central, end];
  const out = new Uint8Array(all.reduce((n, b) => n + b.length, 0));
  let p = 0;
  for (const b of all) { out.set(b, p); p += b.length; }
  return out;
}

// a .tar (after gunzip for .tar.gz): [{ name, bytes }]
export function untar(bytes) {
  const out = [];
  const dec = new TextDecoder();
  let p = 0;
  while (p + 512 <= bytes.length) {
    const name = dec.decode(bytes.subarray(p, p + 100)).replace(/\0.*$/s, '');
    if (!name) break;
    const size = parseInt(dec.decode(bytes.subarray(p + 124, p + 136)).replace(/\0.*$/s, '').trim() || '0', 8);
    const type = String.fromCharCode(bytes[p + 156] || 48);
    const prefix = dec.decode(bytes.subarray(p + 345, p + 500)).replace(/\0.*$/s, '');
    if (type === '0' || type === '\0') out.push({ name: prefix ? prefix + '/' + name : name, bytes: bytes.slice(p + 512, p + 512 + size) });
    p += 512 + Math.ceil(size / 512) * 512;
  }
  return out;
}
