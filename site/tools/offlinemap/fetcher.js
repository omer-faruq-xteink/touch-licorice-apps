// The map maker's polite tile fetcher: at most `parallel` requests at a time, Retry-After obeyed on
// 429, three retries with backoff on a network error, every tile kept in Cache Storage (a cancelled
// or failed run continues without fetching a tile twice), and at most maxVectorTiles different
// tiles and at most maxBytes (when the source sets it) per pack. registerProtocol() puts it behind MapLibre as xtmap://{z}/{x}/{y}.

export const CACHE = 'offlinemap-tiles-v1';
export const MEMORY_BYTES = 200e6;   // tiles kept in memory per run (Cache Storage can fail)
export const MAX_WAIT_S = 45;           // the longest Retry-After waited out (render.js waits 60 s for a view)

const abortError = () => new DOMException('The run was cancelled.', 'AbortError');

export class TileFetcher {
  constructor(source, { fetch = globalThis.fetch.bind(globalThis), caches = globalThis.caches, signal = null,
    sleep = (ms) => new Promise((r) => setTimeout(r, ms)), onCount = null, memoryBytes = MEMORY_BYTES } = {}) {
    this.source = source;
    this.fetch = fetch;
    this.caches = caches;
    this.signal = signal;
    this.sleep = sleep;
    this.onCount = onCount;
    this.template = source.tiles;
    this.count = 0;          // fetched over the network
    this.fromCache = 0;
    this.bytes = 0;
    this.seen = new Set();
    this.active = 0;
    this.queue = [];
    this.cache = null;
    this.cacheOk = caches ? null : false;    // null: not tried yet
    this.dataDate = null;
    this.pending = new Map();
    this.mem = new Map();    // url -> bytes, oldest first: MapLibre asks a tile again after leaving a view
    this.memBytes = 0;
    this.memoryBytes = memoryBytes;
  }

  remember(url, b) {
    if (b.length > this.memoryBytes) return;
    this.mem.delete(url);
    this.mem.set(url, b);
    this.memBytes += b.length;
    for (const [k, v] of this.mem) {
      if (this.memBytes <= this.memoryBytes) break;
      this.mem.delete(k);
      this.memBytes -= v.length;
    }
  }

  // a TileJSON source: the tile URL (and the data date) from it
  resolve() {
    this.resolving ||= this.resolveOnce();
    return this.resolving;
  }

  async resolveOnce() {
    if (!this.source.tileJson) return;
    try {
      const j = await (await this.fetch(this.source.tileJson, { signal: this.signal })).json();
      if (!this.template) this.template = j.tiles[0];
      const t = j['planetiler:osm:osmosisreplicationtime'] || j['planetiler:buildtime'];
      if (t) this.dataDate = String(t).slice(0, 10);
      // OpenFreeMap names its build in the tile URL: /planet/20261101_080013_pt/
      const b = !t && /\/(\d{4})(\d{2})(\d{2})_\d{6}/.exec(this.template || '');
      if (b) this.dataDate = `${b[1]}-${b[2]}-${b[3]}`;
    } catch (e) {
      if (!this.template) throw e;
    }
  }

  url(z, x, y) {
    let u = this.template.replace('{z}', z).replace('{x}', x).replace('{y}', y);
    if (u.startsWith('/')) u = new URL(u, this.source.tileJson).href;
    return u;
  }

  async slot() {
    if (this.active < this.source.limits.parallel) { this.active++; return; }
    await new Promise((resolve, reject) => {
      this.queue.push({ resolve, reject });
      this.signal?.addEventListener('abort', () => reject(abortError()), { once: true });
    });
  }

  busy() { return this.active > 0 || this.queue.length > 0; }

  release() {
    const next = this.queue.shift();
    if (next) next.resolve();
    else this.active--;
  }

  // -> the tile's bytes, or null for empty paper (404, empty body); the same tile asked twice at once
  // is fetched once
  get(z, x, y) {
    const url = this.url(z, x, y);
    if (this.pending.has(url)) return this.pending.get(url);
    const p = this.load(z, x, y).finally(() => this.pending.delete(url));
    this.pending.set(url, p);
    return p;
  }

  async load(z, x, y) {
    if (this.signal?.aborted) throw abortError();
    const key = `${z}/${x}/${y}`;
    if (!this.seen.has(key)) {
      if (this.seen.size >= this.source.limits.maxVectorTiles) throw new Error('limit');
      if (this.source.limits.maxBytes && this.bytes >= this.source.limits.maxBytes) throw new Error('budget');
      this.seen.add(key);
    }
    const url = this.url(z, x, y);
    const kept = this.mem.get(url);
    if (kept) {
      this.mem.delete(url);                          // newest again
      this.mem.set(url, kept);
      return kept.length ? kept : null;
    }
    if (this.caches && this.cacheOk === null) {
      // Cache Storage can fail (private windows, some embedded browsers): fetch on without it
      try { this.cache = await this.caches.open(CACHE); this.cacheOk = true; } catch { this.cache = null; this.cacheOk = false; }
    }
    let hit = null;
    try { hit = this.cache && await this.cache.match(url); } catch { hit = null; }
    if (hit) {
      this.fromCache++;
      const b = new Uint8Array(await hit.arrayBuffer());
      this.remember(url, b);
      this.onCount?.(this);
      return b.length ? b : null;
    }
    await this.slot();
    try {
      if (this.signal?.aborted) throw abortError();
      let tries = 0;
      for (;;) {
        let res;
        try {
          res = await this.fetch(url, { signal: this.signal });
        } catch (e) {
          if (e.name === 'AbortError' || this.signal?.aborted) throw abortError();
          if (tries >= 3) throw new Error(`Could not fetch map tile ${key}: ${e.message || e}`);
          await this.sleep(500 * 2 ** tries++);
          continue;
        }
        if (res.status === 429 || res.status === 503) {
          const ra = Number(res.headers.get('Retry-After')) || 5;
          // longer than the renderer waits for a view: stop, and say how long (Make again resumes)
          if (ra > MAX_WAIT_S) throw new Error(`The map server asks to wait about ${Math.ceil(ra / 60)} min. Press Make again then: what was fetched is kept.`);
          if (tries++ >= 6) throw new Error(`The map server keeps asking to wait (tile ${key}).`);
          await this.sleep(ra * 1000);
          continue;
        }
        let b;
        if (res.status === 404 || res.status === 204) b = new Uint8Array(0);
        else if (!res.ok) throw new Error(`Map tile ${key}: HTTP ${res.status}`);
        else {
          try {
            b = new Uint8Array(await res.arrayBuffer());
          } catch (e) {                                  // the connection dropped mid-tile: again
            if (e.name === 'AbortError' || this.signal?.aborted) throw abortError();
            if (tries >= 3) throw new Error(`Could not fetch map tile ${key}: ${e.message || e}`);
            await this.sleep(500 * 2 ** tries++);
            continue;
          }
        }
        this.count++;
        this.bytes += b.length;
        if (this.cache) { try { await this.cache.put(url, new Response(b)); } catch { /* a full or broken cache: go on */ } }
        this.remember(url, b);
        this.onCount?.(this);
        return b.length ? b : null;
      }
    } finally {
      this.release();
    }
  }
}

// MapLibre asks xtmap://z/x/y; the fetcher answers (an empty tile for empty paper)
export function registerProtocol(maplibregl, fetcher) {
  try { maplibregl.removeProtocol('xtmap'); } catch { /* not there yet */ }
  maplibregl.addProtocol('xtmap', async (params) => {
    const m = /^xtmap:\/\/(\d+)\/(\d+)\/(\d+)/.exec(params.url);
    const b = await fetcher.get(+m[1], +m[2], +m[3]);
    return { data: b ? b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength) : new ArrayBuffer(0) };
  });
}
