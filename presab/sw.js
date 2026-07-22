/**
 * Presab Service Worker
 * Caches the shell for offline use.
 * Network-first for API calls, cache-first for static assets.
 */

const CACHE_NAME = 'presab-v1';
const SHELL = [
  '/presab/',
  '/presab/index.html',
  '/presab/teacher.html',
  '/presab/manifest.json',
  'https://fonts.googleapis.com/css2?family=DM+Serif+Display:ital@0;1&family=Cormorant:ital,wght@0,300;0,400;1,300;1,400&family=Urbanist:wght@300;400;500;600;700&display=swap'
];

// ── Install: cache the shell ─────────────────────────────────
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(SHELL))
  );
  self.skipWaiting();
});

// ── Activate: clean old caches ───────────────────────────────
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// ── Fetch: network-first for /api/, cache-first for assets ───
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);

  // Always network for API calls (attendance data must be live)
  if (url.pathname.startsWith('/api/') || url.pathname.includes('socket.io')) {
    e.respondWith(fetch(e.request).catch(() => new Response('{"error":"offline"}', {
      headers: { 'Content-Type': 'application/json' }
    })));
    return;
  }

  // Cache-first for everything else
  e.respondWith(
    caches.match(e.request).then(cached => {
      if (cached) return cached;
      return fetch(e.request).then(res => {
        // Cache successful GET responses
        if (e.request.method === 'GET' && res.status === 200) {
          const clone = res.clone();
          caches.open(CACHE_NAME).then(c => c.put(e.request, clone));
        }
        return res;
      }).catch(() => caches.match('/presab/'));
    })
  );
});
