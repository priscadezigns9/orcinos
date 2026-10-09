const CACHE_NAME = 'triplethreat-shell-v1';
const SHELL = [
  '/triplethreat/',
  '/triplethreat/index.html',
  '/triplethreat/manifest.webmanifest',
  '/triplethreat/icon-192.png',
  '/triplethreat/icon-512.png',
  '/triplethreat/apple-touch-icon.png',
  '/assets/logo.png'
];
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key.startsWith('triplethreat-shell-') && key !== CACHE_NAME).map(key => caches.delete(key)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin) return;
  if (url.pathname.startsWith('/triplethreat/')) {
    if (request.mode === 'navigate' || url.pathname.endsWith('.html')) {
      event.respondWith(fetch(request, { cache: 'no-store' }).then(response => {
        if (response.ok) caches.open(CACHE_NAME).then(cache => cache.put(request, response.clone()));
        return response;
      }).catch(() => caches.match(request).then(cached => cached || caches.match('/triplethreat/index.html'))));
    } else {
      event.respondWith(caches.match(request).then(cached => cached || fetch(request)));
    }
  }
});
