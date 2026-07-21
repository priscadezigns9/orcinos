// Orcinos Drive — Service Worker
// Caches drive.html + manifest for full offline use

const CACHE_NAME = 'orcinos-drive-v1';
const ASSETS = [
  '/drive.html',
  '/drive-manifest.json',
  '/deck.html',
  '/deck-manifest.json'
];

// Install — cache all assets immediately
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => {
      return cache.addAll(ASSETS);
    })
  );
  self.skipWaiting();
});

// Activate — clean up old caches
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(
        keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k))
      )
    )
  );
  self.clients.claim();
});

// Fetch — cache-first for our assets, network-first for everything else
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  const isAsset = ASSETS.some(a => url.pathname === a || url.pathname.endsWith(a));

  if (isAsset) {
    event.respondWith(
      caches.match(event.request).then(cached => {
        if (cached) return cached;
        return fetch(event.request).then(response => {
          const clone = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
          return response;
        });
      })
    );
  }
  // All other requests pass through normally
});
