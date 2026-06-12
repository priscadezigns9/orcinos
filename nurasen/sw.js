const CACHE_NAME = 'nurasen-v1';
const urlsToCache = [
  '/nurasen/',
  '/nurasen/index.html',
  '/nurasen/dashboard.html',
  '/logos/NURASEN_DEFINITIVE_2026.png'
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(urlsToCache))
  );
});

self.addEventListener('fetch', event => {
  event.respondWith(
    caches.match(event.request)
      .then(response => response || fetch(event.request))
  );
});
