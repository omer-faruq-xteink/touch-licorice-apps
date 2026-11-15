// A map tile as the reader decodes it fastest: a 256 x 256 1-bit BMP (palette black, white; rows
// bottom-up, as Pillow writes mode "1"), compressed with zlib (CompressionStream "deflate" is the
// zlib format, which ctx.zlib:decompress reads).

const S = 256;
const ROW = S / 8;                 // 32 bytes, already a multiple of 4
const HEAD = 62;

// bits: S*S bytes, 1 = black; -> the BMP file
export function bmp1(bits) {
  const out = new Uint8Array(HEAD + ROW * S);
  const v = new DataView(out.buffer);
  out[0] = 0x42; out[1] = 0x4d;
  v.setUint32(2, out.length, true);
  v.setUint32(10, HEAD, true);
  v.setUint32(14, 40, true);
  v.setInt32(18, S, true);
  v.setInt32(22, S, true);
  v.setUint16(26, 1, true);
  v.setUint16(28, 1, true);
  v.setUint32(34, ROW * S, true);
  v.setUint32(38, 2835, true);
  v.setUint32(42, 2835, true);
  v.setUint32(46, 2, true);
  out.set([0, 0, 0, 0, 255, 255, 255, 0], 54);
  for (let y = 0; y < S; y++) {
    const row = HEAD + (S - 1 - y) * ROW;          // bottom-up
    for (let x = 0; x < S; x += 8) {
      let byte = 0;
      for (let k = 0; k < 8; k++) byte = (byte << 1) | (bits[y * S + x + k] ? 0 : 1);   // 1 = white
      out[row + x / 8] = byte;
    }
  }
  return out;
}

export function isBlank(bits) {
  for (let i = 0; i < bits.length; i++) if (bits[i]) return false;
  return true;
}

export async function zlib(bytes) {
  const cs = new Blob([bytes]).stream().pipeThrough(new CompressionStream('deflate'));
  return new Uint8Array(await new Response(cs).arrayBuffer());
}
