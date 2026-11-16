// Writing a pack to the reader's card in pieces, so the page can show how far the copy is: over USB a
// pack of tens of MB takes a while. onProgress({ done, total }) after each piece, then once with
// closing: true before close(), which can take a while too (the browser moves the file into place).
export async function writeChunked(writable, bytes, onProgress, chunk = 256 * 1024) {
  const total = bytes.length;
  for (let done = 0; done < total;) {
    const end = Math.min(total, done + chunk);
    await writable.write(bytes.subarray(done, end));
    done = end;
    onProgress({ done, total });
  }
  onProgress({ done: total, total, closing: true });
  await writable.close();
}
