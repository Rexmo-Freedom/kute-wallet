// Kute's service worker: the app shell, cached for an instant and offline
// start. Hand-written, not Flutter's flutter_service_worker.js: that one is
// deprecated and, in this Flutter version, only unregisters itself.
//
// `dart run tool/web_pwa_stamp.dart` (after `flutter build web`) fills in
// BUILD (a hash of the whole build) and PRECACHE ([path, sha256] of the
// shell). An unstamped copy is a kill switch: it removes itself and its
// caches, so a deploy that skipped the stamp never leaves old code cached.
//
// What it touches: same-origin GETs under its scope whose path is a shell
// file (see SHELL). Never another origin (the backend, Breez, prices...),
// never a query string (but version.json's cache buster), nothing else.
//   - Navigations to the app, flutter_bootstrap.js and version.json: network
//     first (with a short timeout), the cached copy only when the network
//     fails.
//   - Everything else in the shell: the cache of this build first.
// A new deploy is a new BUILD: the bootstrap registers sw.js?v=<BUILD>, this
// worker installs (re-using unchanged files from the old cache by hash,
// checking every downloaded file's hash), waits, and takes over when a
// freshly loaded page asks it to ("kute-activate"); that page then reloads
// onto the new build. Old caches are deleted on activate.
'use strict';

const BUILD = '__KUTE_BUILD__';
const PRECACHE = /*__KUTE_PRECACHE__*/[];

const PREFIX = 'kute-shell-';
const CACHE = PREFIX + BUILD;
const STAMPED = !BUILD.startsWith('__');
const HASH_HEADER = 'x-kute-sha256';
const SCOPE = new URL(self.registration.scope);
const NETWORK_TIMEOUT_MS = 4000;

// Scope-relative paths of the app shell. Anything else goes to the network
// untouched.
const SHELL = new RegExp(
  '^(flutter_bootstrap\\.js|flutter\\.js|main\\.dart\\.(js|mjs|wasm)' +
    '|main\\.dart\\.js_\\d+\\.part\\.js|manifest\\.json|favicon\\.png' +
    '|splash\\.js|breez_boot\\.js|bdk_boot\\.js' +
    '|canvaskit/[\\w/.-]+\\.(js|wasm)' +
    '|breez_sdk_spark/[\\w/.-]+\\.(js|wasm)|bdk_wallet_web/[\\w.-]+\\.(js|wasm)' +
    '|icons/[\\w.-]+\\.png|splash/img/[\\w.-]+\\.png' +
    '|assets/(?!NOTICES$)[^?#]+)$'
);
const NETWORK_FIRST = new Set(['flutter_bootstrap.js']);
const ROOT = './';

const scoped = (path) => new URL(path, SCOPE).href;

async function sha256(buffer) {
  const digest = await crypto.subtle.digest('SHA-256', buffer);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, '0')).join('');
}

// A cacheable copy of a response, carrying the file's hash.
function tagged(body, response, hash) {
  const headers = new Headers(response.headers);
  if (hash) headers.set(HASH_HEADER, hash);
  return new Response(body, { status: 200, statusText: 'OK', headers });
}

function cacheable(response) {
  return response && response.status === 200 && response.type === 'basic';
}

async function findInOldCaches(url, hash) {
  for (const name of await caches.keys()) {
    if (!name.startsWith(PREFIX) || name === CACHE) continue;
    const hit = await (await caches.open(name)).match(url);
    if (hit && hit.headers.get(HASH_HEADER) === hash) return hit;
  }
  return null;
}

self.addEventListener('install', (event) => {
  if (!STAMPED) {
    self.skipWaiting();
    return;
  }
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    // Fill the cache with exactly this build: unchanged files are copied
    // from an older build's cache, the rest downloaded and hash-checked, so
    // a deploy that lands mid-install fails the install (retried later)
    // instead of mixing two builds.
    const queue = PRECACHE.slice();
    const worker = async () => {
      for (let item = queue.shift(); item; item = queue.shift()) {
        const [path, hash] = item;
        const url = scoped(path);
        if (await cache.match(url)) continue;
        const old = await findInOldCaches(url, hash);
        if (old) {
          await cache.put(url, old);
          continue;
        }
        const response = await fetch(new Request(url, { cache: 'no-cache', credentials: 'same-origin' }));
        if (!cacheable(response)) throw new Error('precache ' + path + ': ' + response.status);
        const body = await response.arrayBuffer();
        if ((await sha256(body)) !== hash) throw new Error('precache ' + path + ': not this build');
        await cache.put(url, tagged(body, response, hash));
      }
    };
    try {
      await Promise.all([worker(), worker(), worker(), worker()]);
    } catch (e) {
      await caches.delete(CACHE);
      throw e;
    }
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const name of await caches.keys()) {
      if (name.startsWith(PREFIX) && (name !== CACHE || !STAMPED)) await caches.delete(name);
    }
    if (!STAMPED) {
      // Kill switch: no worker, no cache; open pages reload from the network.
      await self.registration.unregister();
      for (const client of await self.clients.matchAll({ type: 'window' })) {
        if ('navigate' in client) client.navigate(client.url);
      }
      return;
    }
    await self.clients.claim();
  })());
});

self.addEventListener('message', (event) => {
  const data = event.data;
  if (data === 'kute-activate') {
    // A page of this build is waiting on the splash: take over now.
    self.skipWaiting();
  } else if (data && data.kute === 'used' && Array.isArray(data.urls) && STAMPED) {
    // First visit: the page loaded before this worker controlled it; keep
    // the shell files it used so the next start works offline.
    event.waitUntil(cacheUsed(data.urls.slice(0, 2000)));
  }
});

async function cacheUsed(urls) {
  const cache = await caches.open(CACHE);
  for (const raw of urls) {
    let url;
    try { url = new URL(raw); } catch (_) { continue; }
    const path = shellPath(url);
    if (!path || NETWORK_FIRST.has(path) || (await cache.match(url.href))) continue;
    try {
      const response = await fetch(url.href, { credentials: 'same-origin' });
      if (cacheable(response)) await cache.put(url.href, tagged(await response.arrayBuffer(), response));
    } catch (_) { /* offline: try again next time */ }
  }
}

// The scope-relative shell path of [url], or null when the worker must not
// touch it.
function shellPath(url) {
  if (url.origin !== SCOPE.origin || !url.pathname.startsWith(SCOPE.pathname)) return null;
  if (url.search) return null;
  let path;
  try {
    path = decodeURIComponent(url.pathname.slice(SCOPE.pathname.length));
  } catch (_) {
    return null;
  }
  return SHELL.test(path) ? path : null;
}

self.addEventListener('fetch', (event) => {
  if (!STAMPED) return;
  const request = event.request;
  if (request.method !== 'GET' || request.headers.has('range')) return;
  const url = new URL(request.url);
  if (request.mode === 'navigate') {
    // Only the app itself (the root, with any query); other pages on the
    // site are not ours.
    if (url.origin !== SCOPE.origin) return;
    const path = url.pathname.slice(SCOPE.pathname.length);
    if (path !== '' && path !== 'index.html') return;
    event.respondWith(networkFirst(request, scoped(ROOT)));
    return;
  }
  if (url.origin === SCOPE.origin && url.pathname === SCOPE.pathname + 'version.json') {
    // package_info_plus asks for version.json?cachebuster=...: the network's
    // answer, this build's copy offline.
    event.respondWith(networkFirst(request, scoped('version.json')));
    return;
  }
  const path = shellPath(url);
  if (!path) return;
  if (NETWORK_FIRST.has(path)) {
    event.respondWith(networkFirst(request, url.href));
  } else {
    event.respondWith(cacheFirst(request, url.href));
  }
});

// The network's answer, never stored (the cache holds exactly what this
// build installed); the cached copy when the network fails or stalls.
async function networkFirst(request, key) {
  const cache = await caches.open(CACHE);
  const network = fetch(request);
  network.catch(() => {});
  let timer;
  const timeout = new Promise((resolve) => { timer = setTimeout(resolve, NETWORK_TIMEOUT_MS); });
  try {
    const response = await Promise.race([network, timeout]);
    if (response && response.ok) return response;
    if (response) {
      const cached = await cache.match(key);
      return cached ? new Response(cached.body, cached) : response;
    }
  } catch (_) {
    // fall through to the cache
  } finally {
    clearTimeout(timer);
  }
  const cached = await cache.match(key);
  if (cached) return new Response(cached.body, cached);
  return network;
}

async function cacheFirst(request, key) {
  const cache = await caches.open(CACHE);
  const cached = await cache.match(key);
  if (cached) return cached;
  const response = await fetch(request);
  if (cacheable(response)) {
    const copy = response.clone();
    // Lazily loaded shell files (images, sounds): kept for offline use.
    copy.arrayBuffer().then((body) => cache.put(key, tagged(body, copy))).catch(() => {});
  }
  return response;
}
